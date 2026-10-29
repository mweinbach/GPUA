// Swift-only: unit tests for WindowsDispatcher task scheduling, priority queues, and wakeups

#if os(Windows)
import Foundation
import Testing
import GPUI
import Scheduler
@testable import GPUIWindows

@Suite("WindowsDispatcherTests")
struct WindowsDispatcherTests {
    @Test
    func testDispatcherMainThreadDetection() {
        let dispatcher = WindowsDispatcher()
        #expect(dispatcher.isMainThread() == true)
        #expect(dispatcher.asTest() == nil)
        #expect(dispatcher.now().timeIntervalSince1970 > 0)
    }

    @Test
    func testDispatcherPriorityQueueOrdering() {
        let dispatcher = WindowsDispatcher()
        let executionOrder = LockedBox<[String]>([])

        // Enqueue in mixed order
        dispatcher.dispatchOnMainThread({
            executionOrder.withValue { $0.append("low1") }
        }, priority: .low)

        dispatcher.dispatchOnMainThread({
            executionOrder.withValue { $0.append("medium1") }
        }, priority: .medium)

        dispatcher.dispatchOnMainThread({
            executionOrder.withValue { $0.append("high1") }
        }, priority: .high)

        dispatcher.dispatchOnMainThread({
            executionOrder.withValue { $0.append("high2") }
        }, priority: .high)

        dispatcher.dispatchOnMainThread({
            executionOrder.withValue { $0.append("low2") }
        }, priority: .low)

        // Run all foreground tasks
        let ran = dispatcher.runForegroundTasks(timeout: 1.0)
        #expect(ran == 5)
        #expect(executionOrder.withValue { $0 } == ["high1", "high2", "medium1", "low1", "low2"])
    }

// PORT NOTE: LockedBox coordinates mutable test state across thread boundaries.
private final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    init(_ value: T) {
        self.value = value
    }

    func withValue<R>(_ body: (inout T) -> R) -> R {
        lock.withLock {
            body(&value)
        }
    }
}

    @Test
    func testDispatcherBackgroundDispatch() async {
        let dispatcher = WindowsDispatcher()
        let box = LockedBox(false)

        dispatcher.dispatch({
            box.withValue { $0 = true }
        }, priority: .high)

        // Poll for background task completion
        for _ in 0..<50 {
            if box.withValue({ $0 }) { break }
            try? await _Concurrency.Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(box.withValue({ $0 }) == true)
    }

    @Test
    func testDispatcherTimerResolution() {
        let dispatcher = WindowsDispatcher()
        let cleanup = dispatcher.increaseTimerResolution()
        cleanup()
    }
}

#endif
