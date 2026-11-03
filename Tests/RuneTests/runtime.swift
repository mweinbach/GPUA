// Tests ported from: crates/rune/src/runtime.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import RuneMotion
import Taffy
import Testing
@testable import Rune

// Shared `rt*`-prefixed test helpers for `RuneTests` (avoiding unprefixed `El` extensions so
// `el/*` merges cleanly without method collisions).

func rtClick<S>(_ rt: Runtime<S>, _ key: String) {
    guard let (x, y) = rt.find(key) else {
        Issue.record("Missing element key '\(key)'")
        return
    }
    rt.pointerMove(x, y)
    rt.pointerDown(x, y)
    rt.pointerUp(x, y)
}

func rtStepFrames<S>(_ rt: Runtime<S>, _ count: Int, dt: Double = 1.0 / 120.0) {
    guard count > 0 else { return }
    for _ in 0..<count {
        _ = rt.frame(dt)
    }
}

func rtElement<S>(_ rt: Runtime<S>, _ key: String) -> ElementInfo? {
    rt.elements().first { $0.key == key }
}

func rtWithHover<S>(_ base: El, _ f: @escaping (inout S, Bool, inout Tx) -> Void) -> El {
    var copy = base
    copy.onHoverHandler = { states, hovered, tx in
        _ = states.withMutable { (s: inout S) in
            f(&s, hovered, &tx)
        }
    }
    return copy
}

func rtSelectable(_ base: El, _ on: Bool = true) -> El {
    var copy = base
    copy.textSpec?.value.selectable = on
    return copy
}

func rtSelectionGroup(_ base: El, _ on: Bool = true) -> El {
    var copy = base
    copy.selectionGroupFlag = on
    return copy
}

func rtAnchored(_ base: El, _ anchor: Anchor) -> El {
    var copy = base
    copy.aboveAnchor = anchor
    return copy
}

func rtScale(_ base: El, _ factor: Float) -> El {
    var copy = base
    copy.scaleValue = factor
    return copy
}

func rtAnimateLayout(_ base: El, _ on: Bool = true) -> El {
    var copy = base
    copy.animateLayoutFlag = on
    return copy
}

func rtInstant(_ base: El, _ on: Bool = true) -> El {
    var copy = base
    copy.instantChangesFlag = on
    return copy
}

func rtAbsolute(_ base: El, _ x: Float, _ y: Float) -> El {
    var copy = base
    copy.style.position = .absolute
    copy.style.inset.left = .length(x)
    copy.style.inset.top = .length(y)
    return copy
}

func rtAspectFit(_ base: El, _ ratio: Float) -> El {
    var copy = base
    copy.aspectFitValue = ratio
    return copy
}

func rtGroupOpacity(_ base: El, _ rest: Float) -> El {
    var copy = base
    copy.vis.groupOpacity = rest
    return copy
}

func rtHoverGroup(_ base: El) -> El {
    var copy = base
    if copy.vis.hover.a <= 0.0 {
        copy.vis.hover = Color(r: 1.0, g: 1.0, b: 1.0, a: 0.0001)
    }
    return copy
}

func rtMaxLines(_ base: El, _ n: Int) -> El {
    var copy = base
    copy.textSpec?.value.maxLines = n
    copy.textSpec?.value.wrap = true
    return copy
}

@Suite("RuntimeModuleTests")
struct RuntimeModuleTests {
    @Test("Runtime initializes, commits initial frame, and applies state updates")
    func runtimeInitializesAndUpdates() {
        let rt = Runtime.new(0, { count, _ in
            col().key("root-col").wFull().hFull().child(
                text("count=\(count)").key("label")
            )
        }, (320.0, 200.0), Env.new(true, 2.0))

        _ = rt.frame(0.0)
        #expect(rt.stats.commits == 1)
        #expect(rtElement(rt, "label")?.text == "count=0")

        rt.update { s, _ in s = 42 }
        #expect(rt.needsCommit())
        _ = rt.frame(1.0 / 60.0)
        #expect(rtElement(rt, "label")?.text == "count=42")
    }

    @Test("Anchor position flips to opposite side when primary side overflows window")
    func anchorPositionFlipsWhenClamped() {
        let anchor = Anchor(key: "btn", side: .bottom, align: .start, gap: 4.0)
        let placed = anchorPosition(anchor, [20.0, 170.0, 80.0, 190.0], (100.0, 60.0), (300.0, 200.0))
        #expect(placed.0 == 20.0)
        #expect(placed.1 == 106.0)
    }
}
