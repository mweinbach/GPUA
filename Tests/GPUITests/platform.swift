// Tests ported from: crates/gpui/src/platform.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Testing
@testable import GPUI

@Suite("Platform Image Tests")
struct PlatformImageTests {
    @Test("test_svg_image_to_image_data_converts_to_bgra")
    func test_svg_image_to_image_data_converts_to_bgra() throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="1" height="1">
        <rect width="1" height="1" fill="#38BDF8"/>
        </svg>
        """

        let image = Image.fromBytes(
            format: .svg,
            bytes: Array(svg.utf8)
        )

        let renderer = SvgRenderer.new(assetSource: NoopAssetSource())
        let renderImage = try image.toImageData(svgRenderer: renderer)
        guard let bytes = renderImage.asBytes(0) else {
            Issue.record("Expected bytes for rendered SVG image")
            return
        }

        #expect(!bytes.isEmpty)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let pixel = Array(bytes[i..<i+4])
            #expect(pixel == [0xF8, 0xBD, 0x38, 0xFF])
        }
    }
}
