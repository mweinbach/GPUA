// Ported from: crates/rune/src/gpu/metal/layout.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Bind group layouts, pipeline layouts, and bind groups for Rune's Metal backend, assigning
//! contiguous Metal buffer, texture, and sampler indices across bind groups plus optional
//! immediate data and `_buffer_sizes` slots.

/// Shader stage visibility bitset matching `wgpu::ShaderStages`.
public struct MetalShaderStages: OptionSet, Sendable, Equatable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let vertex = MetalShaderStages(rawValue: 1 << 0)
    public static let fragment = MetalShaderStages(rawValue: 1 << 1)
    public static let compute = MetalShaderStages(rawValue: 1 << 2)
    public static let vertexFragment: MetalShaderStages = [.vertex, .fragment]
    public static let all: MetalShaderStages = [.vertex, .fragment, .compute]
}

/// Per-group resource slot counts in Metal's flat buffer/texture/sampler tables.
public struct MetalResourceCounts: Sendable, Equatable, Hashable {
    public var buffers: UInt8
    public var textures: UInt8
    public var samplers: UInt8

    public init(buffers: UInt8 = 0, textures: UInt8 = 0, samplers: UInt8 = 0) {
        self.buffers = buffers
        self.textures = textures
        self.samplers = samplers
    }

    public static func + (lhs: MetalResourceCounts, rhs: MetalResourceCounts) -> MetalResourceCounts {
        MetalResourceCounts(
            buffers: lhs.buffers &+ rhs.buffers,
            textures: lhs.textures &+ rhs.textures,
            samplers: lhs.samplers &+ rhs.samplers
        )
    }
}

/// Kind of binding in a `MetalBindGroupLayoutEntry`.
public enum MetalBindingType: Sendable, Equatable, Hashable {
    case uniformBuffer(hasDynamicOffset: Bool)
    case storageBuffer(readOnly: Bool, hasDynamicOffset: Bool)
    case texture(multisampled: Bool)
    case storageTexture(formatName: String, writeOnly: Bool)
    case sampler
}

/// Single entry in a `MetalBindGroupLayout`.
public struct MetalBindGroupLayoutEntry: Sendable, Equatable, Hashable {
    public var binding: UInt32
    public var visibility: MetalShaderStages
    public var ty: MetalBindingType

    public init(binding: UInt32, visibility: MetalShaderStages, ty: MetalBindingType) {
        self.binding = binding
        self.visibility = visibility
        self.ty = ty
    }
}

/// Assigned Metal slot within a group (`buffer`, `texture`, or `sampler` relative to group base).
public enum MetalAssignedSlot: Sendable, Equatable, Hashable {
    case buffer(index: UInt8, dynamicIndex: Int?, sized: Bool, mutable: Bool)
    case texture(index: UInt8, mutable: Bool)
    case sampler(index: UInt8)
}

/// Bind group layout mapping WGSL `@binding(n)` numbers to relative Metal table offsets.
public final class MetalBindGroupLayout: Sendable {
    public let label: String?
    public let entries: [MetalBindGroupLayoutEntry]
    public let counts: MetalResourceCounts
    public let slotsByBinding: [UInt32: MetalAssignedSlot]
    public let dynamicBufferCount: Int
    public let stages: MetalShaderStages

    public init(label: String? = nil, entries: [MetalBindGroupLayoutEntry]) {
        self.label = label
        let sorted = entries.sorted { $0.binding < $1.binding }
        self.entries = sorted

        var counts = MetalResourceCounts()
        var slots: [UInt32: MetalAssignedSlot] = [:]
        var dynCount = 0
        var stages: MetalShaderStages = []

        for entry in sorted {
            stages.formUnion(entry.visibility)
            switch entry.ty {
            case .uniformBuffer(let dyn):
                let dynIdx: Int? = dyn ? dynCount : nil
                if dyn { dynCount += 1 }
                slots[entry.binding] = .buffer(index: counts.buffers, dynamicIndex: dynIdx, sized: false, mutable: false)
                counts.buffers &+= 1
            case .storageBuffer(let readOnly, let dyn):
                let dynIdx: Int? = dyn ? dynCount : nil
                if dyn { dynCount += 1 }
                slots[entry.binding] = .buffer(index: counts.buffers, dynamicIndex: dynIdx, sized: true, mutable: !readOnly)
                counts.buffers &+= 1
            case .texture:
                slots[entry.binding] = .texture(index: counts.textures, mutable: false)
                counts.textures &+= 1
            case .storageTexture(_, let writeOnly):
                slots[entry.binding] = .texture(index: counts.textures, mutable: writeOnly || true)
                counts.textures &+= 1
            case .sampler:
                slots[entry.binding] = .sampler(index: counts.samplers)
                counts.samplers &+= 1
            }
        }

        self.counts = counts
        self.slotsByBinding = slots
        self.dynamicBufferCount = dynCount
        self.stages = stages
    }
}

/// Pipeline layout assigning per-group Metal base offsets, immediate buffer slot, and `_buffer_sizes` slot.
public final class MetalPipelineLayout: Sendable {
    public let label: String?
    public let groups: [MetalBindGroupLayout]
    public let bases: [MetalResourceCounts]
    public let totals: MetalResourceCounts
    public let stages: MetalShaderStages
    public let immediateSize: UInt32
    public let immediateSlot: UInt8?
    public let sizesSlot: UInt8

    public init(label: String? = nil, bindGroupLayouts: [MetalBindGroupLayout?], immediateSize: UInt32 = 0) {
        self.label = label
        var concreteGroups: [MetalBindGroupLayout] = []
        var bases: [MetalResourceCounts] = []
        var running = MetalResourceCounts()
        var stages: MetalShaderStages = []

        for maybeGroup in bindGroupLayouts {
            let g = maybeGroup ?? MetalBindGroupLayout(entries: [])
            concreteGroups.append(g)
            bases.append(running)
            running = running + g.counts
            stages.formUnion(g.stages)
        }

        self.groups = concreteGroups
        self.bases = bases
        self.totals = running
        self.stages = stages
        self.immediateSize = immediateSize
        if immediateSize > 0 {
            self.immediateSlot = running.buffers
            self.sizesSlot = running.buffers &+ 1
        } else {
            self.immediateSlot = nil
            self.sizesSlot = running.buffers
        }
    }

    /// Resolves `(group, binding)` to the absolute Metal `(buffer, texture, sampler)` slot.
    public func metalSlot(group: UInt32, binding: UInt32) -> MetalAssignedSlot? {
        let g = Int(group)
        guard g >= 0 && g < groups.count, let rel = groups[g].slotsByBinding[binding] else {
            return nil
        }
        let base = bases[g]
        switch rel {
        case .buffer(let idx, let dyn, let sized, let mutable):
            return .buffer(index: base.buffers &+ idx, dynamicIndex: dyn, sized: sized, mutable: mutable)
        case .texture(let idx, let mutable):
            return .texture(index: base.textures &+ idx, mutable: mutable)
        case .sampler(let idx):
            return .sampler(index: base.samplers &+ idx)
        }
    }
}

/// Resource bound into a `MetalBindGroupEntry`.
public enum MetalBindingResource: Sendable {
    case buffer(buffer: MetalBuffer, offset: UInt64, size: UInt64?)
    case textureView(MetalView)
    case sampler(MetalSampler)
}

/// Single entry in `MetalBindGroupDescriptor`.
public struct MetalBindGroupEntry: Sendable {
    public var binding: UInt32
    public var resource: MetalBindingResource

    public init(binding: UInt32, resource: MetalBindingResource) {
        self.binding = binding
        self.resource = resource
    }

    public static func buffer(
        binding: UInt32,
        _ buffer: MetalBuffer,
        offset: UInt64 = 0,
        size: UInt64? = nil
    ) -> MetalBindGroupEntry {
        MetalBindGroupEntry(binding: binding, resource: .buffer(buffer: buffer, offset: offset, size: size))
    }

    public static func buffer(
        binding: UInt32,
        buffer: MetalBuffer,
        offset: UInt64 = 0,
        size: UInt64? = nil
    ) -> MetalBindGroupEntry {
        MetalBindGroupEntry(binding: binding, resource: .buffer(buffer: buffer, offset: offset, size: size))
    }

    public static func textureView(binding: UInt32, _ view: MetalView) -> MetalBindGroupEntry {
        MetalBindGroupEntry(binding: binding, resource: .textureView(view))
    }

    public static func textureView(binding: UInt32, view: MetalView) -> MetalBindGroupEntry {
        MetalBindGroupEntry(binding: binding, resource: .textureView(view))
    }

    public static func sampler(binding: UInt32, _ sampler: MetalSampler) -> MetalBindGroupEntry {
        MetalBindGroupEntry(binding: binding, resource: .sampler(sampler))
    }

    public static func sampler(binding: UInt32, sampler: MetalSampler) -> MetalBindGroupEntry {
        MetalBindGroupEntry(binding: binding, resource: .sampler(sampler))
    }
}

/// Concrete bind group holding bound buffers, texture views, and samplers in relative slot order.
public final class MetalBindGroup: Sendable {
    public struct BoundBuffer: Sendable {
        public let relativeSlot: UInt8
        public let buffer: MetalBuffer
        public let offset: UInt64
        public let boundSize: UInt64
        public let dynamicIndex: Int?
        public let sized: Bool
    }

    public struct BoundTexture: Sendable {
        public let relativeSlot: UInt8
        public let view: MetalView
    }

    public struct BoundSampler: Sendable {
        public let relativeSlot: UInt8
        public let sampler: MetalSampler
    }

    public let label: String?
    public let layout: MetalBindGroupLayout
    public let buffers: [BoundBuffer]
    public let textures: [BoundTexture]
    public let samplers: [BoundSampler]

    public init(label: String? = nil, layout: MetalBindGroupLayout, entries: [MetalBindGroupEntry]) {
        self.label = label
        self.layout = layout

        var bufs: [BoundBuffer] = []
        var texs: [BoundTexture] = []
        var smps: [BoundSampler] = []

        for entry in entries {
            guard let slot = layout.slotsByBinding[entry.binding] else { continue }
            switch (slot, entry.resource) {
            case let (.buffer(idx, dynIdx, sized, _), .buffer(buf, offset, explicitSize)):
                let effectiveSize = explicitSize ?? UInt64(max(0, buf.size - Int(offset)))
                bufs.append(
                    BoundBuffer(
                        relativeSlot: idx,
                        buffer: buf,
                        offset: offset,
                        boundSize: effectiveSize,
                        dynamicIndex: dynIdx,
                        sized: sized
                    )
                )
            case let (.texture(idx, _), .textureView(view)):
                texs.append(BoundTexture(relativeSlot: idx, view: view))
            case let (.sampler(idx), .sampler(smp)):
                smps.append(BoundSampler(relativeSlot: idx, sampler: smp))
            default:
                break
            }
        }

        self.buffers = bufs.sorted { $0.relativeSlot < $1.relativeSlot }
        self.textures = texs.sorted { $0.relativeSlot < $1.relativeSlot }
        self.samplers = smps.sorted { $0.relativeSlot < $1.relativeSlot }
    }
}
