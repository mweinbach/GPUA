// Ported from: crates/rune-knobs/src/lib.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

/// Live tuning for any Rune app, in the look of a web knobs panel.
/// Knobs live in groups, each tied to the keyed element it tunes. ⌘⇧K opens the panel on the
/// last group used. ``side(_:_:_:_:_:)`` makes it a right-hand side panel that slides in and pushes the page
/// over, every group a section in one scroll; ``layer(_:_:_:_:)`` floats it over the window with a tab per
/// group. Hovering a group's tab or header outlines its part of the window. The
/// target button picks a part by pointing at it. With the panel focused (click in it), ↑/↓ pick
/// a knob, ←/→ step it (⇧ for 10×), Tab or `[` `]` switch groups. Each group has Random, Reset, Undo, Copy (`name = value` lines)
/// and presets, both declared in code and saved from the panel. Esc closes.
///
/// Values are plain `name -> Float`; the app saves `values`, `saved` and `kept` with its other
/// state. ``Knobs/change(_:_:)`` makes an undoable change (``Knobs/undo()``, ``Knobs/redo()``);
/// ``Knobs/keep()`` saves the values Revert goes back to and ``Knobs/differs(_:)`` marks.

#if !os(WASI)
import Foundation
#endif
import Rune

// PORT NOTE: Upstream Cargo feature `panel` is enabled by default in `rune-knobs/Cargo.toml` and is
// unconditionally active in SwiftPM `RuneKnobs` so `side`, `layer`, `inline`, `actions`, `key`, and `get`
// work out of the box without requiring a custom SwiftPM trait.

/// The spring the side panel slides in and out on by default; send ⌘⇧K's commit on
/// ``Knobs/slide()`` (`tx.motion(s.knobs.slide())`), so the page moves over with the panel.
public let SLIDE: Spring = Spring.new(0.3, 0.0)

/// ``SLIDE`` as knobs, for a story that tunes it.
public let SLIDE_TIME: Knob = Knob.new("Knobs slide", 0.1, 0.8, 0.3).label("Panel slide time")
public let SLIDE_BOUNCE: Knob = Knob.new("Knobs slide bounce", 0.0, 0.4, 0.0).label("Panel slide bounce")

/// How the side panel lays its groups out, for comparing: a tree of pages and their parts,
/// what's on screen first, or a tab per page.
public let LAYOUT: Knob = Knob.choice("Knobs layout", ["Tree", "On screen", "Tabs"], 0)
    .label("Panel layout")
    .about("How this panel lists its parts: a folding tree, what's on screen first, or a tab per page")

/// How long a section takes to fold or open.
public let FOLD_TIME: Knob = Knob.new("Knobs fold", 0.05, 0.6, 0.2)
    .label("Section fold time")
    .about("How long a section of this panel takes to fold or open")

/// The side panel's width until its edge is dragged, and the range it can be dragged in.
public let SIDE_W: Float = 340.0
public let SIDE_MIN: Float = 280.0
public let SIDE_MAX: Float = 640.0

let DEFAULT: String = "Default"

/// Scoped mutable lens into a ``Knobs`` value inside app state `S`.
// PORT NOTE: Replaces Rust's `fn(&mut S) -> &mut Knobs` reference-returning function pointer with a
// value-safe scoped mutator supporting both `WritableKeyPath<S, Knobs>` and `(inout S, (inout Knobs) -> Void) -> Void`
// closures, matching `EditAccess<S>` in `Rune`.
public struct KnobsAccess<S> {
    private let mutate: (inout S, (inout Knobs) -> Void) -> Void

    public init(_ keyPath: WritableKeyPath<S, Knobs>) {
        self.mutate = { state, body in
            body(&state[keyPath: keyPath])
        }
    }

    public init(_ closure: @escaping (inout S, (inout Knobs) -> Void) -> Void) {
        self.mutate = closure
    }

    public func withMutable<R>(_ state: inout S, _ body: (inout Knobs) -> R) -> R {
        var result: R?
        mutate(&state) { k in
            result = body(&k)
        }
        guard let result else {
            preconditionFailure("KnobsAccess closure must invoke its body")
        }
        return result
    }
}

public func knobsAccess<S>(_ keyPath: WritableKeyPath<S, Knobs>) -> KnobsAccess<S> {
    KnobsAccess(keyPath)
}

public func knobsAccess<S>(_ closure: @escaping (inout S, (inout Knobs) -> Void) -> Void) -> KnobsAccess<S> {
    KnobsAccess(closure)
}

/// A button that does one thing, with the key that does it: see ``actions(_:_:)``.
public struct Action<S> {
    public var cap: String
    public var label: String
    public var run: (inout S, inout Tx) -> Void

    public init(cap: String, label: String, run: @escaping (inout S, inout Tx) -> Void) {
        self.cap = cap
        self.label = label
        self.run = run
    }

    public init(_ cap: String, _ label: String, _ run: @escaping (inout S, inout Tx) -> Void) {
        self.init(cap: cap, label: label, run: run)
    }

    public static func new(_ cap: String, _ label: String, _ run: @escaping (inout S, inout Tx) -> Void) -> Action<S> {
        Action(cap: cap, label: label, run: run)
    }
}

/// A tunable number. `step` snaps it (0 is continuous); `labels` make it a choice between
/// `min`, `min + 1`, … shown as a segmented control.
public struct Knob: Sendable, Equatable {
    /// The knob's key: values and presets are stored under it, so it never changes.
    public var name: String
    /// What the panel calls it, in plain words, when that differs from `name`.
    public var label: String
    public var min: Float
    public var max: Float
    public var `default`: Float
    public var step: Float
    public var labels: [String]
    /// One plain line on what it changes, shown while it's hovered or the keyboard is on it.
    public var about: String
    /// One short line per option of a choice, shown while that option is hovered or picked.
    public var hints: [String]

    public init(
        name: String,
        label: String = "",
        min: Float,
        max: Float,
        default defaultValue: Float,
        step: Float = 0.0,
        labels: [String] = [],
        about: String = "",
        hints: [String] = []
    ) {
        self.name = name
        self.label = label
        self.min = min
        self.max = max
        self.`default` = defaultValue
        self.step = step
        self.labels = labels
        self.about = about
        self.hints = hints
    }

    public init(_ name: String, _ min: Float, _ max: Float, _ defaultValue: Float) {
        self.init(name: name, min: min, max: max, default: defaultValue)
    }

    public static func new(_ name: String, _ min: Float, _ max: Float, _ defaultValue: Float) -> Knob {
        Knob(name: name, min: min, max: max, default: defaultValue)
    }

    /// Shows the knob as `label` and keeps storing it under its name.
    public func label(_ label: String) -> Knob {
        var copy = self
        copy.label = label
        return copy
    }

    /// Says in one plain line what it changes.
    public func about(_ about: String) -> Knob {
        var copy = self
        copy.about = about
        return copy
    }

    /// One line per option, in order.
    public func hints(_ hints: [String]) -> Knob {
        var copy = self
        copy.hints = hints
        return copy
    }

    /// What the panel calls it.
    public func title() -> String {
        if let n = lookupNote(name), !n.label.isEmpty {
            return n.label
        }
        if label.isEmpty {
            return name
        }
        return label
    }

    /// The line on what it changes: its note's, or its own.
    public func describe() -> String {
        if let n = lookupNote(name), !n.about.isEmpty {
            return n.about
        }
        return about
    }

    /// The line on option `i` of a choice, or `""` when there isn't one.
    public func hint(_ i: Int) -> String {
        let own = (i >= 0 && i < hints.count) ? hints[i] : ""
        let optLabel = (i >= 0 && i < labels.count) ? labels[i] : ""
        if let n = lookupNote(name),
           let pair = n.hints.first(where: { $0.0 == optLabel }),
           !pair.1.isEmpty
        {
            return pair.1
        }
        return own
    }

    public func step(_ step: Float) -> Knob {
        var copy = self
        copy.step = step
        return copy
    }

    /// One of `labels`, stored as its index.
    public static func choice(_ name: String, _ labels: [String], _ defaultIndex: Int) -> Knob {
        Knob(
            name: name,
            label: "",
            min: 0.0,
            max: Float(Swift.max(labels.count - 1, 0)),
            default: Float(defaultIndex),
            step: 1.0,
            labels: labels,
            about: "",
            hints: []
        )
    }

    func clamp(_ v: Float) -> Float {
        let clamped = Swift.min(Swift.max(v, min), max)
        if step > 0.0 {
            return Swift.min(min + ((clamped - min) / step).rounded() * step, max)
        }
        return clamped
    }
}

/// What an app says about a knob from one table instead of on the knob: a plainer name, one
/// line on what it changes, and a line per option, keyed by the option's label so a reordered
/// knob keeps them right. Hand the table to ``describe(_:)``; a note wins over the knob's own label,
/// about and hints.
public struct Note: Sendable, Equatable {
    public var name: String
    public var label: String
    public var about: String
    public var hints: [(String, String)]

    public init(
        name: String,
        label: String = "",
        about: String,
        hints: [(String, String)] = []
    ) {
        self.name = name
        self.label = label
        self.about = about
        self.hints = hints
    }

    public init(_ name: String, _ about: String) {
        self.init(name: name, about: about)
    }

    public static func new(_ name: String, _ about: String) -> Note {
        Note(name: name, about: about)
    }

    public func label(_ label: String) -> Note {
        var copy = self
        copy.label = label
        return copy
    }

    public func hints(_ hints: [(String, String)]) -> Note {
        var copy = self
        copy.hints = hints
        return copy
    }

    public static func == (lhs: Note, rhs: Note) -> Bool {
        guard lhs.name == rhs.name,
              lhs.label == rhs.label,
              lhs.about == rhs.about,
              lhs.hints.count == rhs.hints.count
        else { return false }
        for (a, b) in zip(lhs.hints, rhs.hints) where a.0 != b.0 || a.1 != b.1 {
            return false
        }
        return true
    }
}

// PORT NOTE: Synchronizes one-shot `NOTES` registration (`std::sync::OnceLock` in upstream) with `NSLock` on multithreaded targets and single-threaded access on WASI.
private final class NotesOnceBox: @unchecked Sendable {
    #if !os(WASI)
    private let lock = NSLock()
    #endif
    private var storage: [Note]? = nil

    func set(_ notes: [Note]) {
        #if !os(WASI)
        lock.lock()
        defer { lock.unlock() }
        #endif
        if storage == nil {
            storage = notes
        }
    }

    func get() -> [Note]? {
        #if !os(WASI)
        lock.lock()
        defer { lock.unlock() }
        #endif
        return storage
    }
}

private let NOTES = NotesOnceBox()

/// Sets the app's notes on its knobs, once; later calls are ignored.
public func describe(_ notes: [Note]) {
    NOTES.set(notes)
}

private func lookupNote(_ name: String) -> Note? {
    NOTES.get()?.first(where: { $0.name == name })
}

/// Values a group starts from, by knob name; knobs it leaves out take their defaults.
public struct Preset: Sendable, Equatable {
    public var name: String
    public var values: [(String, Float)]

    public init(name: String, values: [(String, Float)]) {
        self.name = name
        self.values = values
    }

    public init(_ name: String, _ values: [(String, Float)]) {
        self.name = name
        self.values = values
    }

    public static func new(_ name: String, _ values: [(String, Float)]) -> Preset {
        Preset(name: name, values: values)
    }

    public static func == (lhs: Preset, rhs: Preset) -> Bool {
        guard lhs.name == rhs.name, lhs.values.count == rhs.values.count else {
            return false
        }
        for (a, b) in zip(lhs.values, rhs.values) where a.0 != b.0 || a.1 != b.1 {
            return false
        }
        return true
    }
}

/// Knobs for one part of the window: `region` is the key of the element they tune.
public struct Group: Sendable, Equatable {
    public var name: String
    public var region: String
    public var knobs: [Knob]
    public var presets: [Preset]
    /// What the defaults' chip says ("Default"), when they are a version with a name.
    public var defaultLabel: String
    /// The page this group is a part of ("Item page"), which the side panel folds as one;
    /// empty for a group that stands alone.
    public var under: String

    public init(
        name: String,
        region: String,
        knobs: [Knob],
        presets: [Preset] = [],
        defaultLabel: String = "Default",
        under: String = ""
    ) {
        self.name = name
        self.region = region
        self.knobs = knobs
        self.presets = presets
        self.defaultLabel = defaultLabel
        self.under = under
    }

    public init(_ name: String, _ region: String, _ knobs: [Knob]) {
        self.init(name: name, region: region, knobs: knobs)
    }

    public static func new(_ name: String, _ region: String, _ knobs: [Knob]) -> Group {
        Group(name: name, region: region, knobs: knobs)
    }

    /// Files the group under a page: names must still be unique across all groups.
    public func under(_ page: String) -> Group {
        var copy = self
        copy.under = page
        return copy
    }

    /// The page it's on: its own name when it stands alone.
    public func page() -> String {
        under.isEmpty ? name : under
    }

    public func presets(_ presets: [Preset]) -> Group {
        var copy = self
        copy.presets = presets
        return copy
    }

    /// Names the defaults' chip, as knobs' `defaultLabel`: "Native" when the defaults are
    /// what the platform does.
    public func defaultLabel(_ label: String) -> Group {
        var copy = self
        copy.defaultLabel = label
        return copy
    }
}

/// A preset saved from the panel.
public typealias Saved = [(String, [String: Float])]

public struct Knobs: Equatable {
    /// The layer is showing.
    public var open: Bool = false
    /// Values that were changed; the rest are at their defaults.
    public var values: [String: Float] = [:]
    /// Presets saved from the panel, by group name, in the order they were saved.
    public var saved: [String: Saved] = [:]
    /// The values as last kept with ``Knobs/keep()``: ``Knobs/revert(_:)`` goes back to them and
    /// ``Knobs/differs(_:)`` marks a knob moved off them. Knobs left out were kept at their
    /// defaults. The app saves it with `values`.
    public var kept: [String: Float] = [:]
    /// The group the panel shows; the last one used, and the first group until one is picked.
    public var group: String? = nil
    /// Picking a region with the target button: the panel shows no group meanwhile.
    public var picking: Bool = false
    /// What the app is set to while other values are tried (a storybook sets it as it opens),
    /// by knob name: choice rows mark that option with a dot. Knobs left out get no mark.
    public var settled: [String: Float]? = nil
    /// The side panel's width as dragged (0 until it is); the app saves it.
    public var width: Float = 0.0
    /// Side panel sections folded, and ones opened, by group or page name, while the panel
    /// is open. Opening it again folds everything but the group last opened (see ``show()``).
    public var folded: Set<String> = []
    public var unfolded: Set<String> = []
    /// What has been typed to filter the side panel: the filter field's text, kept in step with
    /// it on every edit. Set it with ``Knobs/setQuery(_:)`` so the field follows.
    public var query: String = ""
    /// The filter field is editing: `/` (or a click on it) starts, Esc or Return stops. While
    /// it does, the field owns the keys it edits with.
    public var filtering: Bool = false
    /// The filter field's model: caret, selection, undo. `query` mirrors its text.
    var editModel: TextEdit = TextEdit()
    /// The page the side panel's Tabs layout shows, once one is picked.
    public var tab: String? = nil
    /// The side panel's keyboard row.
    var atNode: Node? = nil
    /// The long choice showing all its options under its stepper.
    var expanded: String? = nil
    /// The group whose region is outlined: under the pointer while picking, or its tab hovered.
    var hover: String? = nil
    /// The active knob for the keyboard, and whether the keyboard is driving the panel.
    var cursor: Int = 0
    var kbd: Bool = false
    /// The slider under the pointer, and the one being dragged.
    var hot: String? = nil
    /// The option of a choice under the pointer: its knob and index.
    var hotOpt: (String, Int)? = nil
    var drag: String? = nil
    /// The preset each group last applied.
    var activePresets: [String: String] = [:]
    var undoStack: [[String: Float]] = []
    var redoStack: [[String: Float]] = []
    var seed: UInt64 = 0

    public init() {}

    public static func == (lhs: Knobs, rhs: Knobs) -> Bool {
        guard lhs.open == rhs.open,
              lhs.values == rhs.values,
              lhs.kept == rhs.kept,
              lhs.group == rhs.group,
              lhs.picking == rhs.picking,
              lhs.settled == rhs.settled,
              lhs.width == rhs.width,
              lhs.folded == rhs.folded,
              lhs.unfolded == rhs.unfolded,
              lhs.query == rhs.query,
              lhs.filtering == rhs.filtering,
              lhs.editModel == rhs.editModel,
              lhs.tab == rhs.tab,
              lhs.atNode == rhs.atNode,
              lhs.expanded == rhs.expanded,
              lhs.hover == rhs.hover,
              lhs.cursor == rhs.cursor,
              lhs.kbd == rhs.kbd,
              lhs.hot == rhs.hot,
              lhs.drag == rhs.drag,
              lhs.activePresets == rhs.activePresets,
              lhs.undoStack == rhs.undoStack,
              lhs.redoStack == rhs.redoStack,
              lhs.seed == rhs.seed
        else { return false }

        switch (lhs.hotOpt, rhs.hotOpt) {
        case (nil, nil):
            break
        case let (a?, b?):
            if a.0 != b.0 || a.1 != b.1 { return false }
        default:
            return false
        }

        guard lhs.saved.count == rhs.saved.count else { return false }
        for (gName, lList) in lhs.saved {
            guard let rList = rhs.saved[gName], lList.count == rList.count else {
                return false
            }
            for (la, rb) in zip(lList, rList) where la.0 != rb.0 || la.1 != rb.1 {
                return false
            }
        }
        return true
    }

    /// The side panel's spring, from ``SLIDE_TIME`` and ``SLIDE_BOUNCE``.
    public func slide() -> Spring {
        Spring.new(get(SLIDE_TIME), get(SLIDE_BOUNCE))
    }

    public func get(_ k: Knob) -> Float {
        k.clamp(values[k.name] ?? k.`default`)
    }

    public mutating func set(_ k: Knob, _ v: Float) {
        values[k.name] = k.clamp(v)
    }

    /// The side panel's width, open or not.
    public func sideW() -> Float {
        width > 0.0 ? min(max(width, SIDE_MIN), SIDE_MAX) : SIDE_W
    }

    /// How much room the side panel takes from the page: its width while open, else 0.
    public func sideRoom() -> Float {
        open ? sideW() : 0.0
    }

    /// The side panel's fold spring, from ``FOLD_TIME``.
    public func foldSpring() -> Spring {
        Spring.new(get(FOLD_TIME), 0.0)
    }

    /// Whether side panel section `name` is folded, given whether it would be by default.
    public func isFolded(_ name: String, _ byDefault: Bool) -> Bool {
        if folded.contains(name) {
            return true
        } else if unfolded.contains(name) {
            return false
        } else {
            return byDefault
        }
    }

    /// Folds or opens a side panel section, and remembers it.
    public mutating func setFolded(_ name: String, _ fold: Bool) {
        if fold {
            unfolded.remove(name)
            folded.insert(name)
        } else {
            folded.remove(name)
            unfolded.insert(name)
        }
    }

    /// Opens the panel. Coming from shut, every section starts folded, a list of all the parts,
    /// except the group last used if it was left open (and so its page).
    public mutating func show() {
        if !open {
            let keep = group.flatMap { unfolded.contains($0) ? $0 : nil }
            folded.removeAll()
            unfolded.removeAll()
            if let keep {
                unfolded.insert(keep)
            }
        }
        open = true
        picking = false
        kbd = false
        hover = nil
    }

    /// Starts picking a region of the window with the pointer.
    public mutating func pickRegion() {
        picking = true
        hover = nil
    }

    /// The group the panel shows, if not picking.
    public func current(_ groups: [Group]) -> Group? {
        if picking {
            return nil
        }
        if let n = group, let found = groups.first(where: { $0.name == n }) {
            return found
        }
        return groups.first
    }

    /// Puts the pointer over knob `name` (and option `option` of a choice), for a still or a test.
    public mutating func hover(_ name: String, _ option: Int?) {
        hot = name
        hotOpt = option.map { (name, $0) }
    }

    /// Sets the filter's text, in the field and in `query`.
    public mutating func setQuery(_ q: String) {
        query = q
        syncEdit()
    }

    /// Brings the field's text to `query`, if the app changed `query` itself.
    mutating func syncEdit() {
        if editModel.text != query {
            editModel.replaceText(query)
        }
    }

    /// Starts filtering, as `/` does: the field takes focus with its text selected, so typing
    /// replaces it.
    public mutating func filter(_ query: String) {
        setQuery(query)
        startFilter()
    }

    mutating func startFilter() {
        syncEdit()
        filtering = true
        editModel.focused = true
        editModel.setSelection(0, editModel.text.utf8.count)
    }

    /// Stops filtering; focus goes back to the panel.
    mutating func stopFilter() {
        filtering = false
        editModel.focused = false
    }

    /// The field's model as the view draws it.
    func edit() -> TextEdit {
        editModel
    }

    /// The field changed: `query` follows.
    mutating func edited() {
        query = editModel.text
    }

    public mutating func close() {
        open = false
        picking = false
        hover = nil
        kbd = false
        stopFilter()
        hot = nil
        hotOpt = nil
        drag = nil
    }

    public mutating func toggle() {
        if open { close() } else { show() }
    }

    /// Shows `group`'s knobs.
    public mutating func pick(_ groupName: String) {
        if group != groupName {
            cursor = 0
        }
        group = groupName
        setFolded(groupName, false)
        picking = false
        hover = nil
    }

    /// Keys for the panel while it has focus: ↑/↓ pick a knob, ←/→ step it (⇧ for 10×; a choice
    /// moves one option), Tab, ⇧Tab, `[` and `]` switch groups, Esc closes. True if taken.
    public mutating func panelKey(_ groups: [Group], _ ev: KeyEvent) -> Bool {
        // Focus left the filter field without the panel hearing of it.
        if filtering && !editModel.focused {
            filtering = false
        }
        if ev.mods.cmd || ev.mods.alt || ev.mods.ctrl || filtering {
            return false
        }
        if ev.key == .escape {
            close()
            return true
        }
        guard let g = current(groups) ?? groups.first else { return false }
        let n = g.knobs.count
        switch ev.key {
        case .up where n > 0, .down where n > 0:
            let at = min(cursor, n - 1) + (ev.key == .down ? 1 : -1)
            cursor = euclidMod(at, n)
        case .left where n > 0, .right where n > 0:
            step(g.knobs[min(cursor, n - 1)], ev.key == .right, ev.mods.shift)
        case .tab:
            guard !groups.isEmpty else { return false }
            let back = ev.mods.shift
            let i = groups.firstIndex(where: { $0.name == g.name }) ?? 0
            let next = euclidMod(i + (back ? -1 : 1), groups.count)
            pick(groups[next].name)
        case .text(let t) where t == "[" || t == "]":
            guard !groups.isEmpty else { return false }
            let back = (t == "[")
            let i = groups.firstIndex(where: { $0.name == g.name }) ?? 0
            let next = euclidMod(i + (back ? -1 : 1), groups.count)
            pick(groups[next].name)
        default:
            return false
        }
        kbd = true
        return true
    }

    /// One step of `d` up or down (⇧ for 10×; a choice moves one option), undoable.
    mutating func step(_ d: Knob, _ up: Bool, _ big: Bool) {
        let baseUnit: Float
        if !d.labels.isEmpty {
            baseUnit = 1.0
        } else if d.step > 0.0 {
            baseUnit = d.step
        } else {
            baseUnit = (d.max - d.min) / 100.0
        }
        let unit = (big && d.labels.isEmpty) ? (baseUnit * 10.0) : baseUnit
        let before = get(d)
        checkpoint()
        set(d, before + (up ? unit : -unit))
        if get(d) == before && undoStack.last == values {
            _ = undoStack.popLast()
        }
    }

    /// Anything Reset would change in `g`.
    public func canReset(_ g: Group) -> Bool {
        if g.knobs.contains(where: { abs(get($0) - $0.`default`) > 1e-4 }) {
            return true
        }
        if let a = activePresets[g.name], drifted(g, a) {
            return true
        }
        return false
    }

    /// Remembers the values for Undo, once per change: call it before a change the panel makes
    /// itself (a drag calls it once, as it starts). A new change drops what Redo had.
    public mutating func checkpoint() {
        if undoStack.last != values {
            undoStack.append(values)
            if undoStack.count > 100 {
                undoStack.removeFirst()
            }
        }
        redoStack.removeAll()
    }

    /// Sets `k` to `v` so Undo can take it back.
    public mutating func change(_ k: Knob, _ v: Float) {
        if abs(get(k) - k.clamp(v)) > 1e-6 {
            checkpoint()
            set(k, v)
        }
    }

    /// Takes back the last change. True if there was one.
    @discardableResult
    public mutating func undo() -> Bool {
        guard let v = undoStack.popLast() else { return false }
        let previous = values
        values = v
        redoStack.append(previous)
        return true
    }

    /// Puts back the change Undo took. True if there was one.
    @discardableResult
    public mutating func redo() -> Bool {
        guard let v = redoStack.popLast() else { return false }
        let previous = values
        values = v
        undoStack.append(previous)
        return true
    }

    public func canUndo() -> Bool {
        !undoStack.isEmpty
    }

    public func canRedo() -> Bool {
        !redoStack.isEmpty
    }

    /// What `k` was when the values were last kept.
    public func keptValue(_ k: Knob) -> Float {
        k.clamp(kept[k.name] ?? k.`default`)
    }

    /// `k` has moved off its kept value.
    public func differs(_ k: Knob) -> Bool {
        abs(get(k) - keptValue(k)) > 1e-4
    }

    /// Keeps every value as it is now, as what Revert goes back to.
    public mutating func keep() {
        kept = values
    }

    /// Keeps `knobs` as they are now, the rest as they were kept.
    public mutating func keepSome(_ knobs: [Knob]) {
        for k in knobs {
            if let v = values[k.name] {
                kept[k.name] = v
            } else {
                kept.removeValue(forKey: k.name)
            }
        }
    }

    /// Puts `knobs` back to their kept values, undoably.
    public mutating func revert(_ knobs: [Knob]) {
        guard knobs.contains(where: { differs($0) }) else { return }
        checkpoint()
        for k in knobs {
            if let v = kept[k.name] {
                values[k.name] = v
            } else {
                values.removeValue(forKey: k.name)
            }
        }
    }

    /// Each of `g`'s knobs to a random value in its range.
    public mutating func random(_ g: Group) {
        checkpoint()
        if seed == 0 {
            // PORT NOTE: Uses Swift's standard-library CSPRNG to seed the non-zero xorshift64 state portably across all platforms (including WASI).
            seed = UInt64.random(in: 1...UInt64.max) | 1
        }
        for k in g.knobs {
            // xorshift64
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            let f = Float(seed >> 40) / Float(UInt64(1) << 24)
            set(k, k.min + f * (k.max - k.min))
        }
    }

    /// Puts one knob back to its default, undoably.
    public mutating func resetKnob(_ d: Knob) {
        if values[d.name] != nil {
            checkpoint()
            values.removeValue(forKey: d.name)
        }
    }

    /// Back to the active preset, or, already there, to the defaults.
    public mutating func reset(_ g: Group) {
        if let name = activePresets[g.name], drifted(g, name) {
            apply(g, name)
        } else {
            checkpoint()
            for k in g.knobs {
                values.removeValue(forKey: k.name)
            }
            activePresets.removeValue(forKey: g.name)
        }
    }

    /// A preset's values for every knob in `g`, defaults filled in; "Default" is the defaults.
    public func preset(_ g: Group, _ name: String) -> [String: Float]? {
        var out: [String: Float] = [:]
        for k in g.knobs {
            out[k.name] = k.`default`
        }
        if let p = g.presets.first(where: { $0.name == name }) {
            for (n, v) in p.values {
                out[n] = v
            }
        } else if let list = saved[g.name], let (_, v) = list.first(where: { $0.0 == name }) {
            for (n, val) in v where g.knobs.contains(where: { $0.name == n }) {
                out[n] = val
            }
        } else if name != DEFAULT {
            return nil
        }
        return out
    }

    public mutating func apply(_ g: Group, _ name: String) {
        guard let vals = preset(g, name) else { return }
        checkpoint()
        for k in g.knobs {
            let v = vals[k.name] ?? k.`default`
            if v == k.`default` {
                values.removeValue(forKey: k.name)
            } else {
                set(k, v)
            }
        }
        if name == DEFAULT {
            activePresets.removeValue(forKey: g.name)
        } else {
            activePresets[g.name] = name
        }
    }

    /// The preset `g` last applied ("Default" if none).
    public func active(_ g: Group) -> String {
        activePresets[g.name] ?? DEFAULT
    }

    /// The values have moved off preset `name`.
    public func drifted(_ g: Group, _ name: String) -> Bool {
        guard let vals = preset(g, name) else { return false }
        return g.knobs.contains { k in
            guard let target = vals[k.name] else { return false }
            return abs(get(k) - k.clamp(target)) > 1e-4
        }
    }

    /// Saves `g`'s values as a new preset and makes it active.
    @discardableResult
    public mutating func save(_ g: Group) -> String {
        let list = saved[g.name] ?? []
        var n = 1
        while list.contains(where: { $0.0 == "Saved \(n)" }) {
            n += 1
        }
        let name = "Saved \(n)"
        var vals: [String: Float] = [:]
        for k in g.knobs {
            vals[k.name] = get(k)
        }
        saved[g.name, default: []].append((name, vals))
        activePresets[g.name] = name
        return name
    }

    public mutating func delete(_ g: Group, _ name: String) {
        if var list = saved[g.name] {
            list.removeAll { $0.0 == name }
            saved[g.name] = list
        }
        if activePresets[g.name] == name {
            activePresets.removeValue(forKey: g.name)
        }
    }

    /// `name = value` lines for `g`'s knobs; a choice adds its label.
    public func code(_ g: Group) -> String {
        g.knobs.map { k in
            let v = get(k)
            let idx = Int(v)
            if v >= 0.0, idx >= 0, idx < k.labels.count {
                return "\(k.name) = \(trim(v)) (\(k.labels[idx]))"
            } else {
                return "\(k.name) = \(trim(v))"
            }
        }.joined(separator: "\n")
    }
}

@inline(__always)
func euclidMod(_ a: Int, _ m: Int) -> Int {
    let r = a % m
    return r < 0 ? r + m : r
}

// PORT NOTE: Pure-Swift fixed-decimal formatter avoiding `String(format:)` so `RuneKnobs` builds cleanly on WASI without Foundation formatting dependencies.
func formatFixed(_ value: Float, _ decimals: Int) -> String {
    if value.isNaN { return "NaN" }
    if value.isInfinite { return value < 0 ? "-inf" : "inf" }
    let factor: Double
    switch decimals {
    case 0: factor = 1.0
    case 1: factor = 10.0
    case 2: factor = 100.0
    case 3: factor = 1000.0
    default:
        var p = 1.0
        for _ in 0..<max(decimals, 0) { p *= 10.0 }
        factor = p
    }
    let scaled = (Double(value) * factor).rounded(.toNearestOrEven)
    guard abs(scaled) < 9.0e18 else { return String(value) }
    let negative = scaled < 0.0
    let mag = Int64(abs(scaled))
    if decimals <= 0 {
        return (negative && mag != 0) ? "-\(mag)" : "\(mag)"
    }
    let intFactor = Int64(factor)
    let whole = mag / intFactor
    let frac = mag % intFactor
    var fracStr = String(frac)
    if fracStr.count < decimals {
        fracStr = String(repeating: "0", count: decimals - fracStr.count) + fracStr
    }
    let sign = (negative && mag != 0) ? "-" : ""
    return "\(sign)\(whole).\(fracStr)"
}

private func trim(_ v: Float) -> String {
    var s = formatFixed(v, 3)
    while s.last == "0" {
        s.removeLast()
    }
    if s.last == "." {
        s.removeLast()
    }
    return s == "-0" ? "0" : s
}

/// ⌘⇧K toggles the layer and Esc closes it. Returns true when it took the key.
public func key(_ k: inout Knobs, _ ev: KeyEvent) -> Bool {
    switch ev.key {
    case .command(let c) where (c == "k" || c == "K") && ev.mods.shift:
        k.toggle()
        return true
    case .escape where k.open:
        k.close()
        return true
    default:
        return false
    }
}

/// ``Knobs/panelKey(_:_:)`` as the keys of a playground story's side column, for
/// `Rune.Story.sideKeys` beside ``inline(_:_:_:_:_:)``: ↑ ↓ pick a knob, ← → step it (⇧ for 10×), `[`
/// and `]` switch groups. It leaves Esc and Tab to the playground, which leaves the column.
public func sideKey<S>(
    _ groups: [Group],
    _ lens: KnobsAccess<S>
) -> (inout S, KeyEvent, inout Tx) -> Bool {
    return { s, ev, tx in
        switch ev.key {
        case .escape, .tab:
            return false
        default:
            break
        }
        let taken = lens.withMutable(&s) { $0.panelKey(groups, ev) }
        if taken {
            tx.instant()
        }
        return taken
    }
}

public func sideKey<S>(
    _ groups: [Group],
    _ keyPath: WritableKeyPath<S, Knobs>
) -> (inout S, KeyEvent, inout Tx) -> Bool {
    sideKey(groups, KnobsAccess(keyPath))
}

public func sideKey<S>(
    _ groups: [Group],
    _ lens: @escaping (inout S, (inout Knobs) -> Void) -> Void
) -> (inout S, KeyEvent, inout Tx) -> Bool {
    sideKey(groups, KnobsAccess(lens))
}
