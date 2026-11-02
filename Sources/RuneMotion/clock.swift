// Ported from: crates/rune-motion/src/clock.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

/// Animation time `τ = base + (host − anchor) · scale`, re-anchored whenever the scale changes so
/// running animations continue from where they are.
///
/// - Display mode: call ``Clock/frame(_:)`` with the display link's **target presentation timestamp**,
///   so a late frame still lands on the right pose.
/// - Manual mode: ``Clock/step()`` advances exactly one frame at `hz`; ``Clock/seek(_:)`` jumps. Tests
///   and frame traces are bit-identical run to run.
public struct Clock: Sendable {
    private var _base: Double
    private var _anchor: Double
    private var _scale: Double
    private var _paused: Bool
    private var _manualHz: Double?
    private var _frame: UInt64
    private var _now: Double

    private init(
        base: Double,
        anchor: Double,
        scale: Double,
        paused: Bool,
        manualHz: Double?,
        frame: UInt64,
        now: Double
    ) {
        self._base = base
        self._anchor = anchor
        self._scale = scale
        self._paused = paused
        self._manualHz = manualHz
        self._frame = frame
        self._now = now
    }

    /// Driven by host timestamps (seconds, any epoch).
    public static func display() -> Clock {
        Clock(
            base: 0.0,
            anchor: .nan,
            scale: 1.0,
            paused: false,
            manualHz: nil,
            frame: 0,
            now: 0.0
        )
    }

    /// Driven by `step()` at a fixed rate, starting at τ = 0.
    public static func manual(_ hz: Double) -> Clock {
        precondition(hz > 0.0)
        var c = Clock.display()
        c._manualHz = hz
        return c
    }

    /// Animation time for a host timestamp, without advancing.
    public func timeAt(_ host: Double) -> Double {
        if _anchor.isNaN || _paused {
            return _base
        }
        return _base + (host - _anchor) * _scale
    }

    /// Advances to the frame presented at host time `host` and returns τ.
    @discardableResult
    public mutating func frame(_ host: Double) -> Double {
        if _anchor.isNaN {
            _anchor = host
        }
        _now = timeAt(host)
        _frame += 1
        return _now
    }

    /// Manual mode: one frame (`1/hz` seconds × scale, or nothing while paused). Returns τ.
    @discardableResult
    public mutating func step() -> Double {
        guard let hz = _manualHz else {
            preconditionFailure("Clock.step needs Clock.manual")
        }
        _frame += 1
        if !_paused {
            _base += _scale / hz
        }
        _now = _base
        return _now
    }

    /// Jumps to τ = `t` (scrubbing, deterministic tests).
    public mutating func seek(_ t: Double) {
        _base = t
        _now = t
        if !_anchor.isNaN {
            _anchor = .nan
        }
    }

    /// Slow motion (< 1) or fast-forward (> 1), clamped to [0.02, 4]. Re-anchors at `host`.
    public mutating func setScale(_ scale: Double, _ host: Double) {
        let clamped = min(max(scale, 0.02), 4.0)
        if _manualHz == nil && !_anchor.isNaN {
            _base = timeAt(host)
            _anchor = host
        }
        _scale = clamped
    }

    public mutating func pause(_ host: Double) {
        if !_paused {
            if _manualHz == nil && !_anchor.isNaN {
                _base = timeAt(host)
            }
            _paused = true
        }
    }

    public mutating func resume(_ host: Double) {
        if _paused {
            _paused = false
            if _manualHz == nil {
                _anchor = host
            }
        }
    }

    public func now() -> Double {
        _now
    }

    public func scale() -> Double {
        _scale
    }

    public func isPaused() -> Bool {
        _paused
    }

    public func frameCount() -> UInt64 {
        _frame
    }

    /// The manual frame interval, if any.
    public func frameInterval() -> Double? {
        _manualHz.map { 1.0 / $0 }
    }
}
