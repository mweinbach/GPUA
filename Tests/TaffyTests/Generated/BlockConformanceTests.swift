// Swift-only: Chrome conformance layout test suite for Taffy (CSS Block) transpiled from upstream tests/generated/
import Testing
@testable import Taffy

@Suite("Taffy Conformance: CSS Block")
struct BlockConformanceTests {
    @Test("block_margin_auto_left__border_box")
    func test_block_margin_auto_left__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), margin: Rect(left: .auto(), right: zero(), top: zero(), bottom: zero())))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, size: Size(width: .fromLength(200.0), height: .fromLength(200.0))),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (150.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (50.0)) < 0.1)
    }

    @Test("block_margin_auto_left__content_box")
    func test_block_margin_auto_left__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), margin: Rect(left: .auto(), right: zero(), top: zero(), bottom: zero())))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, boxSizing: .contentBox, size: Size(width: .fromLength(200.0), height: .fromLength(200.0))),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (150.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (50.0)) < 0.1)
    }

    @Test("block_margin_auto_right__border_box")
    func test_block_margin_auto_right__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), margin: Rect(left: zero(), right: .auto(), top: zero(), bottom: zero())))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, size: Size(width: .fromLength(200.0), height: .fromLength(200.0)), alignItems: .center),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (50.0)) < 0.1)
    }

    @Test("block_margin_auto_right__content_box")
    func test_block_margin_auto_right__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), margin: Rect(left: zero(), right: .auto(), top: zero(), bottom: zero())))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, boxSizing: .contentBox, size: Size(width: .fromLength(200.0), height: .fromLength(200.0)), alignItems: .center),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (50.0)) < 0.1)
    }

    @Test("block_margin_auto_left_and_right__border_box")
    func test_block_margin_auto_left_and_right__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), margin: Rect(left: .auto(), right: .auto(), top: zero(), bottom: zero())))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, size: Size(width: .fromLength(200.0), height: .fromLength(200.0))),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (75.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (50.0)) < 0.1)
    }

    @Test("block_margin_auto_left_and_right__content_box")
    func test_block_margin_auto_left_and_right__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), margin: Rect(left: .auto(), right: .auto(), top: zero(), bottom: zero())))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, boxSizing: .contentBox, size: Size(width: .fromLength(200.0), height: .fromLength(200.0))),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (75.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (50.0)) < 0.1)
    }

    @Test("block_margin_auto_bottom_and_top__border_box")
    func test_block_margin_auto_bottom_and_top__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), margin: Rect(left: zero(), right: zero(), top: .auto(), bottom: .auto())))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, size: Size(width: .fromLength(200.0), height: .fromLength(200.0))),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (50.0)) < 0.1)
    }

    @Test("block_margin_auto_bottom_and_top__content_box")
    func test_block_margin_auto_bottom_and_top__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), margin: Rect(left: zero(), right: zero(), top: .auto(), bottom: .auto())))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, boxSizing: .contentBox, size: Size(width: .fromLength(200.0), height: .fromLength(200.0))),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (50.0)) < 0.1)
    }

    @Test("block_margin_auto_left_and_right_with_auto_width__border_box")
    func test_block_margin_auto_left_and_right_with_auto_width__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeafWithContext(
            Style(size: Size(width: .auto(), height: .fromLength(50.0)), maxSize: Size(width: .fromLength(100.0), height: auto()), margin: Rect(left: .auto(), right: .auto(), top: zero(), bottom: zero())),
            TestNodeContext.ahemText("", .horizontal),
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, size: Size(width: .fromLength(200.0), height: .fromLength(200.0))),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
    }

    @Test("block_margin_auto_left_and_right_with_auto_width__content_box")
    func test_block_margin_auto_left_and_right_with_auto_width__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeafWithContext(
            Style(boxSizing: .contentBox, size: Size(width: .auto(), height: .fromLength(50.0)), maxSize: Size(width: .fromLength(100.0), height: auto()), margin: Rect(left: .auto(), right: .auto(), top: zero(), bottom: zero())),
            TestNodeContext.ahemText("", .horizontal),
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, boxSizing: .contentBox, size: Size(width: .fromLength(200.0), height: .fromLength(200.0))),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
    }

    @Test("block_margin_auto_multiple_children__border_box")
    func test_block_margin_auto_multiple_children__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(100.0), height: .fromLength(50.0)), margin: Rect(left: zero(), right: .auto(), top: zero(), bottom: zero())))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), margin: Rect(left: zero(), right: .auto(), top: zero(), bottom: zero())))
        .get();
    let node2 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, size: Size(width: .fromLength(200.0), height: .fromLength(200.0)), alignItems: .center),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (50.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (100.0)) < 0.1)
    }

    @Test("block_margin_auto_multiple_children__content_box")
    func test_block_margin_auto_multiple_children__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: .fromLength(50.0)), margin: Rect(left: zero(), right: .auto(), top: zero(), bottom: zero())))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), margin: Rect(left: zero(), right: .auto(), top: zero(), bottom: zero())))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, boxSizing: .contentBox, size: Size(width: .fromLength(200.0), height: .fromLength(200.0)), alignItems: .center),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (50.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (100.0)) < 0.1)
    }

    @Test("block_margin_y_collapse_complex__border_box")
    func test_block_margin_y_collapse_complex__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: length(-10.0), bottom: length(-10.0))))
        .get();
    let node10 = try! taffy.newLeaf(Style(size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: length(-5.0), bottom: length(-5.0))))
        .get();
    let node11 = try! taffy.newLeaf(Style(size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: length(7.0), bottom: length(3.0))))
        .get();
    let node12 = try! taffy.newLeaf(Style(size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: length(-6.0), bottom: length(9.0))))
        .get();
    let node1 = try! taffy.newWithChildren(
            Style(size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: length(-10.0), bottom: length(-10.0))),
            [node10, node11, node12],
        )
        .get();
    let node2 = try! taffy.newLeaf(Style(size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: length(-5.0), bottom: length(-5.0))))
        .get();
    let node3 = try! taffy.newLeaf(Style(size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: length(-10.0), bottom: length(-10.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, size: Size(width: .fromLength(50.0), height: auto())),
            [node0, node1, node2, node3],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node.size.height - (0.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (-10.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (-10.0)) < 0.1)
        let layout_node10 = try! taffy.layout(node10).get()
        #expect(abs(layout_node10.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node10.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node10.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node10.location.y - (-5.0)) < 0.1)
        let layout_node11 = try! taffy.layout(node11).get()
        #expect(abs(layout_node11.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node11.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node11.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node11.location.y - (7.0)) < 0.1)
        let layout_node12 = try! taffy.layout(node12).get()
        #expect(abs(layout_node12.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node12.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node12.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node12.location.y - (-6.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (-10.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (-10.0)) < 0.1)
    }

    @Test("block_margin_y_collapse_complex__content_box")
    func test_block_margin_y_collapse_complex__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: length(-10.0), bottom: length(-10.0))))
        .get();
    let node10 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: length(-5.0), bottom: length(-5.0))))
        .get();
    let node11 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: length(7.0), bottom: length(3.0))))
        .get();
    let node12 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: length(-6.0), bottom: length(9.0))))
        .get();
    let node1 = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: length(-10.0), bottom: length(-10.0))),
            [node10, node11, node12],
        )
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: length(-5.0), bottom: length(-5.0))))
        .get();
    let node3 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: length(-10.0), bottom: length(-10.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: auto())),
            [node0, node1, node2, node3],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node.size.height - (0.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (-10.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (-10.0)) < 0.1)
        let layout_node10 = try! taffy.layout(node10).get()
        #expect(abs(layout_node10.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node10.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node10.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node10.location.y - (-5.0)) < 0.1)
        let layout_node11 = try! taffy.layout(node11).get()
        #expect(abs(layout_node11.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node11.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node11.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node11.location.y - (7.0)) < 0.1)
        let layout_node12 = try! taffy.layout(node12).get()
        #expect(abs(layout_node12.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node12.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node12.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node12.location.y - (-6.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (-10.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (-10.0)) < 0.1)
    }

    @Test("block_margin_y_collapse_through_blocked_by_border_top__border_box")
    func test_block_margin_y_collapse_through_blocked_by_border_top__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(display: Display.block, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: zero(), bottom: length(10.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(display: Display.block, margin: Rect(left: zero(), right: zero(), top: length(10.0), bottom: length(10.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(display: Display.block, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: length(10.0), bottom: zero())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, size: Size(width: .fromLength(50.0), height: auto())),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node.size.height - (30.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (20.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (20.0)) < 0.1)
    }

    @Test("block_margin_y_collapse_through_blocked_by_border_top__content_box")
    func test_block_margin_y_collapse_through_blocked_by_border_top__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: zero(), bottom: length(10.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox, margin: Rect(left: zero(), right: zero(), top: length(10.0), bottom: length(10.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: length(10.0), bottom: zero())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: auto())),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node.size.height - (30.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (20.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (20.0)) < 0.1)
    }

    @Test("block_margin_y_collapse_through_blocked_by_border_bottom__border_box")
    func test_block_margin_y_collapse_through_blocked_by_border_bottom__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(display: Display.block, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: zero(), bottom: length(10.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(display: Display.block, margin: Rect(left: zero(), right: zero(), top: length(10.0), bottom: length(10.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(display: Display.block, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: length(10.0), bottom: zero())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, size: Size(width: .fromLength(50.0), height: auto())),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node.size.height - (30.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (20.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (20.0)) < 0.1)
    }

    @Test("block_margin_y_collapse_through_blocked_by_border_bottom__content_box")
    func test_block_margin_y_collapse_through_blocked_by_border_bottom__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: zero(), bottom: length(10.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox, margin: Rect(left: zero(), right: zero(), top: length(10.0), bottom: length(10.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: length(10.0), bottom: zero())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: auto())),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node.size.height - (30.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (20.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (20.0)) < 0.1)
    }

    @Test("block_margin_y_collapse_through_blocked_by_padding_top__border_box")
    func test_block_margin_y_collapse_through_blocked_by_padding_top__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(display: Display.block, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: zero(), bottom: length(10.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(display: Display.block, margin: Rect(left: zero(), right: zero(), top: length(10.0), bottom: length(10.0)), padding: Rect(left: zero(), right: zero(), top: length(1.0), bottom: zero())))
        .get();
    let node2 = try! taffy.newLeaf(Style(display: Display.block, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: length(10.0), bottom: zero())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, size: Size(width: .fromLength(50.0), height: auto())),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node.size.height - (41.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (1.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (20.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (31.0)) < 0.1)
    }

    @Test("block_margin_y_collapse_through_blocked_by_padding_top__content_box")
    func test_block_margin_y_collapse_through_blocked_by_padding_top__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: zero(), bottom: length(10.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox, margin: Rect(left: zero(), right: zero(), top: length(10.0), bottom: length(10.0)), padding: Rect(left: zero(), right: zero(), top: length(1.0), bottom: zero())))
        .get();
    let node2 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: length(10.0), bottom: zero())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: auto())),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node.size.height - (41.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (1.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (20.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (31.0)) < 0.1)
    }

    @Test("block_margin_y_collapse_through_blocked_by_padding_bottom__border_box")
    func test_block_margin_y_collapse_through_blocked_by_padding_bottom__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(display: Display.block, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: zero(), bottom: length(10.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(display: Display.block, margin: Rect(left: zero(), right: zero(), top: length(10.0), bottom: length(10.0)), padding: Rect(left: zero(), right: zero(), top: zero(), bottom: length(1.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(display: Display.block, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: length(10.0), bottom: zero())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, size: Size(width: .fromLength(50.0), height: auto())),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node.size.height - (41.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (1.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (20.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (31.0)) < 0.1)
    }

    @Test("block_margin_y_collapse_through_blocked_by_padding_bottom__content_box")
    func test_block_margin_y_collapse_through_blocked_by_padding_bottom__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: zero(), bottom: length(10.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox, margin: Rect(left: zero(), right: zero(), top: length(10.0), bottom: length(10.0)), padding: Rect(left: zero(), right: zero(), top: zero(), bottom: length(1.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: length(10.0), bottom: zero())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: auto())),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node.size.height - (41.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (1.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (20.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (31.0)) < 0.1)
    }

    @Test("block_margin_y_collapse_through_blocked_by_height__border_box")
    func test_block_margin_y_collapse_through_blocked_by_height__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(display: Display.block, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: zero(), bottom: length(10.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(display: Display.block, size: Size(width: auto(), height: .fromLength(1.0)), margin: Rect(left: zero(), right: zero(), top: length(10.0), bottom: length(10.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(display: Display.block, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: length(10.0), bottom: zero())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, size: Size(width: .fromLength(50.0), height: auto())),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node.size.height - (41.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (1.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (20.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (31.0)) < 0.1)
    }

    @Test("block_margin_y_collapse_through_blocked_by_height__content_box")
    func test_block_margin_y_collapse_through_blocked_by_height__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: zero(), bottom: length(10.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(1.0)), margin: Rect(left: zero(), right: zero(), top: length(10.0), bottom: length(10.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: length(10.0), bottom: zero())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: auto())),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node.size.height - (41.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (1.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (20.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (31.0)) < 0.1)
    }

    @Test("block_border_fixed_size__border_box")
    func test_block_border_fixed_size__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: auto(), height: .fromLength(10.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: auto(), height: .fromLength(10.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), border: Rect(left: length(8.0), right: length(4.0), top: length(2.0), bottom: length(6.0))),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (38.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (8.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (2.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (38.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (8.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (12.0)) < 0.1)
    }

    @Test("block_border_fixed_size__content_box")
    func test_block_border_fixed_size__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(10.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(10.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), border: Rect(left: length(8.0), right: length(4.0), top: length(2.0), bottom: length(6.0))),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (62.0)) < 0.1)
        #expect(abs(layout_node.size.height - (58.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (8.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (2.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (8.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (12.0)) < 0.1)
    }

    @Test("block_border_percentage_fixed_size__border_box")
    func test_block_border_percentage_fixed_size__border_box() {

    
    
    var taffy = newTestTree();
    let node00 = try! taffy.newLeaf(Style(display: Display.block, size: Size(width: auto(), height: .fromLength(10.0))))
        .get();
    let node0 = try! taffy.newWithChildren(
            Style(display: Display.block),
            [node00],
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, size: Size(width: .fromLength(50.0), height: .fromLength(50.0))),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node00 = try! taffy.layout(node00).get()
        #expect(abs(layout_node00.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node00.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node00.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node00.location.y - (0.0)) < 0.1)
    }

    @Test("block_border_percentage_fixed_size__content_box")
    func test_block_border_percentage_fixed_size__content_box() {

    
    
    var taffy = newTestTree();
    let node00 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(10.0))))
        .get();
    let node0 = try! taffy.newWithChildren(
            Style(display: Display.block, boxSizing: .contentBox),
            [node00],
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0))),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node00 = try! taffy.layout(node00).get()
        #expect(abs(layout_node00.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node00.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node00.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node00.location.y - (0.0)) < 0.1)
    }

    @Test("block_absolute_layout_percentage_height__border_box")
    func test_block_absolute_layout_percentage_height__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(position: .absolute, inset: Rect(left: length(10.0), right: auto(), top: length(10.0), bottom: auto()), size: Size(width: .fromLength(10.0), height: .fromPercent(0.5))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, size: Size(width: .fromLength(200.0), height: .fromLength(100.0))),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (10.0)) < 0.1)
    }

    @Test("block_absolute_layout_percentage_height__content_box")
    func test_block_absolute_layout_percentage_height__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, position: .absolute, inset: Rect(left: length(10.0), right: auto(), top: length(10.0), bottom: auto()), size: Size(width: .fromLength(10.0), height: .fromPercent(0.5))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, boxSizing: .contentBox, size: Size(width: .fromLength(200.0), height: .fromLength(100.0))),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (10.0)) < 0.1)
    }

    @Test("block_absolute_layout_percentage_bottom_based_on_parent_height__border_box")
    func test_block_absolute_layout_percentage_bottom_based_on_parent_height__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(display: Display.block, position: .absolute, inset: Rect(left: auto(), right: auto(), top: percent(0.5), bottom: auto()), size: Size(width: .fromLength(10.0), height: .fromLength(10.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(display: Display.block, position: .absolute, inset: Rect(left: auto(), right: auto(), top: auto(), bottom: percent(0.5)), size: Size(width: .fromLength(10.0), height: .fromLength(10.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(display: Display.block, position: .absolute, inset: Rect(left: auto(), right: auto(), top: percent(0.1), bottom: percent(0.1)), size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, size: Size(width: .fromLength(100.0), height: .fromLength(200.0))),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (100.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (90.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (160.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (20.0)) < 0.1)
    }

    @Test("block_absolute_layout_percentage_bottom_based_on_parent_height__content_box")
    func test_block_absolute_layout_percentage_bottom_based_on_parent_height__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox, position: .absolute, inset: Rect(left: auto(), right: auto(), top: percent(0.5), bottom: auto()), size: Size(width: .fromLength(10.0), height: .fromLength(10.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox, position: .absolute, inset: Rect(left: auto(), right: auto(), top: auto(), bottom: percent(0.5)), size: Size(width: .fromLength(10.0), height: .fromLength(10.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox, position: .absolute, inset: Rect(left: auto(), right: auto(), top: percent(0.1), bottom: percent(0.1)), size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: .fromLength(200.0))),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (100.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (90.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (160.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (20.0)) < 0.1)
    }

    @Test("block_absolute_child_with_margin_x__border_box")
    func test_block_absolute_child_with_margin_x__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(position: .absolute, size: Size(width: .fromLength(9.0), height: .fromLength(9.0)), margin: Rect(left: length(7.0), right: zero(), top: zero(), bottom: zero())))
        .get();
    let node1 = try! taffy.newLeaf(Style(position: .absolute, size: Size(width: .fromLength(9.0), height: .fromLength(9.0)), margin: Rect(left: zero(), right: length(7.0), top: zero(), bottom: zero())))
        .get();
    let node2 = try! taffy.newLeaf(Style(position: .absolute, size: Size(width: .fromLength(9.0), height: .fromLength(9.0)), margin: Rect(left: length(10.0), right: length(5.0), top: zero(), bottom: zero())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, size: Size(width: .fromLength(20.0), height: .fromLength(37.0))),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node.size.height - (37.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (9.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (9.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (7.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (9.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (9.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (9.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (9.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (10.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
    }

    @Test("block_absolute_child_with_margin_x__content_box")
    func test_block_absolute_child_with_margin_x__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, position: .absolute, size: Size(width: .fromLength(9.0), height: .fromLength(9.0)), margin: Rect(left: length(7.0), right: zero(), top: zero(), bottom: zero())))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, position: .absolute, size: Size(width: .fromLength(9.0), height: .fromLength(9.0)), margin: Rect(left: zero(), right: length(7.0), top: zero(), bottom: zero())))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox, position: .absolute, size: Size(width: .fromLength(9.0), height: .fromLength(9.0)), margin: Rect(left: length(10.0), right: length(5.0), top: zero(), bottom: zero())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, boxSizing: .contentBox, size: Size(width: .fromLength(20.0), height: .fromLength(37.0))),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node.size.height - (37.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (9.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (9.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (7.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (9.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (9.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (9.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (9.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (10.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
    }

    @Test("block_absolute_child_with_margin_y__border_box")
    func test_block_absolute_child_with_margin_y__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(position: .absolute, size: Size(width: .fromLength(9.0), height: .fromLength(9.0)), margin: Rect(left: zero(), right: zero(), top: length(7.0), bottom: zero())))
        .get();
    let node1 = try! taffy.newLeaf(Style(position: .absolute, size: Size(width: .fromLength(9.0), height: .fromLength(9.0)), margin: Rect(left: zero(), right: zero(), top: zero(), bottom: length(7.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(position: .absolute, size: Size(width: .fromLength(9.0), height: .fromLength(9.0)), margin: Rect(left: zero(), right: zero(), top: length(10.0), bottom: length(5.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, size: Size(width: .fromLength(20.0), height: .fromLength(37.0))),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node.size.height - (37.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (9.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (9.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (7.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (9.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (9.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (9.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (9.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (10.0)) < 0.1)
    }

    @Test("block_absolute_child_with_margin_y__content_box")
    func test_block_absolute_child_with_margin_y__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, position: .absolute, size: Size(width: .fromLength(9.0), height: .fromLength(9.0)), margin: Rect(left: zero(), right: zero(), top: length(7.0), bottom: zero())))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, position: .absolute, size: Size(width: .fromLength(9.0), height: .fromLength(9.0)), margin: Rect(left: zero(), right: zero(), top: zero(), bottom: length(7.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox, position: .absolute, size: Size(width: .fromLength(9.0), height: .fromLength(9.0)), margin: Rect(left: zero(), right: zero(), top: length(10.0), bottom: length(5.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, boxSizing: .contentBox, size: Size(width: .fromLength(20.0), height: .fromLength(37.0))),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node.size.height - (37.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (9.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (9.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (7.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (9.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (9.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (9.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (9.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (10.0)) < 0.1)
    }

    @Test("block_absolute_layout_within_border__border_box")
    func test_block_absolute_layout_within_border__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(display: Display.block, position: .absolute, inset: Rect(left: length(0.0), right: auto(), top: length(0.0), bottom: auto()), size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(display: Display.block, position: .absolute, inset: Rect(left: auto(), right: length(0.0), top: auto(), bottom: length(0.0)), size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(display: Display.block, position: .absolute, inset: Rect(left: length(0.0), right: auto(), top: length(0.0), bottom: auto()), size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), margin: Rect(left: length(10.0), right: length(10.0), top: length(10.0), bottom: length(10.0))))
        .get();
    let node3 = try! taffy.newLeaf(Style(display: Display.block, position: .absolute, inset: Rect(left: auto(), right: length(0.0), top: auto(), bottom: length(0.0)), size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), margin: Rect(left: length(10.0), right: length(10.0), top: length(10.0), bottom: length(10.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), padding: Rect(left: length(10.0), right: length(10.0), top: length(10.0), bottom: length(10.0)), border: Rect(left: length(10.0), right: length(10.0), top: length(10.0), bottom: length(10.0))),
            [node0, node1, node2, node3],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (10.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (40.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (20.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (20.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (30.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (30.0)) < 0.1)
    }

    @Test("block_absolute_layout_within_border__content_box")
    func test_block_absolute_layout_within_border__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox, position: .absolute, inset: Rect(left: length(0.0), right: auto(), top: length(0.0), bottom: auto()), size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox, position: .absolute, inset: Rect(left: auto(), right: length(0.0), top: auto(), bottom: length(0.0)), size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox, position: .absolute, inset: Rect(left: length(0.0), right: auto(), top: length(0.0), bottom: auto()), size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), margin: Rect(left: length(10.0), right: length(10.0), top: length(10.0), bottom: length(10.0))))
        .get();
    let node3 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox, position: .absolute, inset: Rect(left: auto(), right: length(0.0), top: auto(), bottom: length(0.0)), size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), margin: Rect(left: length(10.0), right: length(10.0), top: length(10.0), bottom: length(10.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), padding: Rect(left: length(10.0), right: length(10.0), top: length(10.0), bottom: length(10.0)), border: Rect(left: length(10.0), right: length(10.0), top: length(10.0), bottom: length(10.0))),
            [node0, node1, node2, node3],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (140.0)) < 0.1)
        #expect(abs(layout_node.size.height - (140.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (10.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (80.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (20.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (20.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (70.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (70.0)) < 0.1)
    }

    @Test("block_absolute_margin_auto_left_and_right_with_inset__border_box")
    func test_block_absolute_margin_auto_left_and_right_with_inset__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(position: .absolute, inset: Rect(left: length(10.0), right: length(20.0), top: auto(), bottom: auto()), size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), margin: Rect(left: .auto(), right: .auto(), top: zero(), bottom: zero())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, size: Size(width: .fromLength(200.0), height: .fromLength(200.0))),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (70.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
    }

    @Test("block_absolute_margin_auto_left_and_right_with_inset__content_box")
    func test_block_absolute_margin_auto_left_and_right_with_inset__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, position: .absolute, inset: Rect(left: length(10.0), right: length(20.0), top: auto(), bottom: auto()), size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), margin: Rect(left: .auto(), right: .auto(), top: zero(), bottom: zero())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, boxSizing: .contentBox, size: Size(width: .fromLength(200.0), height: .fromLength(200.0))),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (70.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
    }
}
