// Tests ported from: crates/rune/src/runtime/tests/scroll_carried.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Testing
@testable import Rune

private enum RtCarriedZoom: Sendable, CaseIterable {
    case around
    case within
    case turned
}

private func rtScaleEl(_ base: El, _ factor: Float) -> El {
    var copy = base
    copy.scaleValue = factor
    return copy
}

private func rtRotateEl(_ base: El, _ angle: Float) -> El {
    var copy = base
    copy.style.gridTemplateRowNames.append(["__rt_rotate__", "\(angle)"])
    return copy
}

private func rtZoomedScrollView(_ z: RtCarriedZoom, _: Cx<RtCarriedZoom>) -> El {
    var rows = col().key("rows").wFull()
    for i in 0..<30 {
        rows = rows.child(el().key("row\(i)").wFull().h(40.0))
    }
    if z == .within {
        rows = rtScaleEl(col().key("zoom").wFull().child(rows), 1.6)
    }
    let list = col().key("scroll").size(300.0, 200.0).scroll(ScrollSpec(stickBottom: false)).child(rows)
    switch z {
    case .within:
        return col().child(list)
    case .around:
        return rtScaleEl(col().key("zoom").child(list), 1.6)
    case .turned:
        return rtRotateEl(rtScaleEl(col().key("zoom").child(list), 1.6), 0.3)
    }
}

@Suite struct RtScrollCarriedTests {
    @Test
    func whatAScrollCarriesIsMeasuredInTheWindowThroughAZoom() {
        for z in RtCarriedZoom.allCases {
            let rt = Runtime.new(z, rtZoomedScrollView, (600.0, 600.0), Env.new(true, 1.0))
            _ = rt.frame(0.0)
            guard let row0 = rtElement(rt, "row3") else {
                Issue.record("Missing row3")
                return
            }
            let start = [row0.rect[0] + row0.scrolled[0], row0.rect[1] + row0.scrolled[1]]
            rt.update { _, tx in
                tx.scrollTo("scroll", 300.0)
            }

            var carried: Float = 0.0
            for _ in 0..<90 {
                _ = rt.frame(1.0 / 120.0)
                guard let e = rtElement(rt, "row3") else { continue }
                let x = e.rect[0] + e.scrolled[0]
                let y = e.rect[1] + e.scrolled[1]
                #expect(abs(x - start[0]) <= 1.0 && abs(y - start[1]) <= 1.0)
                carried = max(carried, (e.scrolled[0] * e.scrolled[0] + e.scrolled[1] * e.scrolled[1]).squareRoot())
            }

            let screen: Float = (z == .within) ? 300.0 : 480.0
            #expect(abs(carried - screen) < 1.0)
        }
    }
}
