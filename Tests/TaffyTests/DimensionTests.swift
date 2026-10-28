// Swift-only: Behavioral tests for ported Taffy dimension and available space types

import Testing
@testable import Taffy

@Suite("Taffy Dimension and AvailableSpace Tests")
struct TaffyDimensionTests {
    @Test("CompactLength and Dimension resolution")
    func testDimension() {
        let len = Dimension.length(50.0)
        #expect(len.intoOption() == 50.0)
        #expect(!len.isAuto)

        let pct = Dimension.percent(0.25)
        #expect(pct.intoOption() == nil)
        #expect(!pct.isAuto)
        #expect(pct.value.resolvedPercentageSize(parentSize: 200.0) == 50.0)

        let autoDim = Dimension.auto()
        #expect(autoDim.isAuto)
        #expect(autoDim.intoOption() == nil)

        let lpa = LengthPercentageAuto.percent(0.5)
        #expect(lpa.resolveToOption(context: 300.0) == 150.0)

        let lpaAuto = LengthPercentageAuto.auto()
        #expect(lpaAuto.resolveToOption(context: 300.0) == nil)
    }

    @Test("AvailableSpace operations")
    func testAvailableSpace() {
        let def = AvailableSpace.definite(100.0)
        #expect(def.isDefinite)
        #expect(def.intoOption() == 100.0)
        #expect(def.unwrap() == 100.0)
        #expect(def.computeFreeSpace(usedSpace: 40.0) == 60.0)

        let minC = AvailableSpace.minContent
        #expect(!minC.isDefinite)
        #expect(minC.intoOption() == nil)
        #expect(minC.unwrapOr(50.0) == 50.0)
        #expect(minC.computeFreeSpace(usedSpace: 40.0) == 0.0)

        let maxC = AvailableSpace.maxContent
        #expect(!maxC.isDefinite)
        #expect(maxC.computeFreeSpace(usedSpace: 40.0) == Float.infinity)

        #expect(def.isRoughlyEqual(to: .definite(100.0)))
        #expect(!def.isRoughlyEqual(to: .definite(100.1)))
        #expect(minC.isRoughlyEqual(to: .minContent))
        #expect(maxC.isRoughlyEqual(to: .maxContent))
    }
}
