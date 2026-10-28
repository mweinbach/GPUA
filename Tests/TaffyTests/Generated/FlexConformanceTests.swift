// Swift-only: Chrome conformance layout test suite for Taffy (Flexbox) transpiled from upstream tests/generated/
import Testing
@testable import Taffy

@Suite("Taffy Conformance: Flexbox")
struct FlexConformanceTests {
    @Test("flex_grow_to_min__border_box")
    func test_flex_grow_to_min__border_box() {

    
    
    var taffy = newTestTree();
    let node0 =
        try! taffy.newLeaf(Style(flexGrow: 1.0, flexShrink: 1.0)).get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: auto(), height: .fromLength(50.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: auto()), minSize: Size(width: auto(), height: .fromLength(100.0)), maxSize: Size(width: auto(), height: .fromLength(500.0)), flexDirection: .column),
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
        #expect(abs(layout_node0.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (50.0)) < 0.1)
    }

    @Test("flex_grow_to_min__content_box")
    func test_flex_grow_to_min__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, flexGrow: 1.0, flexShrink: 1.0))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(50.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: auto()), minSize: Size(width: auto(), height: .fromLength(100.0)), maxSize: Size(width: auto(), height: .fromLength(500.0)), flexDirection: .column),
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
        #expect(abs(layout_node0.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (50.0)) < 0.1)
    }

    @Test("flex_grow_less_than_factor_one__border_box")
    func test_flex_grow_less_than_factor_one__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(flexBasis: .fromLength(40.0), flexGrow: 0.2, flexShrink: 0.0))
        .get();
    let node1 =
        try! taffy.newLeaf(Style(flexGrow: 0.2, flexShrink: 0.0)).get();
    let node2 =
        try! taffy.newLeaf(Style(flexGrow: 0.4, flexShrink: 0.0)).get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(500.0), height: .fromLength(200.0))),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (500.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (132.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (92.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (132.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (184.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (224.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
    }

    @Test("flex_grow_less_than_factor_one__content_box")
    func test_flex_grow_less_than_factor_one__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, flexBasis: .fromLength(40.0), flexGrow: 0.2, flexShrink: 0.0))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, flexGrow: 0.2, flexShrink: 0.0))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox, flexGrow: 0.4, flexShrink: 0.0))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(500.0), height: .fromLength(200.0))),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (500.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (132.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (92.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (132.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (184.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (224.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
    }

    @Test("flex_grow_flex_basis_percent_min_max__border_box")
    func test_flex_grow_flex_basis_percent_min_max__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: auto(), height: .fromLength(20.0)), minSize: Size(width: .fromLength(60.0), height: auto()), flexBasis: .fromLength(0.0), flexGrow: 1.0, flexShrink: 0.0))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(20.0), height: .fromLength(20.0)), maxSize: Size(width: .fromLength(20.0), height: auto()), flexBasis: .fromPercent(0.5), flexGrow: 1.0, flexShrink: 0.0))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(120.0), height: auto())),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (120.0)) < 0.1)
        #expect(abs(layout_node.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
    }

    @Test("flex_grow_flex_basis_percent_min_max__content_box")
    func test_flex_grow_flex_basis_percent_min_max__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(20.0)), minSize: Size(width: .fromLength(60.0), height: auto()), flexBasis: .fromLength(0.0), flexGrow: 1.0, flexShrink: 0.0))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(20.0), height: .fromLength(20.0)), maxSize: Size(width: .fromLength(20.0), height: auto()), flexBasis: .fromPercent(0.5), flexGrow: 1.0, flexShrink: 0.0))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(120.0), height: auto())),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (120.0)) < 0.1)
        #expect(abs(layout_node.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
    }

    @Test("flex_grow_within_constrained_max_row__border_box")
    func test_flex_grow_within_constrained_max_row__border_box() {

    
    
    var taffy = newTestTree();
    let node00 = try! taffy.newLeaf(Style(flexBasis: .fromLength(100.0), flexShrink: 1.0))
        .get();
    let node01 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: auto())))
        .get();
    let node0 = try! taffy.newWithChildren(
            Style(size: Size(width: auto(), height: .fromLength(100.0)), maxSize: Size(width: .fromLength(100.0), height: auto())),
            [node00, node01],
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(200.0), height: auto()), flexDirection: .column),
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
        #expect(abs(layout_node0.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node00 = try! taffy.layout(node00).get()
        #expect(abs(layout_node00.size.width - (67.0)) < 0.1)
        #expect(abs(layout_node00.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node00.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node00.location.y - (0.0)) < 0.1)
        let layout_node01 = try! taffy.layout(node01).get()
        #expect(abs(layout_node01.size.width - (33.0)) < 0.1)
        #expect(abs(layout_node01.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node01.location.x - (67.0)) < 0.1)
        #expect(abs(layout_node01.location.y - (0.0)) < 0.1)
    }

    @Test("flex_grow_within_constrained_max_row__content_box")
    func test_flex_grow_within_constrained_max_row__content_box() {

    
    
    var taffy = newTestTree();
    let node00 = try! taffy.newLeaf(Style(boxSizing: .contentBox, flexBasis: .fromLength(100.0), flexShrink: 1.0))
        .get();
    let node01 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: auto())))
        .get();
    let node0 = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(100.0)), maxSize: Size(width: .fromLength(100.0), height: auto())),
            [node00, node01],
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(200.0), height: auto()), flexDirection: .column),
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
        #expect(abs(layout_node0.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node00 = try! taffy.layout(node00).get()
        #expect(abs(layout_node00.size.width - (67.0)) < 0.1)
        #expect(abs(layout_node00.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node00.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node00.location.y - (0.0)) < 0.1)
        let layout_node01 = try! taffy.layout(node01).get()
        #expect(abs(layout_node01.size.width - (33.0)) < 0.1)
        #expect(abs(layout_node01.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node01.location.x - (67.0)) < 0.1)
        #expect(abs(layout_node01.location.y - (0.0)) < 0.1)
    }

    @Test("flex_grow_within_constrained_max_column__border_box")
    func test_flex_grow_within_constrained_max_column__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(flexBasis: .fromLength(100.0), flexShrink: 1.0))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: auto(), height: .fromLength(50.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: auto()), maxSize: Size(width: auto(), height: .fromLength(100.0)), flexDirection: .column),
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
        #expect(abs(layout_node0.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (67.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (33.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (67.0)) < 0.1)
    }

    @Test("flex_grow_within_constrained_max_column__content_box")
    func test_flex_grow_within_constrained_max_column__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, flexBasis: .fromLength(100.0), flexShrink: 1.0))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(50.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: auto()), maxSize: Size(width: auto(), height: .fromLength(100.0)), flexDirection: .column),
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
        #expect(abs(layout_node0.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (67.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (33.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (67.0)) < 0.1)
    }

    @Test("flex_grow_shrink_at_most__border_box")
    func test_flex_grow_shrink_at_most__border_box() {

    
    
    var taffy = newTestTree();
    let node00 =
        try! taffy.newLeaf(Style(flexGrow: 1.0, flexShrink: 1.0)).get();
    let node0 = try! taffy.newWithChildren(Style(), [node00]).get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: .fromLength(100.0))),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node00 = try! taffy.layout(node00).get()
        #expect(abs(layout_node00.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node00.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node00.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node00.location.y - (0.0)) < 0.1)
    }

    @Test("flex_grow_shrink_at_most__content_box")
    func test_flex_grow_shrink_at_most__content_box() {

    
    
    var taffy = newTestTree();
    let node00 = try! taffy.newLeaf(Style(boxSizing: .contentBox, flexGrow: 1.0, flexShrink: 1.0))
        .get();
    let node0 = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox),
            [node00],
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: .fromLength(100.0))),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node00 = try! taffy.layout(node00).get()
        #expect(abs(layout_node00.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node00.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node00.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node00.location.y - (0.0)) < 0.1)
    }

    @Test("flex_grow_child__border_box")
    func test_flex_grow_child__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: auto(), height: .fromLength(100.0)), flexBasis: .fromLength(0.0), flexGrow: 1.0))
        .get();
    let node = try! taffy.newWithChildren(Style(), [node0]).get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
    }

    @Test("flex_grow_child__content_box")
    func test_flex_grow_child__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(100.0)), flexBasis: .fromLength(0.0), flexGrow: 1.0))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
    }

    @Test("flex_grow_0_min_size__border_box")
    func test_flex_grow_0_min_size__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeafWithContext(
            Style(flexBasis: .fromPercent(0.0), flexGrow: 0.0, flexShrink: 0.0),
            TestNodeContext.ahemText("one", .horizontal),
        )
        .get();
    let node1 = try! taffy.newLeafWithContext(
            Style(flexBasis: .fromPercent(0.0), flexGrow: 0.0, flexShrink: 0.0),
            TestNodeContext.ahemText("two", .horizontal),
        )
        .get();
    let node2 = try! taffy.newLeafWithContext(
            Style(flexBasis: .fromPercent(0.0), flexGrow: 0.0, flexShrink: 0.0),
            TestNodeContext.ahemText("three", .horizontal),
        )
        .get();
    let node3 = try! taffy.newLeafWithContext(
            Style(flexBasis: .fromPercent(0.0), flexGrow: 0.0, flexShrink: 0.0),
            TestNodeContext.ahemText("four", .horizontal),
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.flex, size: Size(width: .fromLength(400.0), height: .fromLength(100.0)), border: Rect(left: length(1.0), right: length(1.0), top: length(1.0), bottom: length(1.0))),
            [node0, node1, node2, node3],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (400.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (30.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (98.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (1.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (1.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (30.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (98.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (31.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (1.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (98.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (61.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (1.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (98.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (111.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (1.0)) < 0.1)
    }

    @Test("flex_grow_0_min_size__content_box")
    func test_flex_grow_0_min_size__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeafWithContext(
            Style(boxSizing: .contentBox, flexBasis: .fromPercent(0.0), flexGrow: 0.0, flexShrink: 0.0),
            TestNodeContext.ahemText("one", .horizontal),
        )
        .get();
    let node1 = try! taffy.newLeafWithContext(
            Style(boxSizing: .contentBox, flexBasis: .fromPercent(0.0), flexGrow: 0.0, flexShrink: 0.0),
            TestNodeContext.ahemText("two", .horizontal),
        )
        .get();
    let node2 = try! taffy.newLeafWithContext(
            Style(boxSizing: .contentBox, flexBasis: .fromPercent(0.0), flexGrow: 0.0, flexShrink: 0.0),
            TestNodeContext.ahemText("three", .horizontal),
        )
        .get();
    let node3 = try! taffy.newLeafWithContext(
            Style(boxSizing: .contentBox, flexBasis: .fromPercent(0.0), flexGrow: 0.0, flexShrink: 0.0),
            TestNodeContext.ahemText("four", .horizontal),
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.flex, boxSizing: .contentBox, size: Size(width: .fromLength(400.0), height: .fromLength(100.0)), border: Rect(left: length(1.0), right: length(1.0), top: length(1.0), bottom: length(1.0))),
            [node0, node1, node2, node3],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (402.0)) < 0.1)
        #expect(abs(layout_node.size.height - (102.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (30.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (1.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (1.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (30.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (31.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (1.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (61.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (1.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (111.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (1.0)) < 0.1)
    }

    @Test("flex_shrink_to_zero__border_box")
    func test_flex_shrink_to_zero__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), flexShrink: 0.0))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), flexShrink: 1.0))
        .get();
    let node2 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), flexShrink: 0.0))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(75.0), height: auto())),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (75.0)) < 0.1)
        #expect(abs(layout_node.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
    }

    @Test("flex_shrink_to_zero__content_box")
    func test_flex_shrink_to_zero__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), flexShrink: 0.0))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), flexShrink: 1.0))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), flexShrink: 0.0))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(75.0), height: auto())),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (75.0)) < 0.1)
        #expect(abs(layout_node.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
    }

    @Test("flex_shrink_by_outer_margin_with_max_size__border_box")
    func test_flex_shrink_by_outer_margin_with_max_size__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(20.0), height: .fromLength(20.0)), margin: Rect(left: zero(), right: zero(), top: length(100.0), bottom: zero())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: auto(), height: .fromLength(100.0)), maxSize: Size(width: auto(), height: .fromLength(80.0)), flexDirection: .column),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node.size.height - (80.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (100.0)) < 0.1)
    }

    @Test("flex_shrink_by_outer_margin_with_max_size__content_box")
    func test_flex_shrink_by_outer_margin_with_max_size__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(20.0), height: .fromLength(20.0)), margin: Rect(left: zero(), right: zero(), top: length(100.0), bottom: zero())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(100.0)), maxSize: Size(width: auto(), height: .fromLength(80.0)), flexDirection: .column),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node.size.height - (80.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (100.0)) < 0.1)
    }

    @Test("flex_shrink_flex_grow_row__border_box")
    func test_flex_shrink_flex_grow_row__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(500.0), height: .fromLength(100.0)), flexGrow: 0.0, flexShrink: 1.0))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(500.0), height: .fromLength(100.0)), flexGrow: 0.0, flexShrink: 1.0))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(500.0), height: .fromLength(500.0))),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (500.0)) < 0.1)
        #expect(abs(layout_node.size.height - (500.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (250.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (250.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (250.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
    }

    @Test("flex_shrink_flex_grow_row__content_box")
    func test_flex_shrink_flex_grow_row__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(500.0), height: .fromLength(100.0)), flexGrow: 0.0, flexShrink: 1.0))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(500.0), height: .fromLength(100.0)), flexGrow: 0.0, flexShrink: 1.0))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(500.0), height: .fromLength(500.0))),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (500.0)) < 0.1)
        #expect(abs(layout_node.size.height - (500.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (250.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (250.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (250.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
    }

    @Test("flex_shrink_flex_grow_child_flex_shrink_other_child__border_box")
    func test_flex_shrink_flex_grow_child_flex_shrink_other_child__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(500.0), height: .fromLength(100.0)), flexGrow: 0.0, flexShrink: 1.0))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(500.0), height: .fromLength(100.0)), flexGrow: 1.0, flexShrink: 1.0))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(500.0), height: .fromLength(500.0))),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (500.0)) < 0.1)
        #expect(abs(layout_node.size.height - (500.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (250.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (250.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (250.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
    }

    @Test("flex_shrink_flex_grow_child_flex_shrink_other_child__content_box")
    func test_flex_shrink_flex_grow_child_flex_shrink_other_child__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(500.0), height: .fromLength(100.0)), flexGrow: 0.0, flexShrink: 1.0))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(500.0), height: .fromLength(100.0)), flexGrow: 1.0, flexShrink: 1.0))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(500.0), height: .fromLength(500.0))),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (500.0)) < 0.1)
        #expect(abs(layout_node.size.height - (500.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (250.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (250.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (250.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
    }

    @Test("flex_basis_flex_shrink_row__border_box")
    func test_flex_basis_flex_shrink_row__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(flexBasis: .fromLength(100.0)))
        .get();
    let node1 = try! taffy.newLeaf(Style(flexBasis: .fromLength(50.0)))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: .fromLength(100.0))),
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
        #expect(abs(layout_node0.size.width - (67.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (33.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (67.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
    }

    @Test("flex_basis_flex_shrink_row__content_box")
    func test_flex_basis_flex_shrink_row__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, flexBasis: .fromLength(100.0)))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, flexBasis: .fromLength(50.0)))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: .fromLength(100.0))),
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
        #expect(abs(layout_node0.size.width - (67.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (33.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (67.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
    }

    @Test("flex_basis_flex_shrink_column__border_box")
    func test_flex_basis_flex_shrink_column__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(flexBasis: .fromLength(100.0)))
        .get();
    let node1 = try! taffy.newLeaf(Style(flexBasis: .fromLength(50.0)))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), flexDirection: .column),
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
        #expect(abs(layout_node0.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (67.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (33.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (67.0)) < 0.1)
    }

    @Test("flex_basis_flex_shrink_column__content_box")
    func test_flex_basis_flex_shrink_column__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, flexBasis: .fromLength(100.0)))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, flexBasis: .fromLength(50.0)))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), flexDirection: .column),
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
        #expect(abs(layout_node0.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (67.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (33.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (67.0)) < 0.1)
    }

    @Test("flex_basis_unconstraint_row__border_box")
    func test_flex_basis_unconstraint_row__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: auto(), height: .fromLength(100.0)), flexBasis: .fromLength(50.0)))
        .get();
    let node = try! taffy.newWithChildren(Style(), [node0]).get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
    }

    @Test("flex_basis_unconstraint_row__content_box")
    func test_flex_basis_unconstraint_row__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(100.0)), flexBasis: .fromLength(50.0)))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
    }

    @Test("flex_basis_and_main_dimen_set_when_flexing__border_box")
    func test_flex_basis_and_main_dimen_set_when_flexing__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), flexBasis: .fromLength(10.0), flexGrow: 1.0))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(0.0), height: .fromLength(50.0)), flexBasis: .fromLength(10.0), flexGrow: 1.0))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: auto())),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (50.0)) < 0.1)
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
        #expect(abs(layout_node1.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
    }

    @Test("flex_basis_and_main_dimen_set_when_flexing__content_box")
    func test_flex_basis_and_main_dimen_set_when_flexing__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), flexBasis: .fromLength(10.0), flexGrow: 1.0))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(0.0), height: .fromLength(50.0)), flexBasis: .fromLength(10.0), flexGrow: 1.0))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: auto())),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (50.0)) < 0.1)
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
        #expect(abs(layout_node1.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
    }

    @Test("flex_basis_smaller_then_content_with_flex_grow_large_size__border_box")
    func test_flex_basis_smaller_then_content_with_flex_grow_large_size__border_box() {

    
    
    var taffy = newTestTree();
    let node00 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(70.0), height: .fromLength(100.0))))
        .get();
    let node0 = try! taffy.newWithChildren(
            Style(flexDirection: .column, flexBasis: .fromLength(0.0), flexGrow: 1.0),
            [node00],
        )
        .get();
    let node10 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(20.0), height: .fromLength(100.0))))
        .get();
    let node1 = try! taffy.newWithChildren(
            Style(flexDirection: .column, flexBasis: .fromLength(0.0), flexGrow: 1.0),
            [node10],
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: auto())),
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
        #expect(abs(layout_node0.size.width - (70.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node00 = try! taffy.layout(node00).get()
        #expect(abs(layout_node00.size.width - (70.0)) < 0.1)
        #expect(abs(layout_node00.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node00.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node00.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (30.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (70.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node10 = try! taffy.layout(node10).get()
        #expect(abs(layout_node10.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node10.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node10.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node10.location.y - (0.0)) < 0.1)
    }

    @Test("flex_basis_smaller_then_content_with_flex_grow_large_size__content_box")
    func test_flex_basis_smaller_then_content_with_flex_grow_large_size__content_box() {

    
    
    var taffy = newTestTree();
    let node00 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(70.0), height: .fromLength(100.0))))
        .get();
    let node0 = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, flexDirection: .column, flexBasis: .fromLength(0.0), flexGrow: 1.0),
            [node00],
        )
        .get();
    let node10 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(20.0), height: .fromLength(100.0))))
        .get();
    let node1 = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, flexDirection: .column, flexBasis: .fromLength(0.0), flexGrow: 1.0),
            [node10],
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: auto())),
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
        #expect(abs(layout_node0.size.width - (70.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node00 = try! taffy.layout(node00).get()
        #expect(abs(layout_node00.size.width - (70.0)) < 0.1)
        #expect(abs(layout_node00.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node00.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node00.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (30.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (70.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node10 = try! taffy.layout(node10).get()
        #expect(abs(layout_node10.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node10.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node10.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node10.location.y - (0.0)) < 0.1)
    }

    @Test("flex_basis_smaller_then_content_with_flex_grow_small_size__border_box")
    func test_flex_basis_smaller_then_content_with_flex_grow_small_size__border_box() {

    
    
    var taffy = newTestTree();
    let node00 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(70.0), height: .fromLength(100.0))))
        .get();
    let node0 = try! taffy.newWithChildren(
            Style(flexDirection: .column, flexBasis: .fromLength(0.0), flexGrow: 1.0),
            [node00],
        )
        .get();
    let node10 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(20.0), height: .fromLength(100.0))))
        .get();
    let node1 = try! taffy.newWithChildren(
            Style(flexDirection: .column, flexBasis: .fromLength(0.0), flexGrow: 1.0),
            [node10],
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(10.0), height: auto())),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (70.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node00 = try! taffy.layout(node00).get()
        #expect(abs(layout_node00.size.width - (70.0)) < 0.1)
        #expect(abs(layout_node00.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node00.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node00.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (70.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node10 = try! taffy.layout(node10).get()
        #expect(abs(layout_node10.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node10.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node10.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node10.location.y - (0.0)) < 0.1)
    }

    @Test("flex_basis_smaller_then_content_with_flex_grow_small_size__content_box")
    func test_flex_basis_smaller_then_content_with_flex_grow_small_size__content_box() {

    
    
    var taffy = newTestTree();
    let node00 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(70.0), height: .fromLength(100.0))))
        .get();
    let node0 = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, flexDirection: .column, flexBasis: .fromLength(0.0), flexGrow: 1.0),
            [node00],
        )
        .get();
    let node10 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(20.0), height: .fromLength(100.0))))
        .get();
    let node1 = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, flexDirection: .column, flexBasis: .fromLength(0.0), flexGrow: 1.0),
            [node10],
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(10.0), height: auto())),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (70.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node00 = try! taffy.layout(node00).get()
        #expect(abs(layout_node00.size.width - (70.0)) < 0.1)
        #expect(abs(layout_node00.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node00.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node00.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (70.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node10 = try! taffy.layout(node10).get()
        #expect(abs(layout_node10.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node10.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node10.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node10.location.y - (0.0)) < 0.1)
    }

    @Test("flex_basis_flex_grow_row__border_box")
    func test_flex_basis_flex_grow_row__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(flexBasis: .fromLength(50.0), flexGrow: 1.0))
        .get();
    let node1 = try! taffy.newLeaf(Style(flexGrow: 1.0)).get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: .fromLength(100.0))),
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
        #expect(abs(layout_node0.size.width - (75.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (25.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (75.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
    }

    @Test("flex_basis_flex_grow_row__content_box")
    func test_flex_basis_flex_grow_row__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, flexBasis: .fromLength(50.0), flexGrow: 1.0))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, flexGrow: 1.0))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: .fromLength(100.0))),
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
        #expect(abs(layout_node0.size.width - (75.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (25.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (75.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
    }

    @Test("flex_basis_flex_grow_column__border_box")
    func test_flex_basis_flex_grow_column__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(flexBasis: .fromLength(50.0), flexGrow: 1.0))
        .get();
    let node1 = try! taffy.newLeaf(Style(flexGrow: 1.0)).get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), flexDirection: .column),
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
        #expect(abs(layout_node0.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (75.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (25.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (75.0)) < 0.1)
    }

    @Test("flex_basis_flex_grow_column__content_box")
    func test_flex_basis_flex_grow_column__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, flexBasis: .fromLength(50.0), flexGrow: 1.0))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, flexGrow: 1.0))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), flexDirection: .column),
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
        #expect(abs(layout_node0.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (75.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (25.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (75.0)) < 0.1)
    }

    @Test("wrap_reverse_row__border_box")
    func test_wrap_reverse_row__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(31.0), height: .fromLength(30.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(32.0), height: .fromLength(30.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(33.0), height: .fromLength(30.0))))
        .get();
    let node3 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(34.0), height: .fromLength(30.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: auto()), flexWrap: .wrapReverse),
            [node0, node1, node2, node3],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (31.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (30.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (30.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (32.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (30.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (31.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (30.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (33.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (30.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (63.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (30.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (34.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (30.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (0.0)) < 0.1)
    }

    @Test("wrap_reverse_row__content_box")
    func test_wrap_reverse_row__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(31.0), height: .fromLength(30.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(32.0), height: .fromLength(30.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(33.0), height: .fromLength(30.0))))
        .get();
    let node3 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(34.0), height: .fromLength(30.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: auto()), flexWrap: .wrapReverse),
            [node0, node1, node2, node3],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (31.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (30.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (30.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (32.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (30.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (31.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (30.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (33.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (30.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (63.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (30.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (34.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (30.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (0.0)) < 0.1)
    }

    @Test("wrap_reverse_column__border_box")
    func test_wrap_reverse_column__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(30.0), height: .fromLength(31.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(30.0), height: .fromLength(32.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(30.0), height: .fromLength(33.0))))
        .get();
    let node3 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(30.0), height: .fromLength(34.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), flexDirection: .column, flexWrap: .wrapReverse),
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
        #expect(abs(layout_node0.size.width - (30.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (31.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (70.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (30.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (32.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (70.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (31.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (30.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (33.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (70.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (63.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (30.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (34.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (20.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (0.0)) < 0.1)
    }

    @Test("wrap_reverse_column__content_box")
    func test_wrap_reverse_column__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(30.0), height: .fromLength(31.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(30.0), height: .fromLength(32.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(30.0), height: .fromLength(33.0))))
        .get();
    let node3 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(30.0), height: .fromLength(34.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), flexDirection: .column, flexWrap: .wrapReverse),
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
        #expect(abs(layout_node0.size.width - (30.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (31.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (70.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (30.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (32.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (70.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (31.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (30.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (33.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (70.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (63.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (30.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (34.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (20.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (0.0)) < 0.1)
    }

    @Test("wrap_row__border_box")
    func test_wrap_row__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(31.0), height: .fromLength(30.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(32.0), height: .fromLength(30.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(33.0), height: .fromLength(30.0))))
        .get();
    let node3 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(34.0), height: .fromLength(30.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: auto()), flexWrap: .wrap),
            [node0, node1, node2, node3],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (31.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (30.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (32.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (30.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (31.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (33.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (30.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (63.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (34.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (30.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (30.0)) < 0.1)
    }

    @Test("wrap_row__content_box")
    func test_wrap_row__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(31.0), height: .fromLength(30.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(32.0), height: .fromLength(30.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(33.0), height: .fromLength(30.0))))
        .get();
    let node3 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(34.0), height: .fromLength(30.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: auto()), flexWrap: .wrap),
            [node0, node1, node2, node3],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (60.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (31.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (30.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (32.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (30.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (31.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (33.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (30.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (63.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (34.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (30.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (30.0)) < 0.1)
    }

    @Test("wrap_column__border_box")
    func test_wrap_column__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(30.0), height: .fromLength(31.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(30.0), height: .fromLength(32.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(30.0), height: .fromLength(33.0))))
        .get();
    let node3 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(30.0), height: .fromLength(34.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), flexDirection: .column, flexWrap: .wrap),
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
        #expect(abs(layout_node0.size.width - (30.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (31.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (30.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (32.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (31.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (30.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (33.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (63.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (30.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (34.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (0.0)) < 0.1)
    }

    @Test("wrap_column__content_box")
    func test_wrap_column__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(30.0), height: .fromLength(31.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(30.0), height: .fromLength(32.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(30.0), height: .fromLength(33.0))))
        .get();
    let node3 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(30.0), height: .fromLength(34.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), flexDirection: .column, flexWrap: .wrap),
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
        #expect(abs(layout_node0.size.width - (30.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (31.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (30.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (32.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (31.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (30.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (33.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (63.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (30.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (34.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (0.0)) < 0.1)
    }

    @Test("flex_wrap_wrap_to_child_height__border_box")
    func test_flex_wrap_wrap_to_child_height__border_box() {

    
    
    var taffy = newTestTree();
    let node000 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(100.0), height: .fromLength(100.0))))
        .get();
    let node00 = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: auto()), flexDirection: .column),
            [node000],
        )
        .get();
    let node0 = try! taffy.newWithChildren(
            Style(alignItems: .flexStart, flexWrap: .wrap),
            [node00],
        )
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(100.0), height: .fromLength(100.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(flexDirection: .column),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node00 = try! taffy.layout(node00).get()
        #expect(abs(layout_node00.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node00.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node00.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node00.location.y - (0.0)) < 0.1)
        let layout_node000 = try! taffy.layout(node000).get()
        #expect(abs(layout_node000.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node000.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node000.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node000.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (100.0)) < 0.1)
    }

    @Test("flex_wrap_wrap_to_child_height__content_box")
    func test_flex_wrap_wrap_to_child_height__content_box() {

    
    
    var taffy = newTestTree();
    let node000 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: .fromLength(100.0))))
        .get();
    let node00 = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: auto()), flexDirection: .column),
            [node000],
        )
        .get();
    let node0 = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, alignItems: .flexStart, flexWrap: .wrap),
            [node00],
        )
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: .fromLength(100.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, flexDirection: .column),
            [node0, node1],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (200.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node00 = try! taffy.layout(node00).get()
        #expect(abs(layout_node00.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node00.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node00.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node00.location.y - (0.0)) < 0.1)
        let layout_node000 = try! taffy.layout(node000).get()
        #expect(abs(layout_node000.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node000.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node000.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node000.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (100.0)) < 0.1)
    }

    @Test("flex_wrap_children_with_min_main_overriding_flex_basis__border_box")
    func test_flex_wrap_children_with_min_main_overriding_flex_basis__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: auto(), height: .fromLength(50.0)), minSize: Size(width: .fromLength(55.0), height: auto()), flexBasis: .fromLength(50.0)))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: auto(), height: .fromLength(50.0)), minSize: Size(width: .fromLength(55.0), height: auto()), flexBasis: .fromLength(50.0)))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: auto()), flexWrap: .wrap),
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
        #expect(abs(layout_node0.size.width - (55.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (55.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (50.0)) < 0.1)
    }

    @Test("flex_wrap_children_with_min_main_overriding_flex_basis__content_box")
    func test_flex_wrap_children_with_min_main_overriding_flex_basis__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(50.0)), minSize: Size(width: .fromLength(55.0), height: auto()), flexBasis: .fromLength(50.0)))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(50.0)), minSize: Size(width: .fromLength(55.0), height: auto()), flexBasis: .fromLength(50.0)))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: auto()), flexWrap: .wrap),
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
        #expect(abs(layout_node0.size.width - (55.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (55.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (50.0)) < 0.1)
    }

    @Test("align_items_center__border_box")
    func test_align_items_center__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(10.0), height: .fromLength(10.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), alignItems: .center),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (45.0)) < 0.1)
    }

    @Test("align_items_center__content_box")
    func test_align_items_center__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(10.0), height: .fromLength(10.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), alignItems: .center),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (45.0)) < 0.1)
    }

    @Test("align_items_flex_end__border_box")
    func test_align_items_flex_end__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(10.0), height: .fromLength(10.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), alignItems: .flexEnd),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (90.0)) < 0.1)
    }

    @Test("align_items_flex_end__content_box")
    func test_align_items_flex_end__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(10.0), height: .fromLength(10.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), alignItems: .flexEnd),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (90.0)) < 0.1)
    }

    @Test("align_items_stretch__border_box")
    func test_align_items_stretch__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: .fromLength(100.0))),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
    }

    @Test("align_items_stretch__content_box")
    func test_align_items_stretch__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: .fromLength(100.0))),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
    }

    @Test("align_baseline_child__border_box")
    func test_align_baseline_child__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node10 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(10.0))))
        .get();
    let node1 = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(50.0), height: .fromLength(20.0)), flexDirection: .column),
            [node10],
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), alignItems: .baseline),
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
        #expect(abs(layout_node1.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (40.0)) < 0.1)
        let layout_node10 = try! taffy.layout(node10).get()
        #expect(abs(layout_node10.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node10.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node10.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node10.location.y - (0.0)) < 0.1)
    }

    @Test("align_baseline_child__content_box")
    func test_align_baseline_child__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node10 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(10.0))))
        .get();
    let node1 = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(20.0)), flexDirection: .column),
            [node10],
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), alignItems: .baseline),
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
        #expect(abs(layout_node1.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (40.0)) < 0.1)
        let layout_node10 = try! taffy.layout(node10).get()
        #expect(abs(layout_node10.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node10.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node10.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node10.location.y - (0.0)) < 0.1)
    }

    @Test("align_self_center__border_box")
    func test_align_self_center__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(10.0), height: .fromLength(10.0)), alignSelf: .center))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: .fromLength(100.0))),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (45.0)) < 0.1)
    }

    @Test("align_self_center__content_box")
    func test_align_self_center__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(10.0), height: .fromLength(10.0)), alignSelf: .center))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: .fromLength(100.0))),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (45.0)) < 0.1)
    }

    @Test("align_self_flex_end_override_flex_start__border_box")
    func test_align_self_flex_end_override_flex_start__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(10.0), height: .fromLength(10.0)), alignSelf: .flexEnd))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), alignItems: .flexStart),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (90.0)) < 0.1)
    }

    @Test("align_self_flex_end_override_flex_start__content_box")
    func test_align_self_flex_end_override_flex_start__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(10.0), height: .fromLength(10.0)), alignSelf: .flexEnd))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), alignItems: .flexStart),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (90.0)) < 0.1)
    }

    @Test("align_content_center_wrapped__border_box")
    func test_align_content_center_wrapped__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(10.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(10.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(10.0))))
        .get();
    let node3 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(10.0))))
        .get();
    let node4 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(10.0))))
        .get();
    let node5 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(10.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(120.0), height: .fromLength(100.0)), alignContent: .center, flexWrap: .wrap),
            [node0, node1, node2, node3, node4, node5],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (120.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (35.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (35.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (45.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (45.0)) < 0.1)
        let layout_node4 = try! taffy.layout(node4).get()
        #expect(abs(layout_node4.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node4.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node4.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node4.location.y - (55.0)) < 0.1)
        let layout_node5 = try! taffy.layout(node5).get()
        #expect(abs(layout_node5.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node5.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node5.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node5.location.y - (55.0)) < 0.1)
    }

    @Test("align_content_center_wrapped__content_box")
    func test_align_content_center_wrapped__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(10.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(10.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(10.0))))
        .get();
    let node3 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(10.0))))
        .get();
    let node4 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(10.0))))
        .get();
    let node5 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(10.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(120.0), height: .fromLength(100.0)), alignContent: .center, flexWrap: .wrap),
            [node0, node1, node2, node3, node4, node5],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (120.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (35.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (35.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (45.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (45.0)) < 0.1)
        let layout_node4 = try! taffy.layout(node4).get()
        #expect(abs(layout_node4.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node4.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node4.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node4.location.y - (55.0)) < 0.1)
        let layout_node5 = try! taffy.layout(node5).get()
        #expect(abs(layout_node5.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node5.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node5.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node5.location.y - (55.0)) < 0.1)
    }

    @Test("align_content_space_between_wrapped__border_box")
    func test_align_content_space_between_wrapped__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(10.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(10.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(10.0))))
        .get();
    let node3 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(10.0))))
        .get();
    let node4 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(10.0))))
        .get();
    let node5 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(10.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), alignContent: .spaceBetween, flexWrap: .wrap),
            [node0, node1, node2, node3, node4, node5],
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
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (45.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (45.0)) < 0.1)
        let layout_node4 = try! taffy.layout(node4).get()
        #expect(abs(layout_node4.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node4.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node4.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node4.location.y - (90.0)) < 0.1)
        let layout_node5 = try! taffy.layout(node5).get()
        #expect(abs(layout_node5.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node5.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node5.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node5.location.y - (90.0)) < 0.1)
    }

    @Test("align_content_space_between_wrapped__content_box")
    func test_align_content_space_between_wrapped__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(10.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(10.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(10.0))))
        .get();
    let node3 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(10.0))))
        .get();
    let node4 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(10.0))))
        .get();
    let node5 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(10.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), alignContent: .spaceBetween, flexWrap: .wrap),
            [node0, node1, node2, node3, node4, node5],
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
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (45.0)) < 0.1)
        let layout_node3 = try! taffy.layout(node3).get()
        #expect(abs(layout_node3.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node3.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node3.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node3.location.y - (45.0)) < 0.1)
        let layout_node4 = try! taffy.layout(node4).get()
        #expect(abs(layout_node4.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node4.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node4.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node4.location.y - (90.0)) < 0.1)
        let layout_node5 = try! taffy.layout(node5).get()
        #expect(abs(layout_node5.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node5.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node5.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node5.location.y - (90.0)) < 0.1)
    }

    @Test("justify_content_row_center__border_box")
    func test_justify_content_row_center__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node2 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), justifyContent: .center),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (35.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (45.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (55.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
    }

    @Test("justify_content_row_center__content_box")
    func test_justify_content_row_center__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), justifyContent: .center),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (35.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (45.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (55.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
    }

    @Test("justify_content_row_flex_end__border_box")
    func test_justify_content_row_flex_end__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node2 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), justifyContent: .flexEnd),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (70.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (90.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
    }

    @Test("justify_content_row_flex_end__content_box")
    func test_justify_content_row_flex_end__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), justifyContent: .flexEnd),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (70.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (90.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
    }

    @Test("justify_content_row_space_between__border_box")
    func test_justify_content_row_space_between__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node2 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), justifyContent: .spaceBetween),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (45.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (90.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
    }

    @Test("justify_content_row_space_between__content_box")
    func test_justify_content_row_space_between__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), justifyContent: .spaceBetween),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (45.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (90.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
    }

    @Test("justify_content_row_space_around__border_box")
    func test_justify_content_row_space_around__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node2 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), justifyContent: .spaceAround),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (12.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (45.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (78.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
    }

    @Test("justify_content_row_space_around__content_box")
    func test_justify_content_row_space_around__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), justifyContent: .spaceAround),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (12.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (45.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (78.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
    }

    @Test("justify_content_row_space_evenly__border_box")
    func test_justify_content_row_space_evenly__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: auto(), height: .fromLength(10.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: auto(), height: .fromLength(10.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(size: Size(width: auto(), height: .fromLength(10.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), justifyContent: .spaceEvenly),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (25.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (75.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
    }

    @Test("justify_content_row_space_evenly__content_box")
    func test_justify_content_row_space_evenly__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(10.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(10.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(10.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), justifyContent: .spaceEvenly),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (25.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (75.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
    }

    @Test("justify_content_overflow_min_max__border_box")
    func test_justify_content_overflow_min_max__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), flexShrink: 0.0))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), flexShrink: 0.0))
        .get();
    let node2 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), flexShrink: 0.0))
        .get();
    let node = try! taffy.newWithChildren(
            Style(minSize: Size(width: auto(), height: .fromLength(100.0)), maxSize: Size(width: auto(), height: .fromLength(110.0)), justifyContent: .center, flexDirection: .column),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node.size.height - (110.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (-20.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (30.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (80.0)) < 0.1)
    }

    @Test("justify_content_overflow_min_max__content_box")
    func test_justify_content_overflow_min_max__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), flexShrink: 0.0))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), flexShrink: 0.0))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), flexShrink: 0.0))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, minSize: Size(width: auto(), height: .fromLength(100.0)), maxSize: Size(width: auto(), height: .fromLength(110.0)), justifyContent: .center, flexDirection: .column),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node.size.height - (110.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (-20.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (30.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (80.0)) < 0.1)
    }

    @Test("gap_row_gap_determines_parent_height__border_box")
    func test_gap_row_gap_determines_parent_height__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: auto(), height: .fromLength(10.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: auto(), height: .fromLength(20.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(size: Size(width: auto(), height: .fromLength(30.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: auto()), alignItems: .stretch, gap: Size(width: zero(), height: length(10.0)), flexDirection: .column),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (80.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (20.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (30.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (50.0)) < 0.1)
    }

    @Test("gap_row_gap_determines_parent_height__content_box")
    func test_gap_row_gap_determines_parent_height__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(10.0))))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(20.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(30.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: auto()), alignItems: .stretch, gap: Size(width: zero(), height: length(10.0)), flexDirection: .column),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (80.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (20.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (30.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (50.0)) < 0.1)
    }

    @Test("gap_column_gap_determines_parent_width__border_box")
    func test_gap_column_gap_determines_parent_width__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(20.0), height: auto())))
        .get();
    let node2 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(30.0), height: auto())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: auto(), height: .fromLength(100.0)), alignItems: .stretch, gap: Size(width: length(10.0), height: zero())),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (80.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (20.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (30.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
    }

    @Test("gap_column_gap_determines_parent_width__content_box")
    func test_gap_column_gap_determines_parent_width__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(10.0), height: auto())))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(20.0), height: auto())))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(30.0), height: auto())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(100.0)), alignItems: .stretch, gap: Size(width: length(10.0), height: zero())),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (80.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (10.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (20.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (30.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
    }

    @Test("align_content_center_wrapped_negative_space_gap__border_box")
    func test_align_content_center_wrapped_negative_space_gap__border_box() {

    
    
    var taffy = newTestTree();
    let node00 = try! taffy.newLeaf(Style(size: Size(width: .fromPercent(0.8), height: .fromLength(20.0)), flexShrink: 0.0))
        .get();
    let node01 = try! taffy.newLeaf(Style(size: Size(width: .fromPercent(0.8), height: .fromLength(20.0)), flexShrink: 0.0))
        .get();
    let node02 = try! taffy.newLeaf(Style(size: Size(width: .fromPercent(0.8), height: .fromLength(20.0)), flexShrink: 0.0))
        .get();
    let node0 = try! taffy.newWithChildren(
            Style(display: Display.flex, size: Size(width: auto(), height: .fromLength(10.0)), alignContent: .center, justifyContent: .center, gap: Size(width: length(10.0), height: length(10.0)), flexWrap: .wrap),
            [node00, node01, node02],
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.flex, size: Size(width: .fromLength(320.0), height: .fromLength(320.0)), border: Rect(left: length(60.0), right: length(60.0), top: length(60.0), bottom: length(60.0)), flexDirection: .column),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (320.0)) < 0.1)
        #expect(abs(layout_node.size.height - (320.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (60.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (60.0)) < 0.1)
        let layout_node00 = try! taffy.layout(node00).get()
        #expect(abs(layout_node00.size.width - (160.0)) < 0.1)
        #expect(abs(layout_node00.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node00.location.x - (20.0)) < 0.1)
        #expect(abs(layout_node00.location.y - (-35.0)) < 0.1)
        let layout_node01 = try! taffy.layout(node01).get()
        #expect(abs(layout_node01.size.width - (160.0)) < 0.1)
        #expect(abs(layout_node01.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node01.location.x - (20.0)) < 0.1)
        #expect(abs(layout_node01.location.y - (-5.0)) < 0.1)
        let layout_node02 = try! taffy.layout(node02).get()
        #expect(abs(layout_node02.size.width - (160.0)) < 0.1)
        #expect(abs(layout_node02.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node02.location.x - (20.0)) < 0.1)
        #expect(abs(layout_node02.location.y - (25.0)) < 0.1)
    }

    @Test("align_content_center_wrapped_negative_space_gap__content_box")
    func test_align_content_center_wrapped_negative_space_gap__content_box() {

    
    
    var taffy = newTestTree();
    let node00 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromPercent(0.8), height: .fromLength(20.0)), flexShrink: 0.0))
        .get();
    let node01 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromPercent(0.8), height: .fromLength(20.0)), flexShrink: 0.0))
        .get();
    let node02 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromPercent(0.8), height: .fromLength(20.0)), flexShrink: 0.0))
        .get();
    let node0 = try! taffy.newWithChildren(
            Style(display: Display.flex, boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(10.0)), alignContent: .center, justifyContent: .center, gap: Size(width: length(10.0), height: length(10.0)), flexWrap: .wrap),
            [node00, node01, node02],
        )
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.flex, boxSizing: .contentBox, size: Size(width: .fromLength(320.0), height: .fromLength(320.0)), border: Rect(left: length(60.0), right: length(60.0), top: length(60.0), bottom: length(60.0)), flexDirection: .column),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (440.0)) < 0.1)
        #expect(abs(layout_node.size.height - (440.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (320.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (10.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (60.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (60.0)) < 0.1)
        let layout_node00 = try! taffy.layout(node00).get()
        #expect(abs(layout_node00.size.width - (256.0)) < 0.1)
        #expect(abs(layout_node00.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node00.location.x - (32.0)) < 0.1)
        #expect(abs(layout_node00.location.y - (-35.0)) < 0.1)
        let layout_node01 = try! taffy.layout(node01).get()
        #expect(abs(layout_node01.size.width - (256.0)) < 0.1)
        #expect(abs(layout_node01.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node01.location.x - (32.0)) < 0.1)
        #expect(abs(layout_node01.location.y - (-5.0)) < 0.1)
        let layout_node02 = try! taffy.layout(node02).get()
        #expect(abs(layout_node02.size.width - (256.0)) < 0.1)
        #expect(abs(layout_node02.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node02.location.x - (32.0)) < 0.1)
        #expect(abs(layout_node02.location.y - (25.0)) < 0.1)
    }

    @Test("gap_column_gap_percentage_cyclic_partially_shrinkable__border_box")
    func test_gap_column_gap_percentage_cyclic_partially_shrinkable__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(20.0), height: .fromLength(40.0)), flexShrink: 0.0))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(20.0), height: .fromLength(40.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(20.0), height: .fromLength(40.0)), flexShrink: 0.0))
        .get();
    let node = try! taffy.newWithChildren(
            Style(gap: Size(width: percent(0.5), height: zero())),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
    }

    @Test("gap_column_gap_percentage_cyclic_partially_shrinkable__content_box")
    func test_gap_column_gap_percentage_cyclic_partially_shrinkable__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(20.0), height: .fromLength(40.0)), flexShrink: 0.0))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(20.0), height: .fromLength(40.0))))
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(20.0), height: .fromLength(40.0)), flexShrink: 0.0))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, gap: Size(width: percent(0.5), height: zero())),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (0.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
    }

    @Test("margin_auto_left__border_box")
    func test_margin_auto_left__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), margin: Rect(left: .auto(), right: zero(), top: zero(), bottom: zero())))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(200.0), height: .fromLength(200.0)), alignItems: .center),
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
        #expect(abs(layout_node0.location.x - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (75.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (150.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (75.0)) < 0.1)
    }

    @Test("margin_auto_left__content_box")
    func test_margin_auto_left__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), margin: Rect(left: .auto(), right: zero(), top: zero(), bottom: zero())))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(200.0), height: .fromLength(200.0)), alignItems: .center),
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
        #expect(abs(layout_node0.location.x - (100.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (75.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (150.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (75.0)) < 0.1)
    }

    @Test("margin_auto_right__border_box")
    func test_margin_auto_right__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), margin: Rect(left: zero(), right: .auto(), top: zero(), bottom: zero())))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(200.0), height: .fromLength(200.0)), alignItems: .center),
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
        #expect(abs(layout_node0.location.y - (75.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (150.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (75.0)) < 0.1)
    }

    @Test("margin_auto_right__content_box")
    func test_margin_auto_right__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), margin: Rect(left: zero(), right: .auto(), top: zero(), bottom: zero())))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(200.0), height: .fromLength(200.0)), alignItems: .center),
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
        #expect(abs(layout_node0.location.y - (75.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (150.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (75.0)) < 0.1)
    }

    @Test("margin_auto_left_and_right__border_box")
    func test_margin_auto_left_and_right__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), margin: Rect(left: .auto(), right: .auto(), top: zero(), bottom: zero())))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(200.0), height: .fromLength(200.0))),
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
        #expect(abs(layout_node0.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (150.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
    }

    @Test("margin_auto_left_and_right__content_box")
    func test_margin_auto_left_and_right__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), margin: Rect(left: .auto(), right: .auto(), top: zero(), bottom: zero())))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(200.0), height: .fromLength(200.0))),
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
        #expect(abs(layout_node0.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (150.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
    }

    @Test("margin_auto_bottom_and_top_justify_center__border_box")
    func test_margin_auto_bottom_and_top_justify_center__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), margin: Rect(left: zero(), right: zero(), top: .auto(), bottom: .auto())))
        .get();
    let node1 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(200.0), height: .fromLength(200.0)), justifyContent: .center),
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
        #expect(abs(layout_node0.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (75.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
    }

    @Test("margin_auto_bottom_and_top_justify_center__content_box")
    func test_margin_auto_bottom_and_top_justify_center__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0)), margin: Rect(left: zero(), right: zero(), top: .auto(), bottom: .auto())))
        .get();
    let node1 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(50.0), height: .fromLength(50.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(200.0), height: .fromLength(200.0)), justifyContent: .center),
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
        #expect(abs(layout_node0.location.x - (50.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (75.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (50.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (50.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (100.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (0.0)) < 0.1)
    }

    @Test("absolute_child_with_main_margin__border_box")
    func test_absolute_child_with_main_margin__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(position: .absolute, size: Size(width: .fromLength(9.0), height: .fromLength(9.0)), margin: Rect(left: length(7.0), right: zero(), top: zero(), bottom: zero())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(20.0), height: .fromLength(37.0))),
            [node0],
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
    }

    @Test("absolute_child_with_main_margin__content_box")
    func test_absolute_child_with_main_margin__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, position: .absolute, size: Size(width: .fromLength(9.0), height: .fromLength(9.0)), margin: Rect(left: length(7.0), right: zero(), top: zero(), bottom: zero())))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(20.0), height: .fromLength(37.0))),
            [node0],
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
    }

    @Test("absolute_child_with_cross_margin__border_box")
    func test_absolute_child_with_cross_margin__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(28.0), height: .fromLength(27.0)), alignContent: .stretch))
        .get();
    let node1 = try! taffy.newLeafWithContext(
            Style(position: .absolute, size: Size(width: .fromPercent(1.0), height: .fromLength(15.0)), margin: Rect(left: zero(), right: zero(), top: length(4.0), bottom: zero()), alignContent: .stretch, flexGrow: 0.0, flexShrink: 1.0),
            TestNodeContext.ahemText("", .horizontal),
        )
        .get();
    let node2 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(25.0), height: .fromLength(27.0)), alignContent: .stretch))
        .get();
    let node = try! taffy.newWithChildren(
            Style(minSize: Size(width: .fromLength(311.0), height: .fromLength(0.0)), maxSize: Size(width: .fromLength(311.0), height: .fromLength(36893500000000000000.0)), justifyContent: .spaceBetween),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (311.0)) < 0.1)
        #expect(abs(layout_node.size.height - (27.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (28.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (27.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (311.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (15.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (4.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (25.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (27.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (286.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
    }

    @Test("absolute_child_with_cross_margin__content_box")
    func test_absolute_child_with_cross_margin__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(28.0), height: .fromLength(27.0)), alignContent: .stretch))
        .get();
    let node1 = try! taffy.newLeafWithContext(
            Style(boxSizing: .contentBox, position: .absolute, size: Size(width: .fromPercent(1.0), height: .fromLength(15.0)), margin: Rect(left: zero(), right: zero(), top: length(4.0), bottom: zero()), alignContent: .stretch, flexGrow: 0.0, flexShrink: 1.0),
            TestNodeContext.ahemText("", .horizontal),
        )
        .get();
    let node2 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(25.0), height: .fromLength(27.0)), alignContent: .stretch))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, minSize: Size(width: .fromLength(311.0), height: .fromLength(0.0)), maxSize: Size(width: .fromLength(311.0), height: .fromLength(36893500000000000000.0)), justifyContent: .spaceBetween),
            [node0, node1, node2],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (311.0)) < 0.1)
        #expect(abs(layout_node.size.height - (27.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (28.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (27.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
        let layout_node1 = try! taffy.layout(node1).get()
        #expect(abs(layout_node1.size.width - (311.0)) < 0.1)
        #expect(abs(layout_node1.size.height - (15.0)) < 0.1)
        #expect(abs(layout_node1.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node1.location.y - (4.0)) < 0.1)
        let layout_node2 = try! taffy.layout(node2).get()
        #expect(abs(layout_node2.size.width - (25.0)) < 0.1)
        #expect(abs(layout_node2.size.height - (27.0)) < 0.1)
        #expect(abs(layout_node2.location.x - (286.0)) < 0.1)
        #expect(abs(layout_node2.location.y - (0.0)) < 0.1)
    }

    @Test("absolute_layout_align_items_and_justify_content_center__border_box")
    func test_absolute_layout_align_items_and_justify_content_center__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(position: .absolute, size: Size(width: .fromLength(60.0), height: .fromLength(40.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(110.0), height: .fromLength(100.0)), alignItems: .center, justifyContent: .center),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (110.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (25.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (30.0)) < 0.1)
    }

    @Test("absolute_layout_align_items_and_justify_content_center__content_box")
    func test_absolute_layout_align_items_and_justify_content_center__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, position: .absolute, size: Size(width: .fromLength(60.0), height: .fromLength(40.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(110.0), height: .fromLength(100.0)), alignItems: .center, justifyContent: .center),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (110.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (60.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (25.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (30.0)) < 0.1)
    }

    @Test("absolute_layout_in_wrap_reverse_column_container__border_box")
    func test_absolute_layout_in_wrap_reverse_column_container__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(position: .absolute, size: Size(width: .fromLength(20.0), height: .fromLength(20.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), flexDirection: .column, flexWrap: .wrapReverse),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
    }

    @Test("absolute_layout_in_wrap_reverse_column_container__content_box")
    func test_absolute_layout_in_wrap_reverse_column_container__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, position: .absolute, size: Size(width: .fromLength(20.0), height: .fromLength(20.0))))
        .get();
    let node = try! taffy.newWithChildren(
            Style(boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), flexDirection: .column, flexWrap: .wrapReverse),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (20.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (80.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
    }

    @Test("absolute_aspect_ratio_fill_width__border_box")
    func test_absolute_aspect_ratio_fill_width__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(position: .absolute, inset: Rect(left: percent(0.05), right: auto(), top: percent(0.05), bottom: auto()), size: Size(width: auto(), height: .fromPercent(0.2)), aspectRatio: 3.0))
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
        #expect(abs(layout_node0.location.x - (20.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (15.0)) < 0.1)
    }

    @Test("absolute_aspect_ratio_fill_width__content_box")
    func test_absolute_aspect_ratio_fill_width__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, position: .absolute, inset: Rect(left: percent(0.05), right: auto(), top: percent(0.05), bottom: auto()), size: Size(width: auto(), height: .fromPercent(0.2)), aspectRatio: 3.0))
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
        #expect(abs(layout_node0.location.x - (20.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (15.0)) < 0.1)
    }

    @Test("absolute_aspect_ratio_fill_height__border_box")
    func test_absolute_aspect_ratio_fill_height__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(position: .absolute, inset: Rect(left: percent(0.05), right: auto(), top: percent(0.05), bottom: auto()), size: Size(width: .fromPercent(0.5), height: auto()), aspectRatio: 3.0))
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
        #expect(abs(layout_node0.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (67.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (20.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (15.0)) < 0.1)
    }

    @Test("absolute_aspect_ratio_fill_height__content_box")
    func test_absolute_aspect_ratio_fill_height__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, position: .absolute, inset: Rect(left: percent(0.05), right: auto(), top: percent(0.05), bottom: auto()), size: Size(width: .fromPercent(0.5), height: auto()), aspectRatio: 3.0))
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
        #expect(abs(layout_node0.size.width - (200.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (67.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (20.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (15.0)) < 0.1)
    }

    @Test("aspect_ratio_flex_row_fill_width__border_box")
    func test_aspect_ratio_flex_row_fill_width__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: auto(), height: .fromLength(40.0)), aspectRatio: 2.0))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.flex, size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), alignItems: .start),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (80.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
    }

    @Test("aspect_ratio_flex_row_fill_width__content_box")
    func test_aspect_ratio_flex_row_fill_width__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: auto(), height: .fromLength(40.0)), aspectRatio: 2.0))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.flex, boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), alignItems: .start),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (80.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (40.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
    }

    @Test("aspect_ratio_flex_column_fill_height__border_box")
    func test_aspect_ratio_flex_column_fill_height__border_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(size: Size(width: .fromLength(40.0), height: auto()), aspectRatio: 2.0))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.flex, size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), alignItems: .start, flexDirection: .column),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
    }

    @Test("aspect_ratio_flex_column_fill_height__content_box")
    func test_aspect_ratio_flex_column_fill_height__content_box() {

    
    
    var taffy = newTestTree();
    let node0 = try! taffy.newLeaf(Style(boxSizing: .contentBox, size: Size(width: .fromLength(40.0), height: auto()), aspectRatio: 2.0))
        .get();
    let node = try! taffy.newWithChildren(
            Style(display: Display.flex, boxSizing: .contentBox, size: Size(width: .fromLength(100.0), height: .fromLength(100.0)), alignItems: .start, flexDirection: .column),
            [node0],
        )
        .get();
    _ = try! taffy.computeLayoutWithMeasure(node, Size.MAX_CONTENT, testMeasureFunction).get();
    
    
    
        let layout_node = try! taffy.layout(node).get()
        #expect(abs(layout_node.size.width - (100.0)) < 0.1)
        #expect(abs(layout_node.size.height - (100.0)) < 0.1)
        #expect(abs(layout_node.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node.location.y - (0.0)) < 0.1)
        let layout_node0 = try! taffy.layout(node0).get()
        #expect(abs(layout_node0.size.width - (40.0)) < 0.1)
        #expect(abs(layout_node0.size.height - (20.0)) < 0.1)
        #expect(abs(layout_node0.location.x - (0.0)) < 0.1)
        #expect(abs(layout_node0.location.y - (0.0)) < 0.1)
    }
}
