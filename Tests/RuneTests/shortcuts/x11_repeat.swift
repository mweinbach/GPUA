// Tests ported from: crates/rune/src/shortcuts/x11_repeat.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite
struct ShortcutX11RepeatTests {
    @Test
    func aHeldKeyFiresOnceInEitherAutorepeatMode() {
        var r = X11ShortcutRepeats()
        // Release/press pairs with matching timestamps.
        #expect(r.press(38, 10) == true)
        r.release(38, 40)
        #expect(r.press(38, 40) == false)
        r.release(38, 70)
        #expect(r.press(38, 70) == false)
        r.release(38, 90)
        #expect(r.press(38, 300) == true)

        // Detectable autorepeat: presses without releases.
        #expect(r.press(38, 330) == false)
        #expect(r.press(38, 360) == false)
        r.release(38, 400)
        #expect(r.press(39, 410) == true)
        #expect(r.press(38, 420) == true)
    }

    @Test
    func keysPressedDuringAGrabAreForgottenWhenTheGrabKeyIsReleased() {
        var r = X11ShortcutRepeats()
        #expect(r.press(65, 10) == true) // grabbed chord's key starts active grab
        #expect(r.press(38, 20) == true) // another key arrives through the grab
        r.release(65, 30)                // grab ends; 38's release goes to focused window instead
        #expect(r.press(38, 400) == true)
        #expect(r.press(65, 410) == true)
    }
}
