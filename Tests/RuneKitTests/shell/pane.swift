// Tests ported from: crates/rune-kit/src/shell/pane.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneKit

@Suite
struct ShellPaneTests {
    @Test
    func aPeekDocksWhereItFloatsAndEndsWhenClosed() {
        var p = PaneState.new(276.0).collapsed()
        p.peek()
        #expect(p.isPeeking())
        p.endPeek()
        #expect(!p.isPeeking() && p.peekPhase() == .left)
        p.peek()
        p.toggle()
        #expect(p.isOpen() && !p.isPeeking() && p.peekPhase() == .docked, "docks from the peek")
        p.peek()
        #expect(p.peekPhase() == .docked, "an open sidebar doesn't peek")
        p.toggle()
        #expect(p.peekPhase() == .none, "a close from docked isn't a peek")
        p.toggle()
        #expect(p.peekPhase() == .none, "an open without a peek isn't docked from one")
    }

    @Test
    func theDefaultFollowsTheRangeFromTheWidthItWasMadeWith() {
        let p0 = PaneState.new(640.4).withWidth(500.0)
        #expect(p0.width() == 480.0 && p0.defaultWidth() == 480.0)
        let p1 = p0.range(360.0, 960.0)
        #expect(p1.width() == 500.0 && p1.defaultWidth() == 640.0)
        var p2 = p1.range(100.0, 200.0).range(360.0, 960.0)
        #expect(p2.width() == 500.0 && p2.defaultWidth() == 640.0, "ranges don't accumulate")
        p2.setWidth(400.0)
        p2.resetWidth()
        #expect(p2.width() == 640.0)
    }

    @Test
    func theTailFadeFollowsTheSpringAcrossTheLastFraction() {
        let spring = Spring.new(0.3, 0.0)
        let a = tailFade(spring, 0.15, false)
        guard case .uniform(let v) = a.velocity else {
            Issue.record("expected uniform velocity")
            return
        }
        // From the delay on, the faded opacity is the pane's open fraction over 0.15.
        for t: Float in [0.02, 0.05, 0.1, 0.2] {
            let open = spring.sample(1.0, 0.0, 0.0, a.delay + t).0
            let faded = spring.sample(1.0, v, 0.0, t).0
            #expect(abs(open / 0.15 - faded) < 0.01, "t \(t): \(open / 0.15) vs \(faded)")
        }
        #expect(abs(spring.sample(1.0, 0.0, 0.0, a.delay).0 - 0.15) < 0.01)
        guard case .tween(let duration, _) = tailFade(spring, 0.15, true).curve else {
            Issue.record("expected tween curve")
            return
        }
        #expect(duration > 0.01 && duration < 0.06, "an open is solid almost at once: \(duration)")
    }

    @Test
    func theMotionScalesWithWidthWithinItsBounds() {
        let k = Kit.neutral(true)
        let m = PaneMotion.new().spring(Spring.new(0.3, 0.0)).scaleWithWidth(480.0, 0.15, 0.3)
        #expect(abs(m.springFor(k, 276.0).duration - 0.3 * (Float(276.0) / 480.0).squareRoot()) < 1e-5)
        #expect(m.springFor(k, 1000.0).duration == 0.3)
        #expect(m.springFor(k, 50.0).duration == 0.15)
        #expect(PaneMotion.new().springFor(k, 50.0) == k.motion.disclosure)
    }

    @Test
    func widthsClampRoundAndCollapsePastHalfTheMinimum() {
        var p = PaneState.new(276.0).range(136.0, 640.0)
        p.setWidth(1000.0)
        #expect(p.width() == 640.0)
        p.setWidth(100.4)
        #expect(p.width() == 136.0)
        p.setWidth(300.6)
        #expect(p.width() == 301.0)
        p.dragTo(80.0)
        #expect(p.isOpen() && p.width() == 136.0, "above half the minimum it clamps")
        p.dragTo(60.0)
        #expect(!p.isOpen() && p.width() == 136.0, "below half it collapses and keeps its width")
        #expect(p.shownWidth() == 0.0)
        p.dragTo(200.0)
        #expect(p.isOpen() && p.width() == 200.0)
        p.resetWidth()
        #expect(p.width() == 276.0)
        #expect(PaneState.new(20.0).width() == PaneState.MIN)
        p.setWidth(.nan)
        #expect(p.width() == 276.0)
    }
}
