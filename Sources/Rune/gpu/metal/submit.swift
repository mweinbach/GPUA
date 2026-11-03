// Ported from: crates/rune/src/gpu/metal/submit.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Command submission, queue buffer/texture writes, timestamp period calibration, and drawable
//! presentation (`MetalQueue`).

#if canImport(Metal)
import Metal
import QuartzCore
#endif
#if !os(WASI)
import Foundation
#endif

/// Command submission queue paired with a `MetalDevice` (`gpu/metal/submit.rs`).
public final class MetalQueue: Sendable {
    public let shared: MetalShared
    public let timestampPeriodNs: Float

    public init(shared: MetalShared) {
        self.shared = shared
        #if canImport(Metal)
        if let dev = shared.mtlDevice, dev.supportsCounterSampling(.atStageBoundary) {
            _ = dev.sampleTimestamps()
            // On Apple Silicon, `MTLCounterSampleBuffer.resolveCounters` resolves directly to
            // nanoseconds (`period == 1.0`).
            self.timestampPeriodNs = 1.0
        } else {
            self.timestampPeriodNs = 1.0
        }
        #else
        self.timestampPeriodNs = 1.0
        #endif
    }

    public func getTimestampPeriod() -> Float {
        timestampPeriodNs
    }

    /// Writes `data` into `buffer` at `offset`:
    /// - When no recorded unsubmitted encoder references `buffer`'s current backing, writes in place
    ///   (or swaps in a CoW spare if only already-submitted GPU work reads it — `a_queue_write_behind_submitted_work_swaps_rather_than_stages`).
    /// - When an encoder recorded *before* `writeBuffer` already holds `buffer`'s current backing,
    ///   stages a blit upload ahead of the next `submit` so that earlier encoder sees the new bytes
    ///   (`a_queue_write_reaches_an_encoder_recorded_before_it`).
    public func writeBuffer(_ buffer: MetalBuffer, offset: UInt64, data: [UInt8]) {
        guard !data.isEmpty else { return }
        let satisfied = data.withUnsafeBytes { raw in
            buffer.store.writeQueue(
                offset: Int(offset),
                bytes: raw,
                completedSubmission: shared.completedSubmission
            )
        }
        if satisfied {
            return
        }

        // Stage through the pending upload blit command buffer so it lands before the next submit.
        let dstRaw = buffer.store.activeRaw
        buffer.store.gpuWrite(StoreSpan(Int(offset), Int(offset) + data.count))
        #if canImport(Metal)
        if let dev = shared.mtlDevice,
           let dstMtl = dstRaw.mtlBuffer,
           let stageBuf = data.withUnsafeBytes({ raw -> (any MTLBuffer)? in
               guard let ptr = raw.baseAddress else { return nil }
               return dev.makeBuffer(bytes: ptr, length: raw.count, options: .storageModeShared)
           }) {
            let dstOffset = Int(offset)
            let byteCount = data.count
            shared.enqueueBlitUpload(keepObjects: [stageBuf, dstRaw]) { blit in
                blit.copy(
                    from: stageBuf,
                    sourceOffset: 0,
                    to: dstMtl,
                    destinationOffset: dstOffset,
                    size: byteCount
                )
            }
            return
        }
        #endif
        let dstOffset = Int(offset)
        shared.enqueueHostUpload {
            data.withUnsafeBytes { raw in
                dstRaw.write(dstOffset, raw)
            }
        }
    }

    /// Uploads `data` into `texture` ahead of the next `submit`.
    public func writeTexture(
        _ texture: MetalTexture,
        mipLevel: UInt32 = 0,
        originX: UInt32 = 0,
        originY: UInt32 = 0,
        arrayLayer: UInt32 = 0,
        data: [UInt8],
        offset: Int = 0,
        bytesPerRow: UInt32,
        rowsPerImage: UInt32? = nil,
        width: UInt32,
        height: UInt32
    ) {
        guard width > 0 && height > 0, offset < data.count else { return }
        #if canImport(Metal)
        if let dev = shared.mtlDevice,
           let dstTex = texture.raw.mtlTexture {
            let sliceBytes = Array(data[offset...])
            guard !sliceBytes.isEmpty,
                  let stageBuf = sliceBytes.withUnsafeBytes({ raw -> (any MTLBuffer)? in
                      guard let ptr = raw.baseAddress else { return nil }
                      return dev.makeBuffer(bytes: ptr, length: raw.count, options: .storageModeShared)
                  })
            else { return }
            let rpi = Int(rowsPerImage ?? height)
            shared.enqueueBlitUpload(keepObjects: [stageBuf, dstTex]) { blit in
                blit.copy(
                    from: stageBuf,
                    sourceOffset: 0,
                    sourceBytesPerRow: Int(bytesPerRow),
                    sourceBytesPerImage: Int(bytesPerRow) * rpi,
                    sourceSize: MTLSize(width: Int(width), height: Int(height), depth: 1),
                    to: dstTex,
                    destinationSlice: Int(arrayLayer),
                    destinationLevel: Int(mipLevel),
                    destinationOrigin: MTLOrigin(x: Int(originX), y: Int(originY), z: 0)
                )
            }
            return
        }
        #endif
        let rawTex = texture.raw
        let bpp = metalFormatBytesPerPixel(rawTex.format)
        let bpr = Int(bytesPerRow)
        let w = Int(width)
        let h = Int(height)
        let ox = Int(originX)
        let oy = Int(originY)
        let layer = Int(arrayLayer)
        let mip = Int(mipLevel)
        shared.enqueueHostUpload {
            rawTex.hostLock.withLock {
                guard layer < rawTex.hostSlices.count, mip < rawTex.hostSlices[layer].count else { return }
                let dstW = max(1, Int(rawTex.width) >> mip)
                for row in 0..<h {
                    let srcStart = offset + row * bpr
                    let rowBytes = w * bpp
                    let dstStart = ((oy + row) * dstW + ox) * bpp
                    if srcStart + rowBytes <= data.count && dstStart + rowBytes <= rawTex.hostSlices[layer][mip].count {
                        rawTex.hostSlices[layer][mip].replaceSubrange(
                            dstStart..<(dstStart + rowBytes),
                            with: data[srcStart..<(srcStart + rowBytes)]
                        )
                    }
                }
            }
        }
    }

    public func onSubmittedWorkDone(_ callback: @escaping @Sendable () -> Void) {
        shared.enqueueCallback(.workDone(callback))
    }

    /// Commits pending uploads followed by `commandBuffers`, returning the latest submission index.
    @discardableResult
    public func submit(_ commandBuffers: [MetalCommandBuffer]) -> UInt64 {
        let index: UInt64 = shared.lock.withLock {
            #if canImport(Metal)
            shared.flushHeldLocked()
            shared.commitUploadsLocked()
            #endif
            shared.commitHostUploadsLocked()

            for cmd in commandBuffers {
                cmd.consumed = true
                cmd.dropUnsubmittedCallbacks.removeAll()
                #if canImport(Metal)
                if !cmd.hostOps.isEmpty {
                    for op in cmd.hostOps { op() }
                    cmd.hostOps.removeAll()
                    if cmd.mtlCommandBuffer == nil {
                        shared.lastSubmission &+= 1
                        let val = shared.lastSubmission
                        if let ev = shared.sharedEvent {
                            if let signalCb = shared.makeUnretainedCommandBuffer() {
                                signalCb.encodeSignalEvent(ev, value: val)
                                signalCb.commit()
                            } else {
                                ev.signaledValue = val
                            }
                        }
                    }
                }
                if let cb = cmd.mtlCommandBuffer {
                    cmd.mtlCommandBuffer = nil
                    shared.lastSubmission &+= 1
                    let val = shared.lastSubmission
                    if let ev = shared.sharedEvent {
                        cb.encodeSignalEvent(ev, value: val)
                    }
                    for k in cmd.keeps {
                        for (store, raw) in k.rawBufferReleases {
                            store.releaseRecorded(raw, submittedAt: val)
                        }
                        k.rawBufferReleases.removeAll(keepingCapacity: true)
                        shared.retireQueue.append((val, k))
                    }
                    cmd.keeps.removeAll()
                    for wd in cmd.workDoneCallbacks {
                        shared.callbackQueue.append((val, .workDone(wd)))
                    }
                    cmd.workDoneCallbacks.removeAll()
                    // Hold the last command buffer only when `present` follows; otherwise commit immediately.
                    cb.commit()
                } else {
                    let val = shared.lastSubmission
                    for k in cmd.keeps {
                        for (store, raw) in k.rawBufferReleases {
                            store.releaseRecorded(raw, submittedAt: val)
                        }
                        k.rawBufferReleases.removeAll(keepingCapacity: true)
                        if shared.spareKeeps.count < MetalShared.maxSpareKeeps {
                            shared.spareKeeps.append(k)
                        }
                    }
                    cmd.keeps.removeAll()
                    for wd in cmd.workDoneCallbacks {
                        shared.callbackQueue.append((val, .workDone(wd)))
                    }
                    cmd.workDoneCallbacks.removeAll()
                }
                #else
                if !cmd.hostOps.isEmpty {
                    shared.lastSubmission &+= 1
                    for op in cmd.hostOps { op() }
                    cmd.hostOps.removeAll()
                }
                let val = shared.lastSubmission
                for k in cmd.keeps {
                    for (store, raw) in k.rawBufferReleases {
                        store.releaseRecorded(raw, submittedAt: val)
                    }
                    k.rawBufferReleases.removeAll(keepingCapacity: true)
                    if shared.spareKeeps.count < MetalShared.maxSpareKeeps {
                        shared.spareKeeps.append(k)
                    }
                }
                cmd.keeps.removeAll()
                for wd in cmd.workDoneCallbacks {
                    shared.callbackQueue.append((val, .workDone(wd)))
                }
                cmd.workDoneCallbacks.removeAll()
                #endif
            }
            return shared.lastSubmission
        }
        _ = shared.retire()
        return index
    }

    public func present(_ output: MetalOutput) {
        #if canImport(Metal)
        if let drawable = output.drawable, let cb = shared.makeUnretainedCommandBuffer() {
            cb.present(drawable)
            let val: UInt64 = shared.lock.withLock {
                let v = shared.stampLocked(cb, keep: nil)
                shared.frameValues.append(v)
                return v
            }
            _ = val
            cb.commit()
        }
        #else
        _ = output
        #endif
    }
}
