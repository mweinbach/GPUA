// Ported from: crates/rune/src/gpu/metal/pipeline.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Render and compute pipeline descriptors and compiled pipeline state objects (`MetalRenderPipeline`,
//! `MetalComputePipeline`), including automatic layout derivation (`layout: nil`) and vertex
//! buffer layout mapping (`buffer(30 - vbIndex)`).

#if canImport(Metal)
import Metal
#endif
import CWebGPU

public enum MetalVertexFormat: Sendable, Equatable {
    case float32
    case float32x2
    case float32x3
    case float32x4
    case uint32
    case uint32x2
    case uint32x3
    case uint32x4
    case sint32
    case sint32x2
    case sint32x3
    case sint32x4

    public var byteSize: Int {
        switch self {
        case .float32, .uint32, .sint32: return 4
        case .float32x2, .uint32x2, .sint32x2: return 8
        case .float32x3, .uint32x3, .sint32x3: return 12
        case .float32x4, .uint32x4, .sint32x4: return 16
        }
    }

    #if canImport(Metal)
    var mtlFormat: MTLVertexFormat {
        switch self {
        case .float32: return .float
        case .float32x2: return .float2
        case .float32x3: return .float3
        case .float32x4: return .float4
        case .uint32: return .uint
        case .uint32x2: return .uint2
        case .uint32x3: return .uint3
        case .uint32x4: return .uint4
        case .sint32: return .int
        case .sint32x2: return .int2
        case .sint32x3: return .int3
        case .sint32x4: return .int4
        }
    }
    #endif
}

public struct MetalVertexAttribute: Sendable, Equatable {
    public var shaderLocation: UInt32
    public var offset: Int
    public var format: MetalVertexFormat

    public init(shaderLocation: UInt32, offset: Int, format: MetalVertexFormat) {
        self.shaderLocation = shaderLocation
        self.offset = offset
        self.format = format
    }
}

public enum MetalVertexStepMode: Sendable, Equatable {
    case vertex
    case instance
}

public struct MetalVertexBufferLayout: Sendable, Equatable {
    public var arrayStride: Int
    public var stepMode: MetalVertexStepMode
    public var attributes: [MetalVertexAttribute]

    public init(arrayStride: Int, stepMode: MetalVertexStepMode = .vertex, attributes: [MetalVertexAttribute]) {
        self.arrayStride = arrayStride
        self.stepMode = stepMode
        self.attributes = attributes
    }
}

public enum MetalBlendStyle: Sendable, Equatable {
    case replace
    case alphaBlending
    case premultipliedAlpha
    case plusLighter
}

public struct MetalColorTargetState: Sendable, Equatable {
    public var format: WGPUTextureFormat
    public var blend: MetalBlendStyle

    public init(format: WGPUTextureFormat, blend: MetalBlendStyle = .replace) {
        self.format = format
        self.blend = blend
    }
}

public enum MetalPrimitiveTopology: Sendable, Equatable {
    case triangleList
    case triangleStrip
    case pointList
    case lineList
}

public struct MetalRenderPipelineDescriptor {
    public var label: String?
    public var layout: MetalPipelineLayout?
    public var vertexModule: MetalShaderModule
    public var vertexEntryPoint: String?
    public var vertexConstants: [String: Double]
    public var vertexBuffers: [MetalVertexBufferLayout]
    public var fragmentModule: MetalShaderModule?
    public var fragmentEntryPoint: String?
    public var fragmentConstants: [String: Double]
    public var colorTargets: [MetalColorTargetState]
    public var topology: MetalPrimitiveTopology

    public init(
        label: String? = nil,
        layout: MetalPipelineLayout? = nil,
        vertexModule: MetalShaderModule,
        vertexEntryPoint: String? = nil,
        vertexConstants: [String: Double] = [:],
        vertexBuffers: [MetalVertexBufferLayout] = [],
        fragmentModule: MetalShaderModule? = nil,
        fragmentEntryPoint: String? = nil,
        fragmentConstants: [String: Double] = [:],
        colorTargets: [MetalColorTargetState] = [],
        topology: MetalPrimitiveTopology = .triangleList
    ) {
        self.label = label
        self.layout = layout
        self.vertexModule = vertexModule
        self.vertexEntryPoint = vertexEntryPoint
        self.vertexConstants = vertexConstants
        self.vertexBuffers = vertexBuffers
        self.fragmentModule = fragmentModule
        self.fragmentEntryPoint = fragmentEntryPoint
        self.fragmentConstants = fragmentConstants
        self.colorTargets = colorTargets
        self.topology = topology
    }
}

/// First Metal buffer slot reserved downward (`30, 29, ...`) for vertex buffers so they never collide with bind groups.
public let METAL_VERTEX_BUFFER_BASE_SLOT: Int = 30

/// Compiled render pipeline state in Rune's Metal backend.
// PORT NOTE: Immutable `MTLRenderPipelineState` wrapper; thread-safe across render encoders.
public final class MetalRenderPipeline: @unchecked Sendable {
    public let label: String?
    public let layout: MetalPipelineLayout
    public let topology: MetalPrimitiveTopology
    public let vsSizedSlots: [UInt8]
    public let fsSizedSlots: [UInt8]
    #if canImport(Metal)
    public let mtlPipeline: (any MTLRenderPipelineState)?
    #endif

    public init(device: MetalDevice, descriptor: MetalRenderPipelineDescriptor) throws {
        self.label = descriptor.label
        self.topology = descriptor.topology

        let resolvedLayout: MetalPipelineLayout
        if let explicit = descriptor.layout {
            resolvedLayout = explicit
        } else {
            var stages: [MetalStageSource] = [
                MetalStageSource(stage: .vertex, module: descriptor.vertexModule, entryPoint: descriptor.vertexEntryPoint)
            ]
            if let fm = descriptor.fragmentModule {
                stages.append(MetalStageSource(stage: .fragment, module: fm, entryPoint: descriptor.fragmentEntryPoint))
            }
            resolvedLayout = deriveMetalLayout(stages)
        }
        self.layout = resolvedLayout

        #if canImport(Metal)
        if let mtlDev = device.shared.mtlDevice {
            let (vsFn, vsComp) = try compileMetalStageFunction(
                device: mtlDev,
                module: descriptor.vertexModule,
                stage: .vertex,
                entryPoint: descriptor.vertexEntryPoint,
                layout: resolvedLayout,
                constants: descriptor.vertexConstants
            )
            self.vsSizedSlots = vsComp.sizedBufferSlots

            let rpDesc = MTLRenderPipelineDescriptor()
            if let l = descriptor.label { rpDesc.label = l }
            rpDesc.vertexFunction = vsFn

            if !descriptor.vertexBuffers.isEmpty {
                let vDesc = MTLVertexDescriptor()
                for (vbIdx, vb) in descriptor.vertexBuffers.enumerated() {
                    let slot = METAL_VERTEX_BUFFER_BASE_SLOT - vbIdx
                    vDesc.layouts[slot].stride = vb.arrayStride
                    vDesc.layouts[slot].stepFunction = vb.stepMode == .instance ? .perInstance : .perVertex
                    vDesc.layouts[slot].stepRate = 1
                    for attr in vb.attributes {
                        let aIdx = Int(attr.shaderLocation)
                        vDesc.attributes[aIdx].format = attr.format.mtlFormat
                        vDesc.attributes[aIdx].offset = attr.offset
                        vDesc.attributes[aIdx].bufferIndex = slot
                    }
                }
                rpDesc.vertexDescriptor = vDesc
            }

            if let fm = descriptor.fragmentModule {
                let (fsFn, fsComp) = try compileMetalStageFunction(
                    device: mtlDev,
                    module: fm,
                    stage: .fragment,
                    entryPoint: descriptor.fragmentEntryPoint,
                    layout: resolvedLayout,
                    constants: descriptor.fragmentConstants
                )
                self.fsSizedSlots = fsComp.sizedBufferSlots
                rpDesc.fragmentFunction = fsFn
            } else {
                self.fsSizedSlots = []
            }

            for (idx, ct) in descriptor.colorTargets.enumerated() {
                let att = rpDesc.colorAttachments[idx]!
                att.pixelFormat = metalPixelFormat(for: ct.format)
                switch ct.blend {
                case .replace:
                    att.isBlendingEnabled = false
                case .alphaBlending:
                    att.isBlendingEnabled = true
                    att.sourceRGBBlendFactor = .sourceAlpha
                    att.destinationRGBBlendFactor = .oneMinusSourceAlpha
                    att.rgbBlendOperation = .add
                    att.sourceAlphaBlendFactor = .one
                    att.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                    att.alphaBlendOperation = .add
                case .premultipliedAlpha:
                    att.isBlendingEnabled = true
                    att.sourceRGBBlendFactor = .one
                    att.destinationRGBBlendFactor = .oneMinusSourceAlpha
                    att.rgbBlendOperation = .add
                    att.sourceAlphaBlendFactor = .one
                    att.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                    att.alphaBlendOperation = .add
                case .plusLighter:
                    att.isBlendingEnabled = true
                    att.sourceRGBBlendFactor = .one
                    att.destinationRGBBlendFactor = .one
                    att.rgbBlendOperation = .add
                    att.sourceAlphaBlendFactor = .one
                    att.destinationAlphaBlendFactor = .one
                    att.alphaBlendOperation = .add
                }
            }

            self.mtlPipeline = try mtlDev.makeRenderPipelineState(descriptor: rpDesc)
        } else {
            self.vsSizedSlots = []
            self.fsSizedSlots = []
            self.mtlPipeline = nil
        }
        #else
        _ = device
        self.vsSizedSlots = []
        self.fsSizedSlots = []
        #endif
    }

    public func getBindGroupLayout(_ index: Int) -> MetalBindGroupLayout {
        if index >= 0 && index < layout.groups.count {
            return layout.groups[index]
        }
        return MetalBindGroupLayout(entries: [])
    }
}
