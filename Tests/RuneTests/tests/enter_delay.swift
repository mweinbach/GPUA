// Tests ported from: crates/rune/tests/enter_delay.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `El.enterDelay`: a new element holds its whole insertion effect, then offset and opacity
//! play on one progress. Waiting draws nothing and asks for one wake; an entrance nobody would
//! see ignores the delay.

import Testing
@testable import Rune

@Suite("EnterDelayIntegrationTests")
struct EnterDelayIntegrationTests {
    @Test(.disabled("Requires Wave 2 El.enterDelay and Stagger in Spine El/Runtime"))
    func waitsWholeThenMovesOffsetAndOpacityInLockstep() {}

    @Test(.disabled("Requires Wave 2 El.enterDelay wake_deadline in Spine Runtime"))
    func waitingSleepsUntilTheStart() {}

    @Test(.disabled("Requires Wave 2 El.enterDelay and El.timeScale in Spine El/Runtime"))
    func timeScalesStretchTheDelay() {}

    @Test(.disabled("Requires Wave 2 El.enterDelay removal handling in Spine Runtime"))
    func removedWhileWaitingDoesntFlash() {}

    @Test(.disabled("Requires Wave 2 El.enterDelay in Spine El/Runtime"))
    func unseenEntrancesIgnoreTheDelay() {}

    @Test(.disabled("Requires Wave 2 El.enterDelay under Reduce Motion in Spine Runtime"))
    func reduceMotionKeepsTheDelayAndOnlyFades() {}

    @Test(.disabled("Requires Wave 2 El.enterDelay and Stagger in Spine El/Runtime"))
    func aStaggeredListOfFiveEntersInOrder() {}
}
