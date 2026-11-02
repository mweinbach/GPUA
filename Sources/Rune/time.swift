// Ported from: crates/rune/src/time.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Monotonic clock instant (`rune::time::Instant`).

// PORT NOTE: Uses Swift's cross-platform `ContinuousClock.Instant` wrapped in `RuneInstant`
// (`time.Instant`) so `.now()`, `.elapsed()`, and arithmetic match Rust's `std::time::Instant` / `web_time::Instant`.
public struct RuneInstant: Sendable, Equatable, Comparable, Hashable {
    public let raw: ContinuousClock.Instant

    public init(_ raw: ContinuousClock.Instant = ContinuousClock.now) {
        self.raw = raw
    }

    public static func now() -> RuneInstant {
        RuneInstant(ContinuousClock.now)
    }

    public func durationSince(_ earlier: RuneInstant) -> Duration {
        let d = earlier.raw.duration(to: raw)
        return d < .zero ? .zero : d
    }

    public func elapsed() -> Duration {
        Self.now().durationSince(self)
    }

    public func elapsedSeconds() -> Double {
        let d = elapsed()
        return Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18
    }

    public func adding(_ duration: Duration) -> RuneInstant {
        RuneInstant(raw.advanced(by: duration))
    }

    public static func < (lhs: RuneInstant, rhs: RuneInstant) -> Bool {
        lhs.raw < rhs.raw
    }
}

public enum time {
    public typealias Instant = RuneInstant
}
