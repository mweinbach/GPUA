// Ported from: crates/rune/src/playground/testing.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The playground in an app's tests: ``App/headlessRuntime(_:_:)`` attaches it, and
//! ``Runtime/openPlayground(_:_:)`` opens a story the way `--playground NAME --variant V` does.

private let NO_PLAYGROUND_MESSAGE = "this runtime has no playground: build it with App::headless_runtime from an App whose App::playground is enabled"

private final class WeakHeadlessRtBox {
    weak var rt: AnyObject?
}

extension App {
    /// Attaches a ``Playground`` to this app's window (`crates/rune/src/app.rs`).
    public func playground(_ playground: Playground<S>) -> App<S> {
        attachedPlayground = playground
        return self
    }

    /// A runtime for this app with no window, as a headless render builds it: the state from
    /// `AppSpec.init` (or ``App/initState(_:)``'s closure), `AppSpec.setup` given a waker that
    /// does nothing, the app's fonts, `poll` and `onKey`, and its ``App/playground(_:)``
    /// attached, closed, if it's enabled (by default, in debug builds, so in `swift test`).
    /// Nothing is read from the command line. Call ``Runtime/frame(_:)`` to build the first frame.
    public func headlessRuntime(_ size: (Float, Float), _ env: Env) -> Runtime<S> {
        let pg = attachedPlayground as? Playground<S>
        attachedPlayground = nil
        let inset = winOptions.borderless ? 0.0 : chromeSpec.titlebarInset()
        let onFocus = onFocusHook
        let onIme = onImeHook
        let modKeys = modifierKeysFlag
        let tabVisits = tabVisitsControlsFlag
        let srgb = srgbBlendFlag

        var (appSpec, state, _) = intoParts(scene: nil)
        let rawView = appSpec.view
        let rtBox = WeakHeadlessRtBox()
        appSpec.view = { s, cx in
            if let rtObj = rtBox.rt {
                let hs = windowHostState(for: rtObj)
                if hs.hasHostPollBridge && !hs.insideHostCommit {
                    return el()
                }
            }
            return rawView(s, cx)
        }
        let rt = toolingRuntimeFor(spec: appSpec, state: state, size: size, env: env, waker: {})
        rtBox.rt = rt
        if let pg, pg.isEnabled() {
            let live = PlaygroundLive<S>(playground: pg, spec: appSpec, menu: false)
            rt.hostInstallPlayground(live, appPoll: appSpec.poll)
        } else {
            rt.hostInstallSpineFrameBridge(appPoll: appSpec.poll)
        }
        rt.hostSetTitlebarInset(inset)
        rt.hostSetAppOnFocus(onFocus)
        rt.hostSetAppOnIme(onIme)
        let hs = windowHostState(for: rt)
        hs.modifierKeys = modKeys
        hs.tabVisitsControls = tabVisits
        rt.srgbBlend = srgb
        return rt
    }
}

extension WindowSpec {
    /// Attaches a ``Playground`` to this window (`crates/rune/src/windows.rs`).
    public func playground(_ playground: Playground<S>) -> WindowSpec<S> {
        var copy = self
        copy.attachedPlayground = playground
        return copy
    }
}

extension Runtime {
    func playgroundOpenCheck(_ story: String, _ variant: String? = nil) -> Result<Void, ToolingCliError> {
        guard let live = hostPlayground() else {
            return .failure(ToolingCliError(NO_PLAYGROUND_MESSAGE))
        }
        return live.openAt(story, variant)
    }

    func playgroundTriggerCheck(_ key: Character) -> Result<PlaygroundRequest, ToolingCliError> {
        guard let live = hostPlayground(), live.isOpen() else {
            return .failure(ToolingCliError("the playground isn't open: call Runtime::open_playground first"))
        }
        let lower = Character(String(key).lowercased())
        guard let req = live.triggerRequest(lower) else {
            let keys = live.triggers().map { "'\($0.0)' (\($0.1))" }
            return .failure(ToolingCliError("\(live.path(live.selected).debugDescription) has no trigger on '\(key)'; it has: \(keys.joined(separator: ", "))"))
        }
        return .success(req)
    }

    /// Opens the playground at `story` (its `"Group/Name"` path, its name, or its path's
    /// ``playground/slug(_:)``), on `variant` (by number from 1, or by name) if given,
    /// as `--playground NAME --variant V` and ``Tx/openPlaygroundAt(_:_:)`` do.
    public func openPlayground(_ story: String, _ variant: String? = nil) {
        if case .failure(let err) = playgroundOpenCheck(story, variant) {
            preconditionFailure(err.message)
        }
        settlePlayground(.open(story))
    }

    /// Runs the open story's trigger on `key`, as its letter or its button in the side column
    /// does: `'r'` makes the stage again and replays.
    public func playgroundTrigger(_ key: Character) {
        switch playgroundTriggerCheck(key) {
        case .success(let req):
            settlePlayground(req)
        case .failure(let err):
            preconditionFailure(err.message)
        }
    }

    /// Queues `request` as a handler does, then takes two frames that advance no time: the
    /// first applies it, the second runs the steps it made due now.
    private func settlePlayground(_ request: PlaygroundRequest) {
        hostUpdate { _, tx in
            tx.pgPush(request)
        }
        _ = hostFrame(0.0)
        _ = hostFrame(0.0)
    }

    /// The open story's stage state: a scene's `S`, or a ``Story``'s own state. `nil` while
    /// the playground is closed, on a ``Playground/page(_:_:)``, or when `P` isn't the stage's
    /// type. `self.state` stays the app's real state throughout.
    public func playgroundState<P>(_ type: P.Type = P.self) -> P? {
        _ = type
        return hostPlayground()?.stageStateValue() as? P
    }

    /// The element keyed or pathed `key` on the open story's stage, as of the last frame: its
    /// rect, text, role and the rest. The playground's list and side column aren't searched.
    public func playgroundElement(_ key: String) -> ElementInfo? {
        guard let live = hostPlayground(), live.isOpen() else { return nil }
        let all = hostElements()
        guard let idx = playgroundStageElement(all, key) else { return nil }
        return all[idx]
    }
}

/// The index in `all` of the element keyed or pathed `key` on the stage, not exiting.
func playgroundStageElement(_ all: [ElementInfo], _ key: String) -> Int? {
    for i in all.indices {
        let info = all[i]
        guard !info.exiting, (info.key == key || info.path == key) else { continue }
        var cur: Int? = i
        var inStage = false
        while let j = cur {
            if let k = all[j].key, playgroundIsStage(k) {
                inStage = true
                break
            }
            cur = all[j].parent
        }
        if inStage {
            return i
        }
    }
    return nil
}
