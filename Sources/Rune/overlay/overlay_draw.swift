// Ported from: crates/rune/src/overlay/draw.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Overlay frame rendering, compositor hook, and presentation deduplication (`crates/rune/src/overlay/draw.rs`).

extension Overlay {
    /// Renders one frame for `Overlay<T>`. Returns `true` while further frames are needed.
    @discardableResult
    func drawOverlay(now: RuneInstant = .now()) -> Bool {
        guard let window else {
            clock.pause()
            return false
        }

        let dt = drainFrame(clock: &clock, rt: rt, now: now)
        let (instances, layers, stats) = rt.hostFrame(dt)
        syncOverlayInputPolicy()
        if !passthrough {
            window.setCursor(rt.hostCursor())
        }

        let size = window.innerSize()
        let clearColor: Color = .TRANSPARENT
        let preRenderCompActive = compositorAnimating?() ?? false
        let nextTickDue = timerWantsFrame(rt: rt, now: now.adding(FIRST_FRAME_BUDGET))

        if compositorRender == nil
            && !preRenderCompActive
            && !nextTickDue
            && presented.unchanged(
                size: size,
                clear: clearColor,
                rt: rt,
                instances: instances,
                layers: layers,
                stats: stats
            )
        {
            clock.pause()
            return false
        }

        if let renderHook = compositorRender {
            let dummyRenderer = Renderer()
            renderHook(rt, dummyRenderer)
        }
        let compActive = compositorAnimating?() ?? false

        window.prePresentNotify()
        surfaceMeter.presented(false)
        drawCount += 1

        var mergedStats = stats
        if compActive {
            mergedStats.animating = true
        }
        presented.settle(
            size: size,
            clear: clearColor,
            rt: rt,
            instances: instances,
            layers: layers,
            stats: mergedStats
        )

        let keepGoing = mergedStats.animating || rt.hostStale() || nextTickDue
        if !keepGoing {
            clock.pause()
        }
        return keepGoing
    }
}
