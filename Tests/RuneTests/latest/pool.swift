// Tests ported from: crates/rune/src/latest/pool.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if !os(WASI)
import Foundation
import Testing
@testable import Rune

private final class DummyTask: LatestDrive, @unchecked Sendable {
    private let lock = LiveLock()
    private var runs = 0

    func drive() {
        lock.withLock { runs += 1 }
    }

    var runCount: Int {
        lock.withLock { runs }
    }
}

@Suite("LatestPoolTests")
struct LatestPoolTests {
    @Test("pool caps threads and exits workers after idle timeout")
    func poolCapsThreadsAndExitsAfterIdle() {
        let pool = LatestPool(max: 2, idleExit: .milliseconds(60))
        #expect(pool.threads() == (0, 0))
        let tasks = (0..<8).map { _ in DummyTask() }
        for task in tasks {
            pool.submit(task)
            #expect(pool.threads().0 <= 2)
        }
        let deadline = Date(timeIntervalSinceNow: 5.0)
        while tasks.contains(where: { $0.runCount == 0 }) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.002)
        }
        #expect(tasks.allSatisfy { $0.runCount == 1 })
        #expect(pool.threads().1 <= 2)

        let exitDeadline = Date(timeIntervalSinceNow: 5.0)
        while pool.threads().0 > 0 && Date() < exitDeadline {
            Thread.sleep(forTimeInterval: 0.005)
        }
        #expect(pool.threads().0 == 0)
    }
}
#endif
