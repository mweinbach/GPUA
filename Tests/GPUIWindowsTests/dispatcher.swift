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
        var executionOrder: [String] = []

        // Enqueue in mixed order
        dispatcher.dispatchOnMainThread({
            executionOrder.append("low1")
        }, priority: .low)

        dispatcher.dispatchOnMainThread({
            executionOrder.append("medium1")
        }, priority: .medium)

        dispatcher.dispatchOnMainThread({
            executionOrder.append("high1")
        }, priority: .high)

        dispatcher.dispatchOnMainThread({
            executionOrder.append("high2")
        }, priority: .high)

        dispatcher.dispatchOnMainThread({
            executionOrder.append("low2")
        }, priority: .low)

        // Run all foreground tasks
        let ran = dispatcher.runForegroundTasks(timeout: 1.0)
        #expect(ran == 5)
        #expect(executionOrder == ["high1", "high2", "medium1", "low1", "low2"])
    }

    @Test
    func testDispatcherBackgroundDispatch() async {
        let dispatcher = WindowsDispatcher()
        let lock = NSLock()
        var completed = false

        dispatcher.dispatch({
            lock.lock()
            completed = true
            lock.unlock()
        }, priority: .high)

        // Poll for background task completion
        for _ in 0..<50 {
            lock.lock()
            let done = completed
            lock.unlock()
            if done { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        lock.lock()
        let finalDone = completed
        lock.unlock()
        #expect(finalDone == true)
    }

    @Test
    func testDispatcherTimerResolution() {
        let dispatcher = WindowsDispatcher()
        let cleanup = dispatcher.increaseTimerResolution()
        cleanup()
    }
}

#endif
