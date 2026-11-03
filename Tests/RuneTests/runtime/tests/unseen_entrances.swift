// Tests ported from: crates/rune/src/runtime/tests/unseen_entrances.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import RuneMotion
import Testing
@testable import Rune

/// A 100 pt scroll over 40 rows; `n` odd lights every row.
private func rtUnseenLit(_ n: UInt32, _: Cx<UInt32>) -> El {
    let fill = (n % 2 == 1) ? Color.WHITE : Color.TRANSPARENT
    let rows: [El] = (0..<40).map { i in
        col().key("r\(i)").wFull().h(40.0).bg(fill)
    }
    return col().wFull().hFull().child(
        col().key("scroll").wFull().h(100.0).scroll(ScrollSpec(stickBottom: false)).child(col().children(rows))
    )
}

/// A 100 pt scroll over 40 rows, each with a digit; `n` ticks every row's digit.
private func rtUnseenTicking(_ n: UInt32, _: Cx<UInt32>) -> El {
    let rows: [El] = (0..<40).map { i in
        let digit = el().key("d\(i)-\(n)").size(10.0, 10.0).bg(Color.WHITE).transition(.opacity())
        return col().key("r\(i)").wFull().h(40.0).child(digit)
    }
    return col().wFull().hFull().child(
        col().key("scroll").wFull().h(100.0).scroll(ScrollSpec(stickBottom: false)).child(col().children(rows))
    )
}

@Suite
struct RtUnseenEntrancesTests {
    @Test
    func coloursOutOfSightLandAtOnce() {
        let rt = Runtime.new(UInt32(0), rtUnseenLit, (300.0, 300.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)
        _ = rt.frame(1.0 / 120.0)
        rt.update { n, _ in n = 1 }
        _ = rt.frame(1.0 / 120.0)

        let r0Id = rt.nodes.first(where: { $0.key == "r0" })!.nodeId
        let r30Id = rt.nodes.first(where: { $0.key == "r30" })!.nodeId
        let r0Fading = rt.scene.store().isAnimating(r0Id, P_FILL)
        let r30Fading = rt.scene.store().isAnimating(r30Id, P_FILL)
        #expect(r0Fading)
        #expect(!r30Fading)
    }

    @Test
    func whatMountsOutOfSightEntersAtOnce() {
        let rt = Runtime.new(UInt32(0), rtUnseenTicking, (300.0, 300.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)
        _ = rt.frame(1.0 / 120.0)
        rt.update { n, _ in n = 1 }
        _ = rt.frame(1.0 / 120.0)

        let elements = rt.elements()
        let d01 = elements.first(where: { $0.key == "d0-1" })?.opacity
        let d301 = elements.first(where: { $0.key == "d30-1" })?.opacity
        let d300 = elements.first(where: { $0.key == "d30-0" })?.opacity
        #expect(d01 != nil && (d01 ?? 1.0) < 1.0)
        #expect(d301 == 1.0)
        #expect(d300 == nil)
    }
}
