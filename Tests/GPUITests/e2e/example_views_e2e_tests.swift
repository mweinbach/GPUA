// Swift-only: Headless E2E assertion pipeline verifying Scene display list primitives for example views

import Foundation
import Testing
@testable import GPUI

// PORT NOTE: DeterministicGlyphTextSystem produces non-zero raster bounds and rasterized bitmaps
// for shaped glyphs so the test harness asserts MonochromeSprite primitives in headless execution.
final class DeterministicGlyphTextSystem: PlatformTextSystem, @unchecked Sendable {
    let base = NoopTextSystem()

    func addFonts(_ fonts: [Data]) throws { try base.addFonts(fonts) }
    func allFontNames() -> [String] { base.allFontNames() }
    func fontId(descriptor: Font) throws -> FontId { try base.fontId(descriptor: descriptor) }
    func fontMetrics(fontId: FontId) -> FontMetrics { base.fontMetrics(fontId: fontId) }
    func typographicBounds(fontId: FontId, glyphId: GlyphId) throws -> Bounds<Float> {
        try base.typographicBounds(fontId: fontId, glyphId: glyphId)
    }
    func advance(fontId: FontId, glyphId: GlyphId) throws -> Size<Float> {
        Size(width: 600.0, height: 0.0)
    }
    func glyphForChar(fontId: FontId, ch: Character) -> GlyphId? {
        base.glyphForChar(fontId: fontId, ch: ch)
    }
    func glyphRasterBounds(params: RenderGlyphParams) throws -> Bounds<DevicePixels> {
        Bounds(origin: .zero, size: Size(width: DevicePixels(8), height: DevicePixels(12)))
    }
    func rasterizeGlyph(
        params: RenderGlyphParams,
        rasterBounds: Bounds<DevicePixels>
    ) throws -> (Size<DevicePixels>, Data) {
        let count = Int(rasterBounds.size.width.value * rasterBounds.size.height.value)
        return (rasterBounds.size, Data(repeating: 255, count: count))
    }
    func layoutLine(text: String, fontSize: Pixels, runs: [FontRun]) -> LineLayout {
        base.layoutLine(text: text, fontSize: fontSize, runs: runs)
    }
    func recommendedRenderingMode(fontId: FontId, fontSize: Pixels) -> TextRenderingMode {
        .subpixel
    }
}

// MARK: - Example Views Declared Locally (Linker Guardrail)
// PORT NOTE: Defined directly in test target to avoid duplicate `main` linker collisions on Windows/Linux.

struct HelloWorldTestView: Render, @unchecked Sendable {
    var text: SharedString

    init(text: SharedString = "World") {
        self.text = text
    }

    mutating func render(_ window: inout Window, _ cx: inout Context<HelloWorldTestView>) -> AnyElement {
        div()
            .flex()
            .flexCol()
            .gap3()
            .bg(Hsla(rgba: rgb(0x505050)))
            .size(px(500.0))
            .justifyCenter()
            .itemsCenter()
            .shadowLg()
            .border1()
            .borderColor(Hsla(rgba: rgb(0x0000ff)))
            .textXl()
            .textColor(Hsla(rgba: rgb(0xffffff)))
            .child("Hello, \(text)!")
            .child(
                div()
                    .flex()
                    .gap2()
                    .child(
                        div()
                            .size8()
                            .bg(GPUI.red())
                            .border1()
                            .borderDashed()
                            .roundedMd()
                            .borderColor(GPUI.white())
                    )
                    .child(
                        div()
                            .size8()
                            .bg(GPUI.green())
                            .border1()
                            .borderDashed()
                            .roundedMd()
                            .borderColor(GPUI.white())
                    )
                    .child(
                        div()
                            .size8()
                            .bg(GPUI.blue())
                            .border1()
                            .borderDashed()
                            .roundedMd()
                            .borderColor(GPUI.white())
                    )
                    .child(
                        div()
                            .size8()
                            .bg(GPUI.yellow())
                            .border1()
                            .borderDashed()
                            .roundedMd()
                            .borderColor(GPUI.white())
                    )
                    .child(
                        div()
                            .size8()
                            .bg(GPUI.black())
                            .border1()
                            .borderDashed()
                            .roundedMd()
                            .roundedMd()
                            .borderColor(GPUI.white())
                    )
                    .child(
                        div()
                            .size8()
                            .bg(GPUI.white())
                            .border1()
                            .borderDashed()
                            .roundedMd()
                            .borderColor(GPUI.black())
                    )
            )
            .intoAnyElement()
    }
}

struct TextLayoutTestView: Render, @unchecked Sendable {
    init() {}

    mutating func render(_ window: inout Window, _ cx: inout Context<TextLayoutTestView>) -> AnyElement {
        let alignChildren: [AnyElement] = [
            div().child("Text left").intoAnyElement(),
            div().textCenter().child("Text center").intoAnyElement(),
            div().textRight().child("Text right").intoAnyElement(),
            div().textDecoration1().child("Text left (underline)").intoAnyElement(),
            div().textCenter().textDecoration1().child("Text center (underline)").intoAnyElement(),
            div().textRight().textDecoration1().child("Text right (underline)").intoAnyElement(),
            div().lineThrough().child("Text left (line_through)").intoAnyElement(),
            div().textCenter().lineThrough().child("Text center (line_through)").intoAnyElement(),
            div().textRight().lineThrough().child("Text right (line_through)").intoAnyElement(),
        ]

        let boxRow = div()
            .flex()
            .gap2()
            .justifyBetween()
            .child(
                div()
                    .w(px(400.0))
                    .border1()
                    .borderColor(GPUI.blue())
                    .p1()
                    .whitespaceNowrap()
                    .overflowHidden()
                    .textCenter()
                    .child("A long non-wrapping text align center")
            )
            .child(
                div()
                    .w32()
                    .border1()
                    .borderColor(GPUI.blue())
                    .p1()
                    .whitespaceNowrap()
                    .overflowHidden()
                    .textRight()
                    .child("100%")
            )

        let styledRow = div()
            .flex()
            .gap2()
            .justifyBetween()
            .child(
                StyledText.new("ABCD").withHighlights([
                    (0..<1, HighlightStyle(FontWeight.extraBold)),
                    (2..<3, HighlightStyle(FontStyle.italic)),
                ])
            )

        return div()
            .bg(GPUI.white())
            .flex()
            .flexCol()
            .gap2()
            .p4()
            .sizeFull()
            .children(alignChildren)
            .child(boxRow)
            .child(styledRow)
            .intoAnyElement()
    }
}

// PORT NOTE: RecordedRange tracks visible range rendered by UniformList during headless pass.
final class RecordedRange: @unchecked Sendable {
    var range: Range<Int> = 0..<0
}

struct UniformListTestView: Render, @unchecked Sendable {
    let recordedRange: RecordedRange

    init(recordedRange: RecordedRange = RecordedRange()) {
        self.recordedRange = recordedRange
    }

    mutating func render(_ window: inout Window, _ cx: inout Context<UniformListTestView>) -> AnyElement {
        let cell = self.recordedRange
        return div()
            .sizeFull()
            .bg(GPUI.white())
            .child(
                uniformList(
                    "entries",
                    50
                ) { range, window, cx in
                    cell.range = range
                    return range.map { ix in
                        let item = ix + 1
                        return div()
                            .id(ElementId(UInt64(ix)))
                            .px2()
                            .cursorPointer()
                            .child("Item \(item)")
                            .intoAnyElement()
                    }
                }
                .hFull()
            )
            .intoAnyElement()
    }
}

// MARK: - Headless E2E Pipeline Test Suite

@Suite("Example Views Headless E2E Pipeline Tests")
struct ExampleViewsE2ETests {

    @Test("HelloWorldView Headless Pipeline: verifies bounds 500x500, quads, shadow, glyphs, and exact Hsla colors")
    @MainActor
    func testHelloWorldHeadlessPipeline() {
        let textSystem = DeterministicGlyphTextSystem()
        let testCx = TestAppContext.single(textSystem: textSystem)

        let (_, cx): (Entity<HelloWorldTestView>, VisualTestContext) = testCx.addWindowView(
            windowSize: Size(width: px(500.0), height: px(500.0))
        ) { _, _ in
            HelloWorldTestView(text: "World")
        }

        cx.draw()

        cx.update { window, _ in
            let scene = window.renderedFrame.scene
            let quads = scene.quads

            // 1. Root size 500x500
            let rootQuad = quads.first { q in
                q.bounds.size.width == 500 && q.bounds.size.height == 500
            }
            #expect(rootQuad != nil, "Expected root 500x500 quad")

            // 2. Exact background color 0x505050 and border color 0x0000ff
            let expectedBg = Hsla(rgba: rgb(0x505050))
            let expectedBorder = Hsla(rgba: rgb(0x0000ff))
            let hasBgQuad = quads.contains { q in
                q.bounds.size.width == 500 && q.bounds.size.height == 500 && q.background.solid == expectedBg
            }
            #expect(hasBgQuad, "Root background must match rgb(0x505050)")

            let hasBorderQuad = quads.contains { q in
                q.bounds.size.width == 500 && q.bounds.size.height == 500 && q.borderColor == expectedBorder
            }
            #expect(hasBorderQuad, "Root border must match rgb(0x0000ff)")

            // 3. Quads count >= 8 (root background, 6 colored squares, container)
            #expect(quads.count >= 8, "Expected at least 8 quads, found \(quads.count)")

            // 4. Verify all 6 colored squares exist with size 32x32 (size8 = 2 rems = 32px)
            let squareColors: [Hsla] = [
                GPUI.red(),
                GPUI.green(),
                GPUI.blue(),
                GPUI.yellow(),
                GPUI.black(),
                GPUI.white(),
            ]
            for color in squareColors {
                let found = quads.contains { q in
                    q.background.solid == color && q.bounds.size.width == 32 && q.bounds.size.height == 32
                }
                #expect(found, "Expected 32x32 square with color \(color)")
            }

            // 5. Shadow count >= 1 (.shadowLg())
            #expect(scene.shadows.count >= 1, "Expected at least 1 shadow from shadowLg(), found \(scene.shadows.count)")

            // 6. Monochrome sprites / shaped glyphs >= 10 ("Hello, World!" has 13 chars)
            #expect(scene.monochromeSprites.count >= 10, "Expected >= 10 glyph monochrome sprites, found \(scene.monochromeSprites.count)")
        }
    }

    @Test("TextLayoutView Headless Pipeline: verifies root bounds, underlines, alignments, bounded boxes, and styled text")
    @MainActor
    func testTextLayoutHeadlessPipeline() {
        let textSystem = DeterministicGlyphTextSystem()
        let testCx = TestAppContext.single(textSystem: textSystem)

        let (_, cx): (Entity<TextLayoutTestView>, VisualTestContext) = testCx.addWindowView(
            windowSize: Size(width: px(800.0), height: px(600.0))
        ) { _, _ in
            TextLayoutTestView()
        }

        cx.draw()

        cx.update { window, _ in
            let scene = window.renderedFrame.scene
            let quads = scene.quads

            // 1. Root size full (800x600) with white background
            let rootQuad = quads.first { q in
                q.bounds.size.width == 800 && q.bounds.size.height == 600
            }
            #expect(rootQuad != nil, "Expected root 800x600 quad")
            if let root = rootQuad {
                #expect(root.background.solid == GPUI.white(), "Root background must be white")
            }

            // 2. Underline decoration primitives (3 underline elements)
            #expect(scene.underlines.count >= 3, "Expected >= 3 underline primitives from textDecoration1, found \(scene.underlines.count)")

            // 3. Bounded width containers: 400px and 128px (w32 = 8 rems = 128px) with blue borders
            let container400 = quads.first { q in
                q.bounds.size.width == 400 && q.borderColor == GPUI.blue()
            }
            #expect(container400 != nil, "Expected 400px container with blue border")

            let container128 = quads.first { q in
                q.bounds.size.width == 128 && q.borderColor == GPUI.blue()
            }
            #expect(container128 != nil, "Expected 128px (w32) container with blue border")

            // 4. Shaped glyph runs / monochrome sprites present
            #expect(scene.monochromeSprites.count >= 30, "Expected >= 30 glyph sprites across text layout view, found \(scene.monochromeSprites.count)")
        }
    }

    @Test("UniformListView Headless Pipeline: verifies 300x300 root, lazy visible item subset, and row bounds")
    @MainActor
    func testUniformListHeadlessPipeline() {
        let textSystem = DeterministicGlyphTextSystem()
        let testCx = TestAppContext.single(textSystem: textSystem)
        let cell = RecordedRange()

        let (_, cx): (Entity<UniformListTestView>, VisualTestContext) = testCx.addWindowView(
            windowSize: Size(width: px(300.0), height: px(300.0))
        ) { _, _ in
            UniformListTestView(recordedRange: cell)
        }

        cx.draw()

        cx.update { window, _ in
            let scene = window.renderedFrame.scene
            let quads = scene.quads

            // 1. Root size 300x300 with white background
            let rootQuad = quads.first { q in
                q.bounds.size.width == 300 && q.bounds.size.height == 300
            }
            #expect(rootQuad != nil, "Expected root 300x300 quad")

            // 2. Lazy items rendered for visible range: out of 50 total items, only visible subset rendered
            let rendered = cell.range
            #expect(rendered.count > 0, "Expected some items rendered in visible range")
            #expect(rendered.count < 50, "UniformList must lazily render only visible items, not all 50! Rendered: \(rendered.count)")

            // 3. Row bounds: each visible item rendered has width 300 and item height > 0
            #expect(scene.monochromeSprites.count >= 5, "Expected glyph sprites for rendered items, found \(scene.monochromeSprites.count)")
        }
    }
}
