// Ported from: crates/gpui_windows/src/direct_manipulation.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Windows)
import Foundation
import GPUI
#if canImport(CWinSys)
import CWinSys
#endif

// PORT NOTE: DirectManipulationHandler coordinates DirectManipulation COM interfaces to deliver smooth precision touchpad gestures.
public final class DirectManipulationHandler: @unchecked Sendable {
    private var handlerPtr: UnsafeMutableRawPointer?

    public init(window: WinHandle, scaleFactor: Float) {
        self.handlerPtr = cwin_dm_create_handler(window, scaleFactor)
    }

    deinit {
        if let ptr = handlerPtr {
            cwin_dm_destroy_handler(ptr)
        }
    }

    public func setScaleFactor(_ scaleFactor: Float) {
        guard let ptr = handlerPtr else { return }
        cwin_dm_set_scale_factor(ptr, scaleFactor)
    }

    public func onPointerHitTest(_ wparam: UInt) {
        guard let ptr = handlerPtr else { return }
        cwin_dm_on_pointer_hit_test(ptr, wparam)
    }

    public func update() {
        guard let ptr = handlerPtr else { return }
        cwin_dm_update(ptr)
    }

    public func drainEvents() -> [PlatformInput] {
        guard let ptr = handlerPtr else { return [] }
        var rawEvents = [CWinDmEvent](repeating: CWinDmEvent(), count: 64)
        var count: UInt32 = 0
        let ret = cwin_dm_drain_events(ptr, &rawEvents, 64, &count)
        guard ret == 0, count > 0 else { return [] }

        var result: [PlatformInput] = []
        result.reserveCapacity(Int(count))
        let modifiers = current_modifiers()

        for i in 0..<Int(count) {
            let ev = rawEvents[i]
            let pos = Point(x: Pixels(ev.x), y: Pixels(ev.y))
            let phase: TouchPhase = (ev.touch_phase == 0) ? .started : ((ev.touch_phase == 1) ? .moved : .ended)

            if ev.type == 1 { // Scroll
                let delta = Point(x: Pixels(ev.delta_x), y: Pixels(ev.delta_y))
                result.append(PlatformInput.scrollWheel(ScrollWheelEvent(
                    position: pos,
                    delta: .pixels(delta),
                    modifiers: modifiers,
                    touchPhase: phase
                )))
            } else if ev.type == 2 { // Pinch
                result.append(PlatformInput.pinch(PinchEvent(
                    position: pos,
                    delta: ev.scale_delta,
                    modifiers: modifiers,
                    phase: phase
                )))
            }
        }
        return result
    }
}

#endif
