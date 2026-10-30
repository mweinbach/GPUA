// Ported from: src/compute/mod.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

import Testing
@testable import Taffy

@Suite("Taffy Compute Root & Leaf Tests")
struct TaffyComputeTests {
    @Test func hidden_layout_should_hide_recursively() {
        var taffy: TaffyTree<Void> = TaffyTree.new()
        var style = Style<String>.DEFAULT
        style.display = .flex
        style.size = Size(width: .length(50.0), height: .length(50.0))

        let grandchild00 = try! taffy.newLeaf(style).get()
        let grandchild01 = try! taffy.newLeaf(style).get()
        let child00 = try! taffy.newWithChildren(style, [grandchild00, grandchild01]).get()

        let grandchild02 = try! taffy.newLeaf(style).get()
        let child01 = try! taffy.newWithChildren(style, [grandchild02]).get()

        var rootStyle = Style<String>.DEFAULT
        rootStyle.display = .none
        rootStyle.size = Size(width: .length(50.0), height: .length(50.0))
        let root = try! taffy.newWithChildren(rootStyle, [child00, child01]).get()

        computeHiddenLayout(tree: &taffy, node: root)

        for node in [root, child00, child01, grandchild00, grandchild01, grandchild02] {
            let layout = try! taffy.layout(node).get()
            #expect(layout.size == Size<Float>.ZERO)
            #expect(layout.location == Point<Float>.ZERO)
        }
    }

    @Test("Hidden layout produces zero sizes")
    func testHiddenLayout() {
        var tree: TaffyTree<Void> = TaffyTree.new()
        var hiddenStyle = Style<String>.DEFAULT
        hiddenStyle.display = .none
        guard case .success(let node) = tree.newLeaf(hiddenStyle) else { return }

        #expect(tree.computeLayout(root: node, availableSpace: Size.MAX_CONTENT).isSuccess)
        guard case .success(let layout) = tree.layout(node) else { return }
        #expect(layout.size == Size<Float>.ZERO)
        #expect(layout.location == Point<Float>.ZERO)
    }

    @Test("Leaf layout with definite sizes")
    func testLeafDefiniteSize() {
        var tree: TaffyTree<Void> = TaffyTree.new()
        var style = Style<String>.DEFAULT
        style.size = Size(width: .length(120), height: .length(80))
        guard case .success(let node) = tree.newLeaf(style) else { return }

        #expect(tree.computeLayout(root: node, availableSpace: Size(width: .definite(500), height: .definite(500))).isSuccess)
        guard case .success(let layout) = tree.layout(node) else { return }
        #expect(layout.size.width == 120)
        #expect(layout.size.height == 80)
    }

    @Test("Leaf layout with padding and border box-sizing")
    func testLeafBoxSizing() {
        var tree: TaffyTree<Void> = TaffyTree.new()
        
        // Border-box: size includes padding and border
        var borderBoxStyle = Style<String>.DEFAULT
        borderBoxStyle.boxSizing = .borderBox
        borderBoxStyle.size = Size(width: .length(100), height: .length(100))
        borderBoxStyle.padding = Rect(left: .length(10), right: .length(10), top: .length(10), bottom: .length(10))
        borderBoxStyle.border = Rect(left: .length(5), right: .length(5), top: .length(5), bottom: .length(5))

        guard case .success(let n1) = tree.newLeaf(borderBoxStyle) else { return }
        #expect(tree.computeLayout(root: n1, availableSpace: Size(width: .definite(500), height: .definite(500))).isSuccess)
        guard case .success(let l1) = tree.layout(n1) else { return }
        #expect(l1.size.width == 100)
        #expect(l1.size.height == 100)

        // Content-box: size is content only, padding & border added to outer size
        var contentBoxStyle = Style<String>.DEFAULT
        contentBoxStyle.boxSizing = .contentBox
        contentBoxStyle.size = Size(width: .length(100), height: .length(100))
        contentBoxStyle.padding = Rect(left: .length(10), right: .length(10), top: .length(10), bottom: .length(10))
        contentBoxStyle.border = Rect(left: .length(5), right: .length(5), top: .length(5), bottom: .length(5))

        guard case .success(let n2) = tree.newLeaf(contentBoxStyle) else { return }
        #expect(tree.computeLayout(root: n2, availableSpace: Size(width: .definite(500), height: .definite(500))).isSuccess)
        guard case .success(let l2) = tree.layout(n2) else { return }
        #expect(l2.size.width == 130) // 100 + 20 + 10
        #expect(l2.size.height == 130)
    }

    @Test("Coordinate rounding pass rounds float positions and sizes")
    func testCoordinateRounding() {
        var tree: TaffyTree<Void> = TaffyTree.new()
        tree.enableRounding()

        var parentStyle = Style<String>.DEFAULT
        parentStyle.size = Size(width: .length(100.4), height: .length(100.6))
        guard case .success(let parent) = tree.newLeaf(parentStyle) else { return }

        #expect(tree.computeLayout(root: parent, availableSpace: Size.MAX_CONTENT).isSuccess)
        guard case .success(let layout) = tree.layout(parent) else { return }
        #expect(layout.size.width == 100.0)
        #expect(layout.size.height == 101.0)
    }
}
