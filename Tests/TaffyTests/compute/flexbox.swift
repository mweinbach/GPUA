// Swift-only: Behavioral unit tests for Taffy flexbox layout engine

import Testing
@testable import Taffy

@Suite("Taffy Flexbox Layout Tests")
struct TaffyFlexboxLayoutTests {
    @Test("Flex row distributes space according to flex-grow")
    func testFlexGrowDistribution() {
        var tree: TaffyTree<Void> = TaffyTree.new()

        var containerStyle = Style<String>.DEFAULT
        containerStyle.display = .flex
        containerStyle.flexDirection = .row
        containerStyle.size = Size(width: .length(300), height: .length(100))

        // Child 1: flex-grow 1
        var item1 = Style<String>.DEFAULT
        item1.flexGrow = 1.0
        item1.flexBasis = .length(0)

        // Child 2: flex-grow 2
        var item2 = Style<String>.DEFAULT
        item2.flexGrow = 2.0
        item2.flexBasis = .length(0)

        guard case .success(let c1) = tree.newLeaf(item1),
              case .success(let c2) = tree.newLeaf(item2),
              case .success(let root) = tree.newWithChildren(containerStyle, [c1, c2]) else {
            Issue.record("Failed tree setup")
            return
        }

        #expect(tree.computeLayout(root: root, availableSpace: Size(width: .definite(300), height: .definite(100))).isSuccess)

        guard case .success(let l1) = tree.layout(c1),
              case .success(let l2) = tree.layout(c2) else {
            Issue.record("Failed to get layouts")
            return
        }

        // 300 total space: 1/3 (100) to c1, 2/3 (200) to c2
        #expect(l1.size.width == 100)
        #expect(l1.location.x == 0)

        #expect(l2.size.width == 200)
        #expect(l2.location.x == 100)
    }

    @Test("Flex row shrinks items according to flex-shrink")
    func testFlexShrinkDistribution() {
        var tree: TaffyTree<Void> = TaffyTree.new()

        var containerStyle = Style<String>.DEFAULT
        containerStyle.display = .flex
        containerStyle.flexDirection = .row
        containerStyle.size = Size(width: .length(200), height: .length(100))

        // Child 1: basis 150, shrink 1
        var item1 = Style<String>.DEFAULT
        item1.flexBasis = .length(150)
        item1.flexShrink = 1.0

        // Child 2: basis 150, shrink 1
        var item2 = Style<String>.DEFAULT
        item2.flexBasis = .length(150)
        item2.flexShrink = 1.0

        guard case .success(let c1) = tree.newLeaf(item1),
              case .success(let c2) = tree.newLeaf(item2),
              case .success(let root) = tree.newWithChildren(containerStyle, [c1, c2]) else {
            Issue.record("Failed tree setup")
            return
        }

        #expect(tree.computeLayout(root: root, availableSpace: Size(width: .definite(200), height: .definite(100))).isSuccess)

        guard case .success(let l1) = tree.layout(c1),
              case .success(let l2) = tree.layout(c2) else {
            Issue.record("Failed to get layouts")
            return
        }

        // 300 total basis, 200 container -> 100 overflow shrunk equally (50 each)
        #expect(l1.size.width == 100)
        #expect(l2.size.width == 100)
    }

    @Test("Flex auto margins push items to edges")
    func testFlexAutoMargins() {
        var tree: TaffyTree<Void> = TaffyTree.new()

        var containerStyle = Style<String>.DEFAULT
        containerStyle.display = .flex
        containerStyle.flexDirection = .row
        containerStyle.size = Size(width: .length(400), height: .length(100))

        var item1 = Style<String>.DEFAULT
        item1.size = Size(width: .length(50), height: .length(50))
        item1.margin = Rect(left: .length(0), right: .auto(), top: .length(0), bottom: .length(0))

        var item2 = Style<String>.DEFAULT
        item2.size = Size(width: .length(50), height: .length(50))

        guard case .success(let c1) = tree.newLeaf(item1),
              case .success(let c2) = tree.newLeaf(item2),
              case .success(let root) = tree.newWithChildren(containerStyle, [c1, c2]) else {
            Issue.record("Failed tree setup")
            return
        }

        #expect(tree.computeLayout(root: root, availableSpace: Size(width: .definite(400), height: .definite(100))).isSuccess)

        guard case .success(let l1) = tree.layout(c1),
              case .success(let l2) = tree.layout(c2) else {
            Issue.record("Failed to get layouts")
            return
        }

        #expect(l1.location.x == 0)
        // Auto margin absorbs all remaining space: 400 - 50 - 50 = 300
        #expect(l2.location.x == 350)
    }

    @Test("Flex wrapping across lines")
    func testFlexWrap() {
        var tree: TaffyTree<Void> = TaffyTree.new()

        var containerStyle = Style<String>.DEFAULT
        containerStyle.display = .flex
        containerStyle.flexDirection = .row
        containerStyle.flexWrap = .wrap
        containerStyle.size = Size(width: .length(200), height: .auto())

        var item = Style<String>.DEFAULT
        item.size = Size(width: .length(120), height: .length(50))

        guard case .success(let c1) = tree.newLeaf(item),
              case .success(let c2) = tree.newLeaf(item),
              case .success(let root) = tree.newWithChildren(containerStyle, [c1, c2]) else {
            Issue.record("Failed tree setup")
            return
        }

        #expect(tree.computeLayout(root: root, availableSpace: Size(width: .definite(200), height: .maxContent)).isSuccess)

        guard case .success(let lRoot) = tree.layout(root),
              case .success(let l1) = tree.layout(c1),
              case .success(let l2) = tree.layout(c2) else {
            Issue.record("Failed to get layouts")
            return
        }

        // Line 1: c1 at (0, 0)
        #expect(l1.location.x == 0)
        #expect(l1.location.y == 0)

        // Line 2: c2 wraps to (0, 50)
        #expect(l2.location.x == 0)
        #expect(l2.location.y == 50)

        // Container height accommodates both lines: 100
        #expect(lRoot.size.height == 100)
    }

    @Test("Cross axis alignment center")
    func testFlexCrossAxisAlignmentCenter() {
        var tree: TaffyTree<Void> = TaffyTree.new()

        var containerStyle = Style<String>.DEFAULT
        containerStyle.display = .flex
        containerStyle.flexDirection = .row
        containerStyle.alignItems = .center
        containerStyle.size = Size(width: .length(200), height: .length(100))

        var item = Style<String>.DEFAULT
        item.size = Size(width: .length(50), height: .length(40))

        guard case .success(let c1) = tree.newLeaf(item),
              case .success(let root) = tree.newWithChildren(containerStyle, [c1]) else {
            Issue.record("Failed tree setup")
            return
        }

        #expect(tree.computeLayout(root: root, availableSpace: Size(width: .definite(200), height: .definite(100))).isSuccess)

        guard case .success(let l1) = tree.layout(c1) else {
            Issue.record("Failed to get layout")
            return
        }

        // Vertically centered: (100 - 40) / 2 = 30
        #expect(l1.location.y == 30)
    }
}
