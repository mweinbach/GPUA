// Swift-only: Adversarial stress test harness for Refineable

import Testing
@testable import Refineable

struct MultiPropRefinement: Refineable, IsEmpty, DefaultInitializable, Equatable, Sendable {
    typealias Refinement = MultiPropRefinement

    var color: String?
    var fontSize: Double?
    var opacity: Double?
    var padding: Int?
    var tag: String?

    init() {
        self.color = nil
        self.fontSize = nil
        self.opacity = nil
        self.padding = nil
        self.tag = nil
    }

    init(color: String? = nil, fontSize: Double? = nil, opacity: Double? = nil, padding: Int? = nil, tag: String? = nil) {
        self.color = color
        self.fontSize = fontSize
        self.opacity = opacity
        self.padding = padding
        self.tag = tag
    }

    var isEmpty: Bool {
        color == nil && fontSize == nil && opacity == nil && padding == nil && tag == nil
    }

    mutating func refine(with other: MultiPropRefinement) {
        if let c = other.color { self.color = c }
        if let f = other.fontSize { self.fontSize = f }
        if let o = other.opacity { self.opacity = o }
        if let p = other.padding { self.padding = p }
        if let t = other.tag { self.tag = t }
    }

    func isSuperset(of other: MultiPropRefinement) -> Bool {
        if let c = other.color, c != self.color { return false }
        if let f = other.fontSize, f != self.fontSize { return false }
        if let o = other.opacity, o != self.opacity { return false }
        if let p = other.padding, p != self.padding { return false }
        if let t = other.tag, t != self.tag { return false }
        return true
    }

    func subtract(_ other: MultiPropRefinement) -> MultiPropRefinement {
        var diff = MultiPropRefinement()
        if let c = self.color, c != other.color { diff.color = c }
        if let f = self.fontSize, f != other.fontSize { diff.fontSize = f }
        if let o = self.opacity, o != other.opacity { diff.opacity = o }
        if let p = self.padding, p != other.padding { diff.padding = p }
        if let t = self.tag, t != other.tag { diff.tag = t }
        return diff
    }
}

struct MultiPropStyle: Refineable, DefaultInitializable, Equatable, Sendable {
    typealias Refinement = MultiPropRefinement

    var color: String
    var fontSize: Double
    var opacity: Double
    var padding: Int
    var tag: String

    init() {
        self.color = "black"
        self.fontSize = 12.0
        self.opacity = 1.0
        self.padding = 0
        self.tag = "default"
    }

    mutating func refine(with refinement: MultiPropRefinement) {
        if let c = refinement.color { self.color = c }
        if let f = refinement.fontSize { self.fontSize = f }
        if let o = refinement.opacity { self.opacity = o }
        if let p = refinement.padding { self.padding = p }
        if let t = refinement.tag { self.tag = t }
    }

    func isSuperset(of refinement: MultiPropRefinement) -> Bool {
        if let c = refinement.color, c != self.color { return false }
        if let f = refinement.fontSize, f != self.fontSize { return false }
        if let o = refinement.opacity, o != self.opacity { return false }
        if let p = refinement.padding, p != self.padding { return false }
        if let t = refinement.tag, t != self.tag { return false }
        return true
    }

    func subtract(_ refinement: MultiPropRefinement) -> MultiPropRefinement {
        var diff = MultiPropRefinement()
        if self.color != refinement.color { diff.color = self.color }
        if self.fontSize != refinement.fontSize { diff.fontSize = self.fontSize }
        if self.opacity != refinement.opacity { diff.opacity = self.opacity }
        if self.padding != refinement.padding { diff.padding = self.padding }
        if self.tag != refinement.tag { diff.tag = self.tag }
        return diff
    }
}

@Suite("Refineable Adversarial Stress Tests")
struct RefineableStressTests {

    // MARK: - 1. Deep Multi-Layer Cascade (15 layers)

    @Test func test_deep_15_layer_cascade_precedence() {
        var cascade = Cascade<MultiPropStyle>()
        cascade.base = MultiPropRefinement(color: "base_color", fontSize: 10.0, opacity: 0.5, padding: 2, tag: "base")

        var slots: [CascadeSlot] = []
        for i in 1...15 {
            let slot = cascade.reserve()
            slots.append(slot)
            // Each layer overrides tag and conditionally overrides other props
            var ref = MultiPropRefinement(tag: "layer_\(i)")
            if i == 5 { ref.color = "color_layer_5" }
            if i == 8 { ref.fontSize = 24.0 }
            if i == 10 { ref.color = "color_layer_10" } // overrides layer 5
            if i == 12 { ref.padding = 16 }
            if i == 15 { ref.opacity = 0.95 }
            cascade.set(slot, ref)
        }

        let merged = cascade.merged()
        #expect(merged.tag == "layer_15", "Last layer tag should win")
        #expect(merged.color == "color_layer_10", "Layer 10 color should override layer 5")
        #expect(merged.fontSize == 24.0, "Layer 8 font size should be preserved")
        #expect(merged.padding == 16, "Layer 12 padding should be preserved")
        #expect(merged.opacity == 0.95, "Layer 15 opacity should be preserved")

        let style = MultiPropStyle.fromCascade(cascade)
        #expect(style.tag == "layer_15")
        #expect(style.color == "color_layer_10")
        #expect(style.fontSize == 24.0)
        #expect(style.padding == 16)
        #expect(style.opacity == 0.95)
    }

    // MARK: - 2. Sparse & Empty Slots in Cascade

    @Test func test_sparse_and_cleared_slots_cascade() {
        var cascade = Cascade<MultiPropStyle>()
        cascade.base = MultiPropRefinement(color: "red", fontSize: 14.0)

        let slot1 = cascade.reserve()
        let slot2 = cascade.reserve()
        let slot3 = cascade.reserve()
        let slot4 = cascade.reserve()

        // slot1 has refinement
        cascade.set(slot1, MultiPropRefinement(color: "blue"))
        // slot2 is left nil
        // slot3 has an empty refinement (all nil)
        cascade.set(slot3, MultiPropRefinement())
        // slot4 has refinement
        cascade.set(slot4, MultiPropRefinement(fontSize: 20.0))

        var merged = cascade.merged()
        #expect(merged.color == "blue")
        #expect(merged.fontSize == 20.0)

        // Now clear slot1 by setting to nil
        cascade.set(slot1, nil)
        merged = cascade.merged()
        #expect(merged.color == "red", "Should fall back to base refinement color")
        #expect(merged.fontSize == 20.0)

        // Setting out-of-range slot should safely no-op
        let invalidSlot = CascadeSlot(index: 999)
        cascade.set(invalidSlot, MultiPropRefinement(color: "yellow"))
        #expect(cascade.merged().color == "red")
    }

    // MARK: - 3. Superset & Subtract Invariants

    @Test func test_superset_and_subtract_algebra() {
        let full = MultiPropStyle()
        let refined = full.refined(with: MultiPropRefinement(color: "cyan", fontSize: 18.0, padding: 8))

        let partialRef = MultiPropRefinement(color: "cyan", fontSize: 18.0)
        #expect(refined.isSuperset(of: partialRef))

        let nonMatchingRef = MultiPropRefinement(color: "cyan", fontSize: 24.0)
        #expect(!refined.isSuperset(of: nonMatchingRef))

        let diff = refined.subtract(partialRef)
        // Fields that matched should not be in diff
        #expect(diff.color == nil)
        #expect(diff.fontSize == nil)
        // Fields not present in partialRef should remain in diff
        #expect(diff.padding == 8)
        #expect(diff.opacity == 1.0)
    }
}
