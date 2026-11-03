// Ported from: crates/rune/src/gpu/metal/compute.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Compute pipelines (`MetalComputePipeline`) and compute passes (`MetalComputePass`) in Rune's
//! Metal backend, supporting out-of-order `setBindGroup` / `setPipeline`, dynamic offsets,
//! `_buffer_sizes`, mid-pass buffer swap rebinding, and stage-boundary timestamp sampling.

#if canImport(Metal)
import Metal
#endif
#if !os(WASI)
import Foundation
#endif

public struct MetalComputePipelineDescriptor {
    public var label: String?
    public var layout: MetalPipelineLayout?
    public var module: MetalShaderModule
    public var entryPoint: String?
    public var constants: [String: Double]

    public init(
        label: String? = nil,
        layout: MetalPipelineLayout? = nil,
        module: MetalShaderModule,
        entryPoint: String? = nil,
        constants: [String: Double] = [:]
    ) {
        self.label = label
        self.layout = layout
        self.module = module
        self.entryPoint = entryPoint
        self.constants = constants
    }
}

/// Compiled compute pipeline state in Rune's Metal backend.
// PORT NOTE: Immutable `MTLComputePipelineState` wrapper; thread-safe across compute encoders.
public final class MetalComputePipeline: @unchecked Sendable {
    public let label: String?
    public let layout: MetalPipelineLayout
    public let workgroupSize: (UInt32, UInt32, UInt32)
    public let sizedSlots: [UInt8]
    #if canImport(Metal)
    public let mtlPipeline: (any MTLComputePipelineState)?
    #endif

    public init(device: MetalDevice, descriptor: MetalComputePipelineDescriptor) throws {
        self.label = descriptor.label
        let resolvedLayout: MetalPipelineLayout
        if let explicit = descriptor.layout {
            resolvedLayout = explicit
        } else {
            resolvedLayout = deriveMetalLayout([
                MetalStageSource(stage: .compute, module: descriptor.module, entryPoint: descriptor.entryPoint)
            ])
        }
        self.layout = resolvedLayout

        #if canImport(Metal)
        if let mtlDev = device.shared.mtlDevice {
            let (fn, comp) = try compileMetalStageFunction(
                device: mtlDev,
                module: descriptor.module,
                stage: .compute,
                entryPoint: descriptor.entryPoint,
                layout: resolvedLayout,
                constants: descriptor.constants
            )
            let wg = comp.workgroupSize
            self.workgroupSize = (
                max(1, wg.count > 0 ? wg[0] : 1),
                max(1, wg.count > 1 ? wg[1] : 1),
                max(1, wg.count > 2 ? wg[2] : 1)
            )
            self.sizedSlots = comp.sizedBufferSlots
            let cpDesc = MTLComputePipelineDescriptor()
            if let l = descriptor.label { cpDesc.label = l }
            cpDesc.computeFunction = fn
            self.mtlPipeline = try mtlDev.makeComputePipelineState(descriptor: cpDesc, options: [], reflection: nil)
        } else {
            self.workgroupSize = (1, 1, 1)
            self.sizedSlots = []
            self.mtlPipeline = nil
        }
        #else
        _ = device
        self.workgroupSize = (1, 1, 1)
        self.sizedSlots = []
        #endif
    }

    public func getBindGroupLayout(_ index: Int) -> MetalBindGroupLayout {
        if index >= 0 && index < layout.groups.count {
            return layout.groups[index]
        }
        return MetalBindGroupLayout(entries: [])
    }
}

/// Recorded compute pass writing into an owning `MetalCommandEncoder`.
public final class MetalComputePass {
    private struct TrackedGroup {
        var group: MetalBindGroup
        var dynamicOffsets: [UInt32]
        var retainedRaws: [MetalRawBuffer]
        var dirty: Bool
    }

    private let owner: MetalCommandEncoder
    let keep: MetalKeepList
    private let timestampWrites: MetalPassTimestampWrites?
    private var pipeline: MetalComputePipeline?
    private var pipelineDirty: Bool = false
    private var boundGroups: [Int: TrackedGroup] = [:]
    private var immediateBytes: [UInt8] = []
    private var immediatesDirty: Bool = false
    private var ended: Bool = false
    #if canImport(Metal)
    private var mtlEncoder: (any MTLComputeCommandEncoder)?
    #endif

    init(
        owner: MetalCommandEncoder,
        label: String?,
        timestampWrites: MetalPassTimestampWrites?
    ) {
        self.owner = owner
        self.keep = owner.shared.takeKeepList()
        self.timestampWrites = timestampWrites

        if let tw = timestampWrites {
            keep.keep(tw.querySet)
            if let beg = tw.beginningIndex {
                tw.querySet.recordFallbackTimestamp(at: beg, nanoseconds: metalMonotonicNanoseconds())
            }
        }

        #if canImport(Metal)
        if let cb = owner.ensureCommandBuffer() {
            let desc = MTLComputePassDescriptor()
            if let tw = timestampWrites, let counterBuf = tw.querySet.counterBuffer {
                desc.sampleBufferAttachments[0].sampleBuffer = counterBuf
                desc.sampleBufferAttachments[0].startOfEncoderSampleIndex = tw.beginningIndex ?? MTLCounterDontSample
                desc.sampleBufferAttachments[0].endOfEncoderSampleIndex = tw.endIndex ?? MTLCounterDontSample
            }
            let enc = cb.makeComputeCommandEncoder(descriptor: desc)
            if let label, let enc { enc.label = label }
            self.mtlEncoder = enc
        } else {
            self.mtlEncoder = nil
        }
        #else
        _ = label
        #endif
    }

    deinit {
        end()
    }

    public func setPipeline(_ pipeline: MetalComputePipeline) {
        self.pipeline = pipeline
        self.pipelineDirty = true
        keep.keep(pipeline)
    }

    public func setBindGroup(_ index: Int, _ group: MetalBindGroup, dynamicOffsets: [UInt32] = []) {
        keep.keep(group)
        var raws: [MetalRawBuffer] = []
        raws.reserveCapacity(group.buffers.count)
        for b in group.buffers {
            let raw = b.buffer.store.retainForRecording()
            keep.keepRawBuffer(store: b.buffer.store, raw: raw)
            raws.append(raw)
        }
        for t in group.textures {
            keep.keep(t.view)
            keep.keep(t.view.raw)
            if let extOwner = t.view.raw.owner {
                keep.keep(extOwner)
            }
        }
        for s in group.samplers {
            keep.keep(s.sampler)
        }
        boundGroups[index] = TrackedGroup(
            group: group,
            dynamicOffsets: dynamicOffsets,
            retainedRaws: raws,
            dirty: true
        )
    }

    public func setImmediates(offset: Int = 0, data: [UInt8]) {
        guard !data.isEmpty else { return }
        let needed = offset + data.count
        if immediateBytes.count < needed {
            immediateBytes.append(contentsOf: repeatElement(0, count: needed - immediateBytes.count))
        }
        immediateBytes.replaceSubrange(offset..<needed, with: data)
        immediatesDirty = true
    }

    public func dispatchWorkgroups(_ x: UInt32, _ y: UInt32 = 1, _ z: UInt32 = 1) {
        guard x > 0 && y > 0 && z > 0, let pipe = pipeline else { return }
        #if canImport(Metal)
        guard let enc = mtlEncoder, let mtlPipe = pipe.mtlPipeline else { return }
        if pipelineDirty {
            enc.setComputePipelineState(mtlPipe)
        }

        let layout = pipe.layout
        let sizesSlot = Int(layout.sizesSlot)
        var bufferSizes = [UInt32](repeating: 0, count: max(1, sizesSlot))
        var anySizedChanged = pipelineDirty

        for gIdx in 0..<layout.groups.count {
            guard var tracked = boundGroups[gIdx] else { continue }
            let base = layout.bases[gIdx]

            // Check whether any bound buffer swapped its underlying allocation mid-pass
            var swapped = false
            for i in 0..<tracked.group.buffers.count {
                let b = tracked.group.buffers[i]
                let active = b.buffer.store.activeRaw
                if active !== tracked.retainedRaws[i] {
                    let newlyRetained = b.buffer.store.retainForRecording()
                    keep.keepRawBuffer(store: b.buffer.store, raw: newlyRetained)
                    tracked.retainedRaws[i] = newlyRetained
                    swapped = true
                }
            }

            if pipelineDirty || tracked.dirty || swapped {
                for (i, b) in tracked.group.buffers.enumerated() {
                    let slot = Int(base.buffers &+ b.relativeSlot)
                    let dynOff: UInt64 = {
                        if let di = b.dynamicIndex, di < tracked.dynamicOffsets.count {
                            return UInt64(tracked.dynamicOffsets[di])
                        }
                        return 0
                    }()
                    let totalOffset = Int(b.offset + dynOff)
                    if let mtlBuf = tracked.retainedRaws[i].mtlBuffer {
                        enc.setBuffer(mtlBuf, offset: totalOffset, index: slot)
                    }
                }
                for t in tracked.group.textures {
                    let slot = Int(base.textures &+ t.relativeSlot)
                    enc.setTexture(t.view.mtlTexture, index: slot)
                }
                for s in tracked.group.samplers {
                    let slot = Int(base.samplers &+ s.relativeSlot)
                    enc.setSamplerState(s.sampler.mtlSampler, index: slot)
                }
                tracked.dirty = false
                boundGroups[gIdx] = tracked
                anySizedChanged = true
            }

            if !pipe.sizedSlots.isEmpty {
                for b in tracked.group.buffers where b.sized {
                    let slot = Int(base.buffers &+ b.relativeSlot)
                    if slot < bufferSizes.count {
                        bufferSizes[slot] = UInt32(truncatingIfNeeded: b.boundSize)
                    }
                }
            }
        }

        if let immSlot = layout.immediateSlot, (pipelineDirty || immediatesDirty), !immediateBytes.isEmpty {
            immediateBytes.withUnsafeBytes { raw in
                if let ptr = raw.baseAddress {
                    enc.setBytes(ptr, length: raw.count, index: Int(immSlot))
                }
            }
            immediatesDirty = false
        }

        if !pipe.sizedSlots.isEmpty && anySizedChanged {
            bufferSizes.withUnsafeBytes { raw in
                if let ptr = raw.baseAddress {
                    enc.setBytes(ptr, length: raw.count, index: sizesSlot)
                }
            }
        }

        pipelineDirty = false
        let wg = pipe.workgroupSize
        enc.dispatchThreadgroups(
            MTLSize(width: Int(x), height: Int(y), depth: Int(z)),
            threadsPerThreadgroup: MTLSize(width: Int(wg.0), height: Int(wg.1), depth: Int(wg.2))
        )
        #endif
    }

    public func end() {
        guard !ended else { return }
        ended = true
        if let tw = timestampWrites, let endIdx = tw.endIndex {
            tw.querySet.recordFallbackTimestamp(at: endIdx, nanoseconds: metalMonotonicNanoseconds())
        }
        #if canImport(Metal)
        mtlEncoder?.endEncoding()
        mtlEncoder = nil
        #endif
        owner.finishPassKeep(keep)
    }
}

func metalMonotonicNanoseconds() -> UInt64 {
    #if !os(WASI)
    return DispatchTime.now().uptimeNanoseconds
    #else
    return 1
    #endif
}
