// Ported from: crates/rune/src/playground/story.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `Story`, and `OwnStory`, which erases its state type so the playground holds stories of any.

/// A story with its own state, made by `init` when it first shows and kept, timers and
/// animations included, until the playground closes. R makes it again. Handlers built for `P`
/// change it.
public struct Story<P> {
    let name: String
    private var initKind: StoryInit<P>
    private var viewFn: (P, Cx<P>) -> El
    private var pollFn: ((inout P, Double, inout Tx) -> Bool)? = nil
    private var frameSize: (Float, Float)? = nil
    private var stageLayout: Stage = .center
    private var triggersList: [PlaygroundTrigger<P>] = []
    private var sideFn: PlaygroundSideView<P>? = nil
    private var sideKeyFn: PlaygroundSideKey<P>? = nil
    private var variantsList: [(String, PlaygroundVariant<P>)] = []

    /// `name` may be a `"Group/Name"` path. `init` and `view` may be closures.
    public init(
        _ name: String,
        _ initState: @escaping () -> P,
        _ view: @escaping (P, Cx<P>) -> El
    ) {
        self.name = name
        self.initKind = .new(initState)
        self.viewFn = view
    }

    public static func new(
        _ name: String,
        _ initState: @escaping () -> P,
        _ view: @escaping (P, Cx<P>) -> El
    ) -> Story<P> {
        Story(name, initState, view)
    }

    /// A story whose state `derive` makes from the app's real state, each time it's made: when
    /// it first shows, and on R. `S` is the playground's app state.
    public static func fromReal<S>(
        _ name: String,
        _ derive: @escaping (S) -> P,
        _ view: @escaping (P, Cx<P>) -> El
    ) -> Story<P> {
        var s = Story(name, { preconditionFailure("unreachable: Story.fromReal uses derive") }, view)
        s.initKind = .real(ObjectIdentifier(S.self)) { realAny in
            guard let typed = realAny as? S else {
                preconditionFailure("checked by Playground.story")
            }
            return derive(typed)
        }
        return s
    }

    /// An overlay's view at its size, in a dashed frame over the stage, with a state made by `init`.
    public static func overlay(
        _ name: String,
        _ spec: OverlaySpec<P>,
        _ initState: @escaping () -> P
    ) -> Story<P> {
        var s = Story(name, initState, spec.view)
        s.frameSize = spec.size
        return s
    }

    /// Called every frame while the story shows, as `AppSpec.poll` is, after its due steps.
    public func poll(_ poll: @escaping (inout P, Double, inout Tx) -> Bool) -> Story<P> {
        var copy = self
        copy.pollFn = poll
        return copy
    }

    /// A trigger: `key` (a letter, or `' '` for Space) runs `run` on the story's state, as its
    /// button in the side column does.
    public func trigger(
        _ key: Character,
        _ label: String,
        _ run: @escaping (inout P, Play<P>) -> Void
    ) -> Story<P> {
        var copy = self
        copy.triggersList.append(makePlaygroundTrigger(key, label, run))
        return copy
    }

    /// ``Story/trigger(_:_:_:)`` with a step that takes just the ``Tx``.
    public func triggerTx(
        _ key: Character,
        _ label: String,
        _ run: @escaping (inout P, inout Tx) -> Void
    ) -> Story<P> {
        var copy = self
        copy.triggersList.append(makePlaygroundTriggerTx(key, label, run))
        return copy
    }

    /// The app's own controls for this story, at the top of the side column.
    public func side(_ view: @escaping (P, Cx<P>) -> El) -> Story<P> {
        var copy = self
        copy.sideFn = { p, _, cx in view(p, cx) }
        copy.sideKeyFn = nil
        return copy
    }

    /// ``Story/side(_:)`` for controls that take keys.
    public func sideKeys(
        _ view: @escaping (P, Bool, Cx<P>) -> El,
        _ key: @escaping (inout P, KeyEvent, inout Tx) -> Bool
    ) -> Story<P> {
        var copy = self
        copy.sideFn = view
        copy.sideKeyFn = key
        return copy
    }

    /// How the stage lays it out.
    public func stage(_ stage: Stage) -> Story<P> {
        var copy = self
        copy.stageLayout = stage
        return copy
    }

    /// A variant: `apply` runs on the state after `init`. Keys 1 to 9, or its row in the side
    /// column, switch between them, making the state again as R does.
    public func variant(_ name: String, _ apply: @escaping (inout P) -> Void) -> Story<P> {
        var copy = self
        copy.variantsList.append((name, apply))
        return copy
    }

    func realStateType() -> ObjectIdentifier? {
        switch initKind {
        case .new: return nil
        case .real(let id, _): return id
        }
    }

    fileprivate static func staged(_ stage: AnyObject) -> PlaygroundStaged<P> {
        guard let typed = stage as? PlaygroundStaged<P> else {
            preconditionFailure("a story's stage is its own")
        }
        return typed
    }
}

private enum StoryInit<P> {
    case new(() -> P)
    case real(ObjectIdentifier, (Any) -> P)
}

/// A ``Story`` with its state type erased. Its stage is a `PlaygroundStaged<P>`.
protocol OwnStory {
    func initStage(_ real: Any, _ variant: Int) -> AnyObject
    func stateValue(_ stage: AnyObject) -> Any
    func writeBackState(_ stage: AnyObject, from value: Any)
    func view(_ stage: AnyObject, _ cx: Cx<Void>) -> El
    func side(_ stage: AnyObject, _ active: Bool, _ cx: Cx<Void>) -> El?
    func sideKeys() -> Bool
    func sideKey(_ stage: AnyObject, _ ev: KeyEvent, _ tx: inout Tx) -> Bool
    func poll(_ stage: AnyObject, _ t: Double, _ tx: inout Tx) -> Bool
    func polls(_ stage: AnyObject) -> Bool
    @discardableResult
    func trigger(_ stage: AnyObject, _ key: Character, _ now: Double) -> Bool
    func stop(_ stage: AnyObject)
    func triggers() -> [(Character, String)]
    func variants() -> [String]
    func frame() -> (Float, Float)?
    func layout() -> Stage
}

extension Story: OwnStory {
    func initStage(_ real: Any, _ variant: Int) -> AnyObject {
        var state: P
        switch initKind {
        case .new(let fn):
            state = fn()
        case .real(_, let derive):
            state = derive(real)
        }
        if variant >= 0 && variant < variantsList.count {
            variantsList[variant].1(&state)
        }
        return PlaygroundStaged<P>(state)
    }

    func stateValue(_ stage: AnyObject) -> Any {
        Self.staged(stage).state
    }

    func writeBackState(_ stage: AnyObject, from value: Any) {
        if let typed = value as? P {
            Self.staged(stage).state = typed
        }
    }

    func view(_ stage: AnyObject, _ cx: Cx<Void>) -> El {
        let ownCx: Cx<P> = cx.retype()
        let root = viewFn(Self.staged(stage).state, ownCx)
        cx.absorb(ownCx)
        return root
    }

    func side(_ stage: AnyObject, _ active: Bool, _ cx: Cx<Void>) -> El? {
        guard let sideFn else { return nil }
        let ownCx: Cx<P> = cx.retype()
        let root = sideFn(Self.staged(stage).state, active, ownCx)
        cx.absorb(ownCx)
        return root
    }

    func sideKeys() -> Bool {
        sideKeyFn != nil
    }

    func sideKey(_ stage: AnyObject, _ ev: KeyEvent, _ tx: inout Tx) -> Bool {
        guard let sideKeyFn else { return false }
        let st = Self.staged(stage)
        return sideKeyFn(&st.state, ev, &tx)
    }

    func poll(_ stage: AnyObject, _ t: Double, _ tx: inout Tx) -> Bool {
        let st = Self.staged(stage)
        let ran = st.run(t, &tx)
        let polled = pollFn?(&st.state, t, &tx) ?? false
        return polled || ran
    }

    func polls(_ stage: AnyObject) -> Bool {
        pollFn != nil || !Self.staged(stage).script.isEmpty
    }

    @discardableResult
    func trigger(_ stage: AnyObject, _ key: Character, _ now: Double) -> Bool {
        guard let t = triggersList.first(where: { $0.key == key }) else { return false }
        Self.staged(stage).script.append((now, t.queued()))
        return true
    }

    func stop(_ stage: AnyObject) {
        Self.staged(stage).script.removeAll()
    }

    func triggers() -> [(Character, String)] {
        triggersList.map { ($0.key, $0.label) }
    }

    func variants() -> [String] {
        variantsList.map(\.0)
    }

    func frame() -> (Float, Float)? {
        frameSize
    }

    func layout() -> Stage {
        stageLayout
    }
}
