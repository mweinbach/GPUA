// Ported from: crates/rune/src/gpu/metal/encode.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Command buffer recording (`MetalCommandEncoder`) and finished `MetalCommandBuffer`.
//!
//! `MTLCommandBuffer` creation is deferred until the first pass or blit command so an empty
//! encoder commits nothing (`a_frame_is_one_command_buffer_and_writes_land`). Dropping an
//! unsubmitted encoder releases its `MTLCommandBuffer` BEFORE releasing its retained attachments
//! (`an_encoder_dropped_mid_frame_frees_its_buffer_before_its_targets`).

#if canImport(Metal)
import Metal
#endif
#if !os(WASI)
import Foundation
#endif

/// Finished GPU command buffer ready for `MetalQueue.submit(_:)`.
// PORT NOTE: Immutable submission bundle consumed once by `MetalQueue.submit`.
public final class MetalCommandBuffer: @unchecked Sendable {
    let shared: MetalShared
    #if canImport(Metal)
    var mtlCommandBuffer: (any MTLCommandBuffer)?
    #endif
    var keeps: [MetalKeepList]
    var workDoneCallbacks: [@Sendable () -> Void]
    var dropUnsubmittedCallbacks: [@Sendable () -> Void]
    var hostOps: [@Sendable () -> Void]
    var consumed: Bool = false

    #if canImport(Metal)
    init(
        shared: MetalShared,
        mtlCommandBuffer: (any MTLCommandBuffer)?,
        keeps: [MetalKeepList],
        workDoneCallbacks: [@Sendable () -> Void],
        dropUnsubmittedCallbacks: [@Sendable () -> Void] = [],
        hostOps: [@Sendable () -> Void]
    ) {
        self.shared = shared
        self.mtlCommandBuffer = mtlCommandBuffer
        self.keeps = keeps
        self.workDoneCallbacks = workDoneCallbacks
        self.dropUnsubmittedCallbacks = dropUnsubmittedCallbacks
        self.hostOps = hostOps
    }
    #else
    init(
        shared: MetalShared,
        keeps: [MetalKeepList],
        workDoneCallbacks: [@Sendable () -> Void],
        dropUnsubmittedCallbacks: [@Sendable () -> Void] = [],
        hostOps: [@Sendable () -> Void]
    ) {
        self.shared = shared
        self.keeps = keeps
        self.workDoneCallbacks = workDoneCallbacks
        self.dropUnsubmittedCallbacks = dropUnsubmittedCallbacks
        self.hostOps = hostOps
    }
    #endif

    deinit {
        guard !consumed else { return }
        #if canImport(Metal)
        // Drop `mtlCommandBuffer` BEFORE freeing keep lists so Metal closes any open state safely.
        mtlCommandBuffer = nil
        #endif
        for cb in dropUnsubmittedCallbacks {
            cb()
        }
        dropUnsubmittedCallbacks.removeAll()
        for k in keeps {
            shared.recycleKeepList(k, submittedAt: nil)
        }
        keeps.removeAll()
    }
}

/// Records render passes, compute passes, blits, and query resolves into a single `MTLCommandBuffer`.
// PORT NOTE: Single-owner encoder matching `wgpu::CommandEncoder` (`encode.rs`).
public final class MetalCommandEncoder: @unchecked Sendable {
    public let shared: MetalShared
    public let label: String?
    private var keep: MetalKeepList?
    private var passKeeps: [MetalKeepList] = []
    private var workDoneCallbacks: [@Sendable () -> Void] = []
    private var dropUnsubmittedCallbacks: [@Sendable () -> Void] = []
    private var hostOps: [@Sendable () -> Void] = []
    private var finished: Bool = false
    #if canImport(Metal)
    private var mtlCommandBuffer: (any MTLCommandBuffer)? = nil
    private var activeBlit: (any MTLBlitCommandEncoder)? = nil
    #endif

    public init(shared: MetalShared, label: String? = nil) {
        self.shared = shared
        self.label = label
        self.keep = shared.takeKeepList()
        shared.incrementRecording()
    }

    deinit {
        if !finished {
            shared.decrementRecording()
            #if canImport(Metal)
            activeBlit?.endEncoding()
            activeBlit = nil
            // Crucial ordering (`an_encoder_dropped_mid_frame_frees_its_buffer_before_its_targets`):
            // drop `mtlCommandBuffer` FIRST before releasing `passKeeps` and `keep`!
            mtlCommandBuffer = nil
            #endif
            for cb in dropUnsubmittedCallbacks {
                cb()
            }
            dropUnsubmittedCallbacks.removeAll()
            for pk in passKeeps {
                shared.recycleKeepList(pk, submittedAt: nil)
            }
            passKeeps.removeAll()
            if let k = keep {
                keep = nil
                shared.recycleKeepList(k, submittedAt: nil)
            }
        }
    }

    #if canImport(Metal)
    func ensureCommandBuffer() -> (any MTLCommandBuffer)? {
        endActiveBlit()
        if let cb = mtlCommandBuffer {
            return cb
        }
        let cb = shared.makeUnretainedCommandBuffer()
        if let label, let cb { cb.label = label }
        mtlCommandBuffer = cb
        return cb
    }

    private func ensureBlit() -> (any MTLBlitCommandEncoder)? {
        if let blit = activeBlit {
            return blit
        }
        if mtlCommandBuffer == nil {
            let cb = shared.makeUnretainedCommandBuffer()
            if let label, let cb { cb.label = label }
            mtlCommandBuffer = cb
        }
        guard let cb = mtlCommandBuffer, let blit = cb.makeBlitCommandEncoder() else {
            return nil
        }
        activeBlit = blit
        return blit
    }

    private func endActiveBlit() {
        if let blit = activeBlit {
            blit.endEncoding()
            activeBlit = nil
        }
    }
    #endif

    func finishPassKeep(_ passKeep: MetalKeepList) {
        passKeeps.append(passKeep)
    }

    public func beginRenderPass(
        label: String? = nil,
        colorAttachments: [MetalColorAttachment?],
        timestampWrites: MetalPassTimestampWrites? = nil
    ) -> MetalRenderPass {
        MetalRenderPass(
            owner: self,
            label: label,
            colorAttachments: colorAttachments,
            timestampWrites: timestampWrites
        )
    }

    public func beginRenderPass(
        label: String? = nil,
        colorAttachment: MetalColorAttachment,
        timestampWrites: MetalPassTimestampWrites? = nil
    ) -> MetalRenderPass {
        beginRenderPass(
            label: label,
            colorAttachments: [colorAttachment],
            timestampWrites: timestampWrites
        )
    }

    public func beginComputePass(
        label: String? = nil,
        timestampWrites: MetalPassTimestampWrites? = nil
    ) -> MetalComputePass {
        MetalComputePass(
            owner: self,
            label: label,
            timestampWrites: timestampWrites
        )
    }

    public func copyBufferToBuffer(
        source: MetalBuffer,
        sourceOffset: UInt64,
        destination: MetalBuffer,
        destinationOffset: UInt64,
        size: UInt64
    ) {
        guard size > 0 else { return }
        let srcRaw = source.store.retainForRecording()
        let dstRaw = destination.store.retainForRecording()
        keep?.keepRawBuffer(store: source.store, raw: srcRaw)
        keep?.keepRawBuffer(store: destination.store, raw: dstRaw)
        destination.store.gpuWrite(StoreSpan(Int(destinationOffset), Int(destinationOffset + size)))

        #if canImport(Metal)
        if let blit = ensureBlit(), let srcMtl = srcRaw.mtlBuffer, let dstMtl = dstRaw.mtlBuffer {
            blit.copy(
                from: srcMtl,
                sourceOffset: Int(sourceOffset),
                to: dstMtl,
                destinationOffset: Int(destinationOffset),
                size: Int(size)
            )
            return
        }
        #endif
        let sOff = Int(sourceOffset)
        let dOff = Int(destinationOffset)
        let len = Int(size)
        hostOps.append {
            let bytes = srcRaw.readSlice(sOff..<(sOff + len))
            bytes.withUnsafeBytes { raw in
                dstRaw.write(dOff, raw)
            }
        }
    }

    public func copyBufferToTexture(
        source: MetalBuffer,
        sourceOffset: UInt64,
        bytesPerRow: UInt32,
        rowsPerImage: UInt32? = nil,
        destination: MetalTexture,
        mipLevel: UInt32 = 0,
        originX: UInt32 = 0,
        originY: UInt32 = 0,
        arrayLayer: UInt32 = 0,
        width: UInt32,
        height: UInt32
    ) {
        guard width > 0 && height > 0 else { return }
        let srcRaw = source.store.retainForRecording()
        keep?.keepRawBuffer(store: source.store, raw: srcRaw)
        keep?.keep(destination.raw)

        #if canImport(Metal)
        if let blit = ensureBlit(), let srcMtl = srcRaw.mtlBuffer, let dstTex = destination.raw.mtlTexture {
            let rpi = Int(rowsPerImage ?? height)
            blit.copy(
                from: srcMtl,
                sourceOffset: Int(sourceOffset),
                sourceBytesPerRow: Int(bytesPerRow),
                sourceBytesPerImage: Int(bytesPerRow) * rpi,
                sourceSize: MTLSize(width: Int(width), height: Int(height), depth: 1),
                to: dstTex,
                destinationSlice: Int(arrayLayer),
                destinationLevel: Int(mipLevel),
                destinationOrigin: MTLOrigin(x: Int(originX), y: Int(originY), z: 0)
            )
            return
        }
        #endif
        let rawTex = destination.raw
        let bpp = metalFormatBytesPerPixel(rawTex.format)
        let sOff = Int(sourceOffset)
        let bpr = Int(bytesPerRow)
        let w = Int(width)
        let h = Int(height)
        let ox = Int(originX)
        let oy = Int(originY)
        let layer = Int(arrayLayer)
        let mip = Int(mipLevel)
        hostOps.append {
            rawTex.hostLock.withLock {
                guard layer < rawTex.hostSlices.count, mip < rawTex.hostSlices[layer].count else { return }
                let dstW = max(1, Int(rawTex.width) >> mip)
                for row in 0..<h {
                    let rowStart = sOff + row * bpr
                    let rowBytes = w * bpp
                    let bytes = srcRaw.readSlice(rowStart..<(rowStart + rowBytes))
                    let dstStart = ((oy + row) * dstW + ox) * bpp
                    if bytes.count == rowBytes && dstStart + rowBytes <= rawTex.hostSlices[layer][mip].count {
                        rawTex.hostSlices[layer][mip].replaceSubrange(
                            dstStart..<(dstStart + rowBytes),
                            with: bytes
                        )
                    }
                }
            }
        }
    }

    public func copyTextureToBuffer(
        texture: MetalTexture,
        mipLevel: UInt32 = 0,
        originX: UInt32 = 0,
        originY: UInt32 = 0,
        arrayLayer: UInt32 = 0,
        destination: MetalBuffer,
        destinationOffset: UInt64 = 0,
        bytesPerRow: UInt32,
        rowsPerImage: UInt32? = nil,
        width: UInt32,
        height: UInt32
    ) {
        guard width > 0 && height > 0 else { return }
        let dstRaw = destination.store.retainForRecording()
        keep?.keep(texture.raw)
        keep?.keepRawBuffer(store: destination.store, raw: dstRaw)
        let totalBytes = Int(bytesPerRow) * Int(height)
        destination.store.gpuWrite(StoreSpan(Int(destinationOffset), Int(destinationOffset) + totalBytes))

        #if canImport(Metal)
        if let blit = ensureBlit(), let srcTex = texture.raw.mtlTexture, let dstMtl = dstRaw.mtlBuffer {
            let rpi = Int(rowsPerImage ?? height)
            blit.copy(
                from: srcTex,
                sourceSlice: Int(arrayLayer),
                sourceLevel: Int(mipLevel),
                sourceOrigin: MTLOrigin(x: Int(originX), y: Int(originY), z: 0),
                sourceSize: MTLSize(width: Int(width), height: Int(height), depth: 1),
                to: dstMtl,
                destinationOffset: Int(destinationOffset),
                destinationBytesPerRow: Int(bytesPerRow),
                destinationBytesPerImage: Int(bytesPerRow) * rpi
            )
            return
        }
        #endif
        let rawTex = texture.raw
        let bpp = metalFormatBytesPerPixel(rawTex.format)
        let dOff = Int(destinationOffset)
        let bpr = Int(bytesPerRow)
        let w = Int(width)
        let h = Int(height)
        let ox = Int(originX)
        let oy = Int(originY)
        let layer = Int(arrayLayer)
        let mip = Int(mipLevel)
        hostOps.append {
            let slice: [UInt8] = rawTex.hostLock.withLock {
                if layer < rawTex.hostSlices.count && mip < rawTex.hostSlices[layer].count {
                    return rawTex.hostSlices[layer][mip]
                }
                return []
            }
            let srcW = max(1, Int(rawTex.width) >> mip)
            for row in 0..<h {
                let srcStart = ((oy + row) * srcW + ox) * bpp
                let rowBytes = w * bpp
                if srcStart + rowBytes <= slice.count {
                    Array(slice[srcStart..<(srcStart + rowBytes)]).withUnsafeBytes { raw in
                        dstRaw.write(dOff + row * bpr, raw)
                    }
                }
            }
        }
    }

    public func copyTextureToTexture(
        source: MetalTexture,
        sourceMip: UInt32 = 0,
        sourceLayer: UInt32 = 0,
        sourceOrigin: (UInt32, UInt32) = (0, 0),
        destination: MetalTexture,
        destinationMip: UInt32 = 0,
        destinationLayer: UInt32 = 0,
        destinationOrigin: (UInt32, UInt32) = (0, 0),
        width: UInt32,
        height: UInt32
    ) {
        guard width > 0 && height > 0 else { return }
        keep?.keep(source.raw)
        keep?.keep(destination.raw)

        #if canImport(Metal)
        if let blit = ensureBlit(),
           let srcTex = source.raw.mtlTexture,
           let dstTex = destination.raw.mtlTexture {
            blit.copy(
                from: srcTex,
                sourceSlice: Int(sourceLayer),
                sourceLevel: Int(sourceMip),
                sourceOrigin: MTLOrigin(x: Int(sourceOrigin.0), y: Int(sourceOrigin.1), z: 0),
                sourceSize: MTLSize(width: Int(width), height: Int(height), depth: 1),
                to: dstTex,
                destinationSlice: Int(destinationLayer),
                destinationLevel: Int(destinationMip),
                destinationOrigin: MTLOrigin(x: Int(destinationOrigin.0), y: Int(destinationOrigin.1), z: 0)
            )
            return
        }
        #endif
    }

    public func resolveQuerySet(
        _ querySet: MetalQuerySet,
        range: Range<Int>,
        destination: MetalBuffer,
        destinationOffset: UInt64 = 0
    ) {
        guard !range.isEmpty else { return }
        let dstRaw = destination.store.retainForRecording()
        keep?.keep(querySet)
        keep?.keepRawBuffer(store: destination.store, raw: dstRaw)
        let byteLen = range.count * 8
        destination.store.gpuWrite(StoreSpan(Int(destinationOffset), Int(destinationOffset) + byteLen))

        #if canImport(Metal)
        if let counterBuf = querySet.counterBuffer,
           let blit = ensureBlit(),
           let dstMtl = dstRaw.mtlBuffer {
            blit.resolveCounters(
                counterBuf,
                range: range,
                destinationBuffer: dstMtl,
                destinationOffset: Int(destinationOffset)
            )
            return
        }
        #endif
        let dOff = Int(destinationOffset)
        hostOps.append {
            let ticks = querySet.readFallbackRange(range)
            ticks.withUnsafeBytes { raw in
                dstRaw.write(dOff, raw)
            }
        }
    }

    public func onSubmittedWorkDone(_ callback: @escaping @Sendable () -> Void) {
        workDoneCallbacks.append(callback)
    }

    public func onDropUnsubmitted(_ callback: @escaping @Sendable () -> Void) {
        dropUnsubmittedCallbacks.append(callback)
    }

    public func finish() -> MetalCommandBuffer {
        precondition(!finished, "MetalCommandEncoder.finish() called twice")
        finished = true
        shared.decrementRecording()
        #if canImport(Metal)
        endActiveBlit()
        #endif
        var allKeeps: [MetalKeepList] = []
        if let k = keep {
            keep = nil
            allKeeps.append(k)
        }
        allKeeps.append(contentsOf: passKeeps)
        passKeeps.removeAll()

        #if canImport(Metal)
        let cb = mtlCommandBuffer
        mtlCommandBuffer = nil
        return MetalCommandBuffer(
            shared: shared,
            mtlCommandBuffer: cb,
            keeps: allKeeps,
            workDoneCallbacks: workDoneCallbacks,
            dropUnsubmittedCallbacks: dropUnsubmittedCallbacks,
            hostOps: hostOps
        )
        #else
        return MetalCommandBuffer(
            shared: shared,
            keeps: allKeeps,
            workDoneCallbacks: workDoneCallbacks,
            dropUnsubmittedCallbacks: dropUnsubmittedCallbacks,
            hostOps: hostOps
        )
        #endif
    }
}
