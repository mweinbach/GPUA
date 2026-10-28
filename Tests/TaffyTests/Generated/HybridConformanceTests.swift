// Swift-only: Chrome conformance layout test suite for Taffy (Hybrid & Leaf) transpiled from upstream tests/generated/
import Testing
@testable import Taffy

@Suite("Taffy Conformance: Hybrid & Leaf")
struct HybridConformanceTests {
    @Test("blockflex_block_in_flex_column__border_box")
    func test_blockflex_block_in_flex_column__border_box() {

    
    
    var taffy = newTestTree();
    let node0 =
        try! taffy.newLeaf(Style(display: Display.block)).get();
    let node1 = try! taffy.newLeaf(Style(display: Display.block, size: Size(width: .fromLength(50.0), height: auto())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.flex, size: Size(width: .fromLength(200.0), height: .fromLength(50.0)), flexDirection: .column),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
    }

    @Test("blockflex_block_in_flex_column__content_box")
    func test_blockflex_block_in_flex_column__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox))
        .get();
    let node1 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: auto())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.flex, boxSizing: .contentBox, size: Size(width: .fromLength(200.0), height: .fromLength(50.0)), flexDirection: .column),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
    }

    @Test("blockflex_block_in_flex_row__border_box")
    func test_blockflex_block_in_flex_row__border_box() {

    
    
    var taffy = newTestTree();
    let node0 =
        try! taffy.newLeaf(Style(display: Display.block)).get();
    let node1 = try! taffy.newLeaf(Style(display: Display.block, size: Size(width: .fromLength(50.0), height: auto())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.flex, size: Size(width: .fromLength(200.0), height: .fromLength(50.0))),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
    }

    @Test("blockflex_block_in_flex_row__content_box")
    func test_blockflex_block_in_flex_row__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox))
        .get();
    let node1 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: auto())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.flex, boxSizing: .contentBox, size: Size(width: .fromLength(200.0), height: .fromLength(50.0))),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
    }

    @Test("blockflex_flex_in_block__border_box")
    func test_blockflex_flex_in_block__border_box() {

    
    
    var taffy = newTestTree();
    let node00 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node0 = try! taffy.newWithChildren(
            Style(display: Display.flex),
            [node00],
        )
        .get();
    let node1 = try! taffy.newLeaf(Style(display: Display.block, size: Size(width: .fromLength(50.0), height: .fromLength(20.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, size: Size(width: .fromLength(200.0), height: auto())),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (70.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node00 = try! taffy.layout(node00).get()
        #expect(abs(layout_node00.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node00.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node00.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node00.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (50.0)) < 0.1)
    }

    @Test("blockflex_flex_in_block__content_box")
    func test_blockflex_flex_in_block__content_box() {

    
    
    var taffy = newTestTree();
    let node00 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node0 = try! taffy.newWithChildren(
            Style(display: Display.flex, boxSizing: .contentBox),
            [node00],
        )
        .get();
    let node1 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(20.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, boxSizing: .contentBox, size: Size(width: .fromLength(200.0), height: auto())),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (70.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node00 = try! taffy.layout(node00).get()
        #expect(abs(layout_node00.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node00.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node00.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node00.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (50.0)) < 0.1)
    }

    @Test("blockgrid_grid_in_block__border_box")
    func test_blockgrid_grid_in_block__border_box() {

    
    
    var taffy = newTestTree();
    let node00 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node0 = try! taffy.newWithChildren(
            Style(display: Display.grid),
            [node00],
        )
        .get();
    let node1 = try! taffy.newLeaf(Style(display: Display.block, size: Size(width: .fromLength(50.0), height: .fromLength(20.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, size: Size(width: .fromLength(200.0), height: auto())),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (70.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node00 = try! taffy.layout(node00).get()
        #expect(abs(layout_node00.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node00.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node00.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node00.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (50.0)) < 0.1)
    }

    @Test("blockgrid_grid_in_block__content_box")
    func test_blockgrid_grid_in_block__content_box() {

    
    
    var taffy = newTestTree();
    let node00 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node0 = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox),
            [node00],
        )
        .get();
    let node1 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(20.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.block, boxSizing: .contentBox, size: Size(width: .fromLength(200.0), height: auto())),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (70.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node00 = try! taffy.layout(node00).get()
        #expect(abs(layout_node00.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node00.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node00.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node00.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (50.0)) < 0.1)
    }

    @Test("blockgrid_block_in_grid_auto__border_box")
    func test_blockgrid_block_in_grid_auto__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeafWithContext(
            Style(display: Display.block),
            TestNodeContext.ahemText("HH\u{200b}HH", .horizontal),
        )
        .get();
    let node1 =
        try! taffy.newLeaf(Style(display: Display.block)).get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, gridTemplateColumns: [auto()]),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (10.0)) < 0.1)
    }

    @Test("blockgrid_block_in_grid_auto__content_box")
    func test_blockgrid_block_in_grid_auto__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeafWithContext(
            Style(display: Display.block, boxSizing: .contentBox),
            TestNodeContext.ahemText("HH\u{200b}HH", .horizontal),
        )
        .get();
    let node1 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, gridTemplateColumns: [auto()]),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (10.0)) < 0.1)
    }

    @Test("blockgrid_margin_y_collapse_through_blocked_by_grid__border_box")
    func test_blockgrid_margin_y_collapse_through_blocked_by_grid__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(display: Display.block, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: zero(), bottom: length(10.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(display: Display.grid, margin: Rect(left: zero(), right: zero(), top: length(10.0), bottom: length(10.0))))
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
        #expect(abs(layout_node.size.height - (40.0)) < 0.1)
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
        #expect(abs(layout_node2.location.y - (30.0)) < 0.1)
    }

    @Test("blockgrid_margin_y_collapse_through_blocked_by_grid__content_box")
    func test_blockgrid_margin_y_collapse_through_blocked_by_grid__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(10.0)), margin: Rect(left: zero(), right: zero(), top: zero(), bottom: length(10.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(display: Display.grid, boxSizing: .contentBox, margin: Rect(left: zero(), right: zero(), top: length(10.0), bottom: length(10.0))))
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
        #expect(abs(layout_node.size.height - (40.0)) < 0.1)
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
        #expect(abs(layout_node2.location.y - (30.0)) < 0.1)
    }

    @Test("gridflex_row_integration__border_box")
    func test_gridflex_row_integration__border_box() {

    
    
    var taffy = newTestTree();
    let node00 = try! taffy.newLeafWithContext(
            Style(),
            TestNodeContext.ahemText("HH", .horizontal),
        )
        .get();
    let node01 = try! taffy.newLeafWithContext(
            Style(),
            TestNodeContext.ahemText("HH", .horizontal),
        )
        .get();
    let node02 = try! taffy.newLeafWithContext(
            Style(),
            TestNodeContext.ahemText("HH", .horizontal),
        )
        .get();
    let node03 = try! taffy.newLeafWithContext(
            Style(),
            TestNodeContext.ahemText("HH", .horizontal),
        )
        .get();
    let node0 = try! taffy.newWithChildren(
            Style(display: Display.grid, gridTemplateRows: [fr(1.0), fr(1.0)], gridTemplateColumns: [fr(1.0), fr(1.0)]),
            [node00, node01, node02, node03],
        )
        .get();
    let node = try! taffy.newWithChildren(Style(), [node0]).get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node00 = try! taffy.layout(node00).get()
        #expect(abs(layout_node00.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node00.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node00.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node00.location.y - (0.0)) < 0.1)
        let layout_node01 = try! taffy.layout(node01).get()
        #expect(abs(layout_node01.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node01.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node01.location.x - (20.0)) < 0.1)
        #expect(abs(layout_node01.location.y - (0.0)) < 0.1)
        let layout_node02 = try! taffy.layout(node02).get()
        #expect(abs(layout_node02.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node02.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node02.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node02.location.y - (10.0)) < 0.1)
        let layout_node03 = try! taffy.layout(node03).get()
        #expect(abs(layout_node03.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node03.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node03.location.x - (20.0)) < 0.1)
        #expect(abs(layout_node03.location.y - (10.0)) < 0.1)
    }

    @Test("gridflex_row_integration__content_box")
    func test_gridflex_row_integration__content_box() {

    
    
    var taffy = newTestTree();
    let node00 = try! taffy.newLeafWithContext(
            Style(boxSizing: .contentBox),
            TestNodeContext.ahemText("HH", .horizontal),
        )
        .get();
    let node01 = try! taffy.newLeafWithContext(
            Style(boxSizing: .contentBox),
            TestNodeContext.ahemText("HH", .horizontal),
        )
        .get();
    let node02 = try! taffy.newLeafWithContext(
            Style(boxSizing: .contentBox),
            TestNodeContext.ahemText("HH", .horizontal),
        )
        .get();
    let node03 = try! taffy.newLeafWithContext(
            Style(boxSizing: .contentBox),
            TestNodeContext.ahemText("HH", .horizontal),
        )
        .get();
    let node0 = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, gridTemplateRows: [fr(1.0), fr(1.0)], gridTemplateColumns: [fr(1.0), fr(1.0)]),
            [node00, node01, node02, node03],
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node00 = try! taffy.layout(node00).get()
        #expect(abs(layout_node00.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node00.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node00.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node00.location.y - (0.0)) < 0.1)
        let layout_node01 = try! taffy.layout(node01).get()
        #expect(abs(layout_node01.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node01.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node01.location.x - (20.0)) < 0.1)
        #expect(abs(layout_node01.location.y - (0.0)) < 0.1)
        let layout_node02 = try! taffy.layout(node02).get()
        #expect(abs(layout_node02.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node02.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node02.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node02.location.y - (10.0)) < 0.1)
        let layout_node03 = try! taffy.layout(node03).get()
        #expect(abs(layout_node03.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node03.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node03.location.x - (20.0)) < 0.1)
        #expect(abs(layout_node03.location.y - (10.0)) < 0.1)
    }

    @Test("gridflex_column_integration__border_box")
    func test_gridflex_column_integration__border_box() {

    
    
    var taffy = newTestTree();
    let node00 = try! taffy.newLeafWithContext(
            Style(),
            TestNodeContext.ahemText("HH", .horizontal),
        )
        .get();
    let node01 = try! taffy.newLeafWithContext(
            Style(),
            TestNodeContext.ahemText("HH", .horizontal),
        )
        .get();
    let node02 = try! taffy.newLeafWithContext(
            Style(),
            TestNodeContext.ahemText("HH", .horizontal),
        )
        .get();
    let node03 = try! taffy.newLeafWithContext(
            Style(),
            TestNodeContext.ahemText("HH", .horizontal),
        )
        .get();
    let node0 = try! taffy.newWithChildren(
            Style(display: Display.grid, gridTemplateRows: [fr(1.0), fr(1.0)], gridTemplateColumns: [fr(1.0), fr(1.0)]),
            [node00, node01, node02, node03],
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(flexDirection: .column),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node00 = try! taffy.layout(node00).get()
        #expect(abs(layout_node00.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node00.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node00.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node00.location.y - (0.0)) < 0.1)
        let layout_node01 = try! taffy.layout(node01).get()
        #expect(abs(layout_node01.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node01.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node01.location.x - (20.0)) < 0.1)
        #expect(abs(layout_node01.location.y - (0.0)) < 0.1)
        let layout_node02 = try! taffy.layout(node02).get()
        #expect(abs(layout_node02.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node02.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node02.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node02.location.y - (10.0)) < 0.1)
        let layout_node03 = try! taffy.layout(node03).get()
        #expect(abs(layout_node03.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node03.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node03.location.x - (20.0)) < 0.1)
        #expect(abs(layout_node03.location.y - (10.0)) < 0.1)
    }

    @Test("gridflex_column_integration__content_box")
    func test_gridflex_column_integration__content_box() {

    
    
    var taffy = newTestTree();
    let node00 = try! taffy.newLeafWithContext(
            Style(boxSizing: .contentBox),
            TestNodeContext.ahemText("HH", .horizontal),
        )
        .get();
    let node01 = try! taffy.newLeafWithContext(
            Style(boxSizing: .contentBox),
            TestNodeContext.ahemText("HH", .horizontal),
        )
        .get();
    let node02 = try! taffy.newLeafWithContext(
            Style(boxSizing: .contentBox),
            TestNodeContext.ahemText("HH", .horizontal),
        )
        .get();
    let node03 = try! taffy.newLeafWithContext(
            Style(boxSizing: .contentBox),
            TestNodeContext.ahemText("HH", .horizontal),
        )
        .get();
    let node0 = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, gridTemplateRows: [fr(1.0), fr(1.0)], gridTemplateColumns: [fr(1.0), fr(1.0)]),
            [node00, node01, node02, node03],
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, flexDirection: .column),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node00 = try! taffy.layout(node00).get()
        #expect(abs(layout_node00.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node00.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node00.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node00.location.y - (0.0)) < 0.1)
        let layout_node01 = try! taffy.layout(node01).get()
        #expect(abs(layout_node01.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node01.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node01.location.x - (20.0)) < 0.1)
        #expect(abs(layout_node01.location.y - (0.0)) < 0.1)
        let layout_node02 = try! taffy.layout(node02).get()
        #expect(abs(layout_node02.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node02.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node02.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node02.location.y - (10.0)) < 0.1)
        let layout_node03 = try! taffy.layout(node03).get()
        #expect(abs(layout_node03.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node03.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node03.location.x - (20.0)) < 0.1)
        #expect(abs(layout_node03.location.y - (10.0)) < 0.1)
    }

    @Test("leaf_with_content_and_padding_border__border_box")
    func test_leaf_with_content_and_padding_border__border_box() {

    
    
    var taffy = newTestTree();
    let node = try! taffy.newLeafWithContext(
            Style(padding: Rect(left: length(8.0), right: length(4.0), top: length(2.0), bottom: length(6.0)), border: Rect(left: length(7.0), right: length(3.0), top: length(1.0), bottom: length(5.0))),
            TestNodeContext.ahemText("HHHH", .horizontal),
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (62.0)) < 0.1)
        #expect(abs(layout_node.size.height - (24.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
    }

    @Test("leaf_with_content_and_padding_border__content_box")
    func test_leaf_with_content_and_padding_border__content_box() {

    
    
    var taffy = newTestTree();
    let node = try! taffy.newLeafWithContext(
            Style(boxSizing: .contentBox, padding: Rect(left: length(8.0), right: length(4.0), top: length(2.0), bottom: length(6.0)), border: Rect(left: length(7.0), right: length(3.0), top: length(1.0), bottom: length(5.0))),
            TestNodeContext.ahemText("HHHH", .horizontal),
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (62.0)) < 0.1)
        #expect(abs(layout_node.size.height - (24.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
    }

    @Test("leaf_with_content_and_padding__border_box")
    func test_leaf_with_content_and_padding__border_box() {

    
    
    var taffy = newTestTree();
    let node = try! taffy.newLeafWithContext(
            Style(padding: Rect(left: length(8.0), right: length(4.0), top: length(2.0), bottom: length(6.0))),
            TestNodeContext.ahemText("HHHH", .horizontal),
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (52.0)) < 0.1)
        #expect(abs(layout_node.size.height - (18.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
    }

    @Test("leaf_with_content_and_padding__content_box")
    func test_leaf_with_content_and_padding__content_box() {

    
    
    var taffy = newTestTree();
    let node = try! taffy.newLeafWithContext(
            Style(boxSizing: .contentBox, padding: Rect(left: length(8.0), right: length(4.0), top: length(2.0), bottom: length(6.0))),
            TestNodeContext.ahemText("HHHH", .horizontal),
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (52.0)) < 0.1)
        #expect(abs(layout_node.size.height - (18.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
    }
}
