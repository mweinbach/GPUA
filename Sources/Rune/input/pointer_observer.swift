// Ported from: crates/rune/src/input/pointer_observer.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

private struct PointerSample {
    var canvas: [Int32] = [0, 0, 0, 0]
    var displays: [[Int32]] = []
    var follow: Bool = false
    var inside: Bool = false
    var display: Int? = nil
    var last: (Int32, Int32)? = nil
    var pending: (Int32, Int32)? = nil
}

/// A small native-pointer mailbox. Global movement outside the canvas wakes the owner only
/// on exit or a followed-display change. No application state or native API runs under its lock.
// PORT NOTE: Mutable sample state is synchronized via `lock: LiveLock`.
internal final class PointerObserver: @unchecked Sendable {
    private let lock = LiveLock()
    private var sample = PointerSample()
    private let wake: Waker?

    internal init(_ wake: Waker? = nil) {
        self.wake = wake
    }

    internal static func new(_ wake: Waker?) -> PointerObserver {
        PointerObserver(wake)
    }

    internal func needsGeometry(_ canvas: [Int32], _ follow: Bool) -> Bool {
        lock.withLock {
            sample.canvas != canvas || sample.follow != follow
        }
    }

    internal func configure(_ canvas: [Int32], _ displays: [[Int32]], _ follow: Bool) {
        lock.withLock {
            if sample.canvas != canvas || sample.displays != displays || sample.follow != follow {
                sample.last = nil
            }
            sample.canvas = canvas
            sample.displays = displays
            sample.follow = follow
        }
    }

    internal func take() -> (Int32, Int32)? {
        lock.withLock {
            let p = sample.pending
            sample.pending = nil
            return p
        }
    }

    internal func observe(_ point: (Int32, Int32)) {
        let shouldWake: Bool = lock.withLock {
            func contains(_ r: [Int32]) -> Bool {
                guard r.count >= 4 else { return false }
                return point.0 >= r[0] && point.1 >= r[1] && point.0 < r[2] && point.1 < r[3]
            }
            let inside = contains(sample.canvas)
            let display = sample.displays.firstIndex(where: contains) ?? sample.display
            let changed = sample.follow && display != sample.display
            let interested = inside || sample.inside || changed
            sample.inside = inside
            sample.display = display
            let sameAsLast = sample.last.map { $0.0 == point.0 && $0.1 == point.1 } ?? false
            if interested && !sameAsLast {
                sample.last = point
                sample.pending = point
                return true
            }
            return false
        }
        if shouldWake {
            wake?()
        }
    }
}
