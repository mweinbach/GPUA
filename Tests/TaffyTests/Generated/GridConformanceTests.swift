// Swift-only: Chrome conformance layout test suite for Taffy (CSS Grid) transpiled from upstream tests/generated/
import Testing
@testable import Taffy

@Suite("Taffy Conformance: CSS Grid")
struct GridConformanceTests {
    @Test("grid_fr_fixed_size_no_content_proportions__border_box")
    func test_grid_fr_fixed_size_no_content_proportions__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style()).get();
    let node1 = try! taffy.newLeaf(Style()).get();
    let node2 = try! taffy.newLeaf(Style()).get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, size: Size(width: .fromLength(200.0), height: auto()), gridTemplateRows: [length(40.0)], gridTemplateColumns: [fr(1.0), fr(2.0), fr(3.0)]),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (33.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (67.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (33.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (100.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
    }

    @Test("grid_fr_fixed_size_no_content_proportions__content_box")
    func test_grid_fr_fixed_size_no_content_proportions__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, size: Size(width: .fromLength(200.0), height: auto()), gridTemplateRows: [length(40.0)], gridTemplateColumns: [fr(1.0), fr(2.0), fr(3.0)]),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (33.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (67.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (33.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (100.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
    }

    @Test("grid_fr_fixed_size_single_item__border_box")
    func test_grid_fr_fixed_size_single_item__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style()).get();
    let node1 = try! taffy.newLeaf(Style()).get();
    let node2 = try! taffy.newLeaf(Style()).get();
    let node3 = try! taffy.newLeaf(Style()).get();
    let node4 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(100.0), height: auto())))
        .get();
    let node5 = try! taffy.newLeaf(Style()).get();
    let node6 = try! taffy.newLeaf(Style()).get();
    let node7 = try! taffy.newLeaf(Style()).get();
    let node8 = try! taffy.newLeaf(Style()).get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, size: Size(width: .fromLength(200.0), height: .fromLength(200.0)), gridTemplateRows: [length(40.0), fr(1.0), fr(1.0)], gridTemplateColumns: [length(40.0), fr(1.0), fr(1.0)]),
            [node0, node1, node2, node3, node4, node5, node6, node7, node8],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (140.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (80.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (40.0)) < 0.1)
        let layout_node4 = try! taffy.layout(node4).get()
        #expect(abs(layout_node4.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node4.size.height - (80.0)) < 0.1)
        #expect(abs(layout_node4.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node4.location.y - (40.0)) < 0.1)
        let layout_node5 = try! taffy.layout(node5).get()
        #expect(abs(layout_node5.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node5.size.height - (80.0)) < 0.1)
        #expect(abs(layout_node5.location.x - (140.0)) < 0.1)
        #expect(abs(layout_node5.location.y - (40.0)) < 0.1)
        let layout_node6 = try! taffy.layout(node6).get()
        #expect(abs(layout_node6.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node6.size.height - (80.0)) < 0.1)
        #expect(abs(layout_node6.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node6.location.y - (120.0)) < 0.1)
        let layout_node7 = try! taffy.layout(node7).get()
        #expect(abs(layout_node7.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node7.size.height - (80.0)) < 0.1)
        #expect(abs(layout_node7.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node7.location.y - (120.0)) < 0.1)
        let layout_node8 = try! taffy.layout(node8).get()
        #expect(abs(layout_node8.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node8.size.height - (80.0)) < 0.1)
        #expect(abs(layout_node8.location.x - (140.0)) < 0.1)
        #expect(abs(layout_node8.location.y - (120.0)) < 0.1)
    }

    @Test("grid_fr_fixed_size_single_item__content_box")
    func test_grid_fr_fixed_size_single_item__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node3 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node4 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: auto())))
        .get();
    let node5 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node6 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node7 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node8 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, size: Size(width: .fromLength(200.0), height: .fromLength(200.0)), gridTemplateRows: [length(40.0), fr(1.0), fr(1.0)], gridTemplateColumns: [length(40.0), fr(1.0), fr(1.0)]),
            [node0, node1, node2, node3, node4, node5, node6, node7, node8],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (140.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (80.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (40.0)) < 0.1)
        let layout_node4 = try! taffy.layout(node4).get()
        #expect(abs(layout_node4.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node4.size.height - (80.0)) < 0.1)
        #expect(abs(layout_node4.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node4.location.y - (40.0)) < 0.1)
        let layout_node5 = try! taffy.layout(node5).get()
        #expect(abs(layout_node5.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node5.size.height - (80.0)) < 0.1)
        #expect(abs(layout_node5.location.x - (140.0)) < 0.1)
        #expect(abs(layout_node5.location.y - (40.0)) < 0.1)
        let layout_node6 = try! taffy.layout(node6).get()
        #expect(abs(layout_node6.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node6.size.height - (80.0)) < 0.1)
        #expect(abs(layout_node6.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node6.location.y - (120.0)) < 0.1)
        let layout_node7 = try! taffy.layout(node7).get()
        #expect(abs(layout_node7.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node7.size.height - (80.0)) < 0.1)
        #expect(abs(layout_node7.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node7.location.y - (120.0)) < 0.1)
        let layout_node8 = try! taffy.layout(node8).get()
        #expect(abs(layout_node8.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node8.size.height - (80.0)) < 0.1)
        #expect(abs(layout_node8.location.x - (140.0)) < 0.1)
        #expect(abs(layout_node8.location.y - (120.0)) < 0.1)
    }

    @Test("grid_fr_span_2_proportion__border_box")
    func test_grid_fr_span_2_proportion__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(60.0), height: auto()), gridColumn: Line(start: span(2), end: .auto)))
        .get();
    let node1 = try! taffy.newLeaf(Style()).get();
    let node2 = try! taffy.newLeaf(Style()).get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, gridTemplateRows: [length(40.0), length(40.0)], gridTemplateColumns: [fr(1.0), fr(2.0)]),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node.size.height - (80.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (40.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (20.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (40.0)) < 0.1)
    }

    @Test("grid_fr_span_2_proportion__content_box")
    func test_grid_fr_span_2_proportion__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(60.0), height: auto()), gridColumn: Line(start: span(2), end: .auto)))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, gridTemplateRows: [length(40.0), length(40.0)], gridTemplateColumns: [fr(1.0), fr(2.0)]),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node.size.height - (80.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (40.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (20.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (40.0)) < 0.1)
    }

    @Test("grid_fr_fixed_size_no_content_proportions_sub_1_sum__border_box")
    func test_grid_fr_fixed_size_no_content_proportions_sub_1_sum__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style()).get();
    let node1 = try! taffy.newLeaf(Style()).get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, size: Size(width: .fromLength(100.0), height: auto()), gridTemplateRows: [length(40.0)], gridTemplateColumns: [fr(0.3), fr(0.2)]),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (30.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (30.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
    }

    @Test("grid_fr_fixed_size_no_content_proportions_sub_1_sum__content_box")
    func test_grid_fr_fixed_size_no_content_proportions_sub_1_sum__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: auto()), gridTemplateRows: [length(40.0)], gridTemplateColumns: [fr(0.3), fr(0.2)]),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (30.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (30.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
    }

    @Test("grid_auto_takes_precedence_over_fr__border_box")
    func test_grid_auto_takes_precedence_over_fr__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style()).get();
    let node1 = try! taffy.newLeaf(Style()).get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, size: Size(width: .fromLength(200.0), height: .fromLength(200.0)), gridTemplateRows: [length(40.0)], gridTemplateColumns: [auto(), fr(1.0)]),
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
        #expect(abs(layout_node0.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
    }

    @Test("grid_auto_takes_precedence_over_fr__content_box")
    func test_grid_auto_takes_precedence_over_fr__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, size: Size(width: .fromLength(200.0), height: .fromLength(200.0)), gridTemplateRows: [length(40.0)], gridTemplateColumns: [auto(), fr(1.0)]),
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
        #expect(abs(layout_node0.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
    }

    @Test("grid_fr_span_2_proportion_with_non_spanned_track__border_box")
    func test_grid_fr_span_2_proportion_with_non_spanned_track__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(60.0), height: auto()), gridColumn: Line(start: span(2), end: .auto)))
        .get();
    let node1 = try! taffy.newLeaf(Style()).get();
    let node2 = try! taffy.newLeaf(Style()).get();
    let node3 = try! taffy.newLeaf(Style()).get();
    let node4 = try! taffy.newLeaf(Style()).get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, gridTemplateRows: [length(40.0), length(40.0)], gridTemplateColumns: [fr(1.0), fr(2.0), fr(3.0)]),
            [node0, node1, node2, node3, node4],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (120.0)) < 0.1)
        #expect(abs(layout_node.size.height - (80.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (60.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (40.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (20.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (40.0)) < 0.1)
        let layout_node4 = try! taffy.layout(node4).get()
        #expect(abs(layout_node4.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node4.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node4.location.x - (60.0)) < 0.1)
        #expect(abs(layout_node4.location.y - (40.0)) < 0.1)
    }

    @Test("grid_fr_span_2_proportion_with_non_spanned_track__content_box")
    func test_grid_fr_span_2_proportion_with_non_spanned_track__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(60.0), height: auto()), gridColumn: Line(start: span(2), end: .auto)))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node3 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node4 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, gridTemplateRows: [length(40.0), length(40.0)], gridTemplateColumns: [fr(1.0), fr(2.0), fr(3.0)]),
            [node0, node1, node2, node3, node4],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (120.0)) < 0.1)
        #expect(abs(layout_node.size.height - (80.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (60.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (40.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (20.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (40.0)) < 0.1)
        let layout_node4 = try! taffy.layout(node4).get()
        #expect(abs(layout_node4.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node4.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node4.location.x - (60.0)) < 0.1)
        #expect(abs(layout_node4.location.y - (40.0)) < 0.1)
    }

    @Test("grid_minmax_auto_fixed_10px__border_box")
    func test_grid_minmax_auto_fixed_10px__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeafWithContext(
            Style(),
            TestNodeContext.ahemText("HH\u{200b}HH", .horizontal),
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, gridTemplateRows: [length(40.0)], gridTemplateColumns: [minmax(auto(), length(10.0))]),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
    }

    @Test("grid_minmax_auto_fixed_10px__content_box")
    func test_grid_minmax_auto_fixed_10px__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeafWithContext(
            Style(boxSizing: .contentBox),
            TestNodeContext.ahemText("HH\u{200b}HH", .horizontal),
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, gridTemplateRows: [length(40.0)], gridTemplateColumns: [minmax(auto(), length(10.0))]),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
    }

    @Test("grid_minmax_auto_max_content__border_box")
    func test_grid_minmax_auto_max_content__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeafWithContext(
            Style(),
            TestNodeContext.ahemText("HH\u{200b}HH", .horizontal),
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, gridTemplateRows: [length(40.0)], gridTemplateColumns: [minmax(auto(), max_content())]),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
    }

    @Test("grid_minmax_auto_max_content__content_box")
    func test_grid_minmax_auto_max_content__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeafWithContext(
            Style(boxSizing: .contentBox),
            TestNodeContext.ahemText("HH\u{200b}HH", .horizontal),
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, gridTemplateRows: [length(40.0)], gridTemplateColumns: [minmax(auto(), max_content())]),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
    }

    @Test("grid_minmax_auto_min_content__border_box")
    func test_grid_minmax_auto_min_content__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeafWithContext(
            Style(),
            TestNodeContext.ahemText("HH\u{200b}HH", .horizontal),
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, gridTemplateRows: [length(40.0)], gridTemplateColumns: [minmax(auto(), min_content())]),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
    }

    @Test("grid_minmax_auto_min_content__content_box")
    func test_grid_minmax_auto_min_content__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeafWithContext(
            Style(boxSizing: .contentBox),
            TestNodeContext.ahemText("HH\u{200b}HH", .horizontal),
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, gridTemplateRows: [length(40.0)], gridTemplateColumns: [minmax(auto(), min_content())]),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
    }

    @Test("grid_minmax_auto_percent_definite__border_box")
    func test_grid_minmax_auto_percent_definite__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeafWithContext(
            Style(),
            TestNodeContext.ahemText("HH\u{200b}HH", .horizontal),
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, size: Size(width: .fromLength(100.0), height: auto()), gridTemplateRows: [length(40.0)], gridTemplateColumns: [minmax(auto(), percent(0.2))]),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
    }

    @Test("grid_minmax_auto_percent_definite__content_box")
    func test_grid_minmax_auto_percent_definite__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeafWithContext(
            Style(boxSizing: .contentBox),
            TestNodeContext.ahemText("HH\u{200b}HH", .horizontal),
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: auto()), gridTemplateRows: [length(40.0)], gridTemplateColumns: [minmax(auto(), percent(0.2))]),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
    }

    @Test("grid_minmax_column_fixed_width_above_range__border_box")
    func test_grid_minmax_column_fixed_width_above_range__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style()).get();
    let node1 = try! taffy.newLeaf(Style()).get();
    let node2 = try! taffy.newLeaf(Style()).get();
    let node3 = try! taffy.newLeaf(Style()).get();
    let node4 = try! taffy.newLeaf(Style()).get();
    let node5 = try! taffy.newLeaf(Style()).get();
    let node6 = try! taffy.newLeaf(Style()).get();
    let node7 = try! taffy.newLeaf(Style()).get();
    let node8 = try! taffy.newLeaf(Style()).get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, size: Size(width: .fromLength(140.0), height: auto()), gridTemplateRows: [length(40.0), length(40.0), length(40.0)], gridTemplateColumns: [length(40.0), minmax(length(20.0), length(40.0)), length(40.0)]),
            [node0, node1, node2, node3, node4, node5, node6, node7, node8],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (140.0)) < 0.1)
        #expect(abs(layout_node.size.height - (120.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (40.0)) < 0.1)
        let layout_node4 = try! taffy.layout(node4).get()
        #expect(abs(layout_node4.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node4.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node4.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node4.location.y - (40.0)) < 0.1)
        let layout_node5 = try! taffy.layout(node5).get()
        #expect(abs(layout_node5.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node5.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node5.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node5.location.y - (40.0)) < 0.1)
        let layout_node6 = try! taffy.layout(node6).get()
        #expect(abs(layout_node6.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node6.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node6.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node6.location.y - (80.0)) < 0.1)
        let layout_node7 = try! taffy.layout(node7).get()
        #expect(abs(layout_node7.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node7.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node7.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node7.location.y - (80.0)) < 0.1)
        let layout_node8 = try! taffy.layout(node8).get()
        #expect(abs(layout_node8.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node8.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node8.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node8.location.y - (80.0)) < 0.1)
    }

    @Test("grid_minmax_column_fixed_width_above_range__content_box")
    func test_grid_minmax_column_fixed_width_above_range__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node3 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node4 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node5 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node6 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node7 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node8 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, size: Size(width: .fromLength(140.0), height: auto()), gridTemplateRows: [length(40.0), length(40.0), length(40.0)], gridTemplateColumns: [length(40.0), minmax(length(20.0), length(40.0)), length(40.0)]),
            [node0, node1, node2, node3, node4, node5, node6, node7, node8],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (140.0)) < 0.1)
        #expect(abs(layout_node.size.height - (120.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (40.0)) < 0.1)
        let layout_node4 = try! taffy.layout(node4).get()
        #expect(abs(layout_node4.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node4.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node4.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node4.location.y - (40.0)) < 0.1)
        let layout_node5 = try! taffy.layout(node5).get()
        #expect(abs(layout_node5.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node5.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node5.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node5.location.y - (40.0)) < 0.1)
        let layout_node6 = try! taffy.layout(node6).get()
        #expect(abs(layout_node6.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node6.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node6.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node6.location.y - (80.0)) < 0.1)
        let layout_node7 = try! taffy.layout(node7).get()
        #expect(abs(layout_node7.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node7.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node7.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node7.location.y - (80.0)) < 0.1)
        let layout_node8 = try! taffy.layout(node8).get()
        #expect(abs(layout_node8.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node8.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node8.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node8.location.y - (80.0)) < 0.1)
    }

    @Test("grid_fit_content_percent_definite_argument__border_box")
    func test_grid_fit_content_percent_definite_argument__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeafWithContext(
            Style(),
            TestNodeContext.ahemText("HH\u{200b}HH", .horizontal),
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, size: Size(width: .fromLength(60.0), height: auto()), gridTemplateRows: [length(40.0)], gridTemplateColumns: [fit_content(percent(0.5))]),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (30.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
    }

    @Test("grid_fit_content_percent_definite_argument__content_box")
    func test_grid_fit_content_percent_definite_argument__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeafWithContext(
            Style(boxSizing: .contentBox),
            TestNodeContext.ahemText("HH\u{200b}HH", .horizontal),
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, size: Size(width: .fromLength(60.0), height: auto()), gridTemplateRows: [length(40.0)], gridTemplateColumns: [fit_content(percent(0.5))]),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (30.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
    }

    @Test("grid_placement_auto_negative__border_box")
    func test_grid_placement_auto_negative__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(gridRow: Line(start: line(1), end: .auto), gridColumn: Line(start: line(-5), end: .auto)))
        .get();
    let node1 = try! taffy.newLeaf(Style()).get();
    let node2 = try! taffy.newLeaf(Style(gridRow: Line(start: line(2), end: .auto)))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, size: Size(width: .fromLength(120.0), height: .fromLength(120.0)), gridTemplateRows: [length(40.0), length(40.0)], gridTemplateColumns: [length(40.0), length(40.0)]),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (120.0)) < 0.1)
        #expect(abs(layout_node.size.height - (120.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (20.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (40.0)) < 0.1)
    }

    @Test("grid_placement_auto_negative__content_box")
    func test_grid_placement_auto_negative__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, gridRow: Line(start: line(1), end: .auto), gridColumn: Line(start: line(-5), end: .auto)))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox, gridRow: Line(start: line(2), end: .auto)))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, size: Size(width: .fromLength(120.0), height: .fromLength(120.0)), gridTemplateRows: [length(40.0), length(40.0)], gridTemplateColumns: [length(40.0), length(40.0)]),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (120.0)) < 0.1)
        #expect(abs(layout_node.size.height - (120.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (20.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (40.0)) < 0.1)
    }

    @Test("grid_placement_definite_primary__border_box")
    func test_grid_placement_definite_primary__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(gridColumn: Line(start: line(1), end: .auto)))
        .get();
    let node1 = try! taffy.newLeaf(Style(gridColumn: Line(start: line(2), end: .auto)))
        .get();
    let node2 = try! taffy.newLeaf(Style(gridColumn: Line(start: line(1), end: .auto)))
        .get();
    let node3 = try! taffy.newLeaf(Style(gridColumn: Line(start: line(2), end: .auto)))
        .get();
    let node4 = try! taffy.newLeaf(Style(gridColumn: Line(start: line(1), end: .auto)))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, size: Size(width: .fromLength(200.0), height: .fromLength(200.0)), gridTemplateColumns: [percent(0.33), percent(0.74)]),
            [node0, node1, node2, node3, node4],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (66.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (67.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (148.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (67.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (66.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (66.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (66.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (67.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (148.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (66.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (66.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (67.0)) < 0.1)
        let layout_node4 = try! taffy.layout(node4).get()
        #expect(abs(layout_node4.size.width - (66.0)) < 0.1)
        #expect(abs(layout_node4.size.height - (67.0)) < 0.1)
        #expect(abs(layout_node4.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node4.location.y - (133.0)) < 0.1)
    }

    @Test("grid_placement_definite_primary__content_box")
    func test_grid_placement_definite_primary__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, gridColumn: Line(start: line(1), end: .auto)))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, gridColumn: Line(start: line(2), end: .auto)))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox, gridColumn: Line(start: line(1), end: .auto)))
        .get();
    let node3 = try! taffy.newLeaf(Style(boxSizing: .contentBox, gridColumn: Line(start: line(2), end: .auto)))
        .get();
    let node4 = try! taffy.newLeaf(Style(boxSizing: .contentBox, gridColumn: Line(start: line(1), end: .auto)))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, size: Size(width: .fromLength(200.0), height: .fromLength(200.0)), gridTemplateColumns: [percent(0.33), percent(0.74)]),
            [node0, node1, node2, node3, node4],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (66.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (67.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (148.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (67.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (66.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (66.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (66.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (67.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (148.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (66.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (66.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (67.0)) < 0.1)
        let layout_node4 = try! taffy.layout(node4).get()
        #expect(abs(layout_node4.size.width - (66.0)) < 0.1)
        #expect(abs(layout_node4.size.height - (67.0)) < 0.1)
        #expect(abs(layout_node4.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node4.location.y - (133.0)) < 0.1)
    }

    @Test("grid_span_2_max_content_auto_indefinite__border_box")
    func test_grid_span_2_max_content_auto_indefinite__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(gridRow: Line(start: line(1), end: .auto), gridColumn: Line(start: line(1), end: .auto)))
        .get();
    let node1 = try! taffy.newLeaf(Style(gridRow: Line(start: line(1), end: .auto), gridColumn: Line(start: line(2), end: .auto)))
        .get();
    let node2 = try! taffy.newLeafWithContext(
            Style(gridRow: Line(start: line(1), end: .auto), gridColumn: Line(start: line(1), end: span(2))),
            TestNodeContext.ahemText("HHHH\u{200b}HHHH", .horizontal),
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, gridTemplateRows: [length(40.0)], gridTemplateColumns: [max_content(), auto()]),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (80.0)) < 0.1)
        #expect(abs(layout_node.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (60.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (80.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
    }

    @Test("grid_span_2_max_content_auto_indefinite__content_box")
    func test_grid_span_2_max_content_auto_indefinite__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, gridRow: Line(start: line(1), end: .auto), gridColumn: Line(start: line(1), end: .auto)))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, gridRow: Line(start: line(1), end: .auto), gridColumn: Line(start: line(2), end: .auto)))
        .get();
    let node2 = try! taffy.newLeafWithContext(
            Style(boxSizing: .contentBox, gridRow: Line(start: line(1), end: .auto), gridColumn: Line(start: line(1), end: span(2))),
            TestNodeContext.ahemText("HHHH\u{200b}HHHH", .horizontal),
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, gridTemplateRows: [length(40.0)], gridTemplateColumns: [max_content(), auto()]),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (80.0)) < 0.1)
        #expect(abs(layout_node.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (60.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (80.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
    }

    @Test("grid_auto_fill_fixed_size__border_box")
    func test_grid_auto_fill_fixed_size__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style()).get();
    let node1 = try! taffy.newLeaf(Style()).get();
    let node2 = try! taffy.newLeaf(Style()).get();
    let node3 = try! taffy.newLeaf(Style()).get();
    let node4 = try! taffy.newLeaf(Style()).get();
    let node5 = try! taffy.newLeaf(Style()).get();
    let node6 = try! taffy.newLeaf(Style()).get();
    let node7 = try! taffy.newLeaf(Style()).get();
    let node8 = try! taffy.newLeaf(Style()).get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, size: Size(width: .fromLength(120.0), height: .fromLength(120.0)), gridTemplateRows: [length(40.0), length(40.0), length(40.0)], gridTemplateColumns: [length(40.0), repeat_(.autoFill, [length(40.0)])]),
            [node0, node1, node2, node3, node4, node5, node6, node7, node8],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (120.0)) < 0.1)
        #expect(abs(layout_node.size.height - (120.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (40.0)) < 0.1)
        let layout_node4 = try! taffy.layout(node4).get()
        #expect(abs(layout_node4.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node4.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node4.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node4.location.y - (40.0)) < 0.1)
        let layout_node5 = try! taffy.layout(node5).get()
        #expect(abs(layout_node5.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node5.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node5.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node5.location.y - (40.0)) < 0.1)
        let layout_node6 = try! taffy.layout(node6).get()
        #expect(abs(layout_node6.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node6.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node6.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node6.location.y - (80.0)) < 0.1)
        let layout_node7 = try! taffy.layout(node7).get()
        #expect(abs(layout_node7.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node7.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node7.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node7.location.y - (80.0)) < 0.1)
        let layout_node8 = try! taffy.layout(node8).get()
        #expect(abs(layout_node8.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node8.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node8.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node8.location.y - (80.0)) < 0.1)
    }

    @Test("grid_auto_fill_fixed_size__content_box")
    func test_grid_auto_fill_fixed_size__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node3 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node4 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node5 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node6 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node7 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node8 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, size: Size(width: .fromLength(120.0), height: .fromLength(120.0)), gridTemplateRows: [length(40.0), length(40.0), length(40.0)], gridTemplateColumns: [length(40.0), repeat_(.autoFill, [length(40.0)])]),
            [node0, node1, node2, node3, node4, node5, node6, node7, node8],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (120.0)) < 0.1)
        #expect(abs(layout_node.size.height - (120.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (40.0)) < 0.1)
        let layout_node4 = try! taffy.layout(node4).get()
        #expect(abs(layout_node4.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node4.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node4.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node4.location.y - (40.0)) < 0.1)
        let layout_node5 = try! taffy.layout(node5).get()
        #expect(abs(layout_node5.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node5.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node5.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node5.location.y - (40.0)) < 0.1)
        let layout_node6 = try! taffy.layout(node6).get()
        #expect(abs(layout_node6.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node6.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node6.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node6.location.y - (80.0)) < 0.1)
        let layout_node7 = try! taffy.layout(node7).get()
        #expect(abs(layout_node7.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node7.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node7.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node7.location.y - (80.0)) < 0.1)
        let layout_node8 = try! taffy.layout(node8).get()
        #expect(abs(layout_node8.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node8.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node8.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node8.location.y - (80.0)) < 0.1)
    }

    @Test("grid_auto_fit_definite_percentage__border_box")
    func test_grid_auto_fit_definite_percentage__border_box() {

    
    
    var taffy = newTestTree();
    let node00 =
        try! taffy.newLeaf(Style(display: Display.block)).get();
    let node01 =
        try! taffy.newLeaf(Style(display: Display.block)).get();
    let node02 =
        try! taffy.newLeaf(Style(display: Display.block)).get();
    let node03 =
        try! taffy.newLeaf(Style(display: Display.block)).get();
    let node04 =
        try! taffy.newLeaf(Style(display: Display.block)).get();
    let node05 =
        try! taffy.newLeaf(Style(display: Display.block)).get();
    let node06 =
        try! taffy.newLeaf(Style(display: Display.block)).get();
    let node07 =
        try! taffy.newLeaf(Style(display: Display.block)).get();
    let node0 = try! taffy.newWithChildren(
            Style(display: Display.grid, size: Size(width: .fromPercent(1.0), height: .fromPercent(1.0)), padding: Rect(left: length(10.0), right: length(10.0), top: length(10.0), bottom: length(10.0)), gap: Size(width: length(10.0), height: length(10.0)), gridTemplateColumns: [repeat_(.autoFill, [minmax(length(150.0), fr(1.0))])]),
            [node00, node01, node02, node03, node04, node05, node06, node07],
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(730.0), height: .fromLength(300.0))),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (730.0)) < 0.1)
        #expect(abs(layout_node.size.height - (300.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (730.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (300.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node00 = try! taffy.layout(node00).get()
        #expect(abs(layout_node00.size.width - (170.0)) < 0.1)
        #expect(abs(layout_node00.size.height - (135.0)) < 0.1)
        #expect(abs(layout_node00.location.x - (10.0)) < 0.1)
        #expect(abs(layout_node00.location.y - (10.0)) < 0.1)
        let layout_node01 = try! taffy.layout(node01).get()
        #expect(abs(layout_node01.size.width - (170.0)) < 0.1)
        #expect(abs(layout_node01.size.height - (135.0)) < 0.1)
        #expect(abs(layout_node01.location.x - (190.0)) < 0.1)
        #expect(abs(layout_node01.location.y - (10.0)) < 0.1)
        let layout_node02 = try! taffy.layout(node02).get()
        #expect(abs(layout_node02.size.width - (170.0)) < 0.1)
        #expect(abs(layout_node02.size.height - (135.0)) < 0.1)
        #expect(abs(layout_node02.location.x - (370.0)) < 0.1)
        #expect(abs(layout_node02.location.y - (10.0)) < 0.1)
        let layout_node03 = try! taffy.layout(node03).get()
        #expect(abs(layout_node03.size.width - (170.0)) < 0.1)
        #expect(abs(layout_node03.size.height - (135.0)) < 0.1)
        #expect(abs(layout_node03.location.x - (550.0)) < 0.1)
        #expect(abs(layout_node03.location.y - (10.0)) < 0.1)
        let layout_node04 = try! taffy.layout(node04).get()
        #expect(abs(layout_node04.size.width - (170.0)) < 0.1)
        #expect(abs(layout_node04.size.height - (135.0)) < 0.1)
        #expect(abs(layout_node04.location.x - (10.0)) < 0.1)
        #expect(abs(layout_node04.location.y - (155.0)) < 0.1)
        let layout_node05 = try! taffy.layout(node05).get()
        #expect(abs(layout_node05.size.width - (170.0)) < 0.1)
        #expect(abs(layout_node05.size.height - (135.0)) < 0.1)
        #expect(abs(layout_node05.location.x - (190.0)) < 0.1)
        #expect(abs(layout_node05.location.y - (155.0)) < 0.1)
        let layout_node06 = try! taffy.layout(node06).get()
        #expect(abs(layout_node06.size.width - (170.0)) < 0.1)
        #expect(abs(layout_node06.size.height - (135.0)) < 0.1)
        #expect(abs(layout_node06.location.x - (370.0)) < 0.1)
        #expect(abs(layout_node06.location.y - (155.0)) < 0.1)
        let layout_node07 = try! taffy.layout(node07).get()
        #expect(abs(layout_node07.size.width - (170.0)) < 0.1)
        #expect(abs(layout_node07.size.height - (135.0)) < 0.1)
        #expect(abs(layout_node07.location.x - (550.0)) < 0.1)
        #expect(abs(layout_node07.location.y - (155.0)) < 0.1)
    }

    @Test("grid_auto_fit_definite_percentage__content_box")
    func test_grid_auto_fit_definite_percentage__content_box() {

    
    
    var taffy = newTestTree();
    let node00 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox))
        .get();
    let node01 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox))
        .get();
    let node02 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox))
        .get();
    let node03 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox))
        .get();
    let node04 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox))
        .get();
    let node05 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox))
        .get();
    let node06 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox))
        .get();
    let node07 = try! taffy.newLeaf(Style(display: Display.block, boxSizing: .contentBox))
        .get();
    let node0 = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, size: Size(width: .fromPercent(1.0), height: .fromPercent(1.0)), padding: Rect(left: length(10.0), right: length(10.0), top: length(10.0), bottom: length(10.0)), gap: Size(width: length(10.0), height: length(10.0)), gridTemplateColumns: [repeat_(.autoFill, [minmax(length(150.0), fr(1.0))])]),
            [node00, node01, node02, node03, node04, node05, node06, node07],
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(730.0), height: .fromLength(300.0))),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (730.0)) < 0.1)
        #expect(abs(layout_node.size.height - (300.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (730.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (320.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node00 = try! taffy.layout(node00).get()
        #expect(abs(layout_node00.size.width - (170.0)) < 0.1)
        #expect(abs(layout_node00.size.height - (145.0)) < 0.1)
        #expect(abs(layout_node00.location.x - (10.0)) < 0.1)
        #expect(abs(layout_node00.location.y - (10.0)) < 0.1)
        let layout_node01 = try! taffy.layout(node01).get()
        #expect(abs(layout_node01.size.width - (170.0)) < 0.1)
        #expect(abs(layout_node01.size.height - (145.0)) < 0.1)
        #expect(abs(layout_node01.location.x - (190.0)) < 0.1)
        #expect(abs(layout_node01.location.y - (10.0)) < 0.1)
        let layout_node02 = try! taffy.layout(node02).get()
        #expect(abs(layout_node02.size.width - (170.0)) < 0.1)
        #expect(abs(layout_node02.size.height - (145.0)) < 0.1)
        #expect(abs(layout_node02.location.x - (370.0)) < 0.1)
        #expect(abs(layout_node02.location.y - (10.0)) < 0.1)
        let layout_node03 = try! taffy.layout(node03).get()
        #expect(abs(layout_node03.size.width - (170.0)) < 0.1)
        #expect(abs(layout_node03.size.height - (145.0)) < 0.1)
        #expect(abs(layout_node03.location.x - (550.0)) < 0.1)
        #expect(abs(layout_node03.location.y - (10.0)) < 0.1)
        let layout_node04 = try! taffy.layout(node04).get()
        #expect(abs(layout_node04.size.width - (170.0)) < 0.1)
        #expect(abs(layout_node04.size.height - (145.0)) < 0.1)
        #expect(abs(layout_node04.location.x - (10.0)) < 0.1)
        #expect(abs(layout_node04.location.y - (165.0)) < 0.1)
        let layout_node05 = try! taffy.layout(node05).get()
        #expect(abs(layout_node05.size.width - (170.0)) < 0.1)
        #expect(abs(layout_node05.size.height - (145.0)) < 0.1)
        #expect(abs(layout_node05.location.x - (190.0)) < 0.1)
        #expect(abs(layout_node05.location.y - (165.0)) < 0.1)
        let layout_node06 = try! taffy.layout(node06).get()
        #expect(abs(layout_node06.size.width - (170.0)) < 0.1)
        #expect(abs(layout_node06.size.height - (145.0)) < 0.1)
        #expect(abs(layout_node06.location.x - (370.0)) < 0.1)
        #expect(abs(layout_node06.location.y - (165.0)) < 0.1)
        let layout_node07 = try! taffy.layout(node07).get()
        #expect(abs(layout_node07.size.width - (170.0)) < 0.1)
        #expect(abs(layout_node07.size.height - (145.0)) < 0.1)
        #expect(abs(layout_node07.location.x - (550.0)) < 0.1)
        #expect(abs(layout_node07.location.y - (165.0)) < 0.1)
    }

    @Test("grid_auto_columns_fixed_width__border_box")
    func test_grid_auto_columns_fixed_width__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style()).get();
    let node1 = try! taffy.newLeaf(Style()).get();
    let node2 = try! taffy.newLeaf(Style()).get();
    let node3 = try! taffy.newLeaf(Style()).get();
    let node4 = try! taffy.newLeaf(Style()).get();
    let node5 = try! taffy.newLeaf(Style()).get();
    let node6 = try! taffy.newLeaf(Style()).get();
    let node7 = try! taffy.newLeaf(Style()).get();
    let node8 = try! taffy.newLeaf(Style()).get();
    let node9 = try! taffy.newLeaf(Style()).get();
    let node10 = try! taffy.newLeaf(Style()).get();
    let node11 = try! taffy.newLeaf(Style()).get();
    let node12 = try! taffy.newLeaf(Style()).get();
    let node13 = try! taffy.newLeaf(Style()).get();
    let node14 = try! taffy.newLeaf(Style()).get();
    let node15 = try! taffy.newLeaf(Style()).get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, size: Size(width: .fromLength(200.0), height: .fromLength(200.0)), gridTemplateRows: [length(40.0), auto(), length(40.0), auto()], gridTemplateColumns: [length(40.0), auto(), length(40.0), auto()]),
            [
                node0, node1, node2, node3, node4, node5, node6, node7, node8, node9, node10, node11, node12, node13,
                node14, node15,
            ],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (100.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (140.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (0.0)) < 0.1)
        let layout_node4 = try! taffy.layout(node4).get()
        #expect(abs(layout_node4.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node4.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node4.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node4.location.y - (40.0)) < 0.1)
        let layout_node5 = try! taffy.layout(node5).get()
        #expect(abs(layout_node5.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node5.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node5.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node5.location.y - (40.0)) < 0.1)
        let layout_node6 = try! taffy.layout(node6).get()
        #expect(abs(layout_node6.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node6.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node6.location.x - (100.0)) < 0.1)
        #expect(abs(layout_node6.location.y - (40.0)) < 0.1)
        let layout_node7 = try! taffy.layout(node7).get()
        #expect(abs(layout_node7.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node7.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node7.location.x - (140.0)) < 0.1)
        #expect(abs(layout_node7.location.y - (40.0)) < 0.1)
        let layout_node8 = try! taffy.layout(node8).get()
        #expect(abs(layout_node8.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node8.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node8.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node8.location.y - (100.0)) < 0.1)
        let layout_node9 = try! taffy.layout(node9).get()
        #expect(abs(layout_node9.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node9.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node9.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node9.location.y - (100.0)) < 0.1)
        let layout_node10 = try! taffy.layout(node10).get()
        #expect(abs(layout_node10.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node10.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node10.location.x - (100.0)) < 0.1)
        #expect(abs(layout_node10.location.y - (100.0)) < 0.1)
        let layout_node11 = try! taffy.layout(node11).get()
        #expect(abs(layout_node11.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node11.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node11.location.x - (140.0)) < 0.1)
        #expect(abs(layout_node11.location.y - (100.0)) < 0.1)
        let layout_node12 = try! taffy.layout(node12).get()
        #expect(abs(layout_node12.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node12.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node12.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node12.location.y - (140.0)) < 0.1)
        let layout_node13 = try! taffy.layout(node13).get()
        #expect(abs(layout_node13.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node13.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node13.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node13.location.y - (140.0)) < 0.1)
        let layout_node14 = try! taffy.layout(node14).get()
        #expect(abs(layout_node14.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node14.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node14.location.x - (100.0)) < 0.1)
        #expect(abs(layout_node14.location.y - (140.0)) < 0.1)
        let layout_node15 = try! taffy.layout(node15).get()
        #expect(abs(layout_node15.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node15.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node15.location.x - (140.0)) < 0.1)
        #expect(abs(layout_node15.location.y - (140.0)) < 0.1)
    }

    @Test("grid_auto_columns_fixed_width__content_box")
    func test_grid_auto_columns_fixed_width__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node3 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node4 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node5 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node6 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node7 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node8 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node9 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node10 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node11 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node12 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node13 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node14 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node15 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, size: Size(width: .fromLength(200.0), height: .fromLength(200.0)), gridTemplateRows: [length(40.0), auto(), length(40.0), auto()], gridTemplateColumns: [length(40.0), auto(), length(40.0), auto()]),
            [
                node0, node1, node2, node3, node4, node5, node6, node7, node8, node9, node10, node11, node12, node13,
                node14, node15,
            ],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (100.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (140.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (0.0)) < 0.1)
        let layout_node4 = try! taffy.layout(node4).get()
        #expect(abs(layout_node4.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node4.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node4.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node4.location.y - (40.0)) < 0.1)
        let layout_node5 = try! taffy.layout(node5).get()
        #expect(abs(layout_node5.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node5.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node5.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node5.location.y - (40.0)) < 0.1)
        let layout_node6 = try! taffy.layout(node6).get()
        #expect(abs(layout_node6.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node6.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node6.location.x - (100.0)) < 0.1)
        #expect(abs(layout_node6.location.y - (40.0)) < 0.1)
        let layout_node7 = try! taffy.layout(node7).get()
        #expect(abs(layout_node7.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node7.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node7.location.x - (140.0)) < 0.1)
        #expect(abs(layout_node7.location.y - (40.0)) < 0.1)
        let layout_node8 = try! taffy.layout(node8).get()
        #expect(abs(layout_node8.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node8.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node8.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node8.location.y - (100.0)) < 0.1)
        let layout_node9 = try! taffy.layout(node9).get()
        #expect(abs(layout_node9.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node9.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node9.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node9.location.y - (100.0)) < 0.1)
        let layout_node10 = try! taffy.layout(node10).get()
        #expect(abs(layout_node10.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node10.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node10.location.x - (100.0)) < 0.1)
        #expect(abs(layout_node10.location.y - (100.0)) < 0.1)
        let layout_node11 = try! taffy.layout(node11).get()
        #expect(abs(layout_node11.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node11.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node11.location.x - (140.0)) < 0.1)
        #expect(abs(layout_node11.location.y - (100.0)) < 0.1)
        let layout_node12 = try! taffy.layout(node12).get()
        #expect(abs(layout_node12.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node12.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node12.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node12.location.y - (140.0)) < 0.1)
        let layout_node13 = try! taffy.layout(node13).get()
        #expect(abs(layout_node13.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node13.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node13.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node13.location.y - (140.0)) < 0.1)
        let layout_node14 = try! taffy.layout(node14).get()
        #expect(abs(layout_node14.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node14.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node14.location.x - (100.0)) < 0.1)
        #expect(abs(layout_node14.location.y - (140.0)) < 0.1)
        let layout_node15 = try! taffy.layout(node15).get()
        #expect(abs(layout_node15.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node15.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node15.location.x - (140.0)) < 0.1)
        #expect(abs(layout_node15.location.y - (140.0)) < 0.1)
    }

    @Test("grid_align_content_center__border_box")
    func test_grid_align_content_center__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style()).get();
    let node1 = try! taffy.newLeaf(Style()).get();
    let node2 = try! taffy.newLeaf(Style()).get();
    let node3 = try! taffy.newLeaf(Style()).get();
    let node4 = try! taffy.newLeaf(Style()).get();
    let node5 = try! taffy.newLeaf(Style()).get();
    let node6 = try! taffy.newLeaf(Style()).get();
    let node7 = try! taffy.newLeaf(Style()).get();
    let node8 = try! taffy.newLeaf(Style()).get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, size: Size(width: .fromLength(200.0), height: .fromLength(200.0)), alignContent: .center, gridTemplateRows: [length(40.0), length(40.0), length(40.0)], gridTemplateColumns: [length(40.0), length(40.0), length(40.0)]),
            [node0, node1, node2, node3, node4, node5, node6, node7, node8],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (40.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (40.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (40.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (80.0)) < 0.1)
        let layout_node4 = try! taffy.layout(node4).get()
        #expect(abs(layout_node4.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node4.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node4.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node4.location.y - (80.0)) < 0.1)
        let layout_node5 = try! taffy.layout(node5).get()
        #expect(abs(layout_node5.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node5.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node5.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node5.location.y - (80.0)) < 0.1)
        let layout_node6 = try! taffy.layout(node6).get()
        #expect(abs(layout_node6.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node6.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node6.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node6.location.y - (120.0)) < 0.1)
        let layout_node7 = try! taffy.layout(node7).get()
        #expect(abs(layout_node7.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node7.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node7.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node7.location.y - (120.0)) < 0.1)
        let layout_node8 = try! taffy.layout(node8).get()
        #expect(abs(layout_node8.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node8.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node8.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node8.location.y - (120.0)) < 0.1)
    }

    @Test("grid_align_content_center__content_box")
    func test_grid_align_content_center__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node3 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node4 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node5 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node6 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node7 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node8 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, size: Size(width: .fromLength(200.0), height: .fromLength(200.0)), alignContent: .center, gridTemplateRows: [length(40.0), length(40.0), length(40.0)], gridTemplateColumns: [length(40.0), length(40.0), length(40.0)]),
            [node0, node1, node2, node3, node4, node5, node6, node7, node8],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (40.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (40.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (40.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (80.0)) < 0.1)
        let layout_node4 = try! taffy.layout(node4).get()
        #expect(abs(layout_node4.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node4.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node4.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node4.location.y - (80.0)) < 0.1)
        let layout_node5 = try! taffy.layout(node5).get()
        #expect(abs(layout_node5.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node5.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node5.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node5.location.y - (80.0)) < 0.1)
        let layout_node6 = try! taffy.layout(node6).get()
        #expect(abs(layout_node6.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node6.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node6.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node6.location.y - (120.0)) < 0.1)
        let layout_node7 = try! taffy.layout(node7).get()
        #expect(abs(layout_node7.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node7.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node7.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node7.location.y - (120.0)) < 0.1)
        let layout_node8 = try! taffy.layout(node8).get()
        #expect(abs(layout_node8.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node8.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node8.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node8.location.y - (120.0)) < 0.1)
    }

    @Test("grid_align_content_end__border_box")
    func test_grid_align_content_end__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style()).get();
    let node1 = try! taffy.newLeaf(Style()).get();
    let node2 = try! taffy.newLeaf(Style()).get();
    let node3 = try! taffy.newLeaf(Style()).get();
    let node4 = try! taffy.newLeaf(Style()).get();
    let node5 = try! taffy.newLeaf(Style()).get();
    let node6 = try! taffy.newLeaf(Style()).get();
    let node7 = try! taffy.newLeaf(Style()).get();
    let node8 = try! taffy.newLeaf(Style()).get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, size: Size(width: .fromLength(200.0), height: .fromLength(200.0)), alignContent: .end, gridTemplateRows: [length(40.0), length(40.0), length(40.0)], gridTemplateColumns: [length(40.0), length(40.0), length(40.0)]),
            [node0, node1, node2, node3, node4, node5, node6, node7, node8],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (80.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (80.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (80.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (120.0)) < 0.1)
        let layout_node4 = try! taffy.layout(node4).get()
        #expect(abs(layout_node4.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node4.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node4.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node4.location.y - (120.0)) < 0.1)
        let layout_node5 = try! taffy.layout(node5).get()
        #expect(abs(layout_node5.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node5.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node5.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node5.location.y - (120.0)) < 0.1)
        let layout_node6 = try! taffy.layout(node6).get()
        #expect(abs(layout_node6.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node6.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node6.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node6.location.y - (160.0)) < 0.1)
        let layout_node7 = try! taffy.layout(node7).get()
        #expect(abs(layout_node7.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node7.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node7.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node7.location.y - (160.0)) < 0.1)
        let layout_node8 = try! taffy.layout(node8).get()
        #expect(abs(layout_node8.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node8.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node8.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node8.location.y - (160.0)) < 0.1)
    }

    @Test("grid_align_content_end__content_box")
    func test_grid_align_content_end__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node3 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node4 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node5 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node6 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node7 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node8 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, size: Size(width: .fromLength(200.0), height: .fromLength(200.0)), alignContent: .end, gridTemplateRows: [length(40.0), length(40.0), length(40.0)], gridTemplateColumns: [length(40.0), length(40.0), length(40.0)]),
            [node0, node1, node2, node3, node4, node5, node6, node7, node8],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (80.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (80.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (80.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (120.0)) < 0.1)
        let layout_node4 = try! taffy.layout(node4).get()
        #expect(abs(layout_node4.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node4.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node4.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node4.location.y - (120.0)) < 0.1)
        let layout_node5 = try! taffy.layout(node5).get()
        #expect(abs(layout_node5.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node5.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node5.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node5.location.y - (120.0)) < 0.1)
        let layout_node6 = try! taffy.layout(node6).get()
        #expect(abs(layout_node6.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node6.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node6.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node6.location.y - (160.0)) < 0.1)
        let layout_node7 = try! taffy.layout(node7).get()
        #expect(abs(layout_node7.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node7.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node7.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node7.location.y - (160.0)) < 0.1)
        let layout_node8 = try! taffy.layout(node8).get()
        #expect(abs(layout_node8.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node8.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node8.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node8.location.y - (160.0)) < 0.1)
    }

    @Test("grid_justify_content_center__border_box")
    func test_grid_justify_content_center__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style()).get();
    let node1 = try! taffy.newLeaf(Style()).get();
    let node2 = try! taffy.newLeaf(Style()).get();
    let node3 = try! taffy.newLeaf(Style()).get();
    let node4 = try! taffy.newLeaf(Style()).get();
    let node5 = try! taffy.newLeaf(Style()).get();
    let node6 = try! taffy.newLeaf(Style()).get();
    let node7 = try! taffy.newLeaf(Style()).get();
    let node8 = try! taffy.newLeaf(Style()).get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, size: Size(width: .fromLength(200.0), height: .fromLength(200.0)), justifyContent: .center, gridTemplateRows: [length(40.0), length(40.0), length(40.0)], gridTemplateColumns: [length(40.0), length(40.0), length(40.0)]),
            [node0, node1, node2, node3, node4, node5, node6, node7, node8],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (120.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (40.0)) < 0.1)
        let layout_node4 = try! taffy.layout(node4).get()
        #expect(abs(layout_node4.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node4.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node4.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node4.location.y - (40.0)) < 0.1)
        let layout_node5 = try! taffy.layout(node5).get()
        #expect(abs(layout_node5.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node5.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node5.location.x - (120.0)) < 0.1)
        #expect(abs(layout_node5.location.y - (40.0)) < 0.1)
        let layout_node6 = try! taffy.layout(node6).get()
        #expect(abs(layout_node6.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node6.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node6.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node6.location.y - (80.0)) < 0.1)
        let layout_node7 = try! taffy.layout(node7).get()
        #expect(abs(layout_node7.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node7.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node7.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node7.location.y - (80.0)) < 0.1)
        let layout_node8 = try! taffy.layout(node8).get()
        #expect(abs(layout_node8.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node8.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node8.location.x - (120.0)) < 0.1)
        #expect(abs(layout_node8.location.y - (80.0)) < 0.1)
    }

    @Test("grid_justify_content_center__content_box")
    func test_grid_justify_content_center__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node3 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node4 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node5 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node6 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node7 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node8 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, size: Size(width: .fromLength(200.0), height: .fromLength(200.0)), justifyContent: .center, gridTemplateRows: [length(40.0), length(40.0), length(40.0)], gridTemplateColumns: [length(40.0), length(40.0), length(40.0)]),
            [node0, node1, node2, node3, node4, node5, node6, node7, node8],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (120.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (40.0)) < 0.1)
        let layout_node4 = try! taffy.layout(node4).get()
        #expect(abs(layout_node4.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node4.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node4.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node4.location.y - (40.0)) < 0.1)
        let layout_node5 = try! taffy.layout(node5).get()
        #expect(abs(layout_node5.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node5.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node5.location.x - (120.0)) < 0.1)
        #expect(abs(layout_node5.location.y - (40.0)) < 0.1)
        let layout_node6 = try! taffy.layout(node6).get()
        #expect(abs(layout_node6.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node6.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node6.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node6.location.y - (80.0)) < 0.1)
        let layout_node7 = try! taffy.layout(node7).get()
        #expect(abs(layout_node7.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node7.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node7.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node7.location.y - (80.0)) < 0.1)
        let layout_node8 = try! taffy.layout(node8).get()
        #expect(abs(layout_node8.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node8.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node8.location.x - (120.0)) < 0.1)
        #expect(abs(layout_node8.location.y - (80.0)) < 0.1)
    }

    @Test("grid_justify_content_end__border_box")
    func test_grid_justify_content_end__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style()).get();
    let node1 = try! taffy.newLeaf(Style()).get();
    let node2 = try! taffy.newLeaf(Style()).get();
    let node3 = try! taffy.newLeaf(Style()).get();
    let node4 = try! taffy.newLeaf(Style()).get();
    let node5 = try! taffy.newLeaf(Style()).get();
    let node6 = try! taffy.newLeaf(Style()).get();
    let node7 = try! taffy.newLeaf(Style()).get();
    let node8 = try! taffy.newLeaf(Style()).get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, size: Size(width: .fromLength(200.0), height: .fromLength(200.0)), justifyContent: .end, gridTemplateRows: [length(40.0), length(40.0), length(40.0)], gridTemplateColumns: [length(40.0), length(40.0), length(40.0)]),
            [node0, node1, node2, node3, node4, node5, node6, node7, node8],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (120.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (160.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (40.0)) < 0.1)
        let layout_node4 = try! taffy.layout(node4).get()
        #expect(abs(layout_node4.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node4.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node4.location.x - (120.0)) < 0.1)
        #expect(abs(layout_node4.location.y - (40.0)) < 0.1)
        let layout_node5 = try! taffy.layout(node5).get()
        #expect(abs(layout_node5.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node5.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node5.location.x - (160.0)) < 0.1)
        #expect(abs(layout_node5.location.y - (40.0)) < 0.1)
        let layout_node6 = try! taffy.layout(node6).get()
        #expect(abs(layout_node6.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node6.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node6.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node6.location.y - (80.0)) < 0.1)
        let layout_node7 = try! taffy.layout(node7).get()
        #expect(abs(layout_node7.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node7.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node7.location.x - (120.0)) < 0.1)
        #expect(abs(layout_node7.location.y - (80.0)) < 0.1)
        let layout_node8 = try! taffy.layout(node8).get()
        #expect(abs(layout_node8.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node8.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node8.location.x - (160.0)) < 0.1)
        #expect(abs(layout_node8.location.y - (80.0)) < 0.1)
    }

    @Test("grid_justify_content_end__content_box")
    func test_grid_justify_content_end__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node3 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node4 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node5 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node6 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node7 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node8 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, size: Size(width: .fromLength(200.0), height: .fromLength(200.0)), justifyContent: .end, gridTemplateRows: [length(40.0), length(40.0), length(40.0)], gridTemplateColumns: [length(40.0), length(40.0), length(40.0)]),
            [node0, node1, node2, node3, node4, node5, node6, node7, node8],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (120.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (160.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (40.0)) < 0.1)
        let layout_node4 = try! taffy.layout(node4).get()
        #expect(abs(layout_node4.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node4.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node4.location.x - (120.0)) < 0.1)
        #expect(abs(layout_node4.location.y - (40.0)) < 0.1)
        let layout_node5 = try! taffy.layout(node5).get()
        #expect(abs(layout_node5.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node5.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node5.location.x - (160.0)) < 0.1)
        #expect(abs(layout_node5.location.y - (40.0)) < 0.1)
        let layout_node6 = try! taffy.layout(node6).get()
        #expect(abs(layout_node6.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node6.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node6.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node6.location.y - (80.0)) < 0.1)
        let layout_node7 = try! taffy.layout(node7).get()
        #expect(abs(layout_node7.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node7.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node7.location.x - (120.0)) < 0.1)
        #expect(abs(layout_node7.location.y - (80.0)) < 0.1)
        let layout_node8 = try! taffy.layout(node8).get()
        #expect(abs(layout_node8.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node8.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node8.location.x - (160.0)) < 0.1)
        #expect(abs(layout_node8.location.y - (80.0)) < 0.1)
    }

    @Test("grid_align_items_baseline__border_box")
    func test_grid_align_items_baseline__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(display: Display.grid, size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(display: Display.grid, size: Size(width: .fromLength(50.0), height: .fromLength(20.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), alignItems: .baseline),
            [node0, node1],
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
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (65.0)) < 0.1)
    }

    @Test("grid_align_items_baseline__content_box")
    func test_grid_align_items_baseline__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(display: Display.grid, boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(display: Display.grid, boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(20.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), alignItems: .baseline),
            [node0, node1],
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
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (65.0)) < 0.1)
    }

    @Test("grid_justify_items_sized_center__border_box")
    func test_grid_justify_items_sized_center__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(20.0), height: .fromLength(20.0)), gridRow: Line(start: line(1), end: .auto), gridColumn: Line(start: line(1), end: .auto)))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(60.0), height: .fromLength(60.0)), gridRow: Line(start: line(3), end: .auto), gridColumn: Line(start: line(3), end: .auto)))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, size: Size(width: .fromLength(120.0), height: .fromLength(120.0)), justifyItems: .center, gridTemplateRows: [length(40.0), length(40.0), length(40.0)], gridTemplateColumns: [length(40.0), length(40.0), length(40.0)]),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (120.0)) < 0.1)
        #expect(abs(layout_node.size.height - (120.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (70.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (80.0)) < 0.1)
    }

    @Test("grid_justify_items_sized_center__content_box")
    func test_grid_justify_items_sized_center__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(20.0), height: .fromLength(20.0)), gridRow: Line(start: line(1), end: .auto), gridColumn: Line(start: line(1), end: .auto)))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(60.0), height: .fromLength(60.0)), gridRow: Line(start: line(3), end: .auto), gridColumn: Line(start: line(3), end: .auto)))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, size: Size(width: .fromLength(120.0), height: .fromLength(120.0)), justifyItems: .center, gridTemplateRows: [length(40.0), length(40.0), length(40.0)], gridTemplateColumns: [length(40.0), length(40.0), length(40.0)]),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (120.0)) < 0.1)
        #expect(abs(layout_node.size.height - (120.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (70.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (80.0)) < 0.1)
    }

    @Test("grid_absolute_align_self_sized_all__border_box")
    func test_grid_absolute_align_self_sized_all__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(position: .absolute, size: Size(width: .fromLength(20.0), height: .fromLength(20.0)), alignSelf: .start))
        .get();
    let node1 = try! taffy.newLeaf(Style(position: .absolute, size: Size(width: .fromLength(60.0), height: .fromLength(60.0)), alignSelf: .start))
        .get();
    let node2 = try! taffy.newLeaf(Style(position: .absolute, size: Size(width: .fromLength(20.0), height: .fromLength(20.0)), alignSelf: .end))
        .get();
    let node3 = try! taffy.newLeaf(Style(position: .absolute, size: Size(width: .fromLength(60.0), height: .fromLength(60.0)), alignSelf: .end))
        .get();
    let node4 = try! taffy.newLeaf(Style(position: .absolute, size: Size(width: .fromLength(20.0), height: .fromLength(20.0)), alignSelf: .center))
        .get();
    let node5 = try! taffy.newLeaf(Style(position: .absolute, size: Size(width: .fromLength(60.0), height: .fromLength(60.0)), alignSelf: .center))
        .get();
    let node6 = try! taffy.newLeaf(Style(position: .absolute, size: Size(width: .fromLength(20.0), height: .fromLength(20.0)), alignSelf: .stretch))
        .get();
    let node7 = try! taffy.newLeaf(Style(position: .absolute, size: Size(width: .fromLength(60.0), height: .fromLength(60.0)), alignSelf: .stretch))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, size: Size(width: .fromLength(120.0), height: .fromLength(120.0)), gridTemplateRows: [length(40.0), length(40.0), length(40.0)], gridTemplateColumns: [length(40.0), length(40.0), length(40.0)]),
            [node0, node1, node2, node3, node4, node5, node6, node7],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (120.0)) < 0.1)
        #expect(abs(layout_node.size.height - (120.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (100.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (60.0)) < 0.1)
        let layout_node4 = try! taffy.layout(node4).get()
        #expect(abs(layout_node4.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node4.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node4.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node4.location.y - (50.0)) < 0.1)
        let layout_node5 = try! taffy.layout(node5).get()
        #expect(abs(layout_node5.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node5.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node5.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node5.location.y - (30.0)) < 0.1)
        let layout_node6 = try! taffy.layout(node6).get()
        #expect(abs(layout_node6.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node6.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node6.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node6.location.y - (0.0)) < 0.1)
        let layout_node7 = try! taffy.layout(node7).get()
        #expect(abs(layout_node7.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node7.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node7.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node7.location.y - (0.0)) < 0.1)
    }

    @Test("grid_absolute_align_self_sized_all__content_box")
    func test_grid_absolute_align_self_sized_all__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, position: .absolute, size: Size(width: .fromLength(20.0), height: .fromLength(20.0)), alignSelf: .start))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, position: .absolute, size: Size(width: .fromLength(60.0), height: .fromLength(60.0)), alignSelf: .start))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox, position: .absolute, size: Size(width: .fromLength(20.0), height: .fromLength(20.0)), alignSelf: .end))
        .get();
    let node3 = try! taffy.newLeaf(Style(boxSizing: .contentBox, position: .absolute, size: Size(width: .fromLength(60.0), height: .fromLength(60.0)), alignSelf: .end))
        .get();
    let node4 = try! taffy.newLeaf(Style(boxSizing: .contentBox, position: .absolute, size: Size(width: .fromLength(20.0), height: .fromLength(20.0)), alignSelf: .center))
        .get();
    let node5 = try! taffy.newLeaf(Style(boxSizing: .contentBox, position: .absolute, size: Size(width: .fromLength(60.0), height: .fromLength(60.0)), alignSelf: .center))
        .get();
    let node6 = try! taffy.newLeaf(Style(boxSizing: .contentBox, position: .absolute, size: Size(width: .fromLength(20.0), height: .fromLength(20.0)), alignSelf: .stretch))
        .get();
    let node7 = try! taffy.newLeaf(Style(boxSizing: .contentBox, position: .absolute, size: Size(width: .fromLength(60.0), height: .fromLength(60.0)), alignSelf: .stretch))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, size: Size(width: .fromLength(120.0), height: .fromLength(120.0)), gridTemplateRows: [length(40.0), length(40.0), length(40.0)], gridTemplateColumns: [length(40.0), length(40.0), length(40.0)]),
            [node0, node1, node2, node3, node4, node5, node6, node7],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (120.0)) < 0.1)
        #expect(abs(layout_node.size.height - (120.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (100.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (60.0)) < 0.1)
        let layout_node4 = try! taffy.layout(node4).get()
        #expect(abs(layout_node4.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node4.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node4.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node4.location.y - (50.0)) < 0.1)
        let layout_node5 = try! taffy.layout(node5).get()
        #expect(abs(layout_node5.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node5.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node5.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node5.location.y - (30.0)) < 0.1)
        let layout_node6 = try! taffy.layout(node6).get()
        #expect(abs(layout_node6.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node6.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node6.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node6.location.y - (0.0)) < 0.1)
        let layout_node7 = try! taffy.layout(node7).get()
        #expect(abs(layout_node7.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node7.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node7.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node7.location.y - (0.0)) < 0.1)
    }

    @Test("grid_absolute_column_start__border_box")
    func test_grid_absolute_column_start__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(position: .absolute, inset: Rect(left: length(4.0), right: length(3.0), top: length(1.0), bottom: length(2.0)), gridColumn: Line(start: line(1), end: .auto)))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, padding: Rect(left: length(40.0), right: length(20.0), top: length(10.0), bottom: length(30.0)), gridTemplateRows: [length(40.0), length(40.0), length(40.0)], gridTemplateColumns: [length(40.0), length(40.0), length(40.0)]),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (180.0)) < 0.1)
        #expect(abs(layout_node.size.height - (160.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (133.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (157.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (44.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (1.0)) < 0.1)
    }

    @Test("grid_absolute_column_start__content_box")
    func test_grid_absolute_column_start__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, position: .absolute, inset: Rect(left: length(4.0), right: length(3.0), top: length(1.0), bottom: length(2.0)), gridColumn: Line(start: line(1), end: .auto)))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, padding: Rect(left: length(40.0), right: length(20.0), top: length(10.0), bottom: length(30.0)), gridTemplateRows: [length(40.0), length(40.0), length(40.0)], gridTemplateColumns: [length(40.0), length(40.0), length(40.0)]),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (180.0)) < 0.1)
        #expect(abs(layout_node.size.height - (160.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (133.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (157.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (44.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (1.0)) < 0.1)
    }

    @Test("grid_absolute_column_end__border_box")
    func test_grid_absolute_column_end__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(position: .absolute, inset: Rect(left: length(4.0), right: length(3.0), top: length(1.0), bottom: length(2.0)), gridColumn: Line(start: .auto, end: line(1))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, padding: Rect(left: length(40.0), right: length(20.0), top: length(10.0), bottom: length(30.0)), gridTemplateRows: [length(40.0), length(40.0), length(40.0)], gridTemplateColumns: [length(40.0), length(40.0), length(40.0)]),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (180.0)) < 0.1)
        #expect(abs(layout_node.size.height - (160.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (33.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (157.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (4.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (1.0)) < 0.1)
    }

    @Test("grid_absolute_column_end__content_box")
    func test_grid_absolute_column_end__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, position: .absolute, inset: Rect(left: length(4.0), right: length(3.0), top: length(1.0), bottom: length(2.0)), gridColumn: Line(start: .auto, end: line(1))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, padding: Rect(left: length(40.0), right: length(20.0), top: length(10.0), bottom: length(30.0)), gridTemplateRows: [length(40.0), length(40.0), length(40.0)], gridTemplateColumns: [length(40.0), length(40.0), length(40.0)]),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (180.0)) < 0.1)
        #expect(abs(layout_node.size.height - (160.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (33.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (157.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (4.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (1.0)) < 0.1)
    }

    @Test("grid_aspect_ratio_absolute_fill_width_from_inset__border_box")
    func test_grid_aspect_ratio_absolute_fill_width_from_inset__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(position: .absolute, inset: Rect(left: auto(), right: auto(), top: percent(0.3), bottom: percent(0.5)), aspectRatio: 3.0))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.flex, size: Size(width: .fromLength(400.0), height: .fromLength(300.0))),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (400.0)) < 0.1)
        #expect(abs(layout_node.size.height - (300.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (180.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (90.0)) < 0.1)
    }

    @Test("grid_aspect_ratio_absolute_fill_width_from_inset__content_box")
    func test_grid_aspect_ratio_absolute_fill_width_from_inset__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, position: .absolute, inset: Rect(left: auto(), right: auto(), top: percent(0.3), bottom: percent(0.5)), aspectRatio: 3.0))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.flex, boxSizing: .contentBox, size: Size(width: .fromLength(400.0), height: .fromLength(300.0))),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (400.0)) < 0.1)
        #expect(abs(layout_node.size.height - (300.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (180.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (90.0)) < 0.1)
    }

    @Test("grid_aspect_ratio_absolute_fill_height_from_inset__border_box")
    func test_grid_aspect_ratio_absolute_fill_height_from_inset__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(position: .absolute, inset: Rect(left: percent(0.1), right: percent(0.1), top: percent(0.05), bottom: auto()), aspectRatio: 3.0))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, size: Size(width: .fromLength(400.0), height: .fromLength(300.0))),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (400.0)) < 0.1)
        #expect(abs(layout_node.size.height - (300.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (320.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (107.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (15.0)) < 0.1)
    }

    @Test("grid_aspect_ratio_absolute_fill_height_from_inset__content_box")
    func test_grid_aspect_ratio_absolute_fill_height_from_inset__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, position: .absolute, inset: Rect(left: percent(0.1), right: percent(0.1), top: percent(0.05), bottom: auto()), aspectRatio: 3.0))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, size: Size(width: .fromLength(400.0), height: .fromLength(300.0))),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (400.0)) < 0.1)
        #expect(abs(layout_node.size.height - (300.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (320.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (107.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (15.0)) < 0.1)
    }

    @Test("grid_absolute_container_bottom_left__border_box")
    func test_grid_absolute_container_bottom_left__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(position: .absolute, inset: Rect(left: length(0.0), right: auto(), top: auto(), bottom: length(0.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style()).get();
    let node2 = try! taffy.newLeaf(Style()).get();
    let node3 = try! taffy.newLeaf(Style()).get();
    let node4 = try! taffy.newLeaf(Style()).get();
    let node5 = try! taffy.newLeaf(Style()).get();
    let node6 = try! taffy.newLeaf(Style()).get();
    let node7 = try! taffy.newLeaf(Style()).get();
    let node8 = try! taffy.newLeaf(Style()).get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, padding: Rect(left: length(40.0), right: length(20.0), top: length(10.0), bottom: length(30.0)), gridTemplateRows: [length(40.0), length(40.0), length(40.0)], gridTemplateColumns: [length(40.0), length(40.0), length(40.0)]),
            [node0, node1, node2, node3, node4, node5, node6, node7, node8],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (180.0)) < 0.1)
        #expect(abs(layout_node.size.height - (160.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (160.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (10.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (10.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (120.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (10.0)) < 0.1)
        let layout_node4 = try! taffy.layout(node4).get()
        #expect(abs(layout_node4.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node4.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node4.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node4.location.y - (50.0)) < 0.1)
        let layout_node5 = try! taffy.layout(node5).get()
        #expect(abs(layout_node5.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node5.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node5.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node5.location.y - (50.0)) < 0.1)
        let layout_node6 = try! taffy.layout(node6).get()
        #expect(abs(layout_node6.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node6.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node6.location.x - (120.0)) < 0.1)
        #expect(abs(layout_node6.location.y - (50.0)) < 0.1)
        let layout_node7 = try! taffy.layout(node7).get()
        #expect(abs(layout_node7.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node7.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node7.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node7.location.y - (90.0)) < 0.1)
        let layout_node8 = try! taffy.layout(node8).get()
        #expect(abs(layout_node8.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node8.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node8.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node8.location.y - (90.0)) < 0.1)
    }

    @Test("grid_absolute_container_bottom_left__content_box")
    func test_grid_absolute_container_bottom_left__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, position: .absolute, inset: Rect(left: length(0.0), right: auto(), top: auto(), bottom: length(0.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node3 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node4 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node5 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node6 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node7 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node8 = try! taffy.newLeaf(Style(boxSizing: .contentBox))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.grid, boxSizing: .contentBox, padding: Rect(left: length(40.0), right: length(20.0), top: length(10.0), bottom: length(30.0)), gridTemplateRows: [length(40.0), length(40.0), length(40.0)], gridTemplateColumns: [length(40.0), length(40.0), length(40.0)]),
            [node0, node1, node2, node3, node4, node5, node6, node7, node8],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (180.0)) < 0.1)
        #expect(abs(layout_node.size.height - (160.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (160.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (10.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (10.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (120.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (10.0)) < 0.1)
        let layout_node4 = try! taffy.layout(node4).get()
        #expect(abs(layout_node4.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node4.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node4.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node4.location.y - (50.0)) < 0.1)
        let layout_node5 = try! taffy.layout(node5).get()
        #expect(abs(layout_node5.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node5.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node5.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node5.location.y - (50.0)) < 0.1)
        let layout_node6 = try! taffy.layout(node6).get()
        #expect(abs(layout_node6.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node6.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node6.location.x - (120.0)) < 0.1)
        #expect(abs(layout_node6.location.y - (50.0)) < 0.1)
        let layout_node7 = try! taffy.layout(node7).get()
        #expect(abs(layout_node7.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node7.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node7.location.x - (40.0)) < 0.1)
        #expect(abs(layout_node7.location.y - (90.0)) < 0.1)
        let layout_node8 = try! taffy.layout(node8).get()
        #expect(abs(layout_node8.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node8.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node8.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node8.location.y - (90.0)) < 0.1)
    }
}
