// Swift-only: Empirical stress test harness for Taffy 0.9.0 engine and GPUI layout bridge

import Testing
import Foundation
import Refineable
import Taffy
@testable import GPUI

@Suite("Layout & Geometry Empirical Stress Harness")
struct LayoutStressTests {

    // MARK: - 1. Deeply Nested Hierarchies (14+ levels of mixed flexbox, block, and CSS Grid containers)

    @Test("Deeply nested hierarchy (14 levels) with alternating flex, block, and grid containers accumulates exact offsets")
    func testDeeplyNestedMixedContainers() {
        var engine = TaffyLayoutEngine.new()
        let scaleFactor: Float = 1.0
        let remSize = px(16.0)

        // We construct 14 levels:
        // Level 13 (Leaf): explicit 50x50, margin 3
        var leafStyle = Style()
        leafStyle.size = Size(width: .definite(.pixels(px(50.0))), height: .definite(.pixels(px(50.0))))
        leafStyle.margin = Edges(top: .definite(.pixels(px(3.0))), right: .auto, bottom: .auto, left: .definite(.pixels(px(3.0))))
        let leaf = engine.requestLayout(style: leafStyle, remSize: remSize, scaleFactor: scaleFactor)

        var currentChild = leaf
        var expectedOriginX: Float = 3.0
        var expectedOriginY: Float = 3.0

        // Levels 12 down to 0:
        // Alternate between Flex, Block, Grid with specific padding and margins
        for level in (0...12).reversed() {
            var containerStyle = Style()
            let pad: Float = Float(level % 4 + 2) // 2 to 5 px padding
            containerStyle.padding = Edges(top: .pixels(px(pad)), right: .pixels(px(pad)), bottom: .pixels(px(pad)), left: .pixels(px(pad)))
            expectedOriginX += pad
            expectedOriginY += pad

            // Only children (levels 1...12) have margins relative to their parent container
            if level > 0 {
                let mar: Float = Float(level % 3 + 1) // 1 to 3 px margin
                containerStyle.margin = Edges(top: .definite(.pixels(px(mar))), right: .auto, bottom: .auto, left: .definite(.pixels(px(mar))))
                expectedOriginX += mar
                expectedOriginY += mar
            }

            if level % 3 == 0 {
                // Flex container
                containerStyle.display = .flex
                containerStyle.flexDirection = .column
                containerStyle.size = Size(width: .auto, height: .auto)
            } else if level % 3 == 1 {
                // Block container
                containerStyle.display = .block
                containerStyle.size = Size(width: .auto, height: .auto)
            } else {
                // CSS Grid container
                containerStyle.display = .grid
                containerStyle.gridCols = GridTemplate(repeat: 1, minSize: .zero)
                containerStyle.size = Size(width: .auto, height: .auto)
            }

            let parentNode = engine.requestLayout(style: containerStyle, remSize: remSize, scaleFactor: scaleFactor, children: [currentChild])
            currentChild = parentNode
        }

        let root = currentChild

        // Compute layout at root with 1000x1000 definite space
        var window = Window(scaleFactor: scaleFactor)
        var app = App()
        engine.computeLayout(
            id: root,
            availableSpace: Size(width: .definite(px(1000.0)), height: .definite(px(1000.0))),
            window: &window,
            cx: &app
        )

        let rootBounds = engine.layoutBounds(id: root, scaleFactor: scaleFactor)
        let leafBounds = engine.layoutBounds(id: leaf, scaleFactor: scaleFactor)

        // Root starts at origin (0, 0)
        #expect(abs(rootBounds.origin.x.value - 0.0) < 0.1)
        #expect(abs(rootBounds.origin.y.value - 0.0) < 0.1)

        // Leaf dimensions must match explicit size
        #expect(abs(leafBounds.size.width.value - 50.0) < 0.1)
        #expect(abs(leafBounds.size.height.value - 50.0) < 0.1)

        // Leaf origin must match exact accumulated offset through all 14 levels
        #expect(abs(leafBounds.origin.x.value - expectedOriginX) < 0.1)
        #expect(abs(leafBounds.origin.y.value - expectedOriginY) < 0.1)
    }

    // MARK: - 2. Intrinsic Sizing with Custom Measure Functions Under Dynamic Constraints

    @Test("Custom measure function accurately responds to definite, minContent, and maxContent constraints")
    func testIntrinsicSizingUnderDynamicConstraints() {
        var engine = TaffyLayoutEngine.new()
        let remSize = px(16.0)
        let scaleFactor: Float = 1.0

        final class MeasureTracker: @unchecked Sendable {
            var callCount = 0
            var lastAvailableSpace: GPUI.Size<GPUI.AvailableSpace>?
        }
        let tracker = MeasureTracker()

        var leafStyle = Style()
        leafStyle.display = .flex
        leafStyle.size = Size(width: .auto, height: .auto)

        // Simulated text element:
        // - Under maxContent: width = 240, height = 20 (single unwrapped line)
        // - Under minContent: width = 60, height = 80 (narrowest word wrapped)
        // - Under definite width: wraps text proportionally, clamping between 60 and 240
        let measuredNode = engine.requestMeasuredLayout(
            style: leafStyle,
            remSize: remSize,
            scaleFactor: scaleFactor
        ) { knownDimensions, availableSpace, window, cx in
            tracker.callCount += 1
            tracker.lastAvailableSpace = availableSpace

            switch availableSpace.width {
            case .maxContent:
                return Size(width: px(240.0), height: px(20.0))
            case .minContent:
                return Size(width: px(60.0), height: px(80.0))
            case .definite(let w):
                let clampedWidth = max(60.0, min(w.value, 240.0))
                let computedHeight = max(20.0, ceil(4800.0 / clampedWidth))
                return Size(width: px(clampedWidth), height: px(computedHeight))
            }
        }

        var parentStyle = Style()
        parentStyle.display = .flex
        parentStyle.flexDirection = .column
        parentStyle.size = Size(width: .auto, height: .auto)
        parentStyle.padding = Edges(top: .pixels(px(10.0)), right: .pixels(px(10.0)), bottom: .pixels(px(10.0)), left: .pixels(px(10.0)))

        let root = engine.requestLayout(style: parentStyle, remSize: remSize, scaleFactor: scaleFactor, children: [measuredNode])

        var window = Window(scaleFactor: scaleFactor)
        var app = App()

        // 1. Definite available space: 120px width
        // Expected: leaf width = 120, height = ceil(4800 / 120) = 40.0
        // Parent width = 120 + 20 = 140.0, height = 40 + 20 = 60.0
        engine.computeLayout(
            id: root,
            availableSpace: Size(width: .definite(px(140.0)), height: .maxContent),
            window: &window,
            cx: &app
        )

        var leafBounds = engine.layoutBounds(id: measuredNode, scaleFactor: scaleFactor)
        var rootBounds = engine.layoutBounds(id: root, scaleFactor: scaleFactor)
        #expect(abs(leafBounds.size.width.value - 120.0) < 0.1)
        #expect(abs(leafBounds.size.height.value - 40.0) < 0.1)
        #expect(abs(rootBounds.size.width.value - 140.0) < 0.1)
        #expect(abs(rootBounds.size.height.value - 60.0) < 0.1)

        // 2. MaxContent constraint
        // Expected: leaf width = 240, height = 20
        // Parent width = 240 + 20 = 260.0, height = 20 + 20 = 40.0
        engine.computeLayout(
            id: root,
            availableSpace: Size(width: .maxContent, height: .maxContent),
            window: &window,
            cx: &app
        )

        leafBounds = engine.layoutBounds(id: measuredNode, scaleFactor: scaleFactor)
        rootBounds = engine.layoutBounds(id: root, scaleFactor: scaleFactor)
        #expect(abs(leafBounds.size.width.value - 240.0) < 0.1)
        #expect(abs(leafBounds.size.height.value - 20.0) < 0.1)
        #expect(abs(rootBounds.size.width.value - 260.0) < 0.1)
        #expect(abs(rootBounds.size.height.value - 40.0) < 0.1)

        // 3. MinContent constraint
        // Expected: leaf width = 60, height = 80
        // Parent width = 60 + 20 = 80.0, height = 80 + 20 = 100.0
        engine.computeLayout(
            id: root,
            availableSpace: Size(width: .minContent, height: .minContent),
            window: &window,
            cx: &app
        )

        leafBounds = engine.layoutBounds(id: measuredNode, scaleFactor: scaleFactor)
        rootBounds = engine.layoutBounds(id: root, scaleFactor: scaleFactor)
        #expect(abs(leafBounds.size.width.value - 60.0) < 0.1)
        #expect(abs(leafBounds.size.height.value - 80.0) < 0.1)
        #expect(abs(rootBounds.size.width.value - 80.0) < 0.1)
        #expect(abs(rootBounds.size.height.value - 100.0) < 0.1)
    }

    // MARK: - 3. Dynamic Tree Mutations & Cache Invalidation

    @Test("Dynamic tree mutations: insertion, removal, reordering, and ancestor cache invalidation")
    func testDynamicTreeMutationsAndCacheInvalidation() {
        var tree = TaffyTree<NodeContext>()
        tree.disableRounding()

        var parentStyle = Taffy.Style<String>()
        parentStyle.display = .flex
        parentStyle.flexDirection = .row
        parentStyle.size = Taffy.Size(width: .length(400.0), height: .length(100.0))

        var aStyle = Taffy.Style<String>()
        aStyle.size = Taffy.Size(width: .length(80.0), height: .length(60.0))

        var bStyle = Taffy.Style<String>()
        bStyle.size = Taffy.Size(width: .length(100.0), height: .length(60.0))

        var cStyle = Taffy.Style<String>()
        cStyle.size = Taffy.Size(width: .length(120.0), height: .length(60.0))

        let nodeA = try! tree.newLeaf(aStyle).get()
        let nodeB = try! tree.newLeaf(bStyle).get()
        let nodeC = try! tree.newLeaf(cStyle).get()

        let parent = try! tree.newWithChildren(parentStyle, [nodeA, nodeB]).get()

        // Pass 1: Initial layout with [A, B]
        _ = tree.computeLayout(parent, Taffy.Size(width: .definite(400.0), height: .definite(100.0)))

        #expect(tree.dirty(parent) == .success(false))
        #expect(tree.dirty(nodeA) == .success(false))
        #expect(tree.dirty(nodeB) == .success(false))

        var layoutA = try! tree.layout(nodeA).get()
        var layoutB = try! tree.layout(nodeB).get()
        #expect(abs(layoutA.location.x - 0.0) < 0.1)
        #expect(abs(layoutA.size.width - 80.0) < 0.1)
        #expect(abs(layoutB.location.x - 80.0) < 0.1)
        #expect(abs(layoutB.size.width - 100.0) < 0.1)

        // Pass 2: Insert nodeC at index 1 between A and B -> [A, C, B]
        _ = tree.insertChildAtIndex(parent, 1, nodeC)
        #expect(tree.dirty(parent) == .success(true))

        _ = tree.computeLayout(parent, Taffy.Size(width: .definite(400.0), height: .definite(100.0)))
        #expect(tree.dirty(parent) == .success(false))

        layoutA = try! tree.layout(nodeA).get()
        var layoutC = try! tree.layout(nodeC).get()
        layoutB = try! tree.layout(nodeB).get()

        #expect(abs(layoutA.location.x - 0.0) < 0.1)
        #expect(abs(layoutC.location.x - 80.0) < 0.1)
        #expect(abs(layoutC.size.width - 120.0) < 0.1)
        #expect(abs(layoutB.location.x - 200.0) < 0.1) // 80 + 120 = 200

        // Pass 3: Remove nodeA from parent -> [C, B]
        _ = tree.removeChild(parent, nodeA)
        #expect(tree.dirty(parent) == .success(true))

        _ = tree.computeLayout(parent, Taffy.Size(width: .definite(400.0), height: .definite(100.0)))
        layoutC = try! tree.layout(nodeC).get()
        layoutB = try! tree.layout(nodeB).get()

        #expect(abs(layoutC.location.x - 0.0) < 0.1)
        #expect(abs(layoutB.location.x - 120.0) < 0.1)

        // Pass 4: Reorder children via setChildren -> [B, C]
        _ = tree.setChildren(parent, [nodeB, nodeC])
        #expect(tree.dirty(parent) == .success(true))

        _ = tree.computeLayout(parent, Taffy.Size(width: .definite(400.0), height: .definite(100.0)))
        layoutB = try! tree.layout(nodeB).get()
        layoutC = try! tree.layout(nodeC).get()

        #expect(abs(layoutB.location.x - 0.0) < 0.1)
        #expect(abs(layoutC.location.x - 100.0) < 0.1)

        // Pass 5: Mutate style of nodeB and verify ancestor dirty propagation
        var updatedBStyle = bStyle
        updatedBStyle.size.width = .length(150.0)
        _ = tree.setStyle(nodeB, updatedBStyle)

        #expect(tree.dirty(nodeB) == .success(true))
        #expect(tree.dirty(parent) == .success(true))

        _ = tree.computeLayout(parent, Taffy.Size(width: .definite(400.0), height: .definite(100.0)))
        layoutB = try! tree.layout(nodeB).get()
        layoutC = try! tree.layout(nodeC).get()

        #expect(abs(layoutB.size.width - 150.0) < 0.1)
        #expect(abs(layoutC.location.x - 150.0) < 0.1)
    }

    // MARK: - 4. Fractional Flex Factors and Fractional Grid Tracks

    @Test("Fractional flex-grow distribution matches exact proportions")
    func testFractionalFlexGrow() {
        var engine = TaffyLayoutEngine.new()
        let remSize = px(16.0)
        let scaleFactor: Float = 1.0

        // Parent container: 1000px width
        // Child 1: base 100px, flexGrow 0.2
        // Child 2: base 100px, flexGrow 0.3
        // Child 3: base 100px, flexGrow 0.5
        // Total base = 300px. Remaining free space = 700px.
        // Sum flexGrow = 0.2 + 0.3 + 0.5 = 1.0.
        // Child 1 grows by 0.2 * 700 = 140 -> 240px.
        // Child 2 grows by 0.3 * 700 = 210 -> 310px.
        // Child 3 grows by 0.5 * 700 = 350 -> 450px.
        // Sum = 240 + 310 + 450 = 1000px.
        var s1 = Style()
        s1.size = Size(width: .definite(.pixels(px(100.0))), height: .definite(.pixels(px(50.0))))
        s1.flexGrow = 0.2

        var s2 = Style()
        s2.size = Size(width: .definite(.pixels(px(100.0))), height: .definite(.pixels(px(50.0))))
        s2.flexGrow = 0.3

        var s3 = Style()
        s3.size = Size(width: .definite(.pixels(px(100.0))), height: .definite(.pixels(px(50.0))))
        s3.flexGrow = 0.5

        let c1 = engine.requestLayout(style: s1, remSize: remSize, scaleFactor: scaleFactor)
        let c2 = engine.requestLayout(style: s2, remSize: remSize, scaleFactor: scaleFactor)
        let c3 = engine.requestLayout(style: s3, remSize: remSize, scaleFactor: scaleFactor)

        var parentStyle = Style()
        parentStyle.display = .flex
        parentStyle.flexDirection = .row
        parentStyle.size = Size(width: .definite(.pixels(px(1000.0))), height: .definite(.pixels(px(50.0))))

        let parent = engine.requestLayout(style: parentStyle, remSize: remSize, scaleFactor: scaleFactor, children: [c1, c2, c3])

        var window = Window(scaleFactor: scaleFactor)
        var app = App()
        engine.computeLayout(
            id: parent,
            availableSpace: Size(width: .definite(px(1000.0)), height: .definite(px(50.0))),
            window: &window,
            cx: &app
        )

        let b1 = engine.layoutBounds(id: c1, scaleFactor: scaleFactor)
        let b2 = engine.layoutBounds(id: c2, scaleFactor: scaleFactor)
        let b3 = engine.layoutBounds(id: c3, scaleFactor: scaleFactor)

        #expect(abs(b1.size.width.value - 240.0) < 0.1)
        #expect(abs(b1.origin.x.value - 0.0) < 0.1)

        #expect(abs(b2.size.width.value - 310.0) < 0.1)
        #expect(abs(b2.origin.x.value - 240.0) < 0.1)

        #expect(abs(b3.size.width.value - 450.0) < 0.1)
        #expect(abs(b3.origin.x.value - 550.0) < 0.1)
    }

    @Test("Fractional flex-shrink distribution matches weighted proportions")
    func testFractionalFlexShrink() {
        var engine = TaffyLayoutEngine.new()
        let remSize = px(16.0)
        let scaleFactor: Float = 1.0

        // Parent container: 300px width
        // Child 1: base 200px, flexShrink 0.5
        // Child 2: base 200px, flexShrink 1.5
        // Total base = 400px. Overflow = 100px.
        // Scaled factors: 200 * 0.5 = 100; 200 * 1.5 = 300. Total scaled = 400.
        // Child 1 shrink: (100 / 400) * 100 = 25px -> Final width = 175px.
        // Child 2 shrink: (300 / 400) * 100 = 75px -> Final width = 125px.
        var s1 = Style()
        s1.size = Size(width: .definite(.pixels(px(200.0))), height: .definite(.pixels(px(50.0))))
        s1.flexShrink = 0.5

        var s2 = Style()
        s2.size = Size(width: .definite(.pixels(px(200.0))), height: .definite(.pixels(px(50.0))))
        s2.flexShrink = 1.5

        let c1 = engine.requestLayout(style: s1, remSize: remSize, scaleFactor: scaleFactor)
        let c2 = engine.requestLayout(style: s2, remSize: remSize, scaleFactor: scaleFactor)

        var parentStyle = Style()
        parentStyle.display = .flex
        parentStyle.flexDirection = .row
        parentStyle.size = Size(width: .definite(.pixels(px(300.0))), height: .definite(.pixels(px(50.0))))

        let parent = engine.requestLayout(style: parentStyle, remSize: remSize, scaleFactor: scaleFactor, children: [c1, c2])

        var window = Window(scaleFactor: scaleFactor)
        var app = App()
        engine.computeLayout(
            id: parent,
            availableSpace: Size(width: .definite(px(300.0)), height: .definite(px(50.0))),
            window: &window,
            cx: &app
        )

        let b1 = engine.layoutBounds(id: c1, scaleFactor: scaleFactor)
        let b2 = engine.layoutBounds(id: c2, scaleFactor: scaleFactor)

        #expect(abs(b1.size.width.value - 175.0) < 0.1)
        #expect(abs(b1.origin.x.value - 0.0) < 0.1)

        #expect(abs(b2.size.width.value - 125.0) < 0.1)
        #expect(abs(b2.origin.x.value - 175.0) < 0.1)
    }

    @Test("CSS Grid fractional tracks, minmax, and auto placement resolution")
    func testCSSGridFractionalTracksAndAutoPlacement() {
        var tree = TaffyTree<NodeContext>()
        tree.disableRounding()

        // 3-column grid: [minmax(100px, 0.5fr), minmax(100px, 1.5fr), minmax(100px, 2.5fr)]
        // In 900px width:
        // Free space = 900px. Total fr = 0.5 + 1.5 + 2.5 = 4.5fr.
        // Col 1: (0.5 / 4.5) * 900 = 100px (matches min 100px).
        // Col 2: (1.5 / 4.5) * 900 = 300px (>= min 100px).
        // Col 3: (2.5 / 4.5) * 900 = 500px (>= min 100px).
        var gridStyle = Taffy.Style<String>()
        gridStyle.display = .grid
        gridStyle.size = Taffy.Size(width: .length(900.0), height: .length(200.0))
        gridStyle.gridTemplateColumns = [
            minmax(length(100.0), fr(0.5)),
            minmax(length(100.0), fr(1.5)),
            minmax(length(100.0), fr(2.5))
        ]
        gridStyle.gridTemplateRows = [
            minmax(length(80.0), fr(1.0)),
            minmax(length(80.0), fr(1.0))
        ]

        // 4 items:
        // Item 1: Explicitly placed at row 1, col 2
        var item1Style = Taffy.Style<String>()
        item1Style.gridColumn = Line(start: line(2), end: .auto)
        item1Style.gridRow = Line(start: line(1), end: .auto)

        // Item 2: Auto placed (should go to row 1, col 1)
        let item2Style = Taffy.Style<String>()

        // Item 3: Auto placed (should go to row 1, col 3)
        let item3Style = Taffy.Style<String>()

        // Item 4: Auto placed (should wrap to row 2, col 1)
        let item4Style = Taffy.Style<String>()

        let n1 = try! tree.newLeaf(item1Style).get()
        let n2 = try! tree.newLeaf(item2Style).get()
        let n3 = try! tree.newLeaf(item3Style).get()
        let n4 = try! tree.newLeaf(item4Style).get()

        let grid = try! tree.newWithChildren(gridStyle, [n1, n2, n3, n4]).get()

        _ = tree.computeLayout(grid, Taffy.Size(width: .definite(900.0), height: .definite(200.0)))

        let l1 = try! tree.layout(n1).get()
        let l2 = try! tree.layout(n2).get()
        let l3 = try! tree.layout(n3).get()
        let l4 = try! tree.layout(n4).get()

        // Item 2 placed at Row 1, Col 1: (0, 0), width 100, height 100
        #expect(abs(l2.location.x - 0.0) < 0.1)
        #expect(abs(l2.location.y - 0.0) < 0.1)
        #expect(abs(l2.size.width - 100.0) < 0.1)
        #expect(abs(l2.size.height - 100.0) < 0.1)

        // Item 1 placed at Row 1, Col 2: (100, 0), width 300, height 100
        #expect(abs(l1.location.x - 100.0) < 0.1)
        #expect(abs(l1.location.y - 0.0) < 0.1)
        #expect(abs(l1.size.width - 300.0) < 0.1)
        #expect(abs(l1.size.height - 100.0) < 0.1)

        // Item 3 placed at Row 1, Col 3: (400, 0), width 500, height 100
        #expect(abs(l3.location.x - 400.0) < 0.1)
        #expect(abs(l3.location.y - 0.0) < 0.1)
        #expect(abs(l3.size.width - 500.0) < 0.1)
        #expect(abs(l3.size.height - 100.0) < 0.1)

        // Item 4 placed at Row 2, Col 1: (0, 100), width 100, height 100
        #expect(abs(l4.location.x - 0.0) < 0.1)
        #expect(abs(l4.location.y - 100.0) < 0.1)
        #expect(abs(l4.size.width - 100.0) < 0.1)
        #expect(abs(l4.size.height - 100.0) < 0.1)
    }

    // MARK: - 5. Extreme Boundary Values

    @Test("Zero-sized container and elements survive layout without NaN, division by zero, or crashes")
    func testZeroSizeBoundaryValues() {
        var engine = TaffyLayoutEngine.new()
        let remSize = px(16.0)
        let scaleFactor: Float = 1.0

        var zeroChildStyle = Style()
        zeroChildStyle.size = Size(width: .definite(.pixels(px(0.0))), height: .definite(.pixels(px(0.0))))
        zeroChildStyle.flexGrow = 1.0
        zeroChildStyle.flexShrink = 1.0
        zeroChildStyle.aspectRatio = 1.5

        let c1 = engine.requestLayout(style: zeroChildStyle, remSize: remSize, scaleFactor: scaleFactor)

        var zeroParentStyle = Style()
        zeroParentStyle.display = .flex
        zeroParentStyle.size = Size(width: .definite(.pixels(px(0.0))), height: .definite(.pixels(px(0.0))))

        let parent = engine.requestLayout(style: zeroParentStyle, remSize: remSize, scaleFactor: scaleFactor, children: [c1])

        var window = Window(scaleFactor: scaleFactor)
        var app = App()
        engine.computeLayout(
            id: parent,
            availableSpace: Size(width: .definite(px(0.0)), height: .definite(px(0.0))),
            window: &window,
            cx: &app
        )

        let parentBounds = engine.layoutBounds(id: parent, scaleFactor: scaleFactor)
        let childBounds = engine.layoutBounds(id: c1, scaleFactor: scaleFactor)

        #expect(!parentBounds.size.width.value.isNaN && !parentBounds.size.width.value.isInfinite)
        #expect(!parentBounds.size.height.value.isNaN && !parentBounds.size.height.value.isInfinite)
        #expect(abs(parentBounds.size.width.value - 0.0) < 0.1)
        #expect(abs(parentBounds.size.height.value - 0.0) < 0.1)

        #expect(!childBounds.size.width.value.isNaN && !childBounds.size.width.value.isInfinite)
        #expect(!childBounds.size.height.value.isNaN && !childBounds.size.height.value.isInfinite)
        #expect(abs(childBounds.size.width.value - 0.0) < 0.1)
        #expect(abs(childBounds.size.height.value - 0.0) < 0.1)
    }

    @Test("Massive scale factor (100x) preserves exact logical coordinates without precision drift")
    func testMassiveScaleFactor() {
        var engine = TaffyLayoutEngine.new()
        let remSize = px(16.0)
        let scaleFactor: Float = 100.0

        var childStyle = Style()
        childStyle.size = Size(width: .definite(.pixels(px(12.34))), height: .definite(.pixels(px(5.67))))
        childStyle.margin = Edges(top: .definite(.pixels(px(2.5))), right: .auto, bottom: .auto, left: .definite(.pixels(px(2.5))))

        let c1 = engine.requestLayout(style: childStyle, remSize: remSize, scaleFactor: scaleFactor)

        var parentStyle = Style()
        parentStyle.display = .flex
        parentStyle.padding = Edges(top: .pixels(px(10.0)), right: .pixels(px(10.0)), bottom: .pixels(px(10.0)), left: .pixels(px(10.0)))
        parentStyle.size = Size(width: .definite(.pixels(px(200.0))), height: .definite(.pixels(px(100.0))))

        let parent = engine.requestLayout(style: parentStyle, remSize: remSize, scaleFactor: scaleFactor, children: [c1])

        var window = Window(scaleFactor: scaleFactor)
        var app = App()
        engine.computeLayout(
            id: parent,
            availableSpace: Size(width: .definite(px(200.0)), height: .definite(px(100.0))),
            window: &window,
            cx: &app
        )

        let childBounds = engine.layoutBounds(id: c1, scaleFactor: scaleFactor)

        // Child origin in logical pixels: parent.padding(10.0) + child.margin(2.5) = 12.5
        #expect(abs(childBounds.origin.x.value - 12.5) < 0.1)
        #expect(abs(childBounds.origin.y.value - 12.5) < 0.1)

        // Child size in logical pixels: 12.34 x 5.67
        #expect(abs(childBounds.size.width.value - 12.34) < 0.1)
        #expect(abs(childBounds.size.height.value - 5.67) < 0.1)
    }

    @Test("Negative margins correctly shift elements and overlap siblings")
    func testNegativeMargins() {
        var engine = TaffyLayoutEngine.new()
        let remSize = px(16.0)
        let scaleFactor: Float = 1.0

        // In a flex row:
        // Item 1: 100px wide, margin-right: -30px
        // Item 2: 80px wide
        // Expected: Item 2 starts at 100 - 30 = 70px (overlaps Item 1 by 30px)
        var s1 = Style()
        s1.size = Size(width: .definite(.pixels(px(100.0))), height: .definite(.pixels(px(40.0))))
        s1.margin = Edges(top: .definite(.pixels(px(0.0))), right: .definite(.pixels(px(-30.0))), bottom: .definite(.pixels(px(0.0))), left: .definite(.pixels(px(0.0))))

        var s2 = Style()
        s2.size = Size(width: .definite(.pixels(px(80.0))), height: .definite(.pixels(px(40.0))))
        s2.margin = Edges(top: .definite(.pixels(px(0.0))), right: .definite(.pixels(px(0.0))), bottom: .definite(.pixels(px(0.0))), left: .definite(.pixels(px(0.0))))

        let c1 = engine.requestLayout(style: s1, remSize: remSize, scaleFactor: scaleFactor)
        let c2 = engine.requestLayout(style: s2, remSize: remSize, scaleFactor: scaleFactor)

        var parentStyle = Style()
        parentStyle.display = .flex
        parentStyle.flexDirection = .row
        parentStyle.size = Size(width: .definite(.pixels(px(300.0))), height: .definite(.pixels(px(100.0))))

        let parent = engine.requestLayout(style: parentStyle, remSize: remSize, scaleFactor: scaleFactor, children: [c1, c2])

        var window = Window(scaleFactor: scaleFactor)
        var app = App()
        engine.computeLayout(
            id: parent,
            availableSpace: Size(width: .definite(px(300.0)), height: .definite(px(100.0))),
            window: &window,
            cx: &app
        )

        let b1 = engine.layoutBounds(id: c1, scaleFactor: scaleFactor)
        let b2 = engine.layoutBounds(id: c2, scaleFactor: scaleFactor)

        #expect(abs(b1.origin.x.value - 0.0) < 0.1)
        #expect(abs(b1.size.width.value - 100.0) < 0.1)

        #expect(abs(b2.origin.x.value - 70.0) < 0.1)
        #expect(abs(b2.size.width.value - 80.0) < 0.1)
    }

    @Test("Extreme padding exceeding container bounds clamps content box gracefully")
    func testExtremePaddingClamping() {
        var engine = TaffyLayoutEngine.new()
        let remSize = px(16.0)
        let scaleFactor: Float = 1.0

        // Container: width 100px.
        // Padding: left 70px, right 70px (total padding 140px > 100px container width).
        // Under border-box sizing, the border box cannot shrink below the padding sum,
        // so container width clamps to 140px and content box width becomes 0px.
        // Child with auto size inside should resolve without crash or NaN.
        var childStyle = Style()
        childStyle.size = Size(width: .auto, height: .definite(.pixels(px(20.0))))

        let c1 = engine.requestLayout(style: childStyle, remSize: remSize, scaleFactor: scaleFactor)

        var parentStyle = Style()
        parentStyle.display = .flex
        parentStyle.size = Size(width: .definite(.pixels(px(100.0))), height: .definite(.pixels(px(50.0))))
        parentStyle.padding = Edges(top: .pixels(px(10.0)), right: .pixels(px(70.0)), bottom: .pixels(px(10.0)), left: .pixels(px(70.0)))

        let parent = engine.requestLayout(style: parentStyle, remSize: remSize, scaleFactor: scaleFactor, children: [c1])

        var window = Window(scaleFactor: scaleFactor)
        var app = App()
        engine.computeLayout(
            id: parent,
            availableSpace: Size(width: .definite(px(100.0)), height: .definite(px(50.0))),
            window: &window,
            cx: &app
        )

        let parentBounds = engine.layoutBounds(id: parent, scaleFactor: scaleFactor)
        let childBounds = engine.layoutBounds(id: c1, scaleFactor: scaleFactor)

        #expect(abs(parentBounds.size.width.value - 140.0) < 0.1)
        #expect(!childBounds.size.width.value.isNaN && childBounds.size.width.value >= 0.0)
        #expect(abs(childBounds.origin.x.value - 70.0) < 0.1)
    }
}
