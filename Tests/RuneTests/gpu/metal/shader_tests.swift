// Tests ported from: crates/rune/src/gpu/metal/shader_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Testing
import CWebGPU
#if canImport(Metal)
import Metal
#endif
@testable import Rune

@Suite("MetalShaderCompilationTests")
struct MetalShaderCompilationTests {
    #if canImport(Metal)
    @Test("WGSL shaders with overrides, immediates, vertex attributes, and compute kernels compile to MTLLibrary")
    func wgslShadersCompileToMetalLibraries() throws {
        let (device, _) = metalGpu()
        guard let mtlDev = device.shared.mtlDevice else { return }

        // 1. Override specialization constants (`MODE`, `ADDITIVE` like `layer_blur.wgsl`)
        let blurWgsl = """
        override MODE: u32 = 0u;
        override ADDITIVE: bool = false;
        struct Params { step: vec2<f32>, tint: vec4<f32> };
        @group(0) @binding(0) var<uniform> params: Params;
        @group(0) @binding(1) var src: texture_2d<f32>;
        @group(0) @binding(2) var smp: sampler;
        struct VOut { @builtin(position) pos: vec4<f32>, @location(0) uv: vec2<f32> };
        @vertex fn vs(@builtin(vertex_index) vi: u32) -> VOut {
            let uv = vec2<f32>(f32((vi << 1u) & 2u), f32(vi & 2u));
            var o: VOut;
            o.pos = vec4<f32>(uv * 2.0 - 1.0, 0.0, 1.0);
            o.uv = uv;
            return o;
        }
        @fragment fn fs(in: VOut) -> @location(0) vec4<f32> {
            var c = textureSample(src, smp, in.uv + params.step);
            if (MODE == 2u) {
                c = c * params.tint;
            }
            if (ADDITIVE) {
                c = vec4<f32>(c.rgb, 0.0);
            }
            return c;
        }
        """
        let blurMod = device.createShaderModule(wgsl: blurWgsl)
        let blurLayout = deriveMetalLayout([
            MetalStageSource(stage: .vertex, module: blurMod, entryPoint: "vs"),
            MetalStageSource(stage: .fragment, module: blurMod, entryPoint: "fs"),
        ])
        for (mode, add) in [(0.0, 0.0), (0.0, 1.0), (2.0, 0.0), (2.0, 1.0), (3.0, 0.0)] {
            let consts = ["MODE": mode, "ADDITIVE": add]
            let (_, vsComp) = try compileMetalStageFunction(
                device: mtlDev,
                module: blurMod,
                stage: .vertex,
                entryPoint: "vs",
                layout: blurLayout,
                constants: consts
            )
            let (_, fsComp) = try compileMetalStageFunction(
                device: mtlDev,
                module: blurMod,
                stage: .fragment,
                entryPoint: "fs",
                layout: blurLayout,
                constants: consts
            )
            #expect(!vsComp.mslSource.isEmpty)
            #expect(!fsComp.mslSource.isEmpty)
        }

        // 2. Immediate data (`var<immediate>`) + helper function
        let immWgsl = """
        struct Push { scale: vec4<f32> };
        var<immediate> push: Push;
        fn boost(v: vec4<f32>) -> vec4<f32> {
            return v * push.scale;
        }
        @vertex fn vs(@builtin(vertex_index) i: u32) -> @builtin(position) vec4<f32> {
            return vec4<f32>(f32(i & 1u) * 4.0 - 1.0, f32(i >> 1u) * 4.0 - 1.0, 0.0, 1.0);
        }
        @fragment fn fs() -> @location(0) vec4<f32> {
            return boost(vec4<f32>(0.5, 0.25, 0.75, 1.0));
        }
        """
        let immMod = device.createShaderModule(wgsl: immWgsl)
        let immPipe = try device.createRenderPipeline(
            MetalRenderPipelineDescriptor(
                layout: nil,
                vertexModule: immMod,
                vertexEntryPoint: "vs",
                fragmentModule: immMod,
                fragmentEntryPoint: "fs",
                colorTargets: [MetalColorTargetState(format: WGPUTextureFormat_RGBA8Unorm)]
            )
        )
        #expect(immPipe.layout.immediateSize == 16)
        #expect(immPipe.layout.immediateSlot == 0)

        // 3. Compute kernel using `springs.SHADER` types and `spring_sample` compiles cleanly to MSL 3.0!
        let springComputeWgsl = """
        \(springs.SHADER)
        @group(0) @binding(0) var<storage, read_write> out_xy: array<vec2<f32>>;
        @compute @workgroup_size(64)
        fn eval_springs(@builtin(global_invocation_id) id: vec3<u32>) {
            let node = spring_nodes[id.x];
            out_xy[id.x] = vec2<f32>(spring_sample(node.x, vec2<f32>(1.0, 0.5)).x, spring_sample(node.y, vec2<f32>(1.0, 0.5)).x);
        }
        """
        let springMod = device.createShaderModule(label: "springs", wgsl: springComputeWgsl)
        let springPipe = try device.createComputePipeline(
            MetalComputePipelineDescriptor(label: "springs", layout: nil, module: springMod, entryPoint: "eval_springs")
        )
        #expect(springPipe.workgroupSize == (64, 1, 1))
    }

    @Test("All 7 built-in Rune .wgsl shaders compile into Metal render pipelines")
    func allBuiltinRuneWgslShadersCompile() throws {
        let (device, _) = metalGpu()
        guard let mtlDev = device.shared.mtlDevice else { return }

        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // shader_tests.swift -> metal
            .deletingLastPathComponent() // metal -> gpu
            .deletingLastPathComponent() // gpu -> RuneTests
            .deletingLastPathComponent() // RuneTests -> Tests
            .deletingLastPathComponent() // Tests -> repo root
            .appendingPathComponent("Sources/Rune")

        func readWgsl(_ rel: String) throws -> String {
            try String(contentsOf: repoRoot.appendingPathComponent(rel), encoding: .utf8)
        }

        // 1. `native_surface/video.wgsl`
        let videoWgsl = try readWgsl("native_surface/video.wgsl")
        let videoMod = device.createShaderModule(label: "video", wgsl: videoWgsl)
        let _ = try device.createRenderPipeline(
            MetalRenderPipelineDescriptor(
                label: "video",
                layout: nil,
                vertexModule: videoMod,
                vertexEntryPoint: "vs",
                fragmentModule: videoMod,
                fragmentEntryPoint: "fs",
                colorTargets: [MetalColorTargetState(format: WGPUTextureFormat_BGRA8UnormSrgb)],
                topology: .triangleStrip
            )
        )

        // 2. `layer_blur.wgsl` (all specialization combinations)
        let layerBlurWgsl = try readWgsl("layer_blur.wgsl")
        let layerBlurMod = device.createShaderModule(label: "layer-blur", wgsl: layerBlurWgsl)
        for (mode, add) in [(0.0, 0.0), (0.0, 1.0), (2.0, 0.0), (2.0, 1.0), (3.0, 0.0)] {
            let _ = try device.createRenderPipeline(
                MetalRenderPipelineDescriptor(
                    label: "layer-blur-\(Int(mode))-\(Int(add))",
                    layout: nil,
                    vertexModule: layerBlurMod,
                    vertexEntryPoint: "vs",
                    fragmentModule: layerBlurMod,
                    fragmentEntryPoint: "fs",
                    fragmentConstants: ["MODE": mode, "ADDITIVE": add],
                    colorTargets: [MetalColorTargetState(format: WGPUTextureFormat_RGBA16Float)]
                )
            )
        }

        // 3. `backdrop_blur.wgsl` (`fs_down` and `fs_up`)
        let backdropBlurWgsl = try readWgsl("backdrop_blur.wgsl")
        let backdropBlurMod = device.createShaderModule(label: "backdrop-blur", wgsl: backdropBlurWgsl)
        for fsEntry in ["fs_down", "fs_up"] {
            let _ = try device.createRenderPipeline(
                MetalRenderPipelineDescriptor(
                    label: "backdrop-\(fsEntry)",
                    layout: nil,
                    vertexModule: backdropBlurMod,
                    vertexEntryPoint: "vs",
                    fragmentModule: backdropBlurMod,
                    fragmentEntryPoint: fsEntry,
                    colorTargets: [MetalColorTargetState(format: WGPUTextureFormat_BGRA8UnormSrgb)]
                )
            )
        }

        // 4. `clip.wgsl` + `backdrop_composite.wgsl` (instanced vertex attributes)
        let clipWgsl = try readWgsl("clip.wgsl")
        let backdropCompWgsl = clipWgsl + "\n" + (try readWgsl("backdrop_composite.wgsl"))
        let backdropCompMod = device.createShaderModule(label: "backdrop-comp", wgsl: backdropCompWgsl)
        let instanceLayout = MetalVertexBufferLayout(
            arrayStride: 128,
            stepMode: .instance,
            attributes: [
                MetalVertexAttribute(shaderLocation: 0, offset: 0, format: .float32x4),
                MetalVertexAttribute(shaderLocation: 1, offset: 16, format: .float32x4),
                MetalVertexAttribute(shaderLocation: 2, offset: 32, format: .float32x4),
                MetalVertexAttribute(shaderLocation: 3, offset: 48, format: .float32x4),
                MetalVertexAttribute(shaderLocation: 4, offset: 64, format: .float32x4),
                MetalVertexAttribute(shaderLocation: 5, offset: 80, format: .float32x4),
                MetalVertexAttribute(shaderLocation: 6, offset: 96, format: .float32x4),
                MetalVertexAttribute(shaderLocation: 7, offset: 112, format: .uint32x4),
            ]
        )
        let backdropCompBuffers = MetalVertexBufferLayout(
            arrayStride: 128,
            stepMode: .instance,
            attributes: [
                MetalVertexAttribute(shaderLocation: 0, offset: 0, format: .float32x4),
                MetalVertexAttribute(shaderLocation: 1, offset: 16, format: .float32x4),
                MetalVertexAttribute(shaderLocation: 2, offset: 32, format: .float32x4),
                MetalVertexAttribute(shaderLocation: 6, offset: 96, format: .float32x4),
                MetalVertexAttribute(shaderLocation: 7, offset: 112, format: .uint32x4),
            ]
        )
        let _ = try device.createRenderPipeline(
            MetalRenderPipelineDescriptor(
                label: "backdrop-comp",
                layout: nil,
                vertexModule: backdropCompMod,
                vertexEntryPoint: "vs",
                vertexBuffers: [backdropCompBuffers],
                fragmentModule: backdropCompMod,
                fragmentEntryPoint: "fs",
                colorTargets: [MetalColorTargetState(format: WGPUTextureFormat_BGRA8UnormSrgb)],
                topology: .triangleStrip
            )
        )

        // 5. `clip.wgsl` + `shader.wgsl` + `gpu/springs.wgsl` (`vs`, `vs_springs`, `fs`)
        let uberWgsl = clipWgsl + "\n" + (try readWgsl("shader.wgsl")) + "\n" + (try readWgsl("gpu/springs.wgsl"))
        let uberMod = device.createShaderModule(label: "uber", wgsl: uberWgsl)
        for vsEntry in ["vs", "vs_springs"] {
            let _ = try device.createRenderPipeline(
                MetalRenderPipelineDescriptor(
                    label: "uber-\(vsEntry)",
                    layout: nil,
                    vertexModule: uberMod,
                    vertexEntryPoint: vsEntry,
                    vertexBuffers: [instanceLayout],
                    fragmentModule: uberMod,
                    fragmentEntryPoint: "fs",
                    colorTargets: [MetalColorTargetState(format: WGPUTextureFormat_BGRA8UnormSrgb)],
                    topology: .triangleStrip
                )
            )
        }
        _ = mtlDev
    }
    #endif
}
