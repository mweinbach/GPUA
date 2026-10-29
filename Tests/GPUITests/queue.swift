// Tests ported from: crates/gpui/src/queue.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

import Testing
import Scheduler
@testable import GPUI

@Suite("QueueTests")
struct QueueTests {
    @Test
    func all_tasks_get_yielded() throws {
        var (tx, rx): (PriorityQueueSender<Int>?, PriorityQueueReceiver<Int>) = PriorityQueueReceiver.new()
        try tx!.send(priority: .medium, item: 20)
        try tx!.send(priority: .high, item: 30)
        try tx!.send(priority: .low, item: 10)
        try tx!.send(priority: .medium, item: 21)
        try tx!.send(priority: .high, item: 31)

        tx = nil // drop sender

        let collected = Set(rx.iter())
        #expect(collected == Set([30, 31, 20, 21, 10]))
    }

    @Test
    func new_high_prio_task_get_scheduled_quickly() throws {
        let (tx, rx) = PriorityQueueReceiver<Int>.new()
        for _ in 0..<100 {
            try tx.send(priority: .low, item: 1)
        }

        #expect(try rx.pop() == 1)
        try tx.send(priority: .high, item: 3)
        #expect(try rx.pop() == 3)
        #expect(try rx.pop() == 1)
    }
}
