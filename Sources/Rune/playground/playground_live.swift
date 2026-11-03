// Ported from: crates/rune/src/playground/live.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `PlaygroundLive`: a window's playground while it runs, and the requests that move it.

/// A window's playground while it runs (`crates/rune/src/playground/live.rs`).
final class PlaygroundLive<S> {
    var pages: [PlaygroundPage<S>]
    /// By the scene index they're for.
    var triggersList: [(Int, PlaygroundTrigger<S>)] = []
    var sides: [(Int, PlaygroundSide<S>)] = []
    var stages: [(Int, Stage)] = []
    var variantsList: [(Int, String, PlaygroundVariant<S>)] = []
    /// Each story's variant, by its index into scenes then pages, until the playground closes.
    var variant: [Int] = []
    var sizes: [(String, (Float, Float))]
    var shortcut: Shortcut?
    /// The View menu's item takes the shortcut, so keys here leave it alone.
    var menu: Bool
    var bar: Bool
    var initFn: () -> S
    var fresh: ((S) -> S)?
    var keepFn: ((S, inout S) -> Void)?
    var typing: ((S) -> Bool)?
    /// ``Playground/dark(_:)``.
    var appDark: ((S) -> Bool)?
    var scenes: [(String, (inout S) -> Void)]
    var poll: ((inout S, Double, inout Tx) -> Bool)?
    /// Stories, as indices into scenes then pages, in the order the list shows them.
    var order: [Int] = []
    var open: Bool = false
    /// Into scenes then pages.
    var selected: Int = 0
    /// A group header is the list's selection rather than `selected`'s row.
    var header: String? = nil
    /// Groups whose stories the list hides, until the playground closes.
    var folded: [String] = []
    /// ``Playground/folds(_:_:)``.
    var folds: PlaygroundFolds
    /// ``Playground/widths(_:_:)``.
    var widthsConfig: PlaygroundWidths
    /// The keyboard is on the open story's side controls, which take keys.
    var sideActive: Bool = false
    /// The column that has the keyboard.
    var currentRegion: PlaygroundRegion = .list
    /// The focused element's path when the region last looked (see ``seeFocus(_:)``).
    var regionSeen: String? = nil
    var scene: PlaygroundStaged<S>? = nil
    var owned: [AnyObject?]
    var controls: PlaygroundControls
    var dark: Bool? = nil
    var size: Int = 0
    var reduceMotion: Bool = false
    var pending: [PlaygroundRequest] = []
    /// The clock at the last commit or poll, which triggers start from.
    var now: Double = 0.0
    /// Bumped by every select and replay, so the new stage's elements start fresh: scroll
    /// offsets, focus and animations don't carry over from the last one.
    var generation: UInt32 = 0
    /// The node the app's view returned, which holds the window's root handlers.
    var root: Int = 0
    /// The time scale the app had when the playground opened, which every new stage starts
    /// from and Back restores.
    var appTimeScale: Float = 1.0

    init(playground: Playground<S>, spec: AppSpec<S>, menu: Bool) {
        var widths = playground.widthsConfig
        let saveWidths = widths.save
        widths.save = nil

        self.owned = Array(repeating: nil, count: playground.pages.count)
        self.pages = playground.pages
        self.sizes = playground.sizesList
        self.shortcut = playground.shortcutValue
        self.menu = menu
        self.bar = playground.barEnabled
        self.initFn = spec.`init`
        self.fresh = playground.freshFn
        self.keepFn = playground.keepFn
        self.typing = playground.typingFn
        self.appDark = playground.darkFn
        self.scenes = spec.scenes
        self.poll = spec.poll
        self.folds = playground.foldsConfig
        self.widthsConfig = widths
        self.controls = PlaygroundControls(saveWidthsFn: saveWidths)

        let sceneIds = Array(0..<self.scenes.count)
        func resolveScene(_ live: PlaygroundLive<S>, _ name: String) -> Int? {
            let at = live.findIn(name, sceneIds)
            if at == nil {
                toolingStderr("rune: the playground has a trigger, side column or stage for \(name.debugDescription), which isn't one of AppSpec::scenes\n")
            }
            return at
        }

        self.triggersList = playground.triggers.compactMap { name, t in
            guard let idx = resolveScene(self, name) else { return nil }
            return (idx, t)
        }
        self.sides = playground.sides.compactMap { name, s in
            guard let idx = resolveScene(self, name) else { return nil }
            return (idx, s)
        }
        self.stages = playground.stages.compactMap { name, st in
            guard let idx = resolveScene(self, name) else { return nil }
            return (idx, st)
        }
        self.variantsList = playground.variantsList.compactMap { name, variantName, apply in
            guard let idx = resolveScene(self, name) else { return nil }
            return (idx, variantName, apply)
        }
        self.variant = Array(repeating: 0, count: count())

        let show = playground.scenesFilter
        let listed = (0..<count()).filter { i in
            if i < self.scenes.count {
                let sceneName = self.scenes[i].0
                return show?(sceneName) ?? true
            }
            return true
        }
        self.order = treeOrder(listed, playground.groupOrderList)
        self.selected = self.order.first ?? 0
        if self.folds.start {
            self.folded = allGroups()
        }
        loadWidths()
    }

    func isOpen() -> Bool {
        open
    }

    func count() -> Int {
        scenes.count + pages.count
    }

    func path(_ i: Int) -> String {
        if i < scenes.count {
            return scenes[i].0
        }
        return pages[i - scenes.count].name
    }

    func group(_ i: Int) -> String {
        playgroundSplit(path(i), i < scenes.count ? "Scenes" : "Pages").0
    }

    func name(_ i: Int) -> String {
        playgroundSplit(path(i), "").1
    }

    func currentPage() -> (Int, PlaygroundPage<S>)? {
        let i = selected - scenes.count
        guard i >= 0 && i < pages.count else { return nil }
        return (i, pages[i])
    }

    func own() -> (any OwnStory, AnyObject)? {
        guard let (i, page) = currentPage(),
              case .own(let ownStory) = page.kind,
              let stageBox = owned[i]
        else {
            return nil
        }
        return (ownStory, stageBox)
    }

    func isLivePage() -> Bool {
        guard let (_, page) = currentPage() else { return false }
        if case .live = page.kind { return true }
        return false
    }

    /// How the stage lays out the open story.
    func layout() -> Stage {
        if selected < scenes.count {
            if let (_, st) = stages.last(where: { $0.0 == selected }) {
                return st
            }
            return .center
        }
        if let (_, page) = currentPage(), case .own(let ownStory) = page.kind {
            return ownStory.layout()
        }
        return .center
    }

    /// Whether story `i` has triggers of its own, beside R, which the list marks.
    func hasTriggers(_ i: Int) -> Bool {
        if i < scenes.count {
            return triggersList.contains(where: { $0.0 == i })
        }
        let p = i - scenes.count
        guard p >= 0 && p < pages.count else { return false }
        if case .own(let ownStory) = pages[p].kind {
            return !ownStory.triggers().isEmpty
        }
        return false
    }

    /// The open story's triggers, R's first.
    func triggers() -> [(Character, String)] {
        if isLivePage() { return [] }
        var keys: [(Character, String)]
        if selected < scenes.count {
            keys = triggersList.filter { $0.0 == selected }.map { ($0.1.key, $0.1.label) }
        } else if let (ownStory, _) = own() {
            keys = ownStory.triggers()
        } else {
            keys = []
        }
        let replay: (Character, String)
        if let idx = keys.firstIndex(where: { $0.0 == "r" }) {
            replay = keys.remove(at: idx)
        } else {
            replay = ("r", "Replay")
        }
        keys.insert(replay, at: 0)
        return keys
    }

    func request(_ requests: [PlaygroundRequest]) {
        pending.append(contentsOf: requests)
    }

    func hasPending() -> Bool {
        !pending.isEmpty
    }

    func pendingSwapsStage() -> Bool {
        pending.contains(where: \.swapsStage)
    }

    /// Whether the only requests that swap the stage are replays, which keep its story.
    func pendingReplaysOnly() -> Bool {
        pending.filter(\.swapsStage).allSatisfy { req in
            switch req {
            case .replay, .variant:
                return true
            default:
                return false
            }
        }
    }

    /// Applies the requests handlers made since the last commit; true when anything changed.
    func apply(_ clock: Double, _ real: inout S) -> Bool {
        now = clock
        loadFolds()
        loadWidths()
        var changed = false
        let queued = pending
        pending.removeAll()
        for req in queued {
            changed = true
            switch req {
            case .open(let storyName):
                openStory(storyName, &real)
            case .openAt(let storyName, let variantName):
                let resolved = resolve(storyName, variantName)
                openStory(resolved, &real)
            case .close:
                close(&real)
            case .toggle where open:
                close(&real)
            case .toggle:
                open = true
                if folds.start {
                    reveal(selected)
                }
                select(selected, &real)
            case .select(let i):
                reveal(i)
                select(i, &real)
            case .replay:
                replay(&real)
            case .variant(let n) where n >= 0 && n < variants().count:
                if selected >= 0 && selected < variant.count {
                    variant[selected] = n
                }
                replay(&real)
            case .variant:
                break
            case .keep:
                keep(&real)
            case .trigger(let key):
                trigger(key)
            case .dark(let isDark):
                dark = isDark
            case .size(let i):
                size = i
            case .reduceMotion(let on):
                reduceMotion = on
            case .header(let g):
                header = g
            case .fold(let g, let f):
                fold(g, f)
            }
        }
        // Opened on a story whose group is folded, the header stands in for its row.
        settle()
        return changed
    }

    /// Folds a group, unfolds it, or toggles it. A filter shows every match, so folds wait
    /// until it's cleared. A selection whose row goes moves to the header that hid it.
    func fold(_ group: String, _ foldState: Bool?) {
        if !query().isEmpty { return }
        let currentlyFolded = folded.contains(group)
        let target = foldState ?? !currentlyFolded
        if target && !currentlyFolded {
            refold { $0.append(group) }
        } else if !target {
            refold { $0.removeAll { $0 == group } }
        }
        settle()
    }

    /// Story `i`'s row becomes the list's selection, its groups unfolded.
    func reveal(_ i: Int) {
        header = nil
        if i >= 0 && i < count() {
            let gs = groupsOf(i)
            refold { $0.removeAll { gs.contains($0) } }
        }
    }

    /// The open story's stage made again, then its `'r'` trigger.
    func replay(_ real: inout S) {
        if isLivePage() { return }
        if let (i, _) = currentPage() {
            owned[i] = nil
        }
        select(selected, &real)
    }

    /// ``Playground/keep(_:)``, from the scene's stage as it goes.
    func keep(_ real: inout S) {
        if let keepFn, let scene {
            keepFn(scene.state, &real)
        }
    }

    func close(_ real: inout S) {
        keep(&real)
        open = false
        header = nil
        currentRegion = .list
        controls.filter = TextEdit()
        for idx in variant.indices {
            variant[idx] = 0
        }
        scene = nil
        for idx in owned.indices {
            owned[idx] = nil
        }
    }

    /// Shows story `i`. A stage made new, as a scene's always is, runs its `'r'` trigger.
    func select(_ i: Int, _ real: inout S) {
        keep(&real)
        let left = selected - scenes.count
        if left >= 0 && left < pages.count,
           case .own(let ownStory) = pages[left].kind,
           let stageBox = owned[left]
        {
            ownStory.stop(stageBox)
        }
        let total = count()
        selected = total > 0 ? min(max(i, 0), total - 1) : 0
        scene = nil
        generation &+= 1
        let sc = SceneClock(now: now, dt: 1.0 / 60.0)
        if selected < scenes.count {
            let sceneFn = scenes[selected].1
            let initFn = self.initFn
            let freshFn = self.fresh
            let variantFn = sceneVariant()
            let realSnap = real
            let st = withSceneClock(sc) { () -> S in
                var s = freshFn.map { $0(realSnap) } ?? initFn()
                sceneFn(&s)
                variantFn?(&s)
                return s
            }
            scene = PlaygroundStaged<S>(st)
        } else if let (pageIdx, page) = currentPage(),
                  case .own(let ownStory) = page.kind,
                  owned[pageIdx] == nil
        {
            let v = (selected < variant.count) ? variant[selected] : 0
            let realSnap = real
            let stageBox = withSceneClock(sc) {
                ownStory.initStage(realSnap, v)
            }
            owned[pageIdx] = stageBox
        } else {
            return
        }
        trigger("r")
    }

    /// Queues the open story's trigger on `key`, to run at the next poll from now.
    func trigger(_ key: Character) {
        guard open else { return }
        let currentNow = now
        if let scene {
            if let (_, t) = triggersList.first(where: { $0.0 == selected && $0.1.key == key }) {
                scene.script.append((currentNow, t.queued()))
            }
            return
        }
        let pageIdx = selected - scenes.count
        guard pageIdx >= 0 && pageIdx < pages.count else { return }
        if case .own(let ownStory) = pages[pageIdx].kind, let stageBox = owned[pageIdx] {
            ownStory.trigger(stageBox, key, currentNow)
        }
    }

    /// Whether `ev` is the shortcut that opens and closes the playground, where no menu item
    /// takes it first.
    func isShortcut(_ ev: KeyEvent) -> Bool {
        !menu && (shortcut?.matchesKey(ev) ?? false)
    }

    /// The open stage's own state: a scene's, or a story's.
    func stageStateValue() -> Any? {
        guard open else { return nil }
        if let scene {
            return scene.state
        }
        if let (ownStory, stageBox) = own() {
            return ownStory.stateValue(stageBox)
        }
        return nil
    }
}
