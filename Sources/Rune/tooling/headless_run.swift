// Ported from: crates/rune/src/tooling/headless_run.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! What a headless run was asked to do, for the app to read (`tooling.headlessRun`).

/// Physical hardware input event carried in `ScriptEvent.physical` (`crates/rune/src/input/physical_input.rs`).
// PORT NOTE: Named `ScriptPhysicalInput` at top level (with `tooling.PhysicalInput` alias) so it never collides with Wave 2's `input/physical_input.swift`.
public enum ScriptPhysicalInput: Sendable, Equatable {
    case key(key: PhysicalKeyCode, mods: Mods, pressed: Bool, repeat: Bool)
    case modifiers(Mods)
    case focusLost
}

/// Where a `--desktop` run drew one window from time `t` on.
public struct WindowFrame: Sendable, Equatable {
    public var t: Double
    public var key: String
    /// `x, y, width, height` in output points (script coordinates).
    public var frame: [Float]
    public var visible: Bool
    /// The key window, which script keys reach.
    public var focused: Bool

    public init(
        t: Double,
        key: String,
        frame: [Float],
        visible: Bool,
        focused: Bool
    ) {
        self.t = t
        self.key = key
        self.frame = frame
        self.visible = visible
        self.focused = focused
    }
}

/// Where a pointer event lands, as the script wrote it.
public enum ScriptPoint: Sendable, Equatable {
    /// Points from the window's top-left.
    case at(Float, Float)
    /// The centre of the element with this key (or path suffix), found when the event runs.
    case element(String)
    /// An offset from the last pointer-down position (drags, the release of a tap).
    case fromDown(Float, Float)
}

/// Pointer action in a `ScriptEvent`.
public enum PointerAction: Sendable, Equatable {
    case move
    case down
    case up
    case secondaryDown
    case secondaryUp
    /// A wheel or trackpad delta in points.
    case scroll(Float)
    /// A trackpad release velocity in points per second.
    case fling(Float)
    /// A wheel or trackpad delta `(dx, dy)` in points with a horizontal part.
    case scrollXy(Float, Float)
    /// A release velocity `(vx, vy)` in points per second with a horizontal part.
    case flingXy(Float, Float)
    /// `{"type": "wheel"}`: one wheel delta with its modifiers and phase.
    case wheel(WheelEvent)
    /// `{"type": "magnify"}`: a trackpad pinch.
    case magnify(MagnifyEvent)
    /// `{"type": "rotate"}`: a two-finger rotation.
    case rotate(RotateEvent)
    /// `{"type": "smart-magnify"}`: a two-finger double tap.
    case smartMagnify
    /// A press of a button besides the primary and secondary (`"button": "middle"`).
    case buttonDown(PointerButton)
    case buttonUp(PointerButton)
}

/// One input (or marker) a script feeds the app.
public enum ScriptEvent: Sendable, Equatable {
    /// `{"type": "mark", "name": ...}`: a named point in time with no input effect.
    case mark(String)
    /// A logical key; `repeat` is a held key's auto-repeat.
    case key(key: KeyEvent, repeat: Bool)
    /// `{"type": "key-up"}`: a logical key's release.
    case keyUp(KeyEvent)
    case paste(String)
    /// A paste with HTML, RTF, or PNG beside the text.
    case pasteContent(ClipboardContent)
    /// A registered global shortcut chord. Only its handler runs; it never reaches `onKey`.
    case shortcut(Shortcut)
    /// A hardware key or modifier change (`{"physical": ...}`).
    case physical(ScriptPhysicalInput)
    case pointer(action: PointerAction, at: ScriptPoint)
    /// The window gaining (`true`) or losing (`false`) focus.
    case focus(Bool)
    /// `{"reopen": true}`: the app reopened, as a click on its macOS Dock icon does.
    case reopen
    /// `{"type": "resize", "dw": ..., "dh": ..., "dur": ...}`: a person resizing the window.
    case resize(dw: Float, dh: Float)
    /// A native menu item fired by name.
    case menu(String)
    /// A pop-up menu's picked item id, or `nil` when the script dismisses it.
    case popupMenu(String?)
    /// `{"type": "file-dialog", "path": ...}` or `nil` for `{"type": "file-dialog-cancel"}`.
    case fileDialog(String?)
    /// `{"drag_files": ...}`: a file drag from another app moved over the window.
    case dragFiles(paths: [String], at: ScriptPoint)
    /// `{"drop_files": ...}`: files dropped on the window.
    case dropFiles(paths: [String], at: ScriptPoint)
    /// `{"drag_files": "leave"}`: the file drag left the window.
    case dragFilesLeave
}

/// A script event at its time in seconds.
public struct TimedEvent: Sendable, Equatable {
    public var t: Double
    public var event: ScriptEvent

    public init(t: Double, event: ScriptEvent) {
        self.t = t
        self.event = event
    }
}

// PORT NOTE: Synchronized via `LiveLock` so `windowFrames()` and `windowsAt(_:)` are thread-safe across windows in a `--desktop` run.
final class HeadlessWindowsLog: @unchecked Sendable {
    private let lock = LiveLock()
    private var entries: [WindowFrame] = []

    init(_ initial: [WindowFrame] = []) {
        self.entries = initial
    }

    func append(_ frame: WindowFrame) {
        lock.withLock {
            entries.append(frame)
        }
    }

    func snapshot() -> [WindowFrame] {
        lock.withLock { entries }
    }
}

/// The headless run this process is rendering: its script, timing and output. One per run,
/// shared by every window, so a multi-window run reads the same timeline from each.
public final class HeadlessRun: Sendable {
    let scriptPath: String?
    let eventsList: [TimedEvent]
    let scaleVal: Float
    let fpsVal: Double
    let sizeVal: (Float, Float)
    let startVal: Double
    let framesVal: Int
    let endVal: Double
    let desktopPath: String?
    let windowsLog: HeadlessWindowsLog

    init(
        script: String?,
        events: [TimedEvent],
        scale: Float,
        fps: Double,
        size: (Float, Float),
        start: Double,
        frames: Int,
        end: Double,
        desktop: String?,
        windows: HeadlessWindowsLog = HeadlessWindowsLog()
    ) {
        self.scriptPath = script
        self.eventsList = events
        self.scaleVal = scale
        self.fpsVal = fps
        self.sizeVal = size
        self.startVal = start
        self.framesVal = frames
        self.endVal = end
        self.desktopPath = desktop
        self.windowsLog = windows
    }

    /// The `--desktop` backdrop, when the run composites every window over it.
    public func desktop() -> String? { desktopPath }

    /// A `--desktop` run's window frames so far: each window at the start, then one entry
    /// whenever one moves, resizes, shows, hides or takes keys. Empty otherwise.
    public func windowFrames() -> [WindowFrame] {
        windowsLog.snapshot()
    }

    /// Each window as it stands at time `t` in a `--desktop` run, in the order the app made them.
    public func windowsAt(_ t: Double) -> [WindowFrame] {
        let frames = windowsLog.snapshot()
        var out: [WindowFrame] = []
        for f in frames where f.t <= t + 1e-9 {
            if let idx = out.firstIndex(where: { $0.key == f.key }) {
                out[idx] = f
            } else {
                out.append(f)
            }
        }
        return out
    }

    /// The `--script` file.
    public func script() -> String? { scriptPath }

    /// The script's events in time order, expanded as Rune feeds them.
    public func events() -> [TimedEvent] { eventsList }

    /// The script's `mark` events, in time order: `(name, seconds)`.
    public func marks() -> [(String, Double)] {
        eventsList.compactMap { ev in
            if case .mark(let name) = ev.event {
                return (name, ev.t)
            }
            return nil
        }
    }

    /// The time of the first mark called `name`.
    public func mark(_ name: String) -> Double? {
        marks().first(where: { $0.0 == name })?.1
    }

    /// The time of the script's last event (marks included), or 0 without one.
    public func scriptEnd() -> Double {
        eventsList.last?.t ?? 0.0
    }

    /// Device pixels per point (`--scale`, default 2).
    public func scale() -> Float { scaleVal }

    /// Frames per virtual second (`--fps`, default 60).
    public func fps() -> Double { fpsVal }

    /// The rendered window's viewport in points (`--size`, or the window's own size); the whole
    /// output with `--desktop`.
    public func size() -> (Float, Float) { sizeVal }

    /// Seconds of virtual time at the first dumped frame (`--start`, marks resolved).
    public func start() -> Double { startVal }

    /// Frames written to `--video` or `--out` (0 for a `--snap` or `--tree` run).
    public func frames() -> Int { framesVal }

    /// Seconds of virtual time at the last frame the run renders.
    public func end() -> Double { endVal }
}

private let headlessRunLock = LiveLock()
// PORT NOTE: Guarded by `headlessRunLock` for process-wide `HeadlessRun` publication (`AtomicPtr<HeadlessRun>` in Rust).
nonisolated(unsafe) private var publishedHeadlessRun: HeadlessRun? = nil

/// The headless run this process is rendering, or `nil` in a window. Set before the app's
/// state is created, so `init`, `setup`, views and handlers can read it.
public func headlessRun() -> HeadlessRun? {
    headlessRunLock.withLock { publishedHeadlessRun }
}

func publishHeadlessRun(_ run: HeadlessRun) {
    headlessRunLock.withLock { publishedHeadlessRun = run }
}

func clearHeadlessRunForTests() {
    headlessRunLock.withLock { publishedHeadlessRun = nil }
}
