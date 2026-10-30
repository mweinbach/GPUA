// Tests ported from: crates/gpui_metal/src/atlas.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

#if canImport(Metal)
import Foundation
import GPUI
import Metal
import Testing
@testable import GPUIMetal

@Suite("GPUIMetal Atlas Tests")
struct MetalAtlasTests {
    private func createAtlas() -> MetalAtlas? {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return nil
        }
        let isAppleGpu = device.supportsFamily(.apple1)
        return MetalAtlas.new(device, isAppleGpu)
    }

    private func makeImageKey(_ imageId: Int, _ frameIndex: Int) -> AtlasKey {
        .image(RenderImageParams(imageId: ImageId(imageId), frameIndex: frameIndex))
    }

    private func insertTile(
        _ atlas: MetalAtlas,
        _ key: AtlasKey,
        _ size: Size<DevicePixels>,
        fillByte: UInt8 = 0
    ) throws -> AtlasTile {
        let bpp = key.textureKind() == .monochrome ? 1 : 4
        let byteCount = Int(size.width.value) * Int(size.height.value) * bpp
        let tile = try atlas.getOrInsertWith(key: key) {
            (size, Data(repeating: fillByte, count: byteCount))
        }
        return try #require(tile, "Expected atlas allocation callback to produce a tile")
    }

    @Test("remove_clears_stale_keys")
    func removeClearsStaleKeys() throws {
        guard let atlas = createAtlas() else {
            return
        }

        let size = Size(width: DevicePixels(64), height: DevicePixels(64))

        let keyA = makeImageKey(1, 0)
        let keyB = makeImageKey(2, 0)
        let keyC = makeImageKey(3, 0)

        let tileA = try insertTile(atlas, keyA, size)
        let tileB = try insertTile(atlas, keyB, size)
        let tileC = try insertTile(atlas, keyC, size)

        #expect(tileA.textureId == tileB.textureId)
        #expect(tileB.textureId == tileC.textureId)

        atlas.remove(key: keyA)
        atlas.remove(key: keyB)
        atlas.remove(key: keyC)

        let tileA2 = try insertTile(atlas, keyA, size)
        #expect(tileA2.textureId.index == tileA.textureId.index)
        let texture = atlas.metalTexture(tileA2.textureId)
        #expect(texture.width >= 1024)
        #expect(texture.height >= 1024)
    }

    @Test("remove_missing_key_is_noop")
    func removeMissingKeyIsNoop() {
        guard let atlas = createAtlas() else {
            return
        }

        atlas.remove(key: makeImageKey(999, 0))
    }

    @Test("Monochrome and polychrome uploads cache keys and pack non-overlapping shelves")
    func monochromeAndPolychromeUploadAndPacking() throws {
        guard let atlas = createAtlas() else {
            return
        }

        let monoSize = Size(width: DevicePixels(16), height: DevicePixels(16))
        let monoKey1 = AtlasKey.svg(RenderSvgParams(path: SharedString("icon_a.svg"), size: monoSize))
        let monoKey2 = AtlasKey.svg(RenderSvgParams(path: SharedString("icon_b.svg"), size: monoSize))

        let monoTile1 = try insertTile(atlas, monoKey1, monoSize, fillByte: 0xAB)
        let monoTile1Cached = try insertTile(atlas, monoKey1, monoSize, fillByte: 0x00)
        let monoTile2 = try insertTile(atlas, monoKey2, monoSize, fillByte: 0xCD)

        #expect(monoTile1 == monoTile1Cached)
        #expect(monoTile1.textureId.kind == .monochrome)
        #expect(monoTile1.textureId == monoTile2.textureId)
        #expect(!monoTile1.bounds.intersects(monoTile2.bounds))

        let monoTexture = atlas.metalTexture(monoTile1.textureId)
        #expect(monoTexture.pixelFormat == .a8Unorm)

        var readback = [UInt8](repeating: 0, count: 16 * 16)
        readback.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            monoTexture.getBytes(
                base,
                bytesPerRow: 16,
                from: MTLRegionMake2D(
                    Int(monoTile1.bounds.origin.x.value),
                    Int(monoTile1.bounds.origin.y.value),
                    16,
                    16
                ),
                mipmapLevel: 0
            )
        }
        #expect(readback.allSatisfy { $0 == 0xAB })
    }
}
#endif
