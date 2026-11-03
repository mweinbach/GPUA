// Tests ported from: crates/rune/src/cursor/image.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("CursorImageDecodeTests")
struct CursorImageDecodeTests {
    @Test("raw RGBA cursor decodes and falls back to source scale for non-positive scale")
    func rawRgbaCursorDecodesAndFallsBackToSourceScale() throws {
        let rgba: [UInt8] = [
            255, 0, 0, 255, 0, 255, 0, 255,
            0, 0, 255, 255, 255, 255, 255, 255,
        ]
        let cursor = CursorImage(width: 2, height: 2, hotspotX: 1, hotspotY: 1, rgba: rgba)
        let decoded = try decodeCursorImage(cursor, 0.0).get()
        #expect(decoded.scale == CURSOR_SOURCE_SCALE)
        #expect(decoded.width == 2 && decoded.height == 2)
        #expect(decoded.rgba == rgba)
        #expect(decoded.hot == [1, 1])

        let nanDecoded = try decodeCursorImage(cursor, .nan).get()
        #expect(nanDecoded.scale == CURSOR_SOURCE_SCALE)

        let invalid = CursorImage(width: 2, height: 2, rgba: [0, 0, 0])
        if case .success = decodeCursorImage(invalid, 2.0) {
            Issue.record("expected invalid RGBA byte length to fail")
        }
    }
}
