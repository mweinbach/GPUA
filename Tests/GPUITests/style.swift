// Tests ported from: crates/gpui/src/style.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
import Refineable
@testable import GPUI

@Suite("Style Tests")
struct StyleTests {

    // MARK: - Upstream Ported Tests

    @Test("Basic highlight style combination matches upstream behavior")
    func testBasicHighlightStyleCombination() {
        var styleA = HighlightStyle()
        let styleB = HighlightStyle()
        styleA = styleA.highlight(styleB)
        #expect(
            styleA == HighlightStyle(),
            "Combining empty styles should not produce a non-empty style."
        )

        var styleB2 = HighlightStyle(
            color: red(),
            fontWeight: FontWeight(300.0),
            fontStyle: .italic,
            backgroundColor: yellow(),
            underline: UnderlineStyle(
                thickness: px(2.0),
                color: red(),
                wavy: true
            ),
            strikethrough: StrikethroughStyle(
                thickness: px(2.0),
                color: blue()
            ),
            fadeOut: 0.0
        )
        let expectedStyle = styleB2

        styleA = styleA.highlight(styleB2)
        #expect(
            styleA == expectedStyle,
            "Blending an empty style with another style should return the other style"
        )

        styleB2 = styleB2.highlight(HighlightStyle())
        #expect(
            styleB2 == expectedStyle,
            "Blending a style with an empty style should not change the style."
        )

        var styleC = expectedStyle

        let styleD = HighlightStyle(
            color: blue().alpha(0.7),
            fontWeight: FontWeight(800.0),
            fontStyle: .oblique,
            backgroundColor: green(),
            underline: UnderlineStyle(
                thickness: px(4.0),
                color: nil,
                wavy: false
            ),
            strikethrough: StrikethroughStyle(
                thickness: px(4.0),
                color: red()
            ),
            fadeOut: 0.0
        )

        let expectedStyle2 = HighlightStyle(
            color: red().blend(with: blue().alpha(0.7)),
            fontWeight: FontWeight(800.0),
            fontStyle: .oblique,
            backgroundColor: green(),
            underline: UnderlineStyle(
                thickness: px(4.0),
                color: nil,
                wavy: false
            ),
            strikethrough: StrikethroughStyle(
                thickness: px(4.0),
                color: red()
            ),
            fadeOut: 0.0
        )

        styleC = styleC.highlight(styleD)
        #expect(
            styleC == expectedStyle2,
            "Blending styles should blend properties where possible and override all others"
        )
    }

    @Test("Combine highlights merges multiple intervals accurately")
    func testCombineHighlights() {
        let result = combineHighlights(
            [
                (0..<5, HighlightStyle(green())),
                (4..<10, HighlightStyle(FontWeight.bold)),
                (15..<20, HighlightStyle(yellow())),
            ],
            [
                (2..<6, HighlightStyle(FontStyle.italic)),
                (1..<3, HighlightStyle(blue())),
                (21..<23, HighlightStyle(red())),
            ]
        )

        let expected: [(Range<Int>, HighlightStyle)] = [
            (
                0..<1,
                HighlightStyle(color: green())
            ),
            (
                1..<2,
                HighlightStyle(color: blue())
            ),
            (
                2..<3,
                HighlightStyle(
                    color: blue(),
                    fontStyle: .italic
                )
            ),
            (
                3..<4,
                HighlightStyle(
                    color: green(),
                    fontStyle: .italic
                )
            ),
            (
                4..<5,
                HighlightStyle(
                    color: green(),
                    fontWeight: .bold,
                    fontStyle: .italic
                )
            ),
            (
                5..<6,
                HighlightStyle(
                    fontWeight: .bold,
                    fontStyle: .italic
                )
            ),
            (
                6..<10,
                HighlightStyle(
                    fontWeight: .bold
                )
            ),
            (
                15..<20,
                HighlightStyle(
                    color: yellow()
                )
            ),
            (
                21..<23,
                HighlightStyle(
                    color: red()
                )
            )
        ]

        #expect(result.count == expected.count)
        for i in 0..<min(result.count, expected.count) {
            #expect(result[i].0 == expected[i].0)
            #expect(result[i].1 == expected[i].1)
        }
    }

    @Test("Text style refinement applies font size and weight overrides")
    func testTextStyleRefinement() {
        var style = Style()
        style.refine(StyleRefinement().textSize(px(20.0)))
        style.refine(StyleRefinement().fontWeight(.semibold))

        #expect(
            style.textStyle()?.fontSize == AbsoluteLength.pixels(px(20.0))
        )
        #expect(
            style.textStyle()?.fontWeight == FontWeight.semibold
        )
    }

    // MARK: - ObjectFit Tests

    @Test("ObjectFit .fill returns container bounds verbatim")
    func testObjectFitFill() {
        let container = Bounds(origin: point(px(10.0), px(20.0)), size: size(px(200.0), px(100.0)))
        let img = Size(width: DevicePixels(50), height: DevicePixels(80))
        let result = ObjectFit.fill.getBounds(bounds: container, imageSize: img)
        #expect(result == container)
    }

    @Test("ObjectFit .contain scales aspect-preserving inside container")
    func testObjectFitContain() {
        // Container wider than image (boundsRatio 2.0 > imageRatio 1.0)
        let container = Bounds(origin: point(px(0.0), px(0.0)), size: size(px(200.0), px(100.0)))
        let squareImg = Size(width: DevicePixels(100), height: DevicePixels(100))
        let res1 = ObjectFit.contain.getBounds(bounds: container, imageSize: squareImg)
        #expect(res1.size == size(px(100.0), px(100.0)))
        #expect(res1.origin == point(px(50.0), px(0.0)))

        // Container taller than image (boundsRatio 0.5 < imageRatio 1.0)
        let tallContainer = Bounds(origin: point(px(0.0), px(0.0)), size: size(px(100.0), px(200.0)))
        let res2 = ObjectFit.contain.getBounds(bounds: tallContainer, imageSize: squareImg)
        #expect(res2.size == size(px(100.0), px(100.0)))
        #expect(res2.origin == point(px(0.0), px(50.0)))
    }

    @Test("ObjectFit .cover scales aspect-preserving covering container")
    func testObjectFitCover() {
        // Container wider than image (boundsRatio 2.0 > imageRatio 1.0)
        let container = Bounds(origin: point(px(0.0), px(0.0)), size: size(px(200.0), px(100.0)))
        let squareImg = Size(width: DevicePixels(100), height: DevicePixels(100))
        let res1 = ObjectFit.cover.getBounds(bounds: container, imageSize: squareImg)
        #expect(res1.size == size(px(200.0), px(200.0)))
        #expect(res1.origin == point(px(0.0), px(-50.0)))

        // Container taller than image (boundsRatio 0.5 < imageRatio 1.0)
        let tallContainer = Bounds(origin: point(px(0.0), px(0.0)), size: size(px(100.0), px(200.0)))
        let res2 = ObjectFit.cover.getBounds(bounds: tallContainer, imageSize: squareImg)
        #expect(res2.size == size(px(200.0), px(200.0)))
        #expect(res2.origin == point(px(-50.0), px(0.0)))
    }

    @Test("ObjectFit .scaleDown chooses smaller of original or contain")
    func testObjectFitScaleDown() {
        let container = Bounds(origin: point(px(0.0), px(0.0)), size: size(px(200.0), px(100.0)))

        // Image larger than container: behaves like .contain
        let largeImg = Size(width: DevicePixels(400), height: DevicePixels(400))
        let res1 = ObjectFit.scaleDown.getBounds(bounds: container, imageSize: largeImg)
        #expect(res1.size == size(px(100.0), px(100.0)))
        #expect(res1.origin == point(px(50.0), px(0.0)))

        // Image smaller than container: centers at original size
        let smallImg = Size(width: DevicePixels(60), height: DevicePixels(40))
        let res2 = ObjectFit.scaleDown.getBounds(bounds: container, imageSize: smallImg)
        #expect(res2.size == size(px(60.0), px(40.0)))
        #expect(res2.origin == point(px(70.0), px(30.0)))
    }

    @Test("ObjectFit .none places image at original size at bounds origin")
    func testObjectFitNone() {
        let container = Bounds(origin: point(px(15.0), px(25.0)), size: size(px(200.0), px(100.0)))
        let img = Size(width: DevicePixels(80), height: DevicePixels(60))
        let res = ObjectFit.none.getBounds(bounds: container, imageSize: img)
        #expect(res.origin == container.origin)
        #expect(res.size == size(px(80.0), px(60.0)))
    }

    @Test("ObjectFit handles zero dimensions gracefully")
    func testObjectFitZeroDimensions() {
        let container = Bounds(origin: point(px(10.0), px(10.0)), size: .zero)
        let img = Size(width: DevicePixels(100), height: DevicePixels(100))
        let res = ObjectFit.contain.getBounds(bounds: container, imageSize: img)
        #expect(res.size == .zero)
        #expect(res.origin == container.origin)

        let validContainer = Bounds(origin: point(px(10.0), px(10.0)), size: size(px(100.0), px(100.0)))
        let zeroImg = Size(width: DevicePixels(0), height: DevicePixels(100))
        let res2 = ObjectFit.contain.getBounds(bounds: validContainer, imageSize: zeroImg)
        #expect(res2.size == .zero)
    }

    // MARK: - Overflow Mask Tests

    @Test("Overflow mask returns nil when both axes are visible")
    func testOverflowMaskBothVisible() {
        var style = Style()
        style.overflow = Point(x: .visible, y: .visible)
        let bounds = Bounds(origin: point(px(0.0), px(0.0)), size: size(px(100.0), px(100.0)))
        #expect(style.overflowMask(bounds: bounds, remSize: px(16.0)) == nil)
    }

    @Test("Overflow mask insets by border widths when border is non-transparent")
    func testOverflowMaskBothHiddenWithBorders() {
        var style = Style()
        style.overflow = Point(x: .hidden, y: .hidden)
        style.borderColor = red()
        style.borderWidths = Edges(
            top: .pixels(px(2.0)),
            right: .pixels(px(4.0)),
            bottom: .pixels(px(6.0)),
            left: .pixels(px(8.0))
        )
        let bounds = Bounds(origin: point(px(10.0), px(20.0)), size: size(px(100.0), px(100.0)))
        let mask = style.overflowMask(bounds: bounds, remSize: px(16.0))
        #expect(mask != nil)
        // bounds.origin is (10, 20), bottomRight is (110, 120)
        // min = (10 + 8, 20 + 2) = (18, 22)
        // max = (110 - 4, 120 - 6) = (106, 114)
        // size = (106 - 18, 114 - 22) = (88, 92)
        #expect(mask?.bounds.origin == point(px(18.0), px(22.0)))
        #expect(mask?.bounds.size == size(px(88.0), px(92.0)))
    }

    @Test("Overflow mask does not inset when border is transparent or absent")
    func testOverflowMaskBothHiddenTransparentBorder() {
        var style = Style()
        style.overflow = Point(x: .hidden, y: .hidden)
        style.borderColor = red().alpha(0.0)
        style.borderWidths = Edges(
            top: .pixels(px(5.0)),
            right: .pixels(px(5.0)),
            bottom: .pixels(px(5.0)),
            left: .pixels(px(5.0))
        )
        let bounds = Bounds(origin: point(px(0.0), px(0.0)), size: size(px(100.0), px(100.0)))
        let mask = style.overflowMask(bounds: bounds, remSize: px(16.0))
        #expect(mask?.bounds == bounds)
    }

    @Test("Overflow mask handles mixed visibility axes")
    func testOverflowMaskOneAxisVisible() {
        var style = Style()
        style.overflow = Point(x: .visible, y: .hidden)
        style.borderColor = red()
        style.borderWidths = Edges(
            top: .pixels(px(5.0)),
            right: .pixels(px(5.0)),
            bottom: .pixels(px(5.0)),
            left: .pixels(px(5.0))
        )
        let bounds = Bounds(origin: point(px(0.0), px(0.0)), size: size(px(100.0), px(100.0)))
        let mask = style.overflowMask(bounds: bounds, remSize: px(16.0))
        #expect(mask != nil)
    }

    // MARK: - Cascade & Refine Tests

    @Test("Style refinement modifies properties in place and checks superset")
    func testStyleCascadeAndRefine() {
        var style = Style()
        #expect(style.display == .block)
        #expect(style.visibility == .visible)
        #expect(style.opacity == nil)

        var ref = StyleRefinement()
        ref.display = .flex
        ref.visibility = .hidden
        ref.opacity = 0.65
        ref.aspectRatio = Float(16.0) / Float(9.0)
        ref.flexDirection = .columnReverse
        ref.gap = SizeRefinement(
            width: .absolute(.pixels(px(12.0))),
            height: .absolute(.pixels(px(8.0)))
        )

        style.refine(with: ref)
        #expect(style.display == .flex)
        #expect(style.visibility == .hidden)
        #expect(style.opacity == 0.65)
        #expect(style.aspectRatio == Float(16.0) / Float(9.0))
        #expect(style.flexDirection == .columnReverse)
        #expect(style.gap.width == .absolute(.pixels(px(12.0))))
        #expect(style.gap.height == .absolute(.pixels(px(8.0))))
        #expect(style.isSuperset(of: ref))

        // Cascade test
        var cascade = Cascade<Style>()
        let s1 = cascade.reserve()
        let s2 = cascade.reserve()
        cascade.set(s1, StyleRefinement(display: .grid))
        cascade.set(s2, StyleRefinement(display: Display.none))
        let merged = cascade.merged()
        #expect(merged.display == Display.none)
    }

    @Test("Style refinement subtraction produces difference")
    func testStyleRefinementSubtraction() {
        let refA = StyleRefinement(display: .flex, opacity: 0.8)
        let refB = StyleRefinement(display: .flex, opacity: 0.5)
        let diff = refA.subtract(refB)
        #expect(diff.display == nil)
        #expect(diff.opacity == 0.8)
    }

    @Test("Opaque background and border visibility predicates")
    func testHasOpaqueBackgroundAndBorderVisible() {
        var style = Style()
        #expect(!style.hasOpaqueBackground())

        style.background = Fill(red())
        #expect(style.hasOpaqueBackground())

        style.background = Fill(red().alpha(0.0))
        #expect(!style.hasOpaqueBackground())

        style.borderColor = red()
        style.borderWidths = Edges(
            top: .pixels(px(1.0)),
            right: .pixels(.zero),
            bottom: .pixels(.zero),
            left: .pixels(.zero)
        )
        #expect(style.isBorderVisible())

        style.borderWidths = Edges.zero
        #expect(!style.isBorderVisible())
    }

    @Test("GridTemplate refinement and superset")
    func testGridTemplateRefinement() {
        var grid = GridTemplate(repeat: 3, minSize: .zero)
        let ref = GridTemplateRefinement(repeat: 5, minSize: .minContent)
        grid.refine(with: ref)
        #expect(grid.repeat == 5)
        #expect(grid.minSize == .minContent)
        #expect(grid.isSuperset(of: ref))
    }

    @Test("UnderlineStyle and StrikethroughStyle refinement")
    func testUnderlineAndStrikethroughRefinement() {
        var u = UnderlineStyle()
        let uRef = UnderlineStyleRefinement(thickness: px(3.0), color: blue(), wavy: true)
        u.refine(with: uRef)
        #expect(u.thickness == px(3.0))
        #expect(u.color == blue())
        #expect(u.wavy == true)
        #expect(u.isSuperset(of: uRef))
        let uSub = u.subtract(uRef)
        #expect(uSub.isEmpty)

        var s = StrikethroughStyle()
        let sRef = StrikethroughStyleRefinement(thickness: px(2.5), color: red())
        s.refine(with: sRef)
        #expect(s.thickness == px(2.5))
        #expect(s.color == red())
        #expect(s.isSuperset(of: sRef))
        let sSub = s.subtract(sRef)
        #expect(sSub.isEmpty)
    }
}
