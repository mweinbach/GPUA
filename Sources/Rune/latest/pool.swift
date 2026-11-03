// Ported from: crates/rune/src/latest/pool.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if !os(WASI)
import Foundation

/// Threads at most, shared by every ``Latest``: enough that a newer request needn't wait behind
/// a slow stale one, few enough that typing never piles threads up.
internal let LATEST_MAX_THREADS: Int = 4
internal let LATEST_IDLE_EXIT: Duration = .seconds(10)

/// What a worker runs: one ``Latest``'s newest request, after its debounce.
internal protocol LatestDrive: AnyObject, Sendable {
    func drive()
}

// PORT NOTE: All mutable worker pool state (queue, threads, idle, started) is guarded by `condition: NSCondition`.
internal final class LatestPool: @unchecked Sendable {
    private let condition = NSCondition()
    private var queue: [any LatestDrive] = []
    private var head: Int = 0
    private var threadCount: Int = 0
    private var idleCount: Int = 0
    private var startedCount: Int = 0

    private let maxThreads: Int
    private let idleExitSeconds: TimeInterval

    internal static let shared = LatestPool(max: LATEST_MAX_THREADS, idleExit: LATEST_IDLE_EXIT)

    internal init(max: Int, idleExit: Duration) {
        self.maxThreads = Swift.max(1, max)
        let comps = idleExit.components
        self.idleExitSeconds = Swift.max(
            0.0,
            Double(comps.seconds) + Double(comps.attoseconds) * 1e-18
        )
    }

    private var queuedCount: Int {
        queue.count - head
    }

    private func popTaskLocked() -> (any LatestDrive)? {
        guard head < queue.count else { return nil }
        let task = queue[head]
        head += 1
        if head >= 32 && head * 2 >= queue.count {
            queue.removeFirst(head)
            head = 0
        } else if head == queue.count {
            queue.removeAll(keepingCapacity: true)
            head = 0
        }
        return task
    }

    internal func submit(_ task: any LatestDrive) {
        condition.lock()
        queue.append(task)
        condition.signal()
        if queuedCount <= idleCount || threadCount >= maxThreads {
            condition.unlock()
            return
        }
        threadCount += 1
        startedCount += 1
        condition.unlock()

        let thread = Thread { [self] in
            self.work()
        }
        thread.name = "rune-latest"
        thread.start()
    }

    private func work() {
        condition.lock()
        while true {
            if let task = popTaskLocked() {
                condition.unlock()
                task.drive()
                condition.lock()
                continue
            }
            idleCount += 1
            let deadline = Date(timeIntervalSinceNow: idleExitSeconds)
            let signaled = condition.wait(until: deadline)
            idleCount -= 1
            if !signaled && queuedCount == 0 {
                threadCount -= 1
                condition.unlock()
                return
            }
            // Even if signaled returns true near deadline or spuriously, check if deadline passed while empty:
            if queuedCount == 0 && Date() >= deadline {
                threadCount -= 1
                condition.unlock()
                return
            }
        }
    }

    /// Live worker threads, and how many ever started.
    internal func threads() -> (Int, Int) {
        condition.lock()
        defer { condition.unlock() }
        return (threadCount, startedCount)
    }
}
#endif
