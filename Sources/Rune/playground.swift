// Ported from: crates/rune/src/playground.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `App.playground`: a storybook built into the window (⌘⇧D). Its stories, grouped by type,
//! are the app's scenes and its own `Story`s and pages. One shows at a time on a plain stage,
//! live and interactive, with a column beside it for that story's triggers and controls.
//! Nothing touches the app's real state.

#if !os(WASI)
import Foundation
#endif
import Taffy

/// The bar's height when the playground is closed, hairline included.
let PLAYGROUND_BAR: Float = 26.0
let PLAYGROUND_SIDEBAR: Float = 200.0
let PLAYGROUND_SIDE: Float = 264.0
let PLAYGROUND_HEADER: Float = 38.0
let PLAYGROUND_BAND: Float = 28.0
let PLAYGROUND_ROW: Float = 28.0
let PLAYGROUND_CONTROL: Float = 24.0
/// The story list's filter field.
let PLAYGROUND_FILTER: String = "playground-filter"
/// How far each level of the story list indents.
let PLAYGROUND_INDENT: Float = 12.0

/// Module namespace mirroring `rune::playground`.
public enum playground {
    public typealias Play<X> = Rune.Play<X>
    public typealias Playground<S> = Rune.Playground<S>
    public typealias Stage = Rune.Stage
    public typealias Step<X> = Rune.Step<X>
    public typealias Story<P> = Rune.Story<P>

    public static func slug(_ path: String) -> String {
        playgroundSlug(path)
    }
}

/// A storybook for one window, given to ``App/playground(_:)``.
public struct Playground<S> {
    var pages: [PlaygroundPage<S>] = []
    var triggers: [(String, PlaygroundTrigger<S>)] = []
    var sides: [(String, PlaygroundSide<S>)] = []
    var stages: [(String, Stage)] = []
    var sizesList: [(String, (Float, Float))] = []
    var shortcutValue: Shortcut?
    var barEnabled: Bool = true
    var enabledFlag: Bool
    var scenesFilter: ((String) -> Bool)? = nil
    var freshFn: ((S) -> S)? = nil
    var keepFn: ((S, inout S) -> Void)? = nil
    var variantsList: [(String, String, PlaygroundVariant<S>)] = []
    var typingFn: ((S) -> Bool)? = nil
    var darkFn: ((S) -> Bool)? = nil
    var foldsConfig = PlaygroundFolds()
    var widthsConfig = PlaygroundWidths()
    var groupOrderList: [String] = []
    /// Tracks whether `widths(...)` was called explicitly, vs defaulting to `Prefs` in windowed runs.
    var customWidthsConfigured: Bool = false

    /// No pages, a bar, ⌘⇧D (Ctrl+Shift+D off macOS), and enabled in debug builds only.
    public init() {
        #if os(macOS)
        self.shortcutValue = Shortcut("Shift+Cmd+D")
        #else
        self.shortcutValue = Shortcut("Ctrl+Shift+D")
        #endif
        #if DEBUG
        self.enabledFlag = true
        #else
        self.enabledFlag = false
        #endif
    }

    public static func new() -> Playground<S> {
        Playground<S>()
    }

    /// A page drawn by `view` from the app's live state. Its handlers change the real state,
    /// and it has no triggers or replay.
    public func page(_ name: String, _ view: @escaping (S, Cx<S>) -> El) -> Playground<S> {
        var copy = self
        copy.pages.append(PlaygroundPage(name: name, kind: .live(view)))
        return copy
    }

    /// A story with its own state: see ``Story``.
    public func story<P>(_ story: Story<P>) -> Playground<S> {
        if let realType = story.realStateType(), realType != ObjectIdentifier(S.self) {
            preconditionFailure("Story.fromReal(\(story.name.debugDescription)) derives from another app state than this playground's")
        }
        var copy = self
        copy.pages.append(PlaygroundPage(name: story.name, kind: .own(story)))
        return copy
    }

    /// A trigger for the scene named `scene` (its path, or just its name): `key` runs `run` on
    /// the scene's stage state, as its button in the side column does. An `'r'` trigger runs
    /// when the scene is chosen and on each replay, so its motion plays at once.
    public func trigger(
        _ scene: String,
        _ key: Character,
        _ label: String,
        _ run: @escaping (inout S, Play<S>) -> Void
    ) -> Playground<S> {
        var copy = self
        copy.triggers.append((scene, makePlaygroundTrigger(key, label, run)))
        return copy
    }

    /// ``Playground/trigger(_:_:_:_:)`` with a step that takes just the ``Tx``.
    public func triggerTx(
        _ scene: String,
        _ key: Character,
        _ label: String,
        _ run: @escaping (inout S, inout Tx) -> Void
    ) -> Playground<S> {
        var copy = self
        copy.triggers.append((scene, makePlaygroundTriggerTx(key, label, run)))
        return copy
    }

    /// The app's own controls for the scene named `scene`, at the top of the side column, drawn
    /// from and acting on the scene's stage state.
    public func side(_ scene: String, _ view: @escaping (S, Cx<S>) -> El) -> Playground<S> {
        var copy = self
        copy.sides.append((scene, .stage(view)))
        return copy
    }

    /// A variant of the scene named `scene`: `apply` runs on its state after the scene fn.
    public func variant(
        _ scene: String,
        _ name: String,
        _ apply: @escaping (inout S) -> Void
    ) -> Playground<S> {
        var copy = self
        copy.variantsList.append((scene, name, apply))
        return copy
    }

    /// ``Playground/side(_:_:)``, drawn from the stage and the real state both.
    public func sideReal(
        _ scene: String,
        _ view: @escaping (S, S, Cx<S>) -> El
    ) -> Playground<S> {
        var copy = self
        copy.sides.append((scene, .real(view)))
        return copy
    }

    /// ``Playground/side(_:_:)`` for controls that take keys, for the scene named `scene`.
    public func sideKeys(
        _ scene: String,
        _ view: @escaping (S, Bool, Cx<S>) -> El,
        _ key: @escaping (inout S, KeyEvent, inout Tx) -> Bool
    ) -> Playground<S> {
        var copy = self
        copy.sides.append((scene, .keys(view, key)))
        return copy
    }

    /// How the stage lays out the scene named `scene`.
    public func stage(_ scene: String, _ stage: Stage) -> Playground<S> {
        var copy = self
        copy.stages.append((scene, stage))
        return copy
    }

    /// Which of `AppSpec.scenes` the list shows, by name. By default, all of them.
    public func scenes(_ show: @escaping (String) -> Bool) -> Playground<S> {
        var copy = self
        copy.scenesFilter = show
        return copy
    }

    /// Scenes start from `fresh(real)` rather than `AppSpec.init`, then their scene fn applies.
    public func fresh(_ fresh: @escaping (S) -> S) -> Playground<S> {
        var copy = self
        copy.freshFn = fresh
        return copy
    }

    /// Runs before a scene's stage goes, on R, another story or Back, with the stage and the
    /// real state.
    public func keep(_ keep: @escaping (S, inout S) -> Void) -> Playground<S> {
        var copy = self
        copy.keepFn = keep
        return copy
    }

    /// While `typing` is true of the stage's state, `AppSpec.onKey` gets every key before the
    /// playground and focused fields do.
    public func typing(_ typing: @escaping (S) -> Bool) -> Playground<S> {
        var copy = self
        copy.typingFn = typing
        return copy
    }

    /// Whether the app is dark, read from its real state, for the playground's bar and chrome
    /// and the stage's appearance until the switch beside it changes it.
    public func dark(_ dark: @escaping (S) -> Bool) -> Playground<S> {
        var copy = self
        copy.darkFn = dark
        return copy
    }

    /// Stage sizes offered beside "Window".
    public func sizes(_ sizes: [(String, (Float, Float))]) -> Playground<S> {
        var copy = self
        copy.sizesList = sizes
        return copy
    }

    /// The shortcut that opens and closes the playground, or `nil` for none.
    public func shortcut(_ shortcut: Shortcut?) -> Playground<S> {
        var copy = self
        copy.shortcutValue = shortcut
        return copy
    }

    /// The bar along the window's bottom edge that opens the playground.
    public func bar(_ on: Bool) -> Playground<S> {
        var copy = self
        copy.barEnabled = on
        return copy
    }

    /// Whether the window offers the playground at all; by default only in debug builds.
    public func enabled(_ on: Bool) -> Playground<S> {
        var copy = self
        copy.enabledFlag = on
        return copy
    }

    func isEnabled() -> Bool {
        enabledFlag
    }

    func shortcutKey() -> Shortcut? {
        shortcutValue
    }
}

enum PlaygroundSide<S> {
    case stage((S, Cx<S>) -> El)
    case real((S, S, Cx<S>) -> El)
    case keys((S, Bool, Cx<S>) -> El, (inout S, KeyEvent, inout Tx) -> Bool)
}

typealias PlaygroundVariant<X> = (inout X) -> Void
typealias PlaygroundSideView<X> = (X, Bool, Cx<X>) -> El
typealias PlaygroundSideKey<X> = (inout X, KeyEvent, inout Tx) -> Bool

struct PlaygroundPage<S> {
    var name: String
    var kind: PlaygroundPageKind<S>
}

enum PlaygroundPageKind<S> {
    case live((S, Cx<S>) -> El)
    case own(any OwnStory)
}

/// A story's group and name, from its path: everything before the last `/` names its group,
/// the rest the story.
func playgroundSplit(_ path: String, _ defaultGroup: String) -> (String, String) {
    if let range = path.range(of: "/", options: .backwards) {
        let group = String(path[..<range.lowerBound])
        let name = String(path[range.upperBound...])
        return (group, name)
    }
    return (defaultGroup, path)
}

/// What a handler asks of the playground (`Tx.openPlayground`, its keys and its controls),
/// applied at the start of the next commit, before the view runs against the new stage.
enum PlaygroundRequest: Equatable, Sendable {
    case open(String?)
    case openAt(String, String?)
    case close
    case toggle
    case select(Int)
    case replay
    case keep
    case variant(Int)
    case trigger(Character)
    case dark(Bool)
    case size(Int)
    case reduceMotion(Bool)
    case header(String)
    case fold(String, Bool?)

    /// Whether this one changes the stage's state, so handlers built for the old one must go.
    var swapsStage: Bool {
        switch self {
        case .open, .openAt, .close, .toggle, .select, .replay, .variant:
            return true
        case .keep, .trigger, .dark, .size, .reduceMotion, .header, .fold:
            return false
        }
    }
}

/// What a key does in the open playground, for the runtime to carry out.
enum PlaygroundNav: Equatable {
    case pass
    case stay
    case request(PlaygroundRequest)
    case intoSide
    case intoStage
    case filter
    case outOfSide
    case sideStep(Int)
}

/// The playground's own controls' state: the story list's filter field and column widths.
final class PlaygroundControls {
    var filter: TextEdit = TextEdit()
    var sidebarW: Float = PLAYGROUND_SIDEBAR
    var sideW: Float = PLAYGROUND_SIDE
    var saveWidthsFn: ((Float, Float) -> Void)? = nil

    init(
        filter: TextEdit = TextEdit(),
        sidebarW: Float = PLAYGROUND_SIDEBAR,
        sideW: Float = PLAYGROUND_SIDE,
        saveWidthsFn: ((Float, Float) -> Void)? = nil
    ) {
        self.filter = filter
        self.sidebarW = sidebarW
        self.sideW = sideW
        self.saveWidthsFn = saveWidthsFn
    }
}

// PORT NOTE: Carries queued `PlaygroundRequest` values on `Tx` via `sidecar` without modifying `Sources/Rune/el/el_tx.swift`; `latched` is synchronized by `pgUnlatchedLock`.
final class PlaygroundRequestBox: @unchecked Sendable {
    let request: PlaygroundRequest
    var latched: Bool = false
    init(_ request: PlaygroundRequest) { self.request = request }
}

private let pgUnlatchedLock = LiveLock()
#if os(WASI)
// PORT NOTE: Single-threaded WASI storage capturing `PlaygroundRequestBox` values emitted inside Spine `Runtime.update` where `hostLatchTx` does not run directly.
nonisolated(unsafe) private var pgUnlatchedBoxes: [PlaygroundRequestBox] = []
#else
// PORT NOTE: Guarded by `pgUnlatchedLock` and keyed by `Thread.current` so concurrent tests never cross-drain `PlaygroundRequestBox` values emitted inside Spine `Runtime.update`.
nonisolated(unsafe) private var pgUnlatchedBoxesByThread: [ObjectIdentifier: [PlaygroundRequestBox]] = [:]
#endif

func pgDrainUnlatchedRequests() -> [PlaygroundRequest] {
    pgUnlatchedLock.withLock {
        #if os(WASI)
        guard !pgUnlatchedBoxes.isEmpty else { return [] }
        var out: [PlaygroundRequest] = []
        for box in pgUnlatchedBoxes where !box.latched {
            box.latched = true
            out.append(box.request)
        }
        pgUnlatchedBoxes.removeAll()
        return out
        #else
        let tid = ObjectIdentifier(Thread.current)
        guard let boxes = pgUnlatchedBoxesByThread.removeValue(forKey: tid), !boxes.isEmpty else {
            return []
        }
        var out: [PlaygroundRequest] = []
        for box in boxes where !box.latched {
            box.latched = true
            out.append(box.request)
        }
        return out
        #endif
    }
}

func pgMarkBoxesLatched(_ boxes: [PlaygroundRequestBox]) -> [PlaygroundRequest] {
    pgUnlatchedLock.withLock {
        var out: [PlaygroundRequest] = []
        out.reserveCapacity(boxes.count)
        for box in boxes {
            box.latched = true
            out.append(box.request)
        }
        #if os(WASI)
        pgUnlatchedBoxes.removeAll(where: { $0.latched })
        #else
        let tid = ObjectIdentifier(Thread.current)
        if var threadBoxes = pgUnlatchedBoxesByThread[tid] {
            threadBoxes.removeAll(where: { $0.latched })
            if threadBoxes.isEmpty {
                pgUnlatchedBoxesByThread.removeValue(forKey: tid)
            } else {
                pgUnlatchedBoxesByThread[tid] = threadBoxes
            }
        }
        #endif
        return out
    }
}

extension Tx {
    mutating func pgPush(_ request: PlaygroundRequest) {
        let box = PlaygroundRequestBox(request)
        pgUnlatchedLock.withLock {
            #if os(WASI)
            pgUnlatchedBoxes.append(box)
            #else
            let tid = ObjectIdentifier(Thread.current)
            pgUnlatchedBoxesByThread[tid, default: []].append(box)
            #endif
        }
        appendSidecar(box)
    }

    /// Show ``App/playground(_:)`` in this window.
    public mutating func openPlayground() {
        pgPush(.open(nil))
    }

    /// Back to the app from the playground, as its Back button does.
    public mutating func closePlayground() {
        pgPush(.close)
    }

    /// Runs ``Playground/keep(_:)`` now, with the open scene's stage and the real state, as a
    /// switch would before the stage goes. The stage stays.
    public mutating func keepPlayground() {
        pgPush(.keep)
    }

    public mutating func togglePlayground() {
        pgPush(.toggle)
    }
}

/// Whether `key` is the stage's, around the story's root.
func playgroundIsStage(_ key: String) -> Bool {
    guard key.hasPrefix("playground-stage-") else { return false }
    let suffix = key.dropFirst("playground-stage-".count)
    return UInt32(suffix) != nil
}

/// `--playground [NAME]`'s optional story name, taking it when the next argument isn't a flag.
func playgroundArg(_ argv: [String], _ i: inout Int) -> String? {
    guard i + 1 < argv.count else { return nil }
    let candidate = argv[i + 1]
    guard !candidate.hasPrefix("-") else { return nil }
    i += 1
    return candidate
}

private func playgroundHiddenByEnv() -> Bool {
    #if os(WASI)
    return false
    #else
    return ProcessInfo.processInfo.environment["RUNE_PLAYGROUND"] == "0"
    #endif
}

func playgroundOfferedByEnv() -> Bool {
    !playgroundHiddenByEnv()
}

/// Shows `playground` in `rt`'s window when this run offers it (`crates/rune/src/playground.rs:405-417`).
func playgroundAttach<S>(
    rt: Runtime<S>,
    playground: Playground<S>?,
    spec: AppSpec<S>,
    open: String??,
    variant: String?,
    windowed: Bool,
    inUnitTest: Bool = false
) {
    guard var playground, playground.isEnabled() else { return }
    if open == nil && (!windowed || playgroundHiddenByEnv()) { return }
    if windowed && !inUnitTest && !playground.customWidthsConfigured {
        playground.widthsConfig = PlaygroundWidths.prefs(currentAppId() ?? spec.title)
    }
    #if os(macOS)
    let hasMacMenu = windowed
    #else
    let hasMacMenu = false
    #endif
    let live = PlaygroundLive<S>(playground: playground, spec: spec, menu: hasMacMenu)
    if let openOpt = open {
        if case .failure(let msg) = live.openAt(openOpt, variant) {
            toolingDie(msg.message)
        }
        live.pending.append(.open(openOpt))
    }
    rt.hostInstallPlayground(live, appPoll: spec.poll)
}

func playgroundAttachHeadless<S>(
    rt: inout Runtime<S>,
    playground: Any?,
    spec: AppSpec<S>,
    cliPlayground: String??,
    cliVariant: String?,
    windowed: Bool
) {
    playgroundAttach(
        rt: rt,
        playground: playground as? Playground<S>,
        spec: spec,
        open: cliPlayground,
        variant: cliVariant,
        windowed: windowed
    )
}

// MARK: - Internal `pg*` `El` Layout/Visual Helpers (avoiding Wave 2 collisions on `el/**`)

extension El {
    func pgFill(_ c: Color) -> El { bg(c) }
    func pgRadius(_ r: Float) -> El { rounded(r) }
    func pgCenterY() -> El { itemsCenter() }
    func pgCenter() -> El { itemsCenter().justifyCenter() }
    func pgPadding(_ p: Float) -> El { pad(p) }

    func pgPx(_ x: Float) -> El {
        var copy = self
        copy.style.padding.left = .length(x)
        copy.style.padding.right = .length(x)
        return copy
    }

    func pgPl(_ l: Float) -> El {
        var copy = self
        copy.style.padding.left = .length(l)
        return copy
    }

    func pgPr(_ r: Float) -> El {
        var copy = self
        copy.style.padding.right = .length(r)
        return copy
    }

    func pgPt(_ t: Float) -> El {
        var copy = self
        copy.style.padding.top = .length(t)
        return copy
    }

    func pgPb(_ b: Float) -> El {
        var copy = self
        copy.style.padding.bottom = .length(b)
        return copy
    }

    func pgMl(_ l: Float) -> El {
        var copy = self
        copy.style.margin.left = .length(l)
        return copy
    }

    func pgOutline(_ width: Float, _ offset: Float, _ color: Color) -> El {
        var copy = self
        copy.vis.cold.value.outline = Outline(width: width, offset: offset, color: color)
        return copy
    }

    func pgBorderDash(_ dash: Float, _ gap: Float) -> El {
        _ = (dash, gap)
        return self
    }

    func pgClipRounded(_ radius: Float) -> El {
        rounded(radius).clip(true)
    }

    func pgWindowDrag() -> El {
        var copy = self
        copy.windowDragFlag = true
        return copy
    }

    func pgFocusHighlight(_ color: Color) -> El {
        var copy = self
        copy.focusSpec.value.highlight = color
        return copy
    }

    func pgCaret(_ caretColor: Color, _ selectionColor: Color) -> El {
        var copy = self
        copy.input?.caret = caretColor
        copy.input?.selection = selectionColor
        return copy
    }

    func pgCursor(_ cursor: Cursor) -> El {
        hostAttachExtras(self) { $0.cursor = cursor }
    }

    func pgOnPressTx<T>(_ f: @escaping (inout T, inout Tx) -> Void) -> El {
        onPress(f)
    }

    func pgOnDoublePressTx<T>(_ f: @escaping (inout T, inout Tx) -> Void) -> El {
        hostAttachExtras(self) { extras in
            extras.onDoublePress = { states, tx in
                _ = states.withMutable { (target: inout T) in
                    f(&target, &tx)
                }
            }
        }
    }

    func pgOnEdit<T>(_ access: EditAccess<T>) -> El {
        let erased = access.erase()
        let animateLayout = self.input?.animateLayout ?? false
        var copy = hostAttachExtras(self.focusable(true)) { extras in
            extras.editAccess = erased
        }
        let prevOnKey = copy.onKeyHandler
        copy.onKeyHandler = { states, ev, tx in
            if let prevOnKey, prevOnKey(states, ev, &tx) {
                return true
            }
            var handled = false
            var shouldBlur = false
            var copiedText: String? = nil
            _ = erased(states) { edit in
                switch ev.key {
                case .text(let s) where !ev.mods.cmd && !ev.mods.ctrl && !ev.mods.alt:
                    edit.insert(s)
                    handled = true
                case .backspace where !ev.mods.cmd && !ev.mods.alt:
                    let (a, b) = edit.range()
                    if a < b {
                        edit.insert("")
                    } else if a > 0 {
                        let scalars = Array(edit.text.unicodeScalars)
                        var byteAcc = 0
                        var prevBoundary = 0
                        for sc in scalars {
                            let next = byteAcc + sc.utf8.count
                            if next >= a { break }
                            prevBoundary = next
                            byteAcc = next
                        }
                        edit.anchor = prevBoundary
                        edit.focus = a
                        edit.insert("")
                    }
                    handled = true
                case .delete where !ev.mods.cmd && !ev.mods.alt:
                    let (a, b) = edit.range()
                    let total = edit.text.utf8.count
                    if a < b {
                        edit.insert("")
                    } else if b < total {
                        let scalars = Array(edit.text.unicodeScalars)
                        var byteAcc = 0
                        var nextBoundary = total
                        for sc in scalars {
                            let next = byteAcc + sc.utf8.count
                            if byteAcc >= b {
                                nextBoundary = next
                                break
                            }
                            byteAcc = next
                        }
                        edit.anchor = b
                        edit.focus = nextBoundary
                        edit.insert("")
                    }
                    handled = true
                case .command("a") where !ev.mods.alt:
                    edit.anchor = 0
                    edit.focus = edit.text.utf8.count
                    handled = true
                case .command("c") where !ev.mods.alt:
                    if !edit.isSecure() {
                        let (a, b) = edit.range()
                        if a < b, let sel = String(bytes: edit.text.utf8.dropFirst(a).prefix(b - a), encoding: .utf8) {
                            copiedText = sel
                        }
                    }
                    handled = true
                case .command("x") where !ev.mods.alt:
                    if !edit.isSecure() {
                        let (a, b) = edit.range()
                        if a < b, let sel = String(bytes: edit.text.utf8.dropFirst(a).prefix(b - a), encoding: .utf8) {
                            copiedText = sel
                            edit.insert("")
                        }
                    }
                    handled = true
                case .escape where !ev.mods.cmd && !ev.mods.alt && !ev.mods.ctrl && !ev.mods.shift:
                    if edit.anchor != edit.focus {
                        edit.anchor = edit.focus
                    } else {
                        shouldBlur = true
                    }
                    handled = true
                case .left where !ev.mods.alt && !ev.mods.ctrl:
                    let pos = min(edit.anchor, edit.focus)
                    let next = ev.mods.cmd ? 0 : max(0, pos - 1)
                    edit.focus = next
                    if !ev.mods.shift { edit.anchor = next }
                    handled = true
                case .right where !ev.mods.alt && !ev.mods.ctrl:
                    let total = edit.text.utf8.count
                    let pos = max(edit.anchor, edit.focus)
                    let next = ev.mods.cmd ? total : min(total, pos + 1)
                    edit.focus = next
                    if !ev.mods.shift { edit.anchor = next }
                    handled = true
                default:
                    break
                }
            }
            if let copiedText {
                tx.copy(copiedText)
            }
            if handled {
                tx.instantFlag = !animateLayout
            }
            if shouldBlur {
                tx.blur()
            }
            return handled
        }
        return copy
    }

    func pgOnPaste<T>(_ f: @escaping (inout T, String, inout Tx) -> Void) -> El {
        hostAttachExtras(self) { extras in
            extras.onPaste = { states, text, tx in
                _ = states.withMutable { (target: inout T) in
                    f(&target, text, &tx)
                }
            }
        }
    }

    func pgOnDropFiles<T>(_ f: @escaping (inout T, [String], inout Tx) -> Void) -> El {
        hostAttachExtras(self) { extras in
            extras.onDropFiles = { states, files, tx in
                _ = states.withMutable { (target: inout T) in
                    f(&target, files, &tx)
                }
            }
        }
    }

    func pgOnDropHover<T>(_ f: @escaping (inout T, Bool, inout Tx) -> Void) -> El {
        hostAttachExtras(self) { extras in
            extras.onDropHover = { states, hovering, tx in
                _ = states.withMutable { (target: inout T) in
                    f(&target, hovering, &tx)
                }
            }
        }
    }

    func pgOnWindowFocus<T>(_ f: @escaping (inout T, Bool, inout Tx) -> Void) -> El {
        hostAttachExtras(self) { extras in
            extras.onWindowFocus = { states, focused, tx in
                _ = states.withMutable { (target: inout T) in
                    f(&target, focused, &tx)
                }
            }
        }
    }

    func pgOnSubmit<T>(_ f: @escaping (inout T, inout Tx) -> Void) -> El {
        hostAttachExtras(self) { extras in
            extras.onSubmit = { states, tx in
                _ = states.withMutable { (target: inout T) in
                    f(&target, &tx)
                }
            }
        }
    }

    func pgOnHoverChange<T>(_ f: @escaping (inout T, Bool, inout Tx) -> Void) -> El {
        var copy = self
        copy.onHoverHandler = { states, hovering, tx in
            _ = states.withMutable { (target: inout T) in
                f(&target, hovering, &tx)
            }
        }
        return copy
    }

    func pgOnStep<T>(_ f: @escaping (inout T, Int32, inout Tx) -> Void) -> El {
        self.focusable(true).onKey { (target: inout T, ev: KeyEvent, tx: inout Tx) in
            guard !ev.mods.cmd && !ev.mods.ctrl && !ev.mods.alt else { return false }
            switch ev.key {
            case .up, .right:
                f(&target, 1, &tx)
                return true
            case .down, .left:
                f(&target, -1, &tx)
                return true
            default:
                return false
            }
        }
    }
}
