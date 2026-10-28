// Tests ported from: crates/scheduler/src/scheduler.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
@testable import Scheduler

@Suite("Scheduler Core Tests")
struct SchedulerCoreTests {
    @Test func test_priority_weights() {
        #expect(Priority.high.weight == 60)
        #expect(Priority.medium.weight == 30)
        #expect(Priority.low.weight == 10)
        #expect(Priority.realtimeAudio.weight == 0)
    }

    @Test func test_session_id() {
        let s1 = SessionId(1)
        let s2 = SessionId(2)
        #expect(s1 < s2)
        #expect(s1 == SessionId(1))
    }
}
