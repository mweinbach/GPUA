// Ported from: crates/rune/src/overlay/frame.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Per-tick overlay stepping, pointer following, and wake deadline calculation (`crates/rune/src/overlay/frame.rs`).

let OVERLAY_POINTER_POLL: Duration = .milliseconds(32)

extension Overlay {
    func stepOverlayFrame(now: RuneInstant = .now(), displays: [Display] = [Display()]) {
        let requestedRedraw = drainOverlayRequests(displays: displays)

        if !visible {
            if hiddenPace.takeDue(now: now, hasPoll: rt.poll != nil) {
                rt.hostPollHidden()
            }
            if timerWantsFrame(rt: rt, now: now) {
                let dt = drainFrame(clock: &clock, rt: rt, now: now)
                _ = rt.hostFrame(dt)
                clock.pause()
            }
            return
        }

        if options.followPointer && options.display == .underPointer {
            repositionOverlay(displays: displays)
        }

        if requestedRedraw
            || timerWantsFrame(rt: rt, now: now)
            || rt.hostStale()
            || clock.isRunning
            || (window?.takeRedrawRequested() == true)
            || (compositorAnimating?() == true)
        {
            _ = drawOverlay(now: now)
        }
    }

    func computeOverlayWakeDeadline(now: RuneInstant) -> RuneInstant? {
        var earliest = timerDeadline(rt: rt, now: now, covered: !visible, hiddenPace: &hiddenPace)

        func merge(_ candidate: RuneInstant?) {
            guard let c = candidate else { return }
            if let cur = earliest {
                earliest = min(cur, c)
            } else {
                earliest = c
            }
        }

        if visible {
            if options.followPointer && options.display == .underPointer {
                merge(now.adding(OVERLAY_POINTER_POLL))
            }
            if clock.isRunning || rt.hostStale() || (compositorAnimating?() == true) {
                merge(now.adding(FIRST_FRAME_BUDGET))
            }
        }
        return earliest
    }
}
