// Ported from: crates/rune/src/runtime/system_settings.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Environment dark mode, pixel scale, system accent, reduced motion, sRGB blend, and font smoothing setters.

extension Runtime {
    public func setEnv(_ next: Env) {
        guard env != next else { return }
        let scaleChanged = env.scale != next.scale
        env = next
        if scaleChanged {
            scene.setPixelScale(max(next.scale, 0.001))
            textLayoutCache.removeAll()
        }
        markDirty(CommitWhy.ENV)
    }

    public func setSystemDark(_ dark: Bool) {
        var next = env
        next.systemDark = dark
        setEnv(next)
    }

    public func setScale(_ scale: Float) {
        let clamped = max(scale, 0.1)
        guard env.scale != clamped else { return }
        var next = env
        next.scale = clamped
        setEnv(next)
    }

    public func setSystemAccent(_ accent: SystemAccent) {
        guard systemAccent != accent else { return }
        systemAccent = accent
        memo.clear()
        markDirty(CommitWhy.ACCENT)
    }

    public func setSystemReducedMotion(_ reduced: Bool) {
        guard systemReducedMotion != reduced else { return }
        systemReducedMotion = reduced
        reducedMotion = reduced
        scene.setReducedMotion(reduced)
        markDirty(CommitWhy.REDUCED_MOTION)
    }

    public func setReducedMotion(_ reduced: Bool) {
        guard reducedMotion != reduced else { return }
        reducedMotion = reduced
        scene.setReducedMotion(reduced)
        markDirty(CommitWhy.REDUCED_MOTION)
    }

    public func setTimeScale(_ scale: Float) {
        let clamped = min(max(scale, 0.0), 8.0)
        guard timeScale != clamped else { return }
        timeScale = clamped
    }

    public func srgbBlendEnabled() -> Bool {
        srgbBlend
    }

    public func setSrgbBlend(_ enabled: Bool) {
        guard srgbBlend != enabled else { return }
        srgbBlend = enabled
        markDirty(CommitWhy.BLEND)
    }

    public func fontSmoothing() -> FontSmoothing {
        text.fontSmoothing()
    }

    public func setFontSmoothing(_ mode: FontSmoothing) {
        guard text.fontSmoothing() != mode else { return }
        text.setFontSmoothing(mode)
        markDirty(CommitWhy.FONTS)
    }

    public func setTitlebarInset(_ inset: Float) {
        guard titlebarInset != inset else { return }
        titlebarInset = inset
        memo.clear()
        markDirty(CommitWhy.ENV)
    }

    public func setChrome(_ next: Chrome) {
        guard chrome != next else { return }
        chrome = next
        titlebarInset = next.titlebarInset()
        memo.clear()
        markDirty(CommitWhy.ENV)
    }

    public func setTabVisitsControls(_ on: Bool) {
        tabVisitsControls = on
    }

    public func resize(_ width: Float, _ height: Float, _ nextEnv: Env? = nil) {
        let w = max(width, 0.0)
        let h = max(height, 0.0)
        let vpChanged = viewport.0 != w || viewport.1 != h
        let envChanged = nextEnv != nil && nextEnv != env
        guard vpChanged || envChanged else { return }
        if vpChanged {
            viewport = (w, h)
            markDirty(CommitWhy.RESIZE)
        }
        if let nextEnv, envChanged {
            env = nextEnv
            markDirty(CommitWhy.ENV)
        }
    }
}
