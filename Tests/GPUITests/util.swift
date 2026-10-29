// Tests ported from: crates/gpui/src/util.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

import Testing
import Foundation
@testable import GPUI

@Suite("UtilTests")
struct UtilTests {
    @Test
    func test_with_timeout() async {
        let dispatcher = TestDispatcher.new(seed: 0)
        let executor = BackgroundExecutor(dispatcher: dispatcher)

        let readyTask = GPUI.Task.ready(())
        let res1 = await readyTask.withTimeout(.seconds(1), executor: executor).value
        switch res1 {
        case .success:
            #expect(true)
        case .failure:
            Issue.record("Timeout should be noop")
        }

        let longDuration = Duration.seconds(6000)
        let shortDuration = Duration.seconds(1)
        let slowTask = executor.timer(longDuration)
        let timeoutOp = slowTask.withTimeout(shortDuration, executor: executor)

        executor.advanceClock(.seconds(2))
        let res2 = await timeoutOp.value
        switch res2 {
        case .failure(let err):
            #expect(err == Timeout())
        case .success:
            Issue.record("timeout should have triggered")
        }
    }

    @Test
    func test_fluent_builder() {
        struct Container: FluentBuilder, Equatable {
            var value: Int
        }

        let c = Container(value: 10)
            .when(true) { Container(value: $0.value + 5) }
            .when(false) { Container(value: $0.value + 100) }
            .whenElse(true, then: { Container(value: $0.value * 2) }, else: { $0 })
            .whenSome(Int?(7)) { Container(value: $0.value + $1) }
            .whenNone(Int?.none) { Container(value: $0.value + 3) }

        #expect(c.value == (10 + 5) * 2 + 7 + 3)
    }
}
