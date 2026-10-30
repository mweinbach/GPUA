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
    func new_should_allocate_default_capacity() {
        let taffy: TaffyTree<Void> = TaffyTree.new()
        #expect(taffy.children.capacity >= 16)
        #expect(taffy.parents.capacity >= 16)
        #expect(taffy.nodes.capacity >= 16)
    }

    @Test("TaffyTree with custom capacity")
    func test_with_capacity() {
        let taffy: TaffyTree<Void> = TaffyTree.withCapacity(8)
        #expect(taffy.children.capacity >= 8)
        #expect(taffy.parents.capacity >= 8)
        #expect(taffy.nodes.capacity >= 8)
    }

    @Test("New leaf creation")
    func test_new_leaf() {
        var taffy: TaffyTree<Void> = TaffyTree.new()
        let res = taffy.newLeaf(Style<String>.DEFAULT)
        #expect(res.isSuccess)
        guard case .success(let node) = res else { return }
        #expect(taffy.childCount(parentNodeId: node) == 0)
    }

    @Test("New leaf with context")
    func new_leaf_with_context() {
        var taffy: TaffyTree<Size<Float>> = TaffyTree.new()
        let res = taffy.newLeafWithContext(Style<String>.DEFAULT, Size<Float>.ZERO)
        #expect(res.isSuccess)
        guard case .success(let node) = res else { return }
        #expect(taffy.childCount(parentNodeId: node) == 0)
        #expect(taffy.getNodeContext(node) == Size<Float>.ZERO)
    }

    @Test("New with children")
    func test_new_with_children() {
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

    @Test("Remove node should remove")
    func remove_node_should_remove() {
        var taffy: TaffyTree<Void> = TaffyTree.new()
        guard case .success(let node) = taffy.newLeaf(Style<String>.DEFAULT) else { return }
        #expect(taffy.remove(node).isSuccess)
    }

    @Test("Remove node should detach hierarchy")
    func remove_node_should_detach_hierarchy() {
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

    @Test("Remove last node")
    func remove_last_node() {
        var taffy: TaffyTree<Void> = TaffyTree.new()
        guard case .success(let parent) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let child) = taffy.newLeaf(Style<String>.DEFAULT) else { return }

        #expect(taffy.addChild(parent, child).isSuccess)
        #expect(taffy.remove(child).isSuccess)
        #expect(taffy.remove(parent).isSuccess)
    }

    @Test("Set measure")
    func set_measure() {
        var taffy: TaffyTree<Size<Float>> = TaffyTree.new()
        guard case .success(let node) = taffy.newLeafWithContext(
            Style<String>.DEFAULT,
            Size(width: 200.0, height: 200.0)
        ) else { return }

        #expect(taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, sizeMeasureFunction).isSuccess)
        guard case .success(let l1) = taffy.layout(node) else { return }
        #expect(l1.size.width == 200.0)

        #expect(taffy.setNodeContext(node, Size(width: 100.0, height: 100.0)).isSuccess)
        #expect(taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, sizeMeasureFunction).isSuccess)
        guard case .success(let l2) = taffy.layout(node) else { return }
        #expect(l2.size.width == 100.0)
    }

    @Test("Set measure of previously unmeasured node")
    func set_measure_of_previously_unmeasured_node() {
        var taffy: TaffyTree<Size<Float>> = TaffyTree.new()
        guard case .success(let node) = taffy.newLeaf(Style<String>.DEFAULT) else { return }

        #expect(taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, sizeMeasureFunction).isSuccess)
        guard case .success(let l1) = taffy.layout(node) else { return }
        #expect(l1.size.width == 0.0)

        #expect(taffy.setNodeContext(node, Size(width: 100.0, height: 100.0)).isSuccess)
        #expect(taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, sizeMeasureFunction).isSuccess)
        guard case .success(let l2) = taffy.layout(node) else { return }
        #expect(l2.size.width == 100.0)
    }

    @Test("Add child dynamically")
    func add_child() {
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
    func insert_child_at_index() {
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
    func set_children() {
        var taffy: TaffyTree<Void> = TaffyTree.new()
        guard case .success(let child0) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let child1) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let node) = taffy.newWithChildren(Style<String>.DEFAULT, [child0, child1]) else { return }

        #expect(taffy.childCount(parentNodeId: node) == 2)
        guard case .success(let c0) = taffy.children(node) else { return }
        #expect(c0[0] == child0)
        #expect(c0[1] == child1)

        guard case .success(let child2) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let child3) = taffy.newLeaf(Style<String>.DEFAULT) else { return }

        #expect(taffy.setChildren(node, [child2, child3]).isSuccess)
        #expect(taffy.childCount(parentNodeId: node) == 2)
        guard case .success(let c) = taffy.children(node) else { return }
        #expect(c[0] == child2)
        #expect(c[1] == child3)
    }

    @Test("Remove child")
    func remove_child() {
        var taffy: TaffyTree<Void> = TaffyTree.new()
        guard case .success(let child0) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let child1) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let node) = taffy.newWithChildren(Style<String>.DEFAULT, [child0, child1]) else { return }

        #expect(taffy.childCount(parentNodeId: node) == 2)
        #expect(taffy.removeChild(node, child0).isSuccess)
        #expect(taffy.childCount(parentNodeId: node) == 1)
        guard case .success(let c1) = taffy.children(node) else { return }
        #expect(c1[0] == child1)

        #expect(taffy.removeChild(node, child1).isSuccess)
        #expect(taffy.childCount(parentNodeId: node) == 0)
    }

    @Test("Remove child at index")
    func remove_child_at_index() {
        var taffy: TaffyTree<Void> = TaffyTree.new()
        guard case .success(let child0) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let child1) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let node) = taffy.newWithChildren(Style<String>.DEFAULT, [child0, child1]) else { return }

        #expect(taffy.childCount(parentNodeId: node) == 2)
        #expect(taffy.removeChildAtIndex(node, 0).isSuccess)
        #expect(taffy.childCount(parentNodeId: node) == 1)
        guard case .success(let c1) = taffy.children(node) else { return }
        #expect(c1[0] == child1)

        #expect(taffy.removeChildAtIndex(node, 0).isSuccess)
        #expect(taffy.childCount(parentNodeId: node) == 0)
    }

    @Test("Remove children range")
    func remove_children_range() {
        var taffy: TaffyTree<Void> = TaffyTree.new()
        guard case .success(let child0) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let child1) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let child2) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let child3) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let node) = taffy.newWithChildren(Style<String>.DEFAULT, [child0, child1, child2, child3]) else { return }

        #expect(taffy.childCount(parentNodeId: node) == 4)
        #expect(taffy.removeChildrenRange(node, 1...2).isSuccess)
        #expect(taffy.childCount(parentNodeId: node) == 2)

        guard case .success(let rem) = taffy.children(node) else { return }
        #expect(rem == [child0, child3])
        for child in [child0, child3] {
            #expect(taffy.parent(child) == node)
        }
        for child in [child1, child2] {
            #expect(taffy.parent(child) == nil)
        }
    }

    @Test("Remove child updates parents")
    func remove_child_updates_parents() {
        var taffy: TaffyTree<Void> = TaffyTree.new()
        guard case .success(let parent) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let child) = taffy.newLeaf(Style<String>.DEFAULT) else { return }

        #expect(taffy.addChild(parent, child).isSuccess)
        #expect(taffy.remove(parent).isSuccess)
        #expect(taffy.setChildren(child, []).isSuccess)
    }

    @Test("Replace child at index")
    func replace_child_at_index() {
        var taffy: TaffyTree<Void> = TaffyTree.new()
        guard case .success(let child0) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let child1) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let node) = taffy.newWithChildren(Style<String>.DEFAULT, [child0]) else { return }

        #expect(taffy.childCount(parentNodeId: node) == 1)
        guard case .success(let c0) = taffy.children(node) else { return }
        #expect(c0[0] == child0)

        #expect(taffy.replaceChildAtIndex(node, 0, child1).isSuccess)
        #expect(taffy.childCount(parentNodeId: node) == 1)
        guard case .success(let c1) = taffy.children(node) else { return }
        #expect(c1[0] == child1)
    }

    @Test("Child at index")
    func test_child_at_index() {
        var taffy: TaffyTree<Void> = TaffyTree.new()
        guard case .success(let child0) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let child1) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let child2) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let node) = taffy.newWithChildren(Style<String>.DEFAULT, [child0, child1, child2]) else { return }

        #expect(try! taffy.childAtIndex(node, 0).get() == child0)
        #expect(try! taffy.childAtIndex(node, 1).get() == child1)
        #expect(try! taffy.childAtIndex(node, 2).get() == child2)
    }

    @Test("Child count")
    func test_child_count() {
        var taffy: TaffyTree<Void> = TaffyTree.new()
        guard case .success(let child0) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let child1) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let node) = taffy.newWithChildren(Style<String>.DEFAULT, [child0, child1]) else { return }

        #expect(taffy.childCount(parentNodeId: node) == 2)
        #expect(taffy.childCount(parentNodeId: child0) == 0)
        #expect(taffy.childCount(parentNodeId: child1) == 0)
    }

    @Test("Children list")
    func test_children() {
        var taffy: TaffyTree<Void> = TaffyTree.new()
        guard case .success(let child0) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let child1) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let node) = taffy.newWithChildren(Style<String>.DEFAULT, [child0, child1]) else { return }

        guard case .success(let children) = taffy.children(node) else {
            Issue.record("Failed to get children")
            return
        }
        #expect(children == [child0, child1])
        #expect(try! taffy.children(child0).get().isEmpty)
    }

    @Test("Set style")
    func test_set_style() {
        var taffy: TaffyTree<Void> = TaffyTree.new()
        guard case .success(let node) = taffy.newLeaf(Style<String>.DEFAULT) else { return }
        #expect(try! taffy.style(node).get().display == .flex)

        var newStyle = Style<String>.DEFAULT
        newStyle.display = .none
        #expect(taffy.setStyle(node, newStyle).isSuccess)
        #expect(try! taffy.style(node).get().display == .none)
    }

    @Test("Style getter")
    func test_style() {
        var taffy: TaffyTree<Void> = TaffyTree.new()
        var style = Style<String>.DEFAULT
        style.display = .none
        style.flexDirection = .rowReverse

        guard case .success(let node) = taffy.newLeaf(style) else { return }
        let res = taffy.style(node)
        #expect(res.isSuccess)
        #expect(try! res.get() == style)
    }

    @Test("Layout getter")
    func test_layout() {
        var taffy: TaffyTree<Void> = TaffyTree.new()
        guard case .success(let node) = taffy.newLeaf(Style<String>.DEFAULT) else { return }
        let res = taffy.layout(node)
        #expect(res.isSuccess)
    }

    @Test("Mark dirty propagates")
    func test_mark_dirty() {
        var taffy: TaffyTree<Void> = TaffyTree.new()
        guard case .success(let child0) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let child1) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let node) = taffy.newWithChildren(Style<String>.DEFAULT, [child0, child1]) else { return }

        #expect(taffy.computeLayout(node, Size.MAX_CONTENT).isSuccess)
        #expect(try! taffy.dirty(child0).get() == false)
        #expect(try! taffy.dirty(child1).get() == false)
        #expect(try! taffy.dirty(node).get() == false)

        #expect(taffy.markDirty(node).isSuccess)
        #expect(try! taffy.dirty(child0).get() == false)
        #expect(try! taffy.dirty(child1).get() == false)
        #expect(try! taffy.dirty(node).get() == true)

        #expect(taffy.computeLayout(node, Size.MAX_CONTENT).isSuccess)
        #expect(taffy.markDirty(child0).isSuccess)
        #expect(try! taffy.dirty(child0).get() == true)
        #expect(try! taffy.dirty(child1).get() == false)
        #expect(try! taffy.dirty(node).get() == true)
    }

    @Test("Compute layout produces valid result")
    func compute_layout_should_produce_valid_result() {
        var taffy: TaffyTree<Void> = TaffyTree.new()
        var style = Style<String>.DEFAULT
        style.size = Size(width: .fromLength(10.0), height: .fromLength(10.0))
        guard case .success(let node) = taffy.newLeaf(style) else { return }

        let layoutRes = taffy.computeLayout(
            node,
            Size(width: .definite(100.0), height: .definite(100.0))
        )
        #expect(layoutRes.isSuccess)
    }

    @Test("Layout location is top-left")
    func make_sure_layout_location_is_top_left() {
        var taffy: TaffyTree<Void> = TaffyTree.new()
        var childStyle = Style<String>.DEFAULT
        childStyle.size = Size(width: .fromPercent(1.0), height: .fromPercent(1.0))
        guard case .success(let node) = taffy.newLeaf(childStyle) else { return }

        var rootStyle = Style<String>.DEFAULT
        rootStyle.size = Size(width: .fromLength(100.0), height: .fromLength(100.0))
        rootStyle.padding = Rect(left: .length(10.0), right: .length(20.0), top: .length(30.0), bottom: .length(40.0))

        guard case .success(let root) = taffy.newWithChildren(rootStyle, [node]) else { return }
        #expect(taffy.computeLayout(root, Size.MAX_CONTENT).isSuccess)

        guard case .success(let layout) = taffy.layout(node) else {
            Issue.record("Failed to get layout")
            return
        }
        #expect(layout.location.x == 10.0)
        #expect(layout.location.y == 30.0)
    }

    @Test("Set children reparents node")
    func set_children_reparents() {
        var taffy: TaffyTree<Void> = TaffyTree.new()
        guard case .success(let child) = taffy.newLeaf(Style<String>.DEFAULT),
              case .success(let oldParent) = taffy.newWithChildren(Style<String>.DEFAULT, [child]),
              case .success(let newParent) = taffy.newLeaf(Style<String>.DEFAULT) else { return }

        #expect(taffy.setChildren(newParent, [child]).isSuccess)
        guard case .success(let oldChildren) = taffy.children(oldParent) else { return }
        #expect(oldChildren.isEmpty)
    }
}
