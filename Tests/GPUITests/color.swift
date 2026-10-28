// Tests ported from: crates/gpui/src/color.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Testing
@testable import GPUI

@Suite("Color Tests")
struct ColorTests {

    // MARK: - Upstream Test Ports

    @Test("Upstream test_deserialize_three_value_hex_to_rgba")
    func test_deserialize_three_value_hex_to_rgba() throws {
        let json = "\"#f09\"".data(using: .utf8)!
        let actual = try JSONDecoder().decode(Rgba.self, from: json)
        #expect(actual == rgba(0xff0099ff))
    }

    @Test("Upstream test_deserialize_four_value_hex_to_rgba")
    func test_deserialize_four_value_hex_to_rgba() throws {
        let json = "\"#f09f\"".data(using: .utf8)!
        let actual = try JSONDecoder().decode(Rgba.self, from: json)
        #expect(actual == rgba(0xff0099ff))
    }

    @Test("Upstream test_deserialize_six_value_hex_to_rgba")
    func test_deserialize_six_value_hex_to_rgba() throws {
        let json = "\"#ff0099\"".data(using: .utf8)!
        let actual = try JSONDecoder().decode(Rgba.self, from: json)
        #expect(actual == rgba(0xff0099ff))
    }

    @Test("Upstream test_deserialize_eight_value_hex_to_rgba")
    func test_deserialize_eight_value_hex_to_rgba() throws {
        let json = "\"#ff0099ff\"".data(using: .utf8)!
        let actual = try JSONDecoder().decode(Rgba.self, from: json)
        #expect(actual == rgba(0xff0099ff))
    }

    @Test("Upstream test_deserialize_eight_value_hex_with_padding_to_rgba")
    func test_deserialize_eight_value_hex_with_padding_to_rgba() throws {
        let json = "\" #f5f5f5ff   \"".data(using: .utf8)!
        let actual = try JSONDecoder().decode(Rgba.self, from: json)
        #expect(actual == rgba(0xf5f5f5ff))
    }

    @Test("Upstream test_deserialize_eight_value_hex_with_mixed_case_to_rgba")
    func test_deserialize_eight_value_hex_with_mixed_case_to_rgba() throws {
        let json = "\"#DeAdbEeF\"".data(using: .utf8)!
        let actual = try JSONDecoder().decode(Rgba.self, from: json)
        #expect(actual == rgba(0xdeadbeef))
    }

    @Test("Upstream test_background_solid")
    func test_background_solid() {
        let color = Hsla(rgba: rgba(0xff0099ff))
        var background = solidBackground(color)
        #expect(background.tag == .solid)
        #expect(background.solid == color)

        #expect(background.opacity(0.5).solid == color.opacity(0.5))
        #expect(!background.isTransparent)
        background.solid = hsla(0.0, 0.0, 0.0, 0.0)
        #expect(background.isTransparent)
    }

    @Test("Upstream test_background_linear_gradient")
    func test_background_linear_gradient() {
        let from = linearColorStop(rgba(0xff0099ff), 0.0)
        let to = linearColorStop(rgba(0x00ff99ff), 1.0)
        let background = linearGradient(angle: 90.0, from: from, to: to)
        #expect(background.tag == .linearGradient)
        #expect(background.colors.0 == from)
        #expect(background.colors.1 == to)

        #expect(background.opacity(0.5).colors.0 == from.opacity(0.5))
        #expect(background.opacity(0.5).colors.1 == to.opacity(0.5))
        #expect(!background.isTransparent)
        #expect(background.opacity(0.0).isTransparent)
    }

    // MARK: - Behavioral Parity Tests

    @Test("Rgba blending preserves background alpha")
    func test_rgba_blend_preserves_background_alpha() {
        let bg = Rgba(r: 1.0, g: 0.0, b: 0.0, a: 0.5)
        let fgOpaque = Rgba(r: 0.0, g: 1.0, b: 0.0, a: 1.0)
        let fgTransparent = Rgba(r: 0.0, g: 1.0, b: 0.0, a: 0.0)
        let fgHalf = Rgba(r: 0.0, g: 1.0, b: 0.0, a: 0.5)

        // Opaque top replaces completely
        #expect(bg.blend(with: fgOpaque) == fgOpaque)
        // Transparent top keeps bottom completely
        #expect(bg.blend(with: fgTransparent) == bg)

        // Semi-transparent: background alpha must remain self.a
        let blended = bg.blend(with: fgHalf)
        #expect(blended.a == bg.a)
        #expect(abs(blended.r - 0.5) < 0.001)
        #expect(abs(blended.g - 0.5) < 0.001)
        #expect(blended.b == 0.0)
    }

    @Test("Hsla conversions and total ordering")
    func test_hsla_conversions_and_ordering() {
        // Red round-trip
        let redRgb = Rgba(r: 1.0, g: 0.0, b: 0.0, a: 1.0)
        let redHsl = Hsla(rgba: redRgb)
        #expect(redHsl.h == 0.0)
        #expect(redHsl.s == 1.0)
        #expect(redHsl.l == 0.5)
        #expect(redHsl.toRgb() == redRgb)

        // Green round-trip
        let greenHsl = hsla(1.0 / 3.0, 1.0, 0.5, 1.0)
        let greenRgb = greenHsl.toRgb()
        #expect(abs(greenRgb.r - 0.0) < 0.001)
        #expect(abs(greenRgb.g - 1.0) < 0.001)
        #expect(abs(greenRgb.b - 0.0) < 0.001)

        // Grayscale input
        let greyRgb = Rgba(r: 0.5, g: 0.5, b: 0.5, a: 1.0)
        let greyHsl = Hsla(rgba: greyRgb)
        #expect(greyHsl.s == 0.0)
        #expect(greyHsl.l == 0.5)

        // Ordering: h then s then l then a
        let c1 = hsla(0.1, 0.5, 0.5, 1.0)
        let c2 = hsla(0.2, 0.5, 0.5, 1.0)
        let c3 = hsla(0.1, 0.6, 0.5, 1.0)
        #expect(c1 < c2)
        #expect(c1 < c3)
    }

    @Test("Hsla color modifiers")
    func test_hsla_modifiers() {
        let color = hsla(0.5, 0.8, 0.6, 0.8)
        let grey = color.grayscale()
        #expect(grey.s == 0.0)
        #expect(grey.h == color.h)
        #expect(grey.l == color.l)

        var fading = color
        fading.fadeOut(by: 0.5)
        #expect(abs(fading.a - 0.4) < 0.001)

        let semi = color.alpha(0.25)
        #expect(semi.a == 0.25)

        #expect(!color.isTransparent)
        #expect(hsla(0, 0, 0, 0).isTransparent)
        #expect(hsla(0, 0, 0, 1).isOpaque)
    }

    @Test("Hex parsing edge cases")
    func test_hex_parsing_edge_cases() {
        #expect(Rgba(hex: "f09") == nil) // Missing leading #
        #expect(Rgba(hex: "#12") == nil)  // Invalid length 2
        #expect(Rgba(hex: "#12345") == nil) // Invalid length 5
        #expect(Rgba(hex: "#1234567") == nil) // Invalid length 7
        #expect(Rgba(hex: "#123456789") == nil) // Invalid length 9
        #expect(Rgba(hex: "#gggggg") == nil) // Invalid hex digits
    }

    @Test("swapRgbaPaToBgra premultiplied alpha")
    func test_swap_rgba_pa_to_bgra() {
        var pixel: [UInt8] = [128, 64, 32, 255]
        swapRgbaPaToBgra(&pixel)
        #expect(pixel[0] == 32)
        #expect(pixel[1] == 64)
        #expect(pixel[2] == 128)
        #expect(pixel[3] == 255)

        // Alpha = 0 shouldn't divide by zero
        var transparentPixel: [UInt8] = [10, 20, 30, 0]
        swapRgbaPaToBgra(&transparentPixel)
        #expect(transparentPixel[0] == 30)
        #expect(transparentPixel[2] == 10)
    }

    @Test("Background patterns and layout")
    func test_background_patterns() {
        #expect(MemoryLayout<Background>.size == 72)

        let slash = patternSlash(color: red(), width: 2.0, interval: 4.0)
        #expect(slash.tag == .patternSlash)
        #expect(!slash.isTransparent)

        let check = checkerboard(color: blue(), size: 16.0)
        #expect(check.tag == .checkerboard)
        #expect(!check.isTransparent)
    }

    @Test("Colors palette for appearance")
    func test_colors_palette() {
        let lightColors = Colors.light()
        let darkColors = Colors.dark()

        #expect(lightColors.background == rgb(0xffffff))
        #expect(darkColors.background == rgb(0x222222))

        #expect(Colors.forAppearance(.light) == lightColors)
        #expect(Colors.forAppearance(.vibrantLight) == lightColors)
        #expect(Colors.forAppearance(.dark) == darkColors)
        #expect(Colors.forAppearance(.vibrantDark) == darkColors)

        let defApp = DefaultAppearance(appearance: .vibrantDark)
        #expect(defApp == .dark)
    }
}
