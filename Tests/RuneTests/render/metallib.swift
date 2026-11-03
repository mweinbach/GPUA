// Tests ported from: crates/rune/src/render/metallib.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import CWebGPU
@testable import Rune

@Suite("Rune Render Metallib Tests", .serialized)
struct RuneRenderMetallibTests {
    @Test("uber WGSL and ABI fingerprints match recorded upstream hashes and detect perturbations")
    func precompiledUberMetallibIsFresh() {
        let wgsl = uberWgsl()
        #expect(uberWgslHash(wgsl) == UBER_WGSL_BLAKE3)
        #expect(uberAbiFingerprint() == UBER_ABI_FNV64)

        let altered = wgsl + "\n// perturbed\n"
        #expect(uberWgslHash(altered) != UBER_WGSL_BLAKE3)
    }

    @Test("semantic fingerprint tracks descriptors rather than unrelated labels")
    func semanticFingerprintTracksDescriptorsNotSourceText() {
        let entries = uberBindEntries()
        let vertex = uberVertexLayout()
        let primitive = uberPrimitive()
        let baseline = uberAbiFingerprint(bindEntries: entries, vertexLayout: vertex, topology: primitive)

        var changedEntries = entries
        changedEntries[0] = MetalBindGroupLayoutEntry(
            binding: changedEntries[0].binding,
            visibility: .vertex,
            ty: changedEntries[0].ty
        )
        #expect(uberAbiFingerprint(bindEntries: changedEntries, vertexLayout: vertex, topology: primitive) != baseline)

        changedEntries = entries
        changedEntries[0] = MetalBindGroupLayoutEntry(
            binding: 4,
            visibility: changedEntries[0].visibility,
            ty: changedEntries[0].ty
        )
        #expect(uberAbiFingerprint(bindEntries: changedEntries, vertexLayout: vertex, topology: primitive) != baseline)

        let changedStride = MetalVertexBufferLayout(
            arrayStride: vertex.arrayStride + 16,
            stepMode: vertex.stepMode,
            attributes: vertex.attributes
        )
        #expect(uberAbiFingerprint(bindEntries: entries, vertexLayout: changedStride, topology: primitive) != baseline)

        let changedStep = MetalVertexBufferLayout(
            arrayStride: vertex.arrayStride,
            stepMode: .vertex,
            attributes: vertex.attributes
        )
        #expect(uberAbiFingerprint(bindEntries: entries, vertexLayout: changedStep, topology: primitive) != baseline)

        var attrs = UBER_VERTEX_ATTRS
        attrs[0] = MetalVertexAttribute(
            shaderLocation: attrs[0].shaderLocation,
            offset: attrs[0].offset + 4,
            format: attrs[0].format
        )
        let changedAttr = MetalVertexBufferLayout(
            arrayStride: INSTANCE_BYTE_SIZE,
            stepMode: .instance,
            attributes: attrs
        )
        #expect(uberAbiFingerprint(bindEntries: entries, vertexLayout: changedAttr, topology: primitive) != baseline)

        #expect(uberAbiFingerprint(bindEntries: entries, vertexLayout: vertex, topology: .triangleList) != baseline)
        #expect(uberAbiFingerprint(bindEntries: entries, vertexLayout: vertex, topology: primitive, vertexEntry: "vs_alt") != baseline)
        #expect(uberAbiFingerprint(bindEntries: entries, vertexLayout: vertex, topology: primitive, colorTargetCount: 2) != baseline)
        #expect(uberAbiFingerprint(bindEntries: entries, vertexLayout: vertex, topology: primitive) == baseline)
    }

    #if os(macOS)
    @Test("uber shader loads when enabled and falls back cleanly on disabled or invalid metallib")
    func uberShaderLoadsPrecompiledMetallibAndFallsBackCleanly() {
        let gpu = Gpu.headless()
        let before = metallibThreadLoads()
        _ = withMetallibEnabled(true) {
            Renderer(gpu.metalDevice, OFFSCREEN_FORMAT)
        }
        let afterOn = metallibThreadLoads()
        #expect(afterOn == before + 1)

        _ = withMetallibEnabled(false) {
            Renderer(gpu.metalDevice, OFFSCREEN_FORMAT)
        }
        let afterOff = metallibThreadLoads()
        #expect(afterOff == afterOn)

        let bgl = gpu.metalDevice.createBindGroupLayout(label: "uber-test", entries: uberBindEntries())
        let pl = gpu.metalDevice.createPipelineLayout(label: "uber-test", bindGroupLayouts: [bgl])
        let wgsl = uberWgsl()

        #expect(
            withMetallibEnabled(true) {
                tryUberMetallib(
                    device: gpu.metalDevice,
                    pipelineLayout: pl,
                    format: OFFSCREEN_FORMAT,
                    wgslSource: wgsl,
                    abiHash: 0xdead_beef,
                    metallibBytes: nil
                )
            } == nil
        )
        #expect(
            withMetallibEnabled(true) {
                tryUberMetallib(
                    device: gpu.metalDevice,
                    pipelineLayout: pl,
                    format: OFFSCREEN_FORMAT,
                    wgslSource: wgsl,
                    metallibBytes: Array("not-mtlb".utf8)
                )
            } == nil
        )
        #expect(
            withMetallibEnabled(true) {
                tryUberMetallib(
                    device: gpu.metalDevice,
                    pipelineLayout: pl,
                    format: OFFSCREEN_FORMAT,
                    wgslSource: wgsl,
                    metallibBytes: Array("MTLBcorrupt-payload".utf8)
                )
            } == nil
        )
    }
    #endif
}
