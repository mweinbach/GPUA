// Ported from: crates/scheduler/src/clock.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

public protocol Clock: Sendable {
    func utcNow() -> Date
    func now() -> ContinuousClock.Instant
}

// PORT NOTE: Synchronized via internal NSLock protecting simulated instants and dates across threads.
public final class TestClock: Clock, @unchecked Sendable {
    private struct State {
        var now: ContinuousClock.Instant
        var utcNow: Date
    }

    private let lock = NSLock()
    private var state: State

    public init() {
        let formatter = ISO8601DateFormatter()
        let startDate = formatter.date(from: "2025-07-01T23:59:58Z") ?? Date(timeIntervalSince1970: 1751414398)
        self.state = State(now: .now, utcNow: startDate)
    }

    public func setUtcNow(_ now: Date) {
        lock.lock()
        defer { lock.unlock() }
        state.utcNow = now
    }

    public func advance(by duration: Duration) {
        lock.lock()
        defer { lock.unlock() }
        state.now = state.now.advanced(by: duration)
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18
        state.utcNow = state.utcNow.addingTimeInterval(seconds)
    }

    public func utcNow() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return state.utcNow
    }

    public func now() -> ContinuousClock.Instant {
        lock.lock()
        defer { lock.unlock() }
        return state.now
    }
}
