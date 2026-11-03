// Tests ported from: crates/rune/src/pixels.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

// PORT NOTE: CPU-side `Pixels`, `ImageAtlas`, and `fitImageRect` tests are ported in full below.
// Offscreen WebGPU readback tests (`gpu_*` and `an_image_over_its_fill_fades_into_a_soft_edge_like_a_flat_fill`)
// depend on `render.swift` WebGPU offscreen pipelines owned outside this module cluster.

@Suite("PixelsTests")
struct PixelsTests {
    @Test("fit letterboxes on whole pixels and fill crops the centre")
    func fitLetterboxesOnWholePixelsAndFillCropsCentre() {
        let c = SurfacePlace()
        let rect: [Float] = [10.0, 20.0, 40.0, 40.0]

        let noneFit = fitImageRect(nil, c, rect, (80, 20))
        #expect(noneFit.0 == rect && noneFit.1 == [0.0, 0.0, 1.0, 1.0])

        let wideFit = fitImageRect(.fit, c, rect, (80, 20))
        #expect(wideFit.0 == [10.0, 35.0, 40.0, 10.0] && wideFit.1 == [0.0, 0.0, 1.0, 1.0])

        #expect(fitImageRect(.fit, c, rect, (20, 80)).0 == [25.0, 20.0, 10.0, 40.0])

        let wideFill = fitImageRect(.fill, c, rect, (80, 20))
        #expect(wideFill.0 == rect && wideFill.1 == [0.375, 0.0, 0.625, 1.0])

        let squareFill = fitImageRect(.fill, c, rect, (40, 40))
        #expect(squareFill.0 == rect && squareFill.1 == [0.0, 0.0, 1.0, 1.0])

        #expect(fitImageRect(.fit, c, rect, (0, 0)).0 == rect)
    }

    @Test("frames copy in once per generation and resize moves the slot")
    func framesCopyInOncePerGenerationAndResizeMovesSlot() {
        var atlas = ImageAtlas()
        let px = Pixels.new()
        #expect(atlas.place(px, [2.0, 1.0]) == nil)

        px.set(2, 1, [255, 0, 0, 255, 0, 255, 0, 128])
        #expect(atlas.place(px, [2.0, 1.0])?.rect == [0, 0, 2, 1])
        let dirty0 = atlas.pages[0].dirty
        atlas.pages[0].dirty = nil
        #expect(dirty0?.0 == 0 && dirty0?.1 == 1)
        #expect(Array(atlas.pages[0].data.prefix(8)) == [255, 0, 0, 255, 0, 255, 0, 128])

        _ = atlas.place(px, [2.0, 1.0])
        #expect(atlas.pages[0].dirty == nil)

        px.set(3, 2, [UInt8](repeating: 7, count: 24))
        let placed = atlas.place(px, [3.0, 2.0])!
        let x = placed.rect[0]
        let y = placed.rect[1]
        #expect(placed.rect[2] == 3 && placed.rect[3] == 2)
        #expect(atlas.pages[0].data[Int((y * IMAGE_ATLAS_SIZE + x) * 4)] == 7)

        let other = Pixels.new()
        other.set(1, 1, [UInt8](repeating: 1, count: 4))
        let otherPlaced = atlas.place(other, [1.0, 1.0])!
        atlas.endFrame()
        _ = atlas.place(px, [3.0, 2.0])
        atlas.endFrame()
        // First page keeps unshown `other` without re-copying.
        atlas.pages[0].dirty = nil
        #expect(atlas.place(other, [1.0, 1.0]) == otherPlaced)
        #expect(atlas.pages[0].dirty == nil)
    }

    @Test("an image shown again after a while is not copied again")
    func imageShownAgainAfterAWhileIsNotCopiedAgain() {
        var atlas = ImageAtlas()
        let list = Pixels.new()
        let grid = Pixels.new()
        list.set(32, 32, [UInt8](repeating: 1, count: 32 * 32 * 4))
        grid.set(48, 48, [UInt8](repeating: 2, count: 48 * 48 * 4))
        let shown = atlas.place(list, [32.0, 32.0])!
        atlas.endFrame()
        for _ in 0..<4 {
            _ = atlas.place(grid, [48.0, 48.0])
            atlas.endFrame()
        }
        atlas.pages[0].dirty = nil
        #expect(atlas.place(list, [32.0, 32.0]) == shown)
        #expect(atlas.pages[0].dirty == nil)
    }

    @Test("a full atlas starts over pages that show nothing before it grows")
    func fullAtlasStartsOverPagesThatShowNothingBeforeItGrows() {
        var atlas = ImageAtlas()
        let old: [Pixels] = (0..<4).map { _ in
            let p = Pixels.new()
            p.set(512, 512, [UInt8](repeating: 1, count: 512 * 512 * 4))
            return p
        }
        for p in old {
            _ = atlas.place(p, [512.0, 512.0])
        }
        atlas.endFrame()
        atlas.endFrame()
        #expect(atlas.pages.count == 1)

        let fresh = Pixels.new()
        fresh.set(512, 512, [UInt8](repeating: 2, count: 512 * 512 * 4))
        #expect(atlas.place(fresh, [512.0, 512.0])?.rect == [0, 0, 512, 512])
        #expect(atlas.pages.count == 1)

        let copiesBefore = atlas.copies
        _ = atlas.place(old[0], [512.0, 512.0])
        #expect(atlas.copies == copiesBefore + 1)
    }

    @Test("a full page shown last frame is not started over before its images are drawn")
    func fullPageShownLastFrameIsNotStartedOverBeforeItsImagesAreDrawn() {
        var atlas = ImageAtlas()
        let body: [Pixels] = (0..<4).map { i in
            let p = Pixels.new()
            p.set(512, 512, [UInt8](repeating: UInt8(i), count: 512 * 512 * 4))
            return p
        }
        let placed = body.map { atlas.place($0, [512.0, 512.0])! }
        atlas.endFrame()
        atlas.pages[0].dirty = nil

        let fresh = Pixels.new()
        fresh.set(64, 64, [UInt8](repeating: 9, count: 64 * 64 * 4))
        #expect(atlas.place(fresh, [64.0, 64.0])?.page == 1)
        let replaced = body.map { atlas.place($0, [512.0, 512.0])! }
        #expect(replaced == placed)
        #expect(atlas.pages[0].dirty == nil)
    }

    @Test("an image resized between two draws keeps the first draws pixels")
    func imageResizedBetweenTwoDrawsKeepsFirstDrawsPixels() {
        var atlas = ImageAtlas()
        let px = Pixels.new()
        px.set(512, 512, [UInt8](repeating: 1, count: 512 * 512 * 4))
        let fill: [Pixels] = (0..<3).map { _ in
            let p = Pixels.new()
            p.set(512, 512, [UInt8](repeating: 2, count: 512 * 512 * 4))
            return p
        }
        _ = atlas.place(px, [512.0, 512.0])
        for p in fill {
            _ = atlas.place(p, [512.0, 512.0])
        }
        atlas.endFrame()

        let first = atlas.place(px, [512.0, 512.0])!
        px.set(600, 600, [UInt8](repeating: 3, count: 600 * 600 * 4))
        let second = atlas.place(px, [600.0, 600.0])!
        #expect(second.page != first.page)
        let x = first.rect[0]
        let y = first.rect[1]
        #expect(atlas.pages[first.page].data[Int((y * IMAGE_ATLAS_SIZE + x) * 4)] == 1)
    }

    @Test("pages expand reclaim and keep streaming slots stable")
    func pagesExpandReclaimAndKeepStreamingSlotsStable() {
        var atlas = ImageAtlas()
        let stream = Pixels.new()
        stream.set(224, 128, [UInt8](repeating: 1, count: 224 * 128 * 4))
        let first = atlas.place(stream, [112.0, 64.0])!
        #expect(!first.premultiplied)

        let large = Pixels.new()
        large.set(2048, 1, [UInt8](repeating: 2, count: 2048 * 4))
        let second = atlas.place(large, [2048.0, 1.0])!
        #expect(first.page != second.page)
        #expect(atlas.pages[second.page].width == 2048 && atlas.pages[second.page].height == 1)

        let full = Pixels.new()
        full.set(1024, 1024, [UInt8](repeating: 3, count: 1024 * 1024 * 4))
        let third = atlas.place(full, [1024.0, 1024.0])!
        #expect(third.page == 2)

        atlas.endFrame()
        stream.set(224, 128, [UInt8](repeating: 4, count: 224 * 128 * 4))
        #expect(atlas.place(stream, [112.0, 64.0]) == first)
        _ = atlas.place(full, [1024.0, 1024.0])
        atlas.endFrame()
        #expect(atlas.pages.count == 3)
        #expect(atlas.pages[second.page].data.isEmpty)

        #expect(atlas.place(stream, [112.0, 64.0]) == first)
        atlas.endFrame()
        #expect(atlas.pages.count == 1)
        atlas.endFrame()
        #expect(atlas.pages.count == 1)
    }
}
