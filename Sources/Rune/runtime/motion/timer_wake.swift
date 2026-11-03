// Ported from: crates/rune/src/runtime/motion/timer_wake.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Scheduled timer deadlines (`Tx.wakeAfter(seconds)`) sorted min-first for virtual & host clocks.

struct TimerWakeQueue: Sendable {
    /// Sorted ascending deadlines in runtime `clock` seconds.
    private(set) var deadlines: [Double] = []

    mutating func schedule(now: Double, after seconds: Double) {
        let clamped = max(seconds, 0.0)
        let due = now + clamped
        // Insert keeping ascending order, coalescing near-identical deadlines within 0.1 ms
        for existing in deadlines where abs(existing - due) < 1e-4 {
            return
        }
        let idx = deadlines.firstIndex(where: { $0 > due }) ?? deadlines.count
        deadlines.insert(due, at: idx)
    }

    /// Pop all deadlines `<= now`; returns `true` if at least one timer fired.
    mutating func fireDue(now: Double) -> Bool {
        var fired = 0
        while let first = deadlines.first, first <= now + 1e-9 {
            deadlines.removeFirst()
            fired += 1
        }
        return fired > 0
    }

    /// Seconds until next deadline from `now`, or `nil` if no timers are pending.
    func nextWakeDelay(now: Double) -> Double? {
        guard let first = deadlines.first else { return nil }
        return max(0.0, first - now)
    }

    var isEmpty: Bool {
        deadlines.isEmpty
    }

    mutating func clear() {
        deadlines.removeAll()
    }
}

extension Runtime {
    public func nextWakeAfter() -> Double? {
        let scheduled = timerWakes.nextWakeDelay(now: clock)
        let pending = pendingWakes.map { max(0.0, $0) }.min()
        switch (scheduled, pending) {
        case (let a?, let b?): return min(a, b)
        case (let a?, nil): return a
        case (nil, let b?): return b
        case (nil, nil): return nil
        }
    }
}
