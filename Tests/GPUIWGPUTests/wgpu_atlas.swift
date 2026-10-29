// Tests ported from: crates/gpui_wgpu/src/wgpu_atlas.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux) || os(Windows) || os(Android) || os(WASI)
import Testing
import Foundation
import GPUI
@testable import GPUIWGPU

@Suite("WgpuAtlasTests")
struct WgpuAtlasTests {
    @Test
    func test_shelf_allocator_basic() {
        var allocator = ShelfAtlasAllocator(size: Size(width: DevicePixels(1024), height: DevicePixels(1024)))

        let tile1 = allocator.allocate(size: Size(width: DevicePixels(64), height: DevicePixels(32)))
        #expect(tile1 != nil)
        if let (id, bounds) = tile1 {
            #expect(id == TileId(1))
            #expect(bounds.origin.x.value == 0)
            #expect(bounds.origin.y.value == 0)
            #expect(bounds.size.width.value == 64)
            #expect(bounds.size.height.value == 32)
        }

        // Second tile on the same shelf
        let tile2 = allocator.allocate(size: Size(width: DevicePixels(32), height: DevicePixels(32)))
        #expect(tile2 != nil)
        if let (id, bounds) = tile2 {
            #expect(id == TileId(2))
            #expect(bounds.origin.x.value == 64)
            #expect(bounds.origin.y.value == 0)
            #expect(bounds.size.width.value == 32)
            #expect(bounds.size.height.value == 32)
        }

        // Third tile with larger height creates new shelf
        let tile3 = allocator.allocate(size: Size(width: DevicePixels(48), height: DevicePixels(64)))
        #expect(tile3 != nil)
        if let (id, bounds) = tile3 {
            #expect(id == TileId(3))
            #expect(bounds.origin.x.value == 0)
            #expect(bounds.origin.y.value == 32)
            #expect(bounds.size.width.value == 48)
            #expect(bounds.size.height.value == 64)
        }
    }

    @Test
    func test_shelf_allocator_overflow() {
        var allocator = ShelfAtlasAllocator(size: Size(width: DevicePixels(100), height: DevicePixels(100)))

        // Allocate a tile that exceeds sheet width
        #expect(allocator.allocate(size: Size(width: DevicePixels(150), height: DevicePixels(50))) == nil)

        // Allocate a tile that exceeds sheet height
        #expect(allocator.allocate(size: Size(width: DevicePixels(50), height: DevicePixels(150))) == nil)

        // Fill up sheet vertically
        let t1 = allocator.allocate(size: Size(width: DevicePixels(100), height: DevicePixels(80)))
        #expect(t1 != nil)

        let t2 = allocator.allocate(size: Size(width: DevicePixels(100), height: DevicePixels(20)))
        #expect(t2 != nil)

        // No more vertical space
        let t3 = allocator.allocate(size: Size(width: DevicePixels(10), height: DevicePixels(10)))
        #expect(t3 == nil)
    }

    @Test
    func test_shelf_allocator_best_fit() {
        var allocator = ShelfAtlasAllocator(size: Size(width: DevicePixels(200), height: DevicePixels(200)))

        // Shelf 0: height 64 (fill 190 of 200)
        _ = allocator.allocate(size: Size(width: DevicePixels(190), height: DevicePixels(64)))
        // Shelf 1: height 32 (fill 190 of 200)
        _ = allocator.allocate(size: Size(width: DevicePixels(190), height: DevicePixels(32)))

        // A new 30px high item should best-fit into Shelf 1 (waste: 32-30=2 vs 64-30=34)
        let tile = allocator.allocate(size: Size(width: DevicePixels(10), height: DevicePixels(30)))
        #expect(tile != nil)
        if let (_, bounds) = tile {
            #expect(bounds.origin.y.value == 64) // Shelf 1 starts at y=64
            #expect(bounds.origin.x.value == 190)
        }
    }

    @Test
    func test_shelf_allocator_clear() {
        var allocator = ShelfAtlasAllocator(size: Size(width: DevicePixels(100), height: DevicePixels(100)))
        _ = allocator.allocate(size: Size(width: DevicePixels(100), height: DevicePixels(100)))
        #expect(allocator.allocate(size: Size(width: DevicePixels(10), height: DevicePixels(10))) == nil)

        allocator.clear()
        let fresh = allocator.allocate(size: Size(width: DevicePixels(50), height: DevicePixels(50)))
        #expect(fresh != nil)
        #expect(fresh?.0 == TileId(1))
    }

    #if os(Linux)
    @Test
    func before_frame_skips_uploads_for_removed_texture() throws {
        let instance = WgpuContext.instance()
        let context = try WgpuContext.new(instance: instance, surface: nil)
        let atlas = WgpuAtlas.new(device: context.device, queue: context.queue)

        let key = AtlasKey.image(RenderImageParams(imageId: ImageId(1), frameIndex: 0))
        let size = Size(width: DevicePixels(1), height: DevicePixels(1))

        let tile = try atlas.getOrInsertWith(key: key) {
            (size, Data([0, 0, 0, 255]))
        }
        #expect(tile != nil)

        atlas.remove(key: key)
        atlas.beforeFrame()
    }
    #endif
}
#endif
