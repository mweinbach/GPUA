// Tests ported from: crates/rune/src/cursor/image_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

// PORT NOTE: `an_element_resolves_to_its_image_cursor_and_its_children_inherit_it` and
// `a_macos_image_cursor_is_sized_in_points` depend on `Runtime` pointer routing and `platform/macos/cursor`
// owned outside this module cluster. Element `.cursor(...)` storage and all `CursorImage` / `decodeCursorImage`
// / `ImageCursors` tests are ported below.

/// A `w`×`h` px PNG, opaque red with a transparent blue left column.
private func makeTestPng(_ w: UInt32, _ h: UInt32) -> [UInt8] {
    var rgba = [UInt8]()
    rgba.reserveCapacity(Int(w * h * 4))
    for _ in 0..<h {
        for x in 0..<w {
            if x == 0 {
                rgba.append(contentsOf: [0, 0, 255, 0])
            } else {
                rgba.append(contentsOf: [255, 0, 0, 255])
            }
        }
    }
    return RunePngCodec.encodeRgba8(width: w, height: h, rgba: rgba)
}

private func hashOf<T: Hashable>(_ v: T) -> Int {
    var hasher = Hasher()
    v.hash(into: &hasher)
    return hasher.finalize()
}

@Suite("CursorImageTests")
struct CursorImageTests {
    @Test("element stores its image cursor")
    func elementStoresItsImageCursor() {
        let pencil = CursorImage.png(makeTestPng(64, 64), [2.0, 30.0])
        let canvas = el().key("canvas").size(200.0, 100.0).cursor(.image(pencil))
            .child(el().key("swatch").size(40.0, 40.0))
        #expect(canvas.handlers.getIfSome?.cursor == .image(pencil))
        #expect(canvas.children[0].handlers.getIfSome?.cursor == nil)
    }

    @Test("images are equal by bytes and hot spot")
    func imagesAreEqualByBytesAndHotSpot() {
        let aBytes: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]
        let bBytes: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]
        let cBytes: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 9]
        let a = CursorImage.png(aBytes, [1.0, 2.0])
        #expect(a == CursorImage.png(aBytes, [1.0, 2.0]))
        #expect(Cursor.Image(a) == Cursor.Image(CursorImage.png(aBytes, [1.0, 2.0])))
        #expect(a == CursorImage.png(bBytes, [1.0, 2.0]))
        #expect(a != CursorImage.png(cBytes, [1.0, 2.0]))
        #expect(a != CursorImage.png(Array(aBytes.prefix(7)), [1.0, 2.0]))
        #expect(a != CursorImage.png(aBytes, [1.0, 2.5]))
        #expect(hashOf(a) == hashOf(CursorImage.png(bBytes, [1.0, 2.0])))
        #expect(String(reflecting: a) == "CursorImage { png_bytes: 8, hot: [1.0, 2.0] }")
    }

    @Test("the cache decodes each image once per scale")
    func cacheDecodesEachImageOncePerScale() {
        let image = CursorImage.png(makeTestPng(32, 32), [4.0, 4.0])
        var cache = ImageCursors<UInt32>()
        var made = 0
        for _ in 0..<3 {
            let got = cache.get(image, 2.0) { d in
                made += 1
                return .success(d.width)
            }
            #expect(got == 32)
        }
        #expect(cache.decodes == 1 && made == 1)

        let copy = Array(image.bytes())
        #expect(cache.get(CursorImage.png(copy, [4.0, 4.0]), 2.0, { _ in .success(0) }) == 32)
        #expect(cache.decodes == 1)

        #expect(cache.get(image, 1.0, { d in .success(d.width) }) == 16)
        #expect(cache.decodes == 2)
        #expect(cache.cached(image, 2.0) == .some(.some(32)))
    }

    @Test("the cache is bounded and keeps the newest")
    func cacheIsBoundedAndKeepsNewest() {
        var cache = ImageCursors<Int>()
        let bytes = makeTestPng(8, 8)
        for i in 0..<(CURSOR_MAX_ENTRIES + 5) {
            _ = cache.get(CursorImage.png(bytes, [Float(i), 0.0]), 2.0) { _ in .success(i) }
        }
        #expect(cache.entries.count == CURSOR_MAX_ENTRIES)
        #expect(cache.cached(CursorImage.png(bytes, [0.0, 0.0]), 2.0) == nil)
        let last = CURSOR_MAX_ENTRIES + 4
        #expect(cache.cached(CursorImage.png(bytes, [Float(last), 0.0]), 2.0) == .some(.some(last)))
        #expect(cache.bytes <= CURSOR_MAX_BYTES)
    }

    @Test("the hot spot is clamped into the image")
    func hotSpotIsClampedIntoImage() throws {
        let bytes = makeTestPng(32, 20)
        func hot(_ p: [Float], _ scale: Float) throws -> [UInt32] {
            try decodeCursorImage(CursorImage.png(bytes, p), scale).get().hot
        }
        #expect(try hot([3.5, 2.0], 2.0) == [7, 4])
        #expect(try hot([3.5, 2.0], 1.0) == [3, 2])
        #expect(try hot([100.0, -5.0], 2.0) == [31, 0])
        #expect(try hot([.nan, .infinity], 2.0) == [0, 19])
        #expect(try hot([16.0, 10.0], 1.0) == [15, 9])
    }

    @Test("decoding scales to the display and keeps edges clean")
    func decodingScalesToDisplayAndKeepsEdgesClean() throws {
        let d = try decodeCursorImage(CursorImage.png(makeTestPng(32, 20), [0.0, 0.0]), 1.0).get()
        #expect(d.width == 16 && d.height == 10 && d.rgba.count == 16 * 10 * 4)
        let edge = Array(d.rgba.prefix(4))
        #expect(edge[2] == 0)

        let d3x = try decodeCursorImage(CursorImage.png(makeTestPng(32, 20), [0.0, 0.0]), 3.0).get()
        #expect(d3x.width == 48 && d3x.height == 30)
    }

    @Test("a bad png falls back to the arrow once")
    func badPngFallsBackToArrowOnce() {
        let notPng = Array("not a png".utf8)
        let image = CursorImage.png(notPng, [0.0, 0.0])
        var cache = ImageCursors<Int>()
        var made = false
        #expect(cache.get(image, 2.0, { _ in
            made = true
            return .success(1)
        }) == nil)
        #expect(!made)
        #expect(cache.get(image, 2.0, { _ in .success(1) }) == nil)
        #expect(cache.decodes == 1)
        #expect(cache.cached(image, 2.0) == .some(nil))

        if case .success = decodeCursorImage(CursorImage.png(makeTestPng(300, 8), [0.0, 0.0]), 2.0) {
            Issue.record("expected oversized cursor PNG to fail")
        }
        let refused = CursorImage.png(makeTestPng(8, 8), [0.0, 0.0])
        #expect(cache.get(refused, 2.0, { _ in .failure(ImageError("the OS refused it")) }) == nil)
    }
}
