// Swift-only: Behavioral test suite for Element tree foundation and View system (upstream element.rs has no inline tests)

import Testing
@testable import GPUI

@Suite("ElementTests")
struct ElementTests {
    @Test("ElementId construction and equality")
    func elementIdConstructionAndEquality() {
        let id1: ElementId = "item_1"
        let id2 = ElementId.name("item_1")
        let id3: ElementId = 42

        #expect(id1 == id2)
        #expect(id1 != id3)
        #expect(id3 == ElementId.integer(42))
    }

    @Test("GlobalElementId path and description")
    func globalElementIdPathAndDescription() {
        let globalId = GlobalElementId([
            ElementId.name("root"),
            ElementId.name("list"),
            ElementId.integer(3),
        ])

        #expect(globalId.path.count == 3)
        #expect(globalId.description == "root.list.3")

        let single = GlobalElementId(ElementId.name("main"))
        #expect(single.path.count == 1)
        #expect(single.description == "main")
    }

    @Test("Empty element intoAnyElement")
    func emptyElement() {
        let empty = Empty()
        let anyEl = empty.intoAnyElement()
        #expect(empty.id() == nil)
        #expect(empty.sourceLocation() == nil)
        #expect(anyEl.id() == nil)
    }

    @Test("AnyElement wrapping and inspection")
    func anyElementWrapping() {
        let d = div().w(px(200)).h(px(100)).id("test_div")
        #expect(d.id() == ElementId.name("test_div"))
        let anyDiv = d.intoAnyElement()
        #expect(anyDiv.id() == nil)
    }
}
