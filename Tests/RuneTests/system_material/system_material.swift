// Tests ported from: crates/rune/src/system_material/mod.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import RuneMotion
@testable import Rune

@Suite("SystemMaterialUnitTests")
struct SystemMaterialUnitTests {
    @Test("MaterialDraw points scale from physical pixels")
    func materialDrawPointsScale() {
        let draw = MaterialDraw(
            id: NodeId(1),
            material: .glass,
            rect: [20.0, 40.0, 200.0, 100.0],
            radius: 24.0,
            continuous: true,
            opacity: 1.0
        )
        let (pts2x, r2x) = draw.points(2.0)
        #expect(pts2x == [10.0, 20.0, 100.0, 50.0])
        #expect(r2x == 12.0)
    }
}
