// Ported from: crates/rune/src/platform/web/input.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Browser DOM input bridge state: modifier translation, touch pan/tap state machine, and
//! viewport/motion/visibility synchronization.

struct WebTouchState: Sendable {
    var id: UInt64
    var scroll: NodeId?
    var origin: (Float, Float)
    var last: (Float, Float)
    var atSeconds: Double
    var velocity: Float
    var pan: Bool
    /// The pan moves a horizontal viewport (picked when it starts).
    var horizontal: Bool
}

enum WebTouchPhase: Sendable, Equatable {
    case started
    case moved
    case ended
    case cancelled
}

struct WebInputBridge {
    var mods: Mods = Mods()
    var touch: WebTouchState? = nil
    var copyCache: String = ""
    var fitHeight: Bool = false

    init(fitHeight: Bool = false) {
        self.fitHeight = fitHeight
    }

    mutating func handleViewportInsets(_ insets: [Float]) -> Bool {
        let clamped = (0..<4).map { idx -> Float in
            idx < insets.count ? max(insets[idx], 0.0) : 0.0
        }
        let previous = webReplaceSafeArea(clamped)
        return previous != clamped
    }

    /// Processes a single-finger touch event on non-`fitHeight` canvases, returning `(handled, tapPoint)`.
    mutating func handleTouch(
        id: UInt64,
        phase: WebTouchPhase,
        point: (Float, Float),
        nowSeconds: Double
    ) -> (handled: Bool, tapPoint: (Float, Float)?) {
        guard !fitHeight else { return (false, nil) }
        switch phase {
        case .started:
            guard touch == nil else { return (false, nil) }
            touch = WebTouchState(
                id: id,
                scroll: nil,
                origin: point,
                last: point,
                atSeconds: nowSeconds,
                velocity: 0.0,
                pan: false,
                horizontal: false
            )
            return (true, nil)
        case .moved:
            guard var t = touch, t.id == id else { return (false, nil) }
            let dx = point.0 - t.origin.0
            let dy = point.1 - t.origin.1
            if !t.pan && (dx * dx + dy * dy).squareRoot() > 8.0 {
                t.pan = true
                t.horizontal = abs(dx) > abs(dy)
            }
            let along: ((Float, Float)) -> Float = { p in t.horizontal ? p.0 : p.1 }
            let dt = Float(nowSeconds - t.atSeconds)
            if dt > 0.0 {
                t.velocity = (along(point) - along(t.last)) / dt
            }
            t.last = point
            t.atSeconds = nowSeconds
            touch = t
            return (true, nil)
        case .ended, .cancelled:
            guard let t = touch, t.id == id else { return (false, nil) }
            touch = nil
            let tapPoint: (Float, Float)? = (!t.pan && phase == .ended) ? point : nil
            return (true, tapPoint)
        }
    }
}

func webModifiers(shift: Bool, alt: Bool, ctrl: Bool, superKey: Bool) -> Mods {
    Mods(
        shift: shift,
        cmd: superKey || ctrl,
        alt: alt,
        ctrl: ctrl,
        logo: superKey
    )
}
