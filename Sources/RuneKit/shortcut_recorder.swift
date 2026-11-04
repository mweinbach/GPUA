// Ported from: crates/rune-kit/src/shortcut_recorder.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! A physical shortcut editor. The app owns registration and can reject a proposed change.

import Rune

public struct ShortcutRecorderState: Sendable, Equatable {
    var shortcutVal: Shortcut?
    var recordingVal: Bool
    var heldVal: Mods
    var errorVal: ShortcutError?
    /// The chord the error refused, shown with it until a new chord starts. None for a refused clear.
    var refusedVal: Shortcut?
    // Swallow auto-repeat until the captured/cancelled key is released.
    var finishingVal: PhysicalKeyCode?
    var unregisteredVal: Bool

    public init(_ shortcut: Shortcut? = nil) {
        self.shortcutVal = shortcut
        self.recordingVal = false
        self.heldVal = Mods()
        self.errorVal = nil
        self.refusedVal = nil
        self.finishingVal = nil
        self.unregisteredVal = false
    }

    public static func new(_ shortcut: Shortcut?) -> ShortcutRecorderState {
        ShortcutRecorderState(shortcut)
    }

    public static let `default` = ShortcutRecorderState()

    public func shortcut() -> Shortcut? {
        shortcutVal
    }

    public func isRecording() -> Bool {
        recordingVal
    }

    public func error() -> ShortcutError? {
        errorVal
    }

    /// The chord `onChange` just refused, until another chord starts.
    public func refused() -> Shortcut? {
        refusedVal
    }

    /// The shortcut isn't registered (it failed at launch, say): recording the same chord
    /// proposes it through `onChange` again instead of being a no-op, until a change succeeds.
    public mutating func markUnregistered() {
        unregisteredVal = true
    }

    public mutating func begin() {
        recordingVal = true
        errorVal = nil
        refusedVal = nil
        finishingVal = nil
    }

    public mutating func cancel() {
        recordingVal = false
        heldVal = Mods()
        errorVal = nil
        refusedVal = nil
    }

    public func keycaps() -> [String] {
        if recordingVal, let refused = refusedVal {
            return refused.keycaps()
        } else if recordingVal {
            return modifierKeycaps(heldVal)
        } else {
            return shortcutVal?.keycaps() ?? []
        }
    }

    mutating func input(_ event: PhysicalInput) -> RecorderOutcome {
        switch event {
        case .focusLost:
            let active = recordingVal || finishingVal != nil
            cancel()
            finishingVal = nil
            return active ? .consumed : .pass
        case .modifiers(let mods):
            hold(mods)
            return recordingVal ? .consumed : .pass
        case .key(let key, let mods, let pressed, let isRepeat):
            hold(mods)
            if finishingVal == key {
                if !pressed {
                    finishingVal = nil
                }
                return .consumed
            }
            if !recordingVal {
                return .pass
            }
            if !pressed || isRepeat || isModifierKey(key) {
                return .consumed
            }
            finishingVal = key
            if key == .escape {
                cancel()
                return .consumed
            }
            if key == .backspace {
                return .change(nil)
            }
            switch Shortcut.fromPhysicalKey(key, mods) {
            case .success(let shortcut):
                return .change(shortcut)
            case .failure(let err):
                errorVal = err
                refusedVal = nil
                return .consumed
            }
        }
    }

    /// Pressing another modifier starts a new chord: the refused one and its error go.
    private mutating func hold(_ mods: Mods) {
        let held = heldVal
        if (mods.ctrl && !held.ctrl)
            || (mods.alt && !held.alt)
            || (mods.shift && !held.shift)
            || (mods.cmd && !held.cmd)
            || (mods.logo && !held.logo)
        {
            refusedVal = nil
            errorVal = nil
        }
        heldVal = mods
    }
}

enum RecorderOutcome {
    case pass
    case consumed
    case change(Shortcut?)
}

private func isModifierKey(_ key: PhysicalKeyCode) -> Bool {
    switch key {
    case .shiftLeft, .shiftRight, .controlLeft, .controlRight, .altLeft, .altRight,
         .superLeft, .superRight, .fn, .fnLock:
        return true
    default:
        return false
    }
}

/// The recorder's default error text, for `errorMessage` closures to fall back on:
/// "⇧⌘K is already in use.", or "Add ⌘, ⌃ or ⌥." for a chord without a modifier. The refused
/// chord is `nil` when clearing was refused.
public func shortcutErrorMessage(_ error: ShortcutError, _ shortcut: Shortcut?) -> String {
    guard let shortcut else {
        if case .invalidAccelerator = error {
            return "That key can't be part of a shortcut."
        }
        return "The shortcut couldn't be cleared."
    }
    #if os(macOS)
    let chord = shortcut.keycaps().joined()
    #else
    let chord = shortcut.keycaps().joined(separator: "+")
    #endif
    switch error {
    case .invalidAccelerator:
        if case .failure = shortcut.requireModifier() {
            #if os(macOS)
            return "Add ⌘, ⌃ or ⌥."
            #else
            return "Add Ctrl, Alt or Super."
            #endif
        }
        return "\(chord) couldn't be registered."
    case .conflict:
        return "\(chord) is already in use."
    case .unsupported:
        return "This desktop doesn't support global shortcuts."
    case .permissionDenied:
        return "Permission to use \(chord) was declined."
    default:
        return "\(chord) couldn't be registered."
    }
}

// PORT NOTE: Supports both `WritableKeyPath<S, ShortcutRecorderState>` and scoped mutation
// closures `(inout S, (inout ShortcutRecorderState) -> Void) -> Void` so Swift value-type app
// states mutate cleanly without overlapping borrows during `onChange`.
private struct RecorderAccess<S> {
    let mutate: (inout S, (inout ShortcutRecorderState) -> Void) -> Void

    init(_ keyPath: WritableKeyPath<S, ShortcutRecorderState>) {
        self.mutate = { s, body in
            body(&s[keyPath: keyPath])
        }
    }

    init(_ mutate: @escaping (inout S, (inout ShortcutRecorderState) -> Void) -> Void) {
        self.mutate = mutate
    }

    func withState<R>(_ s: inout S, _ body: (inout ShortcutRecorderState) -> R) -> R {
        var result: R!
        mutate(&s) { st in
            result = body(&st)
        }
        return result
    }
}

/// Click (or activate with Enter/Space) to record. Escape cancels; Backspace clears.
/// `onChange` must register the proposed binding before releasing the previous registration:
/// returning an error keeps the old value and shows the refused chord with a message
/// (`errorMessage` words it). An unchanged chord is a no-op unless the state was marked
/// unregistered (`ShortcutRecorderState.markUnregistered`). A chord without ⌘, ⌃ or ⌥ (Ctrl,
/// Alt or Super elsewhere) other than F1–F24 is refused before `onChange` unless
/// `allowUnmodified`.
public struct ShortcutRecorder<S> {
    private var keyVal: String
    private var stateVal: ShortcutRecorderState
    private var accessVal: RecorderAccess<S>
    private var changeVal: ((inout S, Shortcut?, inout Tx) -> Result<Void, ShortcutError>)?
    private var messageVal: (ShortcutError, Shortcut?) -> String
    private var widthVal: Float
    private var disabledVal: Bool
    private var unmodifiedVal: Bool

    public init(
        _ key: String,
        _ state: ShortcutRecorderState,
        _ keyPath: WritableKeyPath<S, ShortcutRecorderState>
    ) {
        self.keyVal = key
        self.stateVal = state
        self.accessVal = RecorderAccess(keyPath)
        self.changeVal = nil
        self.messageVal = shortcutErrorMessage
        self.widthVal = 240.0
        self.disabledVal = false
        self.unmodifiedVal = false
    }

    public init(
        _ key: String,
        _ state: ShortcutRecorderState,
        _ access: @escaping (inout S, (inout ShortcutRecorderState) -> Void) -> Void
    ) {
        self.keyVal = key
        self.stateVal = state
        self.accessVal = RecorderAccess(access)
        self.changeVal = nil
        self.messageVal = shortcutErrorMessage
        self.widthVal = 240.0
        self.disabledVal = false
        self.unmodifiedVal = false
    }

    public static func new(
        _ key: String,
        _ state: ShortcutRecorderState,
        _ keyPath: WritableKeyPath<S, ShortcutRecorderState>
    ) -> ShortcutRecorder<S> {
        ShortcutRecorder(key, state, keyPath)
    }

    public static func new(
        _ key: String,
        _ state: ShortcutRecorderState,
        _ access: @escaping (inout S, (inout ShortcutRecorderState) -> Void) -> Void
    ) -> ShortcutRecorder<S> {
        ShortcutRecorder(key, state, access)
    }

    public func onChange(
        _ change: @escaping (inout S, Shortcut?, inout Tx) -> Result<Void, ShortcutError>
    ) -> ShortcutRecorder<S> {
        var copy = self
        copy.changeVal = change
        return copy
    }

    /// Words the error shown under the recorder, given the refused chord (`nil` when clearing
    /// was refused). The default, ``shortcutErrorMessage(_:_:)``, is sentence-case and names the
    /// chord: "⌃J is already in use."
    public func errorMessage(
        _ message: @escaping (ShortcutError, Shortcut?) -> String
    ) -> ShortcutRecorder<S> {
        var copy = self
        copy.messageVal = message
        return copy
    }

    /// Propose chords without a modifier too, such as Space or ⇧A. Registering one globally
    /// also needs `App.allowUnmodifiedShortcuts`.
    public func allowUnmodified() -> ShortcutRecorder<S> {
        var copy = self
        copy.unmodifiedVal = true
        return copy
    }

    public func width(_ width: Float) -> ShortcutRecorder<S> {
        var copy = self
        copy.widthVal = width
        return copy
    }

    public func disabled(_ disabled: Bool) -> ShortcutRecorder<S> {
        var copy = self
        copy.disabledVal = disabled
        return copy
    }

    public func build(_ k: Kit) -> El {
        let labels = stateVal.keycaps()
        let placeholder = stateVal.recordingVal ? "Press shortcut" : "Record shortcut"
        let border: Color
        if stateVal.errorVal != nil {
            border = k.c.danger.border
        } else if stateVal.recordingVal {
            border = k.c.borderFocus
        } else {
            border = k.c.borderBase
        }
        var control = row()
            .key(keyVal)
            .role("button")
            .label(labels.isEmpty ? placeholder : labels.joined(separator: " "))
            .w(widthVal)
            .h(32.0)
            .px(8.0)
            .centerY()
            .radius(k.radius.md)
            .fill(k.c.bgBase)
            .border(1.0, border)
            .focusable(!disabledVal)
            .focusRing(2.0, 2.0, k.c.borderFocus)
        if labels.isEmpty {
            control = control.child(text(placeholder).font(k.ty.uiCompact).color(k.c.textFaint))
        } else {
            control = control.child(Keybind.new(labels).build(k))
        }
        let access = accessVal
        if !disabledVal {
            control = control.onPress { (s: inout S) in
                access.withState(&s) { $0.begin() }
            }
        }
        let change = changeVal
        let isDisabled = disabledVal
        let unmodified = unmodifiedVal
        control = control.onPhysicalInput { (s: inout S, event: PhysicalInput, tx: inout Tx) -> Bool in
            if isDisabled {
                if case .focusLost = event {
                    // Allow FocusLost cleanup even when disabled.
                } else {
                    return false
                }
            }
            let outcome = access.withState(&s) { $0.input(event) }
            switch outcome {
            case .pass:
                return false
            case .consumed:
                return true
            case .change(let next):
                let bare: Result<Void, ShortcutError>? = (!unmodified ? next : nil).map { $0.requireModifier() }
                let (currentShortcut, isUnregistered) = access.withState(&s) {
                    ($0.shortcutVal, $0.unregisteredVal)
                }
                let result: Result<Void, ShortcutError>
                if case .failure(let err) = bare {
                    result = .failure(err)
                } else if currentShortcut == next && !isUnregistered {
                    result = .success(())
                } else if let f = change {
                    result = f(&s, next, &tx)
                } else {
                    result = .success(())
                }
                access.withState(&s) { state in
                    switch result {
                    case .success:
                        state.shortcutVal = next
                        state.errorVal = nil
                        state.unregisteredVal = false
                        state.cancel()
                    case .failure(let err):
                        state.errorVal = err
                        state.refusedVal = next
                    }
                }
                return true
            }
        }
        var root = col().key("\(keyVal)-field").gap(4.0).child(control)
        if let err = stateVal.errorVal {
            root = root.child(
                text(messageVal(err, stateVal.refusedVal))
                    .font(k.ty.smallMedium)
                    .color(k.c.danger.fg)
            )
        }
        return root
    }
}

/// Namespace mirroring `rune_kit::shortcut_recorder` module exports.
public enum shortcut_recorder {
    public typealias ShortcutRecorderState = RuneKit.ShortcutRecorderState
    public typealias ShortcutRecorder<S> = RuneKit.ShortcutRecorder<S>
    public static func shortcutErrorMessage(_ error: ShortcutError, _ shortcut: Shortcut?) -> String {
        RuneKit.shortcutErrorMessage(error, shortcut)
    }
}
