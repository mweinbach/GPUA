// Tests ported from: crates/rune/src/window/frame.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import RuneMotion
import Testing
@testable import Rune

@Suite("WindowFrameTests")
struct WindowFrameTests {
    private static let SCREEN: [Float] = [0.0, 33.0, 1728.0, 1084.0]

    @Test("a resize keeps the top edge and stays on screen")
    func aResizeKeepsTheTopEdgeAndStaysOnScreen() {
        let window: [Float] = [100.0, 200.0, 400.0, 432.0]
        #expect(windowFrameTarget(window, (400.0, 632.0), false, Self.SCREEN) == [100.0, 200.0, 400.0, 632.0])
        #expect(windowFrameTarget(window, (400.0, 1000.0), false, Self.SCREEN) == [100.0, 117.0, 400.0, 1000.0])
        #expect(windowFrameTarget(window, (400.0, 2000.0), false, Self.SCREEN) == [100.0, 33.0, 400.0, 2000.0])
    }

    @Test("a window already off screen is not pulled back")
    func aWindowAlreadyOffScreenIsNotPulledBack() {
        let window: [Float] = [-200.0, 900.0, 400.0, 400.0]
        #expect(windowFrameTarget(window, (400.0, 300.0), false, Self.SCREEN) == [-200.0, 900.0, 400.0, 300.0])
        #expect(windowFrameTarget(window, (400.0, 600.0), false, Self.SCREEN) == [-200.0, 700.0, 400.0, 600.0])
    }

    @Test("centring matches appkit")
    func centringMatchesAppkit() {
        #expect(
            windowFrameTarget([0.0, 0.0, 400.0, 100.0], (400.0, 332.0), true, [0.0, 0.0, 1728.0, 1084.0])
                == [664.0, 188.0, 400.0, 332.0]
        )
        #expect(
            windowFrameTarget([0.0, 0.0, 400.0, 100.0], (300.0, 932.0), true, [0.0, 0.0, 1728.0, 1084.0])
                == [714.0, 38.0, 300.0, 932.0]
        )
        #expect(
            windowFrameTarget([5.0, 5.0, 800.0, 132.0], nil, true, Self.SCREEN)
                == [464.0, 33.0 + 238.0, 800.0, 132.0]
        )
    }

    @Test("the spring lands on the target and retargets with its speed")
    func theSpringLandsOnTheTargetAndRetargetsWithItsSpeed() {
        let spring = Spring.new(0.3, 0.0)
        let anim = WindowFrameAnim.new(spring, 1.0, [0.0, 0.0, 400.0, 400.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 400.0, 600.0])
        let (mid, v) = anim.sample(1.1)
        #expect(mid[3] > 400.0 && mid[3] < 600.0 && v[3] > 0.0)
        #expect(Array(mid[0..<3]) == [0.0, 0.0, 400.0])
        #expect(!anim.done(1.1))
        #expect(anim.done(2.0))
        #expect(anim.sample(2.0).0 == anim.to)

        let back = WindowFrameAnim.retarget(anim, spring, 1.1, [9.0, 9.0, 9.0, 9.0], [0.0, 0.0, 400.0, 400.0])
        #expect(back.sample(1.1).0 == mid)
        #expect(back.sample(1.11).0[3] > mid[3])

        let jump = WindowFrameAnim.retarget(anim, nil, 1.1, [9.0, 9.0, 9.0, 9.0], [1.0, 1.0, 1.0, 1.0])
        #expect(jump.done(1.1))
        #expect(jump.sample(1.1).0 == [1.0, 1.0, 1.0, 1.0])
    }

    @Test("a drag mid flight keeps the new origin and the size carries on")
    func aDragMidFlightKeepsTheNewOriginAndTheSizeCarriesOn() {
        let spring = Spring.new(0.3, 0.0)
        var anim = WindowFrameAnim.new(spring, 0.0, [10.0, 20.0, 400.0, 400.0], [0.0, 0.0, 0.0, 0.0], [10.0, 20.0, 400.0, 600.0])
        let before = anim.sample(0.1).0
        anim.shift(50.0, -5.0)
        let after = anim.sample(0.1).0
        #expect(after == [before[0] + 50.0, before[1] - 5.0, before[2], before[3]])
        #expect(anim.to == [60.0, 15.0, 400.0, 600.0])
    }

    @Test("requested sizes stay inside the window limits")
    func requestedSizesStayInsideTheWindowLimits() {
        #expect(clampWindowSize((300.0, 900.0), (420.0, 0.0), (800.0, 700.0)) == (420.0, 700.0))
        #expect(clampWindowSize((500.0, 100.0), (420.0, 200.0), nil) == (500.0, 200.0))
    }

    @Test("later sizes win and centring sticks")
    func laterSizesWinAndCentringSticks() {
        let a = WindowFrameRequest(size: (1.0, 2.0), animate: true, spring: nil, center: true)
        let b = WindowFrameRequest(size: (3.0, 4.0), animate: false, spring: nil, center: false)
        #expect(a.merge(b) == WindowFrameRequest(size: (3.0, 4.0), animate: false, spring: nil, center: true))
        #expect(b.merge(WindowFrameRequest(center: true)) == WindowFrameRequest(size: (3.0, 4.0), animate: false, spring: nil, center: true))
    }
}
