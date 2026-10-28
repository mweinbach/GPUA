// Ported from: src/tree/taffy_tree.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

import Testing
@testable import Taffy

private func sizeMeasureFunction(
    _ knownDimensions: Size<Float?>,
    _ availableSpace: Size<AvailableSpace>,
    _ nodeId: NodeId,
    _ nodeContext: inout Size<Float>?,
    _ style: Style<String>
) -> Size<Float> {
    Size(
        width: knownDimensions.width ?? nodeContext?.width ?? 0.0,
        height: knownDimensions.height ?? nodeContext?.height ?? 0.0
    )
}

@Suite("Taffy TaffyTree Tests")
struct TaffyTreeTests {
    @Test("TaffyTree allocates default capacity")
    func testDefaultCapacity() {
        let taffy: TaffyTree<Void> = TaffyTree.new()
        #expect(taffy.nodes.capacity >= 16)
    }

    @Test("TaffyTree with custom capacity")
    func testWithCapacity() {
        let taffy: TaffyTree<Void> = TaffyTree.withCapacity(8)
        #expect(taffy.nodes.capacity >= 8)
    }

    @Test("New leaf creation")
    func testNewLeaf() {
        var taffy: TaffyTree<Void> = TaffyTree.new()
        let res = taffy.newLeaf(Style<String>.DEFAULT)
        #expect(res.isSuccess)
        guard case .success(let node) = res else { return }
        #expect(taffy.childCount(parentNodeId: node) == 0)
    }

    @Test("New leaf with context")
    func testNewLeafWithContext() {
        var taffy: TaffyTree<Size<Float>> = TaffyTree.new()
        let res = taffy.newLeafWithContext(Style<String>.DEFAULT, Size<Float>.ZERO)
        #expect(res.isSuccess)
        guard case .success(let node) = res else { return }
        #expect(taffy.childCount(parentNodeId: node) == 0)
        #expect(taffy.getNodeContext(node) == Size<Float>.ZERO)
    }

    @Test("New with children")
    func testNewWithChildren() {
        var taffy: TaffyTree<Void> = TaffyTree.new()
        guard case .success(let child0) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let child1) = taffy.newLeaf(Style<String>.DEFAULT) else {
            Issue.record("Failed to create leaves")
            return
        }

        let res = taffy.newWithChildren(Style<String>.DEFAULT, [child0, child1])
        #expect(res.isSuccess)
        guard case .success(let node) = res else { return }

        #expect(taffy.childCount(parentNodeId: node) == 2)
        guard case .success(let children) = taffy.children(node) else {
            Issue.record("Failed to get children")
            return
        }
        #expect(children.count == 2)
        #expect(children[0] == child0)
        #expect(children[1] == child1)
    }

    @Test("Remove node and detach hierarchy")
    func testRemoveNodeDetachHierarchy() {
        var taffy: TaffyTree<Void> = TaffyTree.new()
        guard case .success(let node2) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let node1) = taffy.newWithChildren(Style<String>.DEFAULT, [node2]),
              case .success(let node0) = taffy.newWithChildren(Style<String>.DEFAULT, [node1]) else {
            Issue.record("Failed setup")
            return
        }

        guard case .success(let c0) = taffy.children(node0),
              case .success(let c1) = taffy.children(node1) else {
            Issue.record("Failed to get children")
            return
        }
        #expect(c0 == [node1])
        #expect(c1 == [node2])

        // Remove node1: disconnect hierarchy
        let removeRes = taffy.remove(node1)
        #expect(removeRes.isSuccess)

        guard case .success(let rem0) = taffy.children(node0),
              case .success(let rem2) = taffy.children(node2) else {
            Issue.record("Failed to get remaining children")
            return
        }
        #expect(rem0.isEmpty)
        #expect(rem2.isEmpty)
    }

    @Test("Add child dynamically")
    func testAddChild() {
        var taffy: TaffyTree<Void> = TaffyTree.new()
        guard case .success(let node) = taffy.newLeaf(Style<String>.DEFAULT) else { return }
        #expect(taffy.childCount(parentNodeId: node) == 0)

        guard case .success(let child0) = taffy.newLeaf(Style<String>.DEFAULT) else { return }
        #expect(taffy.addChild(node, child0).isSuccess)
        #expect(taffy.childCount(parentNodeId: node) == 1)

        guard case .success(let child1) = taffy.newLeaf(Style<String>.DEFAULT) else { return }
        #expect(taffy.addChild(node, child1).isSuccess)
        #expect(taffy.childCount(parentNodeId: node) == 2)
    }

    @Test("Insert child at index")
    func testInsertChildAtIndex() {
        var taffy: TaffyTree<Void> = TaffyTree.new()
        guard case .success(let child0) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let child1) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let child2) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let node) = taffy.newLeaf(Style<String>.DEFAULT) else { return }

        #expect(taffy.insertChildAtIndex(node, 0, child0).isSuccess)
        #expect(taffy.childCount(parentNodeId: node) == 1)

        #expect(taffy.insertChildAtIndex(node, 0, child1).isSuccess)
        #expect(taffy.childCount(parentNodeId: node) == 2)
        guard case .success(let c1) = taffy.children(node) else { return }
        #expect(c1[0] == child1)
        #expect(c1[1] == child0)

        #expect(taffy.insertChildAtIndex(node, 1, child2).isSuccess)
        #expect(taffy.childCount(parentNodeId: node) == 3)
        guard case .success(let c2) = taffy.children(node) else { return }
        #expect(c2[0] == child1)
        #expect(c2[1] == child2)
        #expect(c2[2] == child0)
    }

    @Test("Set children replaces list")
    func testSetChildren() {
        var taffy: TaffyTree<Void> = TaffyTree.new()
        guard case .success(let child0) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let child1) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let node) = taffy.newWithChildren(Style<String>.DEFAULT, [child0, child1]),
              case .success(let child2) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let child3) = taffy.newLeaf(Style<String>.DEFAULT) else { return }

        #expect(taffy.setChildren(node, [child2, child3]).isSuccess)
        #expect(taffy.childCount(parentNodeId: node) == 2)
        guard case .success(let c) = taffy.children(node) else { return }
        #expect(c[0] == child2)
        #expect(c[1] == child3)
    }

    @Test("Remove child and remove child at index")
    func testRemoveChild() {
        var taffy: TaffyTree<Void> = TaffyTree.new()
        guard case .success(let child0) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let child1) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let node) = taffy.newWithChildren(Style<String>.DEFAULT, [child0, child1]) else { return }

        #expect(taffy.removeChild(node, child0).isSuccess)
        #expect(taffy.childCount(parentNodeId: node) == 1)
        guard case .success(let c1) = taffy.children(node) else { return }
        #expect(c1[0] == child1)

        #expect(taffy.removeChildAtIndex(node, 0).isSuccess)
        #expect(taffy.childCount(parentNodeId: node) == 0)
    }

    @Test("Measure function intrinsic size calculation")
    func testSetMeasure() {
        var taffy: TaffyTree<Size<Float>> = TaffyTree.new()
        guard case .success(let node) = taffy.newLeafWithContext(
            Style<String>.DEFAULT,
            Size(width: 200.0, height: 200.0)
        ) else { return }

        #expect(taffy.computeLayoutWithMeasure(root: node, availableSpace: Size.MAX_CONTENT, measureFunction: sizeMeasureFunction).isSuccess)
        guard case .success(let l1) = taffy.layout(node) else { return }
        #expect(l1.size.width == 200.0)
        #expect(l1.size.height == 200.0)

        #expect(taffy.setNodeContext(node, Size(width: 100.0, height: 100.0)).isSuccess)
        #expect(taffy.computeLayoutWithMeasure(root: node, availableSpace: Size.MAX_CONTENT, measureFunction: sizeMeasureFunction).isSuccess)
        guard case .success(let l2) = taffy.layout(node) else { return }
        #expect(l2.size.width == 100.0)
        #expect(l2.size.height == 100.0)
    }
}
