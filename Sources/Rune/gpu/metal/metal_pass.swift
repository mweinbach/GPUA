// Ported from: crates/rune/src/gpu/metal/pass.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Render passes (`MetalRenderPass`) in Rune's Metal backend, supporting multiple color attachments,
//! out-of-order `setBindGroup` / `setPipeline`, vertex buffers at `buffer(30 - index)`, dynamic
//! uniform/storage offsets, `_buffer_sizes`, mid-pass buffer swap rebinding, scissor/viewport,
//! and stage-boundary timestamp sampling.

#if canImport(Metal)
import Metal
#endif
#if !os(WASI)
import Foundation
#endif

public enum MetalLoadAction: Sendable, Equatable {
    case clear(r: Double, g: Double, b: Double, a: Double)
    case load
}

public typealias MetalLoadOp = MetalLoadAction

public enum MetalStoreOp: Sendable, Equatable {
    case store
    case discard
}

public struct MetalColorAttachment: Sendable {
    public var view: MetalView
    public var load: MetalLoadAction
    public var store: Bool

    public init(view: MetalView, load: MetalLoadAction, store: Bool = true) {
        self.view = view
        self.load = load
        self.store = store
    }

    public init(view: MetalView, loadOp: MetalLoadAction, storeOp: MetalStoreOp = .store) {
        self.view = view
        self.load = loadOp
        self.store = (storeOp == .store)
    }
}

public typealias MetalRenderPassColorAttachment = MetalColorAttachment

/// Recorded render pass writing into an owning `MetalCommandEncoder`.
public final class MetalRenderPass {
    private struct TrackedGroup {
        var group: MetalBindGroup
        var dynamicOffsets: [UInt32]
        var retainedRaws: [MetalRawBuffer]
        var dirty: Bool
    }

    private struct BoundVertexBuffer {
        var buffer: MetalBuffer
        var offset: Int
        var retainedRaw: MetalRawBuffer
        var dirty: Bool
    }

    private let owner: MetalCommandEncoder
    let keep: MetalKeepList
    private let timestampWrites: MetalPassTimestampWrites?
    private let attachmentWidth: UInt32
    private let attachmentHeight: UInt32
    private var pipeline: MetalRenderPipeline?
    private var pipelineDirty: Bool = false
    private var boundGroups: [Int: TrackedGroup] = [:]
    private var vertexBuffers: [Int: BoundVertexBuffer] = [:]
    private var immediateBytes: [UInt8] = []
    private var immediatesDirty: Bool = false
    private var ended: Bool = false
    #if canImport(Metal)
    private var mtlEncoder: (any MTLRenderCommandEncoder)?
    #endif

    init(
        owner: MetalCommandEncoder,
        label: String?,
        colorAttachments: [MetalColorAttachment?],
        timestampWrites: MetalPassTimestampWrites?
    ) {
        self.owner = owner
        self.keep = owner.shared.takeKeepList()
        self.timestampWrites = timestampWrites

        var w: UInt32 = 1
        var h: UInt32 = 1
        for att in colorAttachments.compactMap({ $0 }) {
            keep.keep(att.view)
            keep.keep(att.view.raw)
            if let extOwner = att.view.raw.owner {
                keep.keep(extOwner)
            }
            let mipW = max(1, att.view.raw.width >> att.view.baseMipLevel)
            let mipH = max(1, att.view.raw.height >> att.view.baseMipLevel)
            w = mipW
            h = mipH
        }
        self.attachmentWidth = w
        self.attachmentHeight = h

        if let tw = timestampWrites {
            keep.keep(tw.querySet)
            if let beg = tw.beginningIndex {
                tw.querySet.recordFallbackTimestamp(at: beg, nanoseconds: metalMonotonicNanoseconds())
            }
        }

        #if canImport(Metal)
        if let cb = owner.ensureCommandBuffer() {
            let rpDesc = MTLRenderPassDescriptor()
            for (idx, maybeAtt) in colorAttachments.enumerated() {
                guard let att = maybeAtt else { continue }
                let ca = rpDesc.colorAttachments[idx]!
                ca.texture = att.view.mtlTexture
                switch att.load {
                case .clear(let r, let g, let b, let a):
                    ca.loadAction = .clear
                    ca.clearColor = MTLClearColor(red: r, green: g, blue: b, alpha: a)
                case .load:
                    ca.loadAction = .load
                }
                ca.storeAction = att.store ? .store : .dontCare
            }
            if let tw = timestampWrites, let counterBuf = tw.querySet.counterBuffer {
                rpDesc.sampleBufferAttachments[0].sampleBuffer = counterBuf
                rpDesc.sampleBufferAttachments[0].startOfVertexSampleIndex = tw.beginningIndex ?? MTLCounterDontSample
                rpDesc.sampleBufferAttachments[0].endOfFragmentSampleIndex = tw.endIndex ?? MTLCounterDontSample
            }
            let enc = cb.makeRenderCommandEncoder(descriptor: rpDesc)
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

    public func setPipeline(_ pipeline: MetalRenderPipeline) {
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

    public func setVertexBuffer(_ slot: Int, _ buffer: MetalBuffer, offset: UInt64 = 0) {
        let raw = buffer.store.retainForRecording()
        keep.keepRawBuffer(store: buffer.store, raw: raw)
        vertexBuffers[slot] = BoundVertexBuffer(
            buffer: buffer,
            offset: Int(offset),
            retainedRaw: raw,
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

    public func setViewport(x: Float, y: Float, width: Float, height: Float, minDepth: Float = 0, maxDepth: Float = 1) {
        setViewport(x: x, y: y, w: width, h: height, minDepth: minDepth, maxDepth: maxDepth)
    }

    public func setViewport(x: Float, y: Float, w: Float, h: Float, minDepth: Float = 0, maxDepth: Float = 1) {
        #if canImport(Metal)
        mtlEncoder?.setViewport(
            MTLViewport(
                originX: Double(x),
                originY: Double(y),
                width: Double(w),
                height: Double(h),
                znear: Double(minDepth),
                zfar: Double(maxDepth)
            )
        )
        #endif
    }

    public func setScissorRect(x: UInt32, y: UInt32, width: UInt32, height: UInt32) {
        #if canImport(Metal)
        let clampedX = min(x, attachmentWidth)
        let clampedY = min(y, attachmentHeight)
        let maxW = attachmentWidth > clampedX ? attachmentWidth - clampedX : 0
        let maxH = attachmentHeight > clampedY ? attachmentHeight - clampedY : 0
        let clampedW = min(width, maxW)
        let clampedH = min(height, maxH)
        mtlEncoder?.setScissorRect(
            MTLScissorRect(
                x: Int(clampedX),
                y: Int(clampedY),
                width: Int(clampedW),
                height: Int(clampedH)
            )
        )
        #endif
    }

    public func draw(vertices: Range<UInt32>, instances: Range<UInt32> = 0..<1) {
        guard !vertices.isEmpty && !instances.isEmpty, let pipe = pipeline else { return }
        #if canImport(Metal)
        guard let enc = mtlEncoder, let mtlPipe = pipe.mtlPipeline else { return }
        if pipelineDirty {
            enc.setRenderPipelineState(mtlPipe)
        }

        // Bind vertex buffers (re-checking for mid-pass CoW swaps)
        for (vbSlot, var vb) in vertexBuffers {
            let active = vb.buffer.store.activeRaw
            var swapped = false
            if active !== vb.retainedRaw {
                let newlyRetained = vb.buffer.store.retainForRecording()
                keep.keepRawBuffer(store: vb.buffer.store, raw: newlyRetained)
                vb.retainedRaw = newlyRetained
                swapped = true
            }
            if pipelineDirty || vb.dirty || swapped {
                let mtlSlot = METAL_VERTEX_BUFFER_BASE_SLOT - vbSlot
                if let mtlBuf = vb.retainedRaw.mtlBuffer {
                    enc.setVertexBuffer(mtlBuf, offset: vb.offset, index: mtlSlot)
                }
                vb.dirty = false
                vertexBuffers[vbSlot] = vb
            }
        }

        // Bind resource groups (re-checking for mid-pass CoW swaps as tested in `a_pass_rebinds_a_buffer_swapped_under_it`)
        let layout = pipe.layout
        let sizesSlot = Int(layout.sizesSlot)
        let needsSizes = !pipe.vsSizedSlots.isEmpty || !pipe.fsSizedSlots.isEmpty
        var bufferSizes = [UInt32](repeating: 0, count: max(1, sizesSlot))
        var anySizedChanged = pipelineDirty

        for gIdx in 0..<layout.groups.count {
            guard var tracked = boundGroups[gIdx] else { continue }
            let base = layout.bases[gIdx]
            let groupStages = layout.groups[gIdx].stages

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
                        if groupStages.contains(.vertex) {
                            enc.setVertexBuffer(mtlBuf, offset: totalOffset, index: slot)
                        }
                        if groupStages.contains(.fragment) {
                            enc.setFragmentBuffer(mtlBuf, offset: totalOffset, index: slot)
                        }
                    }
                }
                for t in tracked.group.textures {
                    let slot = Int(base.textures &+ t.relativeSlot)
                    if groupStages.contains(.vertex) {
                        enc.setVertexTexture(t.view.mtlTexture, index: slot)
                    }
                    if groupStages.contains(.fragment) {
                        enc.setFragmentTexture(t.view.mtlTexture, index: slot)
                    }
                }
                for s in tracked.group.samplers {
                    let slot = Int(base.samplers &+ s.relativeSlot)
                    if groupStages.contains(.vertex) {
                        enc.setVertexSamplerState(s.sampler.mtlSampler, index: slot)
                    }
                    if groupStages.contains(.fragment) {
                        enc.setFragmentSamplerState(s.sampler.mtlSampler, index: slot)
                    }
                }
                tracked.dirty = false
                boundGroups[gIdx] = tracked
                anySizedChanged = true
            }

            if needsSizes {
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
                    enc.setVertexBytes(ptr, length: raw.count, index: Int(immSlot))
                    enc.setFragmentBytes(ptr, length: raw.count, index: Int(immSlot))
                }
            }
            immediatesDirty = false
        }

        if needsSizes && anySizedChanged {
            bufferSizes.withUnsafeBytes { raw in
                if let ptr = raw.baseAddress {
                    if !pipe.vsSizedSlots.isEmpty {
                        enc.setVertexBytes(ptr, length: raw.count, index: sizesSlot)
                    }
                    if !pipe.fsSizedSlots.isEmpty {
                        enc.setFragmentBytes(ptr, length: raw.count, index: sizesSlot)
                    }
                }
            }
        }

        pipelineDirty = false
        let primType: MTLPrimitiveType
        switch pipe.topology {
        case .triangleList: primType = .triangle
        case .triangleStrip: primType = .triangleStrip
        case .pointList: primType = .point
        case .lineList: primType = .line
        }
        enc.drawPrimitives(
            type: primType,
            vertexStart: Int(vertices.lowerBound),
            vertexCount: vertices.count,
            instanceCount: instances.count,
            baseInstance: Int(instances.lowerBound)
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
