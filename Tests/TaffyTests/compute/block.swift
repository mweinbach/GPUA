// Swift-only: Behavioral unit tests for Taffy CSS block layout engine

import Testing
@testable import Taffy

@Suite("Taffy Block Layout Tests")
struct TaffyBlockLayoutTests {
    @Test("Block items stack vertically by default")
    func testBlockVerticalStacking() {
        var tree: TaffyTree<Void> = TaffyTree.new()

        var containerStyle = Style<String>.DEFAULT
        containerStyle.display = .block
        containerStyle.size = Size(width: .length(300), height: .auto())

        var itemStyle1 = Style<String>.DEFAULT
        itemStyle1.size = Size(width: .length(100), height: .length(50))

        var itemStyle2 = Style<String>.DEFAULT
        itemStyle2.size = Size(width: .length(100), height: .length(70))

        guard case .success(let child1) = tree.newLeaf(itemStyle1),
              case .success(let child2) = tree.newLeaf(itemStyle2),
              case .success(let root) = tree.newWithChildren(containerStyle, [child1, child2]) else {
            Issue.record("Failed tree setup")
            return
        }

        #expect(tree.computeLayout(root: root, availableSpace: Size(width: .definite(300), height: .maxContent)).isSuccess)

        guard case .success(let lRoot) = tree.layout(root),
              case .success(let lChild1) = tree.layout(child1),
              case .success(let lChild2) = tree.layout(child2) else {
            Issue.record("Failed to get layouts")
            return
        }

        #expect(lRoot.size.width == 300)
        #expect(lRoot.size.height == 120) // 50 + 70

        #expect(lChild1.location.y == 0)
        #expect(lChild1.size.height == 50)

        #expect(lChild2.location.y == 50)
        #expect(lChild2.size.height == 70)
    }

    @Test("Block auto margins horizontally center element")
    func testBlockAutoMarginsCentering() {
        var tree: TaffyTree<Void> = TaffyTree.new()

        var containerStyle = Style<String>.DEFAULT
        containerStyle.display = .block
        containerStyle.size = Size(width: .length(400), height: .length(200))

        var childStyle = Style<String>.DEFAULT
        childStyle.size = Size(width: .length(200), height: .length(100))
        childStyle.margin = Rect(left: .auto(), right: .auto(), top: .length(0), bottom: .length(0))

        guard case .success(let child) = tree.newLeaf(childStyle),
              case .success(let root) = tree.newWithChildren(containerStyle, [child]) else {
            Issue.record("Failed tree setup")
            return
        }

        #expect(tree.computeLayout(root: root, availableSpace: Size(width: .definite(400), height: .definite(200))).isSuccess)

        guard case .success(let lChild) = tree.layout(child) else {
            Issue.record("Failed to get child layout")
            return
        }

        // 400 container - 200 child = 200 remaining / 2 = 100 on left
        #expect(lChild.location.x == 100)
        #expect(lChild.size.width == 200)
    }

    @Test("Block adjacent vertical margins collapse")
    func testBlockMarginCollapsing() {
        var tree: TaffyTree<Void> = TaffyTree.new()

        var containerStyle = Style<String>.DEFAULT
        containerStyle.display = .block
        containerStyle.size = Size(width: .length(200), height: .auto())

        var itemStyle1 = Style<String>.DEFAULT
        itemStyle1.size = Size(width: .length(100), height: .length(50))
        itemStyle1.margin = Rect(left: .length(0), right: .length(0), top: .length(0), bottom: .length(30))

        var itemStyle2 = Style<String>.DEFAULT
        itemStyle2.size = Size(width: .length(100), height: .length(50))
        itemStyle2.margin = Rect(left: .length(0), right: .length(0), top: .length(20), bottom: .length(0))

        guard case .success(let child1) = tree.newLeaf(itemStyle1),
              case .success(let child2) = tree.newLeaf(itemStyle2),
              case .success(let root) = tree.newWithChildren(containerStyle, [child1, child2]) else {
            Issue.record("Failed tree setup")
            return
        }

        #expect(tree.computeLayout(root: root, availableSpace: Size(width: .definite(200), height: .maxContent)).isSuccess)

        guard case .success(let lRoot) = tree.layout(root),
              case .success(let lChild1) = tree.layout(child1),
              case .success(let lChild2) = tree.layout(child2) else {
            Issue.record("Failed to get layouts")
            return
        }

        // Margins collapse: max(30, 20) = 30
        #expect(lChild1.location.y == 0)
        #expect(lChild2.location.y == 50 + 30) // 80
        #expect(lRoot.size.height == 80 + 50)  // 130
    }
}
