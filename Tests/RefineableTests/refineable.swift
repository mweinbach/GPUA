// Swift-only: unit tests for Refineable/refineable.swift

import Testing
@testable import Refineable

struct TestStyleRefinement: Refineable, IsEmpty, DefaultInitializable, Equatable, Sendable {
    typealias Refinement = TestStyleRefinement

    var color: String?
    var fontSize: Double?

    init() {
        self.color = nil
        self.fontSize = nil
    }

    init(color: String? = nil, fontSize: Double? = nil) {
        self.color = color
        self.fontSize = fontSize
    }

    var isEmpty: Bool {
        color == nil && fontSize == nil
    }

    mutating func refine(with other: TestStyleRefinement) {
        if let newColor = other.color {
            self.color = newColor
        }
        if let newSize = other.fontSize {
            self.fontSize = newSize
        }
    }

    func isSuperset(of other: TestStyleRefinement) -> Bool {
        if let otherColor = other.color, otherColor != self.color {
            return false
        }
        if let otherSize = other.fontSize, otherSize != self.fontSize {
            return false
        }
        return true
    }

    func subtract(_ other: TestStyleRefinement) -> TestStyleRefinement {
        var result = TestStyleRefinement()
        if let selfColor = self.color, selfColor != other.color {
            result.color = selfColor
        }
        if let selfSize = self.fontSize, selfSize != other.fontSize {
            result.fontSize = selfSize
        }
        return result
    }
}

struct TestStyle: Refineable, DefaultInitializable, Equatable, Sendable {
    typealias Refinement = TestStyleRefinement

    var color: String
    var fontSize: Double

    init() {
        self.color = "black"
        self.fontSize = 12.0
    }

    init(color: String, fontSize: Double) {
        self.color = color
        self.fontSize = fontSize
    }

    mutating func refine(with refinement: TestStyleRefinement) {
        if let newColor = refinement.color {
            self.color = newColor
        }
        if let newSize = refinement.fontSize {
            self.fontSize = newSize
        }
    }

    func isSuperset(of refinement: TestStyleRefinement) -> Bool {
        if let refColor = refinement.color, refColor != self.color {
            return false
        }
        if let refSize = refinement.fontSize, refSize != self.fontSize {
            return false
        }
        return true
    }

    func subtract(_ refinement: TestStyleRefinement) -> TestStyleRefinement {
        var diff = TestStyleRefinement()
        if self.color != refinement.color {
            diff.color = self.color
        }
        if self.fontSize != refinement.fontSize {
            diff.fontSize = self.fontSize
        }
        return diff
    }
}

@Suite("Refineable Tests")
struct RefineableTests {
    @Test func test_refinement_merging() {
        var base = TestStyleRefinement(color: "red", fontSize: 14.0)
        let override = TestStyleRefinement(color: "blue") // fontSize nil
        base.refine(with: override)

        #expect(base.color == "blue")
        #expect(base.fontSize == 14.0)
    }

    @Test func test_cascade_slots_and_precedence() {
        var cascade = Cascade<TestStyle>()
        cascade.base = TestStyleRefinement(color: "black", fontSize: 12.0)

        let themeSlot = cascade.reserve()
        let localSlot = cascade.reserve()

        cascade.set(themeSlot, TestStyleRefinement(color: "green", fontSize: 16.0))
        cascade.set(localSlot, TestStyleRefinement(color: "purple")) // overrides color only

        let merged = cascade.merged()
        #expect(merged.color == "purple")
        #expect(merged.fontSize == 16.0)

        // Clear local slot
        cascade.set(localSlot, nil)
        let mergedAfterClear = cascade.merged()
        #expect(mergedAfterClear.color == "green")
        #expect(mergedAfterClear.fontSize == 16.0)
    }

    @Test func test_from_cascade() {
        var cascade = Cascade<TestStyle>()
        cascade.base = TestStyleRefinement(fontSize: 18.0)
        let slot = cascade.reserve()
        cascade.set(slot, TestStyleRefinement(color: "cyan"))

        let style = TestStyle.fromCascade(cascade)
        #expect(style.color == "cyan")
        #expect(style.fontSize == 18.0)
    }

    @Test func test_is_superset_and_subtract() {
        let style = TestStyle(color: "blue", fontSize: 14.0)
        let partial = TestStyleRefinement(color: "blue")
        let nonMatching = TestStyleRefinement(color: "red")

        #expect(style.isSuperset(of: partial))
        #expect(!style.isSuperset(of: nonMatching))

        let diff = style.subtract(partial)
        #expect(diff.color == nil)
        #expect(diff.fontSize == 14.0)
    }
}
