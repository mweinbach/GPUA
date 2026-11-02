// Ported from: crates/rune/src/app.rs
// Upstream commit: 5f6d53ddae78
// Port status: in-progress

//! The app's lifetime beside its window (`App`, `AppHandle`).

/// Thread-safe handle to open, focus, close, update, or quit a running `App<S>`.
// PORT NOTE: Synchronized via `lock` (`LiveLock`), mirroring `Arc<Shared<S>>` in `crates/rune/src/app.rs`.
public final class AppHandle<S>: @unchecked Sendable {
    private let lock = LiveLock()
    private var openRequested: Bool = false
    private var quitRequested: Bool = false
    private var updates: [(inout S, inout Tx) -> Bool] = []

    public init() {}

    public func open() {
        lock.withLock { openRequested = true }
    }

    public func close() {
        lock.withLock { openRequested = false }
    }

    public func quit() {
        lock.withLock { quitRequested = true }
    }

    public func update(_ f: @escaping @Sendable (inout S, inout Tx) -> Void) {
        lock.withLock {
            updates.append { state, tx in
                f(&state, &tx)
                return true
            }
        }
    }

    func drainUpdates(into state: inout S, tx: inout Tx) -> Bool {
        let pending = lock.withLock { () -> [(inout S, inout Tx) -> Bool] in
            let out = updates
            updates.removeAll()
            return out
        }
        var changed = false
        for u in pending {
            if u(&state, &tx) {
                changed = true
            }
        }
        return changed
    }
}

/// An `AppSpec` with its lifetime and window policy.
public final class App<S> {
    var spec: AppSpec<S>
    var chromeSpec: Chrome = .DEFAULT
    var openOnStart: Bool = true
    var keepRunningFlag: Bool = false
    var releaseGpuFlag: Bool = false
    var accessoryFlag: Bool = false
    var standardMenusFlag: Bool = false
    var srgbBlendFlag: Bool = true
    var fontSmoothingMode: FontSmoothing = .default
    var fitContentHeightFlag: Bool = false
    var canvasIdValue: String? = nil
    var fullViewportFlag: Bool = false
    var modifierKeysFlag: Bool = false
    var tabVisitsControlsFlag: Bool = false
    private let sharedHandle = AppHandle<S>()

    public init(_ spec: AppSpec<S>) {
        self.spec = spec
    }

    public static func new(_ spec: AppSpec<S>) -> App<S> {
        App(spec)
    }

    public func handle() -> AppHandle<S> {
        sharedHandle
    }

    public func srgbBlend(_ enabled: Bool) -> App<S> {
        srgbBlendFlag = enabled
        return self
    }

    public func fontSmoothing(_ mode: FontSmoothing) -> App<S> {
        fontSmoothingMode = mode
        return self
    }

    public func chrome(_ chrome: Chrome) -> App<S> {
        chromeSpec = chrome
        return self
    }

    public func fitContentHeight() -> App<S> {
        fitContentHeightFlag = true
        return self
    }

    public func canvasId(_ id: String) -> App<S> {
        canvasIdValue = id
        return self
    }

    public func fullViewport() -> App<S> {
        fullViewportFlag = true
        return self
    }

    public func modifierKeys() -> App<S> {
        modifierKeysFlag = true
        return self
    }

    public func tabVisitsControls(_ on: Bool) -> App<S> {
        tabVisitsControlsFlag = on
        return self
    }

    public func windowless() -> App<S> {
        openOnStart = false
        keepRunningFlag = true
        return self
    }

    public func keepRunning() -> App<S> {
        keepRunningFlag = true
        return self
    }

    public func releaseGpuWhenClosed() -> App<S> {
        releaseGpuFlag = true
        return self
    }

    public func accessory() -> App<S> {
        accessoryFlag = true
        return self
    }

    public func standardMenus() -> App<S> {
        standardMenusFlag = true
        return self
    }

    public func run() {
        let initial = spec.`init`()
        let rt = Runtime.withText(
            initial,
            spec.view,
            spec.size,
            Env(),
            TextSystem.forWindow(spec.fonts, spec.families)
        )
        rt.poll = spec.poll
        rt.onKey = spec.onKey
        _ = rt.frame(0.0)
    }
}
