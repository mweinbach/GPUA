// Ported from: crates/rune/src/render/surface_alpha.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Straight-alpha surface conversion for post-multiplied translucent swapchains.

import CWebGPU

private let ALPHA_SURFACE_WGSL: String = """
@group(0) @binding(0) var source: texture_2d<f32>;

@vertex
fn vs(@builtin(vertex_index) index: u32) -> @builtin(position) vec4<f32> {
    return vec4<f32>(f32((index << 1u) & 2u) * 2.0 - 1.0, f32(index & 2u) * 2.0 - 1.0, 0.0, 1.0);
}

@fragment
fn fs(@builtin(position) point: vec4<f32>) -> @location(0) vec4<f32> {
    let color = textureLoad(source, vec2<i32>(point.xy), 0);
    if (color.a > 0.0) {
        return vec4<f32>(color.rgb / color.a, color.a);
    }
    return vec4<f32>(0.0);
}
"""

public final class AlphaSurface {
    public let format: WGPUTextureFormat
    private let layout: MetalBindGroupLayout
    private let pipeline: MetalRenderPipeline
    public private(set) var texture: MetalTexture
    public private(set) var view: MetalView
    private var bind: MetalBindGroup
    public private(set) var size: (UInt32, UInt32)

    public init(_ device: MetalDevice, _ format: WGPUTextureFormat, _ width: UInt32, _ height: UInt32) {
        self.format = format
        let w = max(width, 1)
        let h = max(height, 1)
        self.size = (w, h)

        let bgl = device.createBindGroupLayout(
            label: "alpha-surface",
            entries: [
                MetalBindGroupLayoutEntry(
                    binding: 0,
                    visibility: .fragment,
                    ty: .texture(multisampled: false)
                )
            ]
        )
        let pl = device.createPipelineLayout(label: "alpha-surface", bindGroupLayouts: [bgl])
        let shader = device.createShaderModule(label: "alpha-surface", wgsl: ALPHA_SURFACE_WGSL)
        let desc = MetalRenderPipelineDescriptor(
            label: "alpha-surface",
            layout: pl,
            vertexModule: shader,
            vertexEntryPoint: "vs",
            fragmentModule: shader,
            fragmentEntryPoint: "fs",
            colorTargets: [MetalColorTargetState(format: format, blend: .replace)],
            topology: .triangleList
        )
        do {
            self.pipeline = try device.createRenderPipeline(desc)
        } catch {
            fatalError("AlphaSurface pipeline compilation failed: \(error)")
        }
        self.layout = bgl

        let tex = Self.makeTexture(device, format, w, h)
        let v = tex.createView()
        self.texture = tex
        self.view = v
        self.bind = device.createBindGroup(
            label: "alpha-surface",
            layout: bgl,
            entries: [.textureView(binding: 0, v)]
        )
    }

    public static func new(
        _ device: MetalDevice,
        _ format: WGPUTextureFormat,
        _ width: UInt32,
        _ height: UInt32
    ) -> AlphaSurface {
        AlphaSurface(device, format, width, height)
    }

    private static func makeTexture(
        _ device: MetalDevice,
        _ format: WGPUTextureFormat,
        _ width: UInt32,
        _ height: UInt32
    ) -> MetalTexture {
        device.createTexture(
            label: "alpha-surface-source",
            format: format,
            width: width,
            height: height,
            usage: UInt32(WGPUTextureUsage_RenderAttachment | WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopySrc)
        )
    }

    @discardableResult
    public func resize(_ device: MetalDevice, _ width: UInt32, _ height: UInt32) -> MetalView {
        let w = max(width, 1)
        let h = max(height, 1)
        if size != (w, h) {
            size = (w, h)
            texture = Self.makeTexture(device, format, w, h)
            view = texture.createView()
            bind = device.createBindGroup(
                label: "alpha-surface",
                layout: layout,
                entries: [.textureView(binding: 0, view)]
            )
        }
        return view
    }

    public func draw(_ encoder: MetalCommandEncoder, _ target: MetalView) {
        let pass = encoder.beginRenderPass(
            label: "alpha-surface",
            colorAttachment: MetalRenderPassColorAttachment(
                view: target,
                loadOp: .clear(r: 0, g: 0, b: 0, a: 0),
                storeOp: .store
            )
        )
        pass.setPipeline(pipeline)
        pass.setBindGroup(0, bind)
        pass.draw(vertices: 0..<3, instances: 0..<1)
        pass.end()
    }
}
