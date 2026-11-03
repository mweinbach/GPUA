// Ported from: crates/rune/src/runtime/input/gesture.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Trackpad pinch-magnify and two-finger rotate gesture state & accumulation.

public struct ActiveGestureState: Sendable, Equatable {
    public var x: Float = 0.0
    public var y: Float = 0.0
    public var scale: Float = 1.0
    public var rotation: Float = 0.0
    public var active: Bool = false

    public init() {}
}

func accumulateMagnifyScale(_ current: Float, delta: Float, minScale: Float = 0.25, maxScale: Float = 8.0) -> Float {
    let next = current * max(1.0 + delta, 0.1)
    return min(max(next, minScale), maxScale)
}

func accumulateRotateRadians(_ current: Float, deltaRadians: Float) -> Float {
    current + deltaRadians
}

extension Runtime {
    public func magnify(_ ev: MagnifyEvent) {
        heldMods = ev.mods
        gestureState.x = ev.x
        gestureState.y = ev.y
        switch ev.phase {
        case .began, .started:
            gestureState.active = true
            gestureState.scale = accumulateMagnifyScale(1.0, delta: ev.delta)
        case .moved:
            gestureState.active = true
            gestureState.scale = accumulateMagnifyScale(gestureState.scale, delta: ev.delta)
        case .ended, .cancelled:
            gestureState.active = false
            if ev.phase == .cancelled {
                gestureState.scale = 1.0
            }
        }
        eventLog.push(t: t, frame: frameIndex, kind: "magnify", detail: "\(ev.phase):\(ev.delta)")
    }

    public func rotate(_ ev: RotateEvent) {
        heldMods = ev.mods
        gestureState.x = ev.x
        gestureState.y = ev.y
        switch ev.phase {
        case .began, .started:
            gestureState.active = true
            gestureState.rotation = accumulateRotateRadians(0.0, deltaRadians: ev.delta)
        case .moved:
            gestureState.active = true
            gestureState.rotation = accumulateRotateRadians(gestureState.rotation, deltaRadians: ev.delta)
        case .ended, .cancelled:
            gestureState.active = false
            if ev.phase == .cancelled {
                gestureState.rotation = 0.0
            }
        }
        eventLog.push(t: t, frame: frameIndex, kind: "rotate", detail: "\(ev.phase):\(ev.delta)")
    }

    public func currentGesture() -> ActiveGestureState {
        gestureState
    }
}
