// Tests ported from: crates/rune/src/input/time.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("InputTimeTests", .serialized)
struct InputTimeTests {
    @Test("input time scopes nest and restore thread arrival time on exit")
    func scopesNestAndRestore() {
        #expect(currentInputTime() == nil)
        let t1 = RuneInstant.now()
        let t2 = t1 + .milliseconds(15)

        withInputTimeScope(t1) {
            #expect(currentInputTime() == t1)
            withInputTimeScope(t2) {
                #expect(currentInputTime() == t2)
            }
            #expect(currentInputTime() == t1)
            withInputTimeScope(nil) {
                #expect(currentInputTime() == nil)
            }
            #expect(currentInputTime() == t1)
        }
        #expect(currentInputTime() == nil)
    }

    @Test("inputArrived records lastInput and scopes arrival time")
    func inputArrivedRecordsLastInput() {
        let before = RuneInstant.now()
        let scope = inputArrived(.key)
        let arrived = currentInputTime()
        #expect(arrived != nil)
        if let last = lastInput() {
            #expect(last >= before)
        } else {
            Issue.record("expected lastInput() to be recorded")
        }
        scope.end()
        #expect(currentInputTime() == nil)
    }

    @Test("RuneInstant arithmetic round-trips duration offsets")
    func instantArithmetic() {
        let base = RuneInstant.now() + .seconds(5)
        let earlier = base - .milliseconds(250)
        #expect(base.checkedSub(.milliseconds(250)) == earlier)
        #expect(earlier + .milliseconds(250) == base)
    }
}
