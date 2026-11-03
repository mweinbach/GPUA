// Ported from: crates/rune/src/gpu/backend.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("GPU Backend Tests")
struct GpuBackendTests {
    @Test("resolve reads the env var and falls back to the platform default")
    func resolveReadsEnvAndFallsBackToPlatformDefault() {
        #if os(macOS) || os(iOS)
        let platformDefault: GpuBackend = .metal
        #else
        let platformDefault: GpuBackend = .wgpu
        #endif

        #expect(tryResolveGpuBackend(nil) == .success(platformDefault))
        #expect(tryResolveGpuBackend("") == .success(platformDefault))
        #expect(tryResolveGpuBackend("  ") == .success(platformDefault))
        #expect(tryResolveGpuBackend("wgpu") == .success(.wgpu))
        #expect(tryResolveGpuBackend("WGPU") == .success(.wgpu))
        #expect(tryResolveGpuBackend(" wgpu ") == .success(.wgpu))

        #if os(macOS) || os(iOS)
        #expect(tryResolveGpuBackend("metal") == .success(.metal))
        #expect(tryResolveGpuBackend("METAL") == .success(.metal))
        #else
        #expect(tryResolveGpuBackend("metal") == .failure(.metalUnsupportedOnPlatform))
        #endif

        #expect(tryResolveGpuBackend("vulkan") == .failure(.invalidValue("vulkan")))
    }

    @Test("serves pairs metal and rejects software fallbacks")
    func servesPairsMetalAndRejectsSoftwareFallbacks() {
        #expect(backendServes(.metal, .metal))
        #expect(!backendServes(.metal, .vulkan))
        #expect(!backendServes(.metal, .gl))
        #expect(!backendServes(.metal, .noop))

        #expect(backendServes(.wgpu, .vulkan))
        #expect(backendServes(.wgpu, .metal))
        #expect(backendServes(.wgpu, .dx12))
        #expect(backendServes(.wgpu, .browserWebGpu))
        #expect(!backendServes(.wgpu, .gl))
        #expect(!backendServes(.wgpu, .noop))
    }

    @Test("wgpuBackendsFor and label reflect chosen backend")
    func wgpuBackendsAndLabel() {
        let current = currentGpuBackend()
        #expect(gpuBackendLabel() == current.description)
        #if os(macOS) || os(iOS)
        #expect(wgpuBackendsFor(.wgpu) == .metal)
        #expect(wgpuBackendsFor(.metal) == .primary)
        #else
        #expect(wgpuBackendsFor(.wgpu) == .primary)
        #endif
    }
}
