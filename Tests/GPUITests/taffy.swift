// Swift-only: Behavioral tests for GPUI Taffy layout engine bridge and Style-to-Taffy conversions

import Testing
import Refineable
import Taffy
@testable import GPUI

@Suite("GPUI Taffy Layout Bridge Tests")
struct GPUITaffyTests {

    // MARK: - AvailableSpace & Conversions

    @Test("AvailableSpace definitions and conversions between GPUI and Taffy")
    func testAvailableSpaceConversions() {
        let definite = GPUI.AvailableSpace.definite(px(120.0))
        let minContent = GPUI.AvailableSpace.minContent
        let maxContent = GPUI.AvailableSpace.maxContent

        let taffyDefinite = definite.toTaffy()
        #expect(taffyDefinite == Taffy.AvailableSpace.definite(120.0))
        #expect(GPUI.AvailableSpace(taffyDefinite) == definite)

        let taffyMin = minContent.toTaffy()
        #expect(taffyMin == Taffy.AvailableSpace.minContent)
        #expect(GPUI.AvailableSpace(taffyMin) == minContent)

        let taffyMax = maxContent.toTaffy()
        #expect(taffyMax == Taffy.AvailableSpace.maxContent)
        #expect(GPUI.AvailableSpace(taffyMax) == maxContent)

        let sizeSpace = Size(width: definite, height: minContent)
        let taffySizeSpace = sizeSpace.toTaffy()
        #expect(taffySizeSpace.width == .definite(120.0))
        #expect(taffySizeSpace.height == .minContent)
        #expect(Size<GPUI.AvailableSpace>(taffySizeSpace) == sizeSpace)

        let minSize = GPUI.AvailableSpace.minSize()
        #expect(minSize.width == .minContent)
        #expect(minSize.height == .minContent)

        let maxSize = GPUI.AvailableSpace.maxSize()
        #expect(maxSize.width == .maxContent)
        #expect(maxSize.height == .maxContent)
    }

    // MARK: - LayoutId

    @Test("LayoutId identity, wrapping, and conversions")
    func testLayoutId() {
        let nodeId = Taffy.NodeId(42)
        let layoutId = LayoutId(nodeId)
        #expect(layoutId.rawValue == nodeId)
        #expect(layoutId.description == "LayoutId(42)")

        let layoutIdFromInt: LayoutId = 100
        #expect(layoutIdFromInt.rawValue.asUInt64 == 100)

        let slice = LayoutId.toTaffySlice([layoutId, layoutIdFromInt])
        #expect(slice == [nodeId, Taffy.NodeId(100)])
    }

    // MARK: - Style to Taffy Style Conversion

    @Test("Style to Taffy Style accurate property translation")
    func testStyleToTaffyConversion() {
        var style = Style()
        style.display = .flex
        style.flexDirection = .row
        style.flexWrap = .wrap
        style.position = .relative
        style.overflow = Point(x: .hidden, y: .scroll)
        style.scrollbarWidth = .pixels(px(14.0))

        style.size = Size(width: .definite(.pixels(px(200.0))), height: .definite(.rems(1.5)))
        style.minSize = Size(width: .definite(.pixels(px(50.0))), height: .auto)
        style.maxSize = Size(width: .auto, height: .definite(.pixels(px(500.0))))
        style.aspectRatio = 1.6

        style.margin = Edges(top: .definite(.pixels(px(10.0))), right: .auto, bottom: .definite(.pixels(px(10.0))), left: .auto)
        style.padding = Edges(top: .pixels(px(8.0)), right: .pixels(px(16.0)), bottom: .pixels(px(8.0)), left: .pixels(px(16.0)))
        style.borderWidths = Edges(top: .pixels(px(1.0)), right: .pixels(px(2.0)), bottom: .pixels(px(1.0)), left: .pixels(px(2.0)))
        style.gap = Size(width: .pixels(px(12.0)), height: .pixels(px(12.0)))

        style.alignItems = .center
        style.alignSelf = .stretch
        style.alignContent = .spaceBetween
        style.justifyContent = .flexEnd

        style.flexGrow = 1.5
        style.flexShrink = 0.5
        style.flexBasis = .definite(.fraction(0.5))

        let remSize = px(16.0)
        let scaleFactor: Float = 2.0

        let taffyStyle = style.toTaffy(remSize: remSize, scaleFactor: scaleFactor)

        #expect(taffyStyle.display == .flex)
        #expect(taffyStyle.flexDirection == .row)
        #expect(taffyStyle.flexWrap == .wrap)
        #expect(taffyStyle.position == .relative)
        #expect(taffyStyle.overflow.x == .hidden)
        #expect(taffyStyle.overflow.y == .scroll)
        #expect(taffyStyle.scrollbarWidth == 14.0 * scaleFactor)

        // 200px * 2.0 = 400px
        #expect(taffyStyle.size.width.intoOption() == 400.0)
        // 1.5 rems * 16px * 2.0 = 48.0
        #expect(taffyStyle.size.height.intoOption() == 48.0)
        #expect(taffyStyle.minSize.width.intoOption() == 100.0)
        #expect(taffyStyle.minSize.height.isAuto)
        #expect(taffyStyle.maxSize.width.isAuto)
        #expect(taffyStyle.maxSize.height.intoOption() == 1000.0)
        #expect(taffyStyle.aspectRatio == 1.6)

        #expect(taffyStyle.padding.left.intoRaw().value == 32.0)
        #expect(taffyStyle.padding.right.intoRaw().value == 32.0)
        #expect(taffyStyle.padding.top.intoRaw().value == 16.0)
        #expect(taffyStyle.padding.bottom.intoRaw().value == 16.0)

        #expect(taffyStyle.border.left.intoRaw().value == 4.0)
        #expect(taffyStyle.border.top.intoRaw().value == 2.0)

        #expect(taffyStyle.alignItems == .center)
        #expect(taffyStyle.alignSelf == .stretch)
        #expect(taffyStyle.alignContent == .spaceBetween)
        #expect(taffyStyle.justifyContent == .flexEnd)

        #expect(taffyStyle.flexGrow == 1.5)
        #expect(taffyStyle.flexShrink == 0.5)
        #expect(taffyStyle.flexBasis.intoRaw() == .percent(0.5))
    }

    // MARK: - Engine Lifecycle & Fixed Leaf Layout

    @Test("TaffyLayoutEngine lays out fixed leaf nodes accurately with scaleFactor")
    func testLeafNodeLayout() {
        var engine = TaffyLayoutEngine.new()
        var style = Style()
        style.size = Size(width: .definite(.pixels(px(120.0))), height: .definite(.pixels(px(80.0))))

        let scaleFactor: Float = 2.0
        let leaf = engine.requestLayout(
            style: style,
            remSize: px(16.0),
            scaleFactor: scaleFactor
        )

        var window = Window(scaleFactor: scaleFactor)
        var app = App()
        let available = Size(
            width: GPUI.AvailableSpace.definite(px(300.0)),
            height: GPUI.AvailableSpace.definite(px(300.0))
        )

        engine.computeLayout(id: leaf, availableSpace: available, window: &window, cx: &app)

        let bounds = engine.layoutBounds(id: leaf, scaleFactor: scaleFactor)
        #expect(abs(bounds.origin.x.value - 0.0) < 0.1)
        #expect(abs(bounds.origin.y.value - 0.0) < 0.1)
        #expect(abs(bounds.size.width.value - 120.0) < 0.1)
        #expect(abs(bounds.size.height.value - 80.0) < 0.1)
    }

    // MARK: - Custom Measurement Callbacks

    @Test("TaffyLayoutEngine invokes measured layout callbacks and scales correctly")
    func testMeasuredLayout() {
        var engine = TaffyLayoutEngine()
        var style = Style()
        style.display = .flex
        style.size = Size(width: .auto, height: .auto)

        final class Counter: @unchecked Sendable {
            var count = 0
        }
        let counter = Counter()

        let measuredNode = engine.requestMeasuredLayout(
            style: style,
            remSize: px(16.0),
            scaleFactor: 1.0
        ) { knownDimensions, availableSpace, window, cx in
            counter.count += 1
            #expect(knownDimensions.width == nil)
            #expect(knownDimensions.height == nil)
            return Size(width: px(75.0), height: px(35.0))
        }

        var window = Window(scaleFactor: 1.0)
        var app = App()
        let available = Size(
            width: GPUI.AvailableSpace.definite(px(200.0)),
            height: GPUI.AvailableSpace.definite(px(200.0))
        )

        engine.computeLayout(id: measuredNode, availableSpace: available, window: &window, cx: &app)

        #expect(counter.count > 0)
        let bounds = engine.layoutBounds(id: measuredNode, scaleFactor: 1.0)
        #expect(abs(bounds.size.width.value - 75.0) < 0.1)
        #expect(abs(bounds.size.height.value - 35.0) < 0.1)
    }

    // MARK: - Flexbox Layout & Gaps

    @Test("TaffyLayoutEngine resolves flex row with padding, gap, and child bounds")
    func testFlexRowLayout() {
        var engine = TaffyLayoutEngine()

        var childStyle1 = Style()
        childStyle1.size = Size(width: .definite(.pixels(px(60.0))), height: .definite(.pixels(px(40.0))))

        var childStyle2 = Style()
        childStyle2.size = Size(width: .definite(.pixels(px(80.0))), height: .definite(.pixels(px(40.0))))

        let c1 = engine.requestLayout(style: childStyle1, remSize: px(16.0), scaleFactor: 1.0)
        let c2 = engine.requestLayout(style: childStyle2, remSize: px(16.0), scaleFactor: 1.0)

        var parentStyle = Style()
        parentStyle.display = .flex
        parentStyle.flexDirection = .row
        parentStyle.padding = Edges(top: .pixels(px(10.0)), right: .pixels(px(10.0)), bottom: .pixels(px(10.0)), left: .pixels(px(10.0)))
        parentStyle.gap = Size(width: .pixels(px(15.0)), height: .pixels(px(0.0)))
        parentStyle.size = Size(width: .auto, height: .auto)

        let parent = engine.requestLayout(style: parentStyle, remSize: px(16.0), scaleFactor: 1.0, children: [c1, c2])

        var window = Window(scaleFactor: 1.0)
        var app = App()
        engine.computeLayout(id: parent, availableSpace: Size(width: .maxContent, height: .maxContent), window: &window, cx: &app)

        let parentBounds = engine.layoutBounds(id: parent, scaleFactor: 1.0)
        let c1Bounds = engine.layoutBounds(id: c1, scaleFactor: 1.0)
        let c2Bounds = engine.layoutBounds(id: c2, scaleFactor: 1.0)

        // Total width = padding(10 + 10) + c1(60) + gap(15) + c2(80) = 175.0
        #expect(abs(parentBounds.size.width.value - 175.0) < 0.1)
        // Total height = padding(10 + 10) + c1(40) = 60.0
        #expect(abs(parentBounds.size.height.value - 60.0) < 0.1)

        // c1 is at (10, 10)
        #expect(abs(c1Bounds.origin.x.value - 10.0) < 0.1)
        #expect(abs(c1Bounds.origin.y.value - 10.0) < 0.1)

        // c2 is at (10 + 60 + 15 = 85, 10)
        #expect(abs(c2Bounds.origin.x.value - 85.0) < 0.1)
        #expect(abs(c2Bounds.origin.y.value - 10.0) < 0.1)
    }

    // MARK: - Flex Grow Distribution

    @Test("TaffyLayoutEngine distributes space according to flexGrow")
    func testFlexGrowDistribution() {
        var engine = TaffyLayoutEngine()

        var childStyle1 = Style()
        childStyle1.size = Size(width: .definite(.pixels(px(50.0))), height: .definite(.pixels(px(50.0))))
        childStyle1.flexGrow = 1.0

        var childStyle2 = Style()
        childStyle2.size = Size(width: .definite(.pixels(px(50.0))), height: .definite(.pixels(px(50.0))))
        childStyle2.flexGrow = 2.0

        let c1 = engine.requestLayout(style: childStyle1, remSize: px(16.0), scaleFactor: 1.0)
        let c2 = engine.requestLayout(style: childStyle2, remSize: px(16.0), scaleFactor: 1.0)

        var parentStyle = Style()
        parentStyle.display = .flex
        parentStyle.flexDirection = .row
        parentStyle.size = Size(width: .definite(.pixels(px(250.0))), height: .definite(.pixels(px(50.0))))

        let parent = engine.requestLayout(style: parentStyle, remSize: px(16.0), scaleFactor: 1.0, children: [c1, c2])

        engine.computeLayout(id: parent, availableSpace: Size(width: .definite(px(250.0)), height: .definite(px(50.0))))

        let c1Bounds = engine.layoutBounds(id: c1, scaleFactor: 1.0)
        let c2Bounds = engine.layoutBounds(id: c2, scaleFactor: 1.0)

        // Initial items total 100px. Free space = 250 - 100 = 150px.
        // Total grow = 1 + 2 = 3.
        // c1 gets 1/3 * 150 = 50px -> 50 + 50 = 100px.
        // c2 gets 2/3 * 150 = 100px -> 50 + 100 = 150px.
        #expect(abs(c1Bounds.size.width.value - 100.0) < 0.1)
        #expect(abs(c2Bounds.size.width.value - 150.0) < 0.1)
    }

    // MARK: - Nested Hierarchical Bounds

    @Test("TaffyLayoutEngine accumulates offsets across nested hierarchies")
    func testNestedHierarchyOffsets() {
        var engine = TaffyLayoutEngine()

        var grandChildStyle = Style()
        grandChildStyle.size = Size(width: .definite(.pixels(px(30.0))), height: .definite(.pixels(px(30.0))))
        grandChildStyle.margin = Edges(top: .definite(.pixels(px(5.0))), right: .auto, bottom: .auto, left: .definite(.pixels(px(5.0))))

        let grandChild = engine.requestLayout(style: grandChildStyle, remSize: px(16.0), scaleFactor: 1.0)

        var childStyle = Style()
        childStyle.display = .flex
        childStyle.margin = Edges(top: .definite(.pixels(px(20.0))), right: .auto, bottom: .auto, left: .definite(.pixels(px(20.0))))
        childStyle.size = Size(width: .definite(.pixels(px(80.0))), height: .definite(.pixels(px(80.0))))

        let child = engine.requestLayout(style: childStyle, remSize: px(16.0), scaleFactor: 1.0, children: [grandChild])

        var rootStyle = Style()
        rootStyle.display = .flex
        rootStyle.padding = Edges(top: .pixels(px(10.0)), right: .pixels(px(10.0)), bottom: .pixels(px(10.0)), left: .pixels(px(10.0)))
        rootStyle.size = Size(width: .definite(.pixels(px(200.0))), height: .definite(.pixels(px(200.0))))

        let root = engine.requestLayout(style: rootStyle, remSize: px(16.0), scaleFactor: 1.0, children: [child])

        engine.computeLayout(id: root, availableSpace: Size(width: .definite(px(200.0)), height: .definite(px(200.0))))

        let rootBounds = engine.layoutBounds(id: root, scaleFactor: 1.0)
        let childBounds = engine.layoutBounds(id: child, scaleFactor: 1.0)
        let grandChildBounds = engine.layoutBounds(id: grandChild, scaleFactor: 1.0)

        #expect(abs(rootBounds.origin.x.value - 0.0) < 0.1)
        #expect(abs(rootBounds.origin.y.value - 0.0) < 0.1)

        // child origin = root.origin + root.padding(10) + child.margin(20) = 30
        #expect(abs(childBounds.origin.x.value - 30.0) < 0.1)
        #expect(abs(childBounds.origin.y.value - 30.0) < 0.1)

        // grandChild origin = child.origin(30) + grandChild.margin(5) = 35
        #expect(abs(grandChildBounds.origin.x.value - 35.0) < 0.1)
        #expect(abs(grandChildBounds.origin.y.value - 35.0) < 0.1)
    }

    // MARK: - CSS Grid Layout Through Bridge

    @Test("TaffyLayoutEngine computes CSS Grid layout correctly")
    func testCSSGridLayout() {
        var engine = TaffyLayoutEngine()

        var childStyle1 = Style()
        childStyle1.size = Size(width: .auto, height: .definite(.pixels(px(40.0))))

        var childStyle2 = Style()
        childStyle2.size = Size(width: .auto, height: .definite(.pixels(px(40.0))))

        let c1 = engine.requestLayout(style: childStyle1, remSize: px(16.0), scaleFactor: 1.0)
        let c2 = engine.requestLayout(style: childStyle2, remSize: px(16.0), scaleFactor: 1.0)

        var gridStyle = Style()
        gridStyle.display = .grid
        gridStyle.size = Size(width: .definite(.pixels(px(200.0))), height: .definite(.pixels(px(100.0))))
        gridStyle.gridCols = GridTemplate(repeat: 2, minSize: .zero)

        let grid = engine.requestLayout(style: gridStyle, remSize: px(16.0), scaleFactor: 1.0, children: [c1, c2])

        engine.computeLayout(id: grid, availableSpace: Size(width: .definite(px(200.0)), height: .definite(px(100.0))))

        let c1Bounds = engine.layoutBounds(id: c1, scaleFactor: 1.0)
        let c2Bounds = engine.layoutBounds(id: c2, scaleFactor: 1.0)

        // In a 200px 2-column equal grid, each column receives 100px width.
        #expect(abs(c1Bounds.size.width.value - 100.0) < 0.1)
        #expect(abs(c1Bounds.origin.x.value - 0.0) < 0.1)

        #expect(abs(c2Bounds.size.width.value - 100.0) < 0.1)
        #expect(abs(c2Bounds.origin.x.value - 100.0) < 0.1)
    }

    // MARK: - Cache Invalidation & Recomputation

    @Test("TaffyLayoutEngine invalidates cache on recomputation")
    func testCacheInvalidation() {
        var engine = TaffyLayoutEngine()

        var childStyle = Style()
        childStyle.size = Size(width: .definite(.fraction(1.0)), height: .definite(.fraction(1.0)))

        let child = engine.requestLayout(style: childStyle, remSize: px(16.0), scaleFactor: 1.0)

        var parentStyle = Style()
        parentStyle.display = .flex
        parentStyle.size = Size(width: .definite(.pixels(px(100.0))), height: .definite(.pixels(px(100.0))))

        let parent = engine.requestLayout(style: parentStyle, remSize: px(16.0), scaleFactor: 1.0, children: [child])

        // First pass at 100x100
        engine.computeLayout(id: parent, availableSpace: Size(width: .definite(px(100.0)), height: .definite(px(100.0))))
        let firstBounds = engine.layoutBounds(id: child, scaleFactor: 1.0)
        #expect(abs(firstBounds.size.width.value - 100.0) < 0.1)

        // Second pass: recompute with available space 300x300
        engine.computeLayout(id: parent, availableSpace: Size(width: .definite(px(300.0)), height: .definite(px(300.0))))
        let secondBounds = engine.layoutBounds(id: child, scaleFactor: 1.0)
        #expect(abs(secondBounds.size.width.value - 100.0) < 0.1) // Parent explicit size is still 100
    }

    // MARK: - Engine Clear & Reuse

    @Test("TaffyLayoutEngine clear resets all state")
    func testEngineClear() {
        var engine = TaffyLayoutEngine()

        var style = Style()
        style.size = Size(width: .definite(.pixels(px(50.0))), height: .definite(.pixels(px(50.0))))

        let n1 = engine.requestLayout(style: style, remSize: px(16.0), scaleFactor: 1.0)
        engine.computeLayout(id: n1, availableSpace: Size(width: .definite(px(50.0)), height: .definite(px(50.0))))

        let b1 = engine.layoutBounds(id: n1, scaleFactor: 1.0)
        #expect(abs(b1.size.width.value - 50.0) < 0.1)

        engine.clear()

        // Create new node after clear
        let n2 = engine.requestLayout(style: style, remSize: px(16.0), scaleFactor: 1.0)
        engine.computeLayout(id: n2, availableSpace: Size(width: .definite(px(80.0)), height: .definite(px(80.0))))
        let b2 = engine.layoutBounds(id: n2, scaleFactor: 1.0)
        #expect(abs(b2.size.width.value - 50.0) < 0.1)
    }
}
