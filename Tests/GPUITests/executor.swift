// Tests ported from: crates/gpui/src/executor.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

import Testing
import Foundation
@testable import GPUI

@Suite("ExecutorTests")
struct ExecutorTests {
    // PORT NOTE: Synchronized test state container for single-thread deterministic execution.
    private final class Box: @unchecked Sendable {
        var value = false
    }

    @Test
    func sanity_test_tasks_run() async {
        let dispatcher = TestDispatcher.new(seed: 0)
        let fg = ForegroundExecutor(dispatcher: dispatcher)

        let box = Box()
        fg.spawn {
            box.value = true
        }.detach()

        dispatcher.runUntilParked()
        #expect(box.value, "Task should run normally when app is alive")
    }
}
