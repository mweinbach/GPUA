// Ported from: crates/rune/src/el/tx.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `Tx`: what a handler may say about the commit it causes.

import Foundation
import RuneMotion

/// A change to the text selection a handler asked for, carried out after its commit.
enum SelectRequest: Sendable, Equatable {
    case range(String, Range<Int>)
    case all(String)
    case clear
}

struct TraceCalls: Sendable {
    var events: [String] = []
    var channels: [(String, String, Float)] = []
}

final class PickReadCell {
    var fn: PickFn?
    init(_ fn: PickFn?) {
        self.fn = fn
    }
}

struct PickRead: CustomDebugStringConvertible {
    var within: String?
    var x: Float
    var y: Float
    var pick: Pick
    let cell: PickReadCell

    func take() -> PickFn? {
        let out = cell.fn
        cell.fn = nil
        return out
    }

    var debugDescription: String {
        "PickRead"
    }
}

/// What a handler asks of the window and the app (`Tx.closeWindow`, `Tx.quit`); the later variant wins
/// when several handlers ask.
public enum Shell: Int, Sendable, Equatable, Comparable {
    /// Close the window as if the user had: `App.keepRunning` keeps the app and its state.
    case close = 0
    case quit = 1

    public static func < (lhs: Shell, rhs: Shell) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What a handler may say about the commit it causes.
public struct Tx {
    var shortcutActivationToken: String? = nil
    var keyRepeatFlag: Bool = false
    /// `Tx.inputTime()`.
    var inputArrivalTime: RuneInstant? = nil
    var physicalKeyCode: PhysicalKeyCode? = nil
    var keyBaseChar: Character? = nil
    var focusedKey: String? = nil
    var instantFlag: Bool = false
    var motionSpring: Spring? = nil
    /// The layout curve from `Tx.motionCurve`; `motionSpring` holds its spring stand-in.
    var motionCurveAnim: Anim? = nil
    /// `Tx.followEdge()`.
    var followEdgeFlag: Bool = false
    var colorMotionSpring: Spring? = nil
    var settleFlag: Bool = false
    var relayoutFlag: Bool = false
    /// The viewport moved only because the window's own resize animation stepped it.
    var windowStepFlag: Bool = false
    var copyWrite: ClipboardWrite? = nil
    var pasteFlag: Bool = false
    var pickReads: [PickRead] = []
    var clearSecretFlag: Bool = false
    var textFlights: [(String, String)] = []
    /// `Tx.launch`: `(source, destination)`.
    var launches: [(String, String)] = []
    /// Rows to reveal or centre (`Tx.scrollIntoView` and `Tx.scrollCenter`).
    var scrollToRequests: [ScrollReveal] = []
    var scrollRevealScopes: [String?] = []
    /// Scroll viewports to send to their bottom: `(key, animated)`.
    var scrollBottomRequests: [(String, Bool)] = []
    /// Scroll viewports to page: `(key, pages)`.
    var scrollPagesRequests: [(String, Int32)] = []
    /// Scroll viewports to move to offsets (`Tx.scrollTo` and kin).
    var scrollOffsetRequests: [ScrollRequest] = []
    var scrollOffsetAnchors: [Bool] = []
    /// Elements to hold where they show across this commit (`Tx.keepOnScreen`).
    var keepOnScreenKeys: [String] = []
    var wakes: [TimeInterval] = []
    var shellRequest: Shell? = nil
    var minimizeFlag: Bool = false
    /// `Tx.dropPoint()`.
    var dropPointEvent: PointerEvent? = nil
    var titleString: String? = nil
    var openUrls: [OpenUrlLink] = []
    var traceCalls: TraceCalls? = nil
    var windowFrameRequest: WindowFrameRequest? = nil
    /// The mouse button driving this press or drag (`Tx.button()`).
    var buttonPressed: PointerButton = .primary
    /// Modifier keys held as the handler runs.
    var heldMods: Mods = Mods()
    var srgbBlendRequest: Bool? = nil
    var fontSmoothingRequest: FontSmoothing? = nil
    var fontFamiliesRequest: (String, String)? = nil
    var blurFlag: Bool = false
    /// The text selection as the event arrived (`Tx.textSelection()`).
    var currentSelection: TextSelection? = nil
    /// `Tx.selectText`, `Tx.selectAllText` and `Tx.clearTextSelection`; the last wins.
    var selectRequest: SelectRequest? = nil
    var selectFromChange: Bool = false
    /// `Tx.liveOnly()`: this handler changed nothing the view reads.
    var liveOnlyFlag: Bool = false

    public init() {}

    /// Pick from the last presented frame, with the geometry and visibility rules of
    /// `Runtime.elementAt`. Runs `f` after this handler, before its view commit.
    public mutating func elementAt<S>(
        _ x: Float,
        _ y: Float,
        _ f: @escaping (inout S, Picked?, inout Tx) -> Void
    ) {
        pickRead(within: nil, x: x, y: y, pick: Pick(), f)
    }

    /// ``elementAt(_:_:_:)`` with options (`Pick`).
    public mutating func elementAtWith<S>(
        _ x: Float,
        _ y: Float,
        _ pick: Pick,
        _ f: @escaping (inout S, Picked?, inout Tx) -> Void
    ) {
        pickRead(within: nil, x: x, y: y, pick: pick, f)
    }

    /// ``elementAt(_:_:_:)`` restricted to `within` and its descendants.
    public mutating func elementAtIn<S>(
        _ within: String,
        _ x: Float,
        _ y: Float,
        _ f: @escaping (inout S, Picked?, inout Tx) -> Void
    ) {
        pickRead(within: within, x: x, y: y, pick: Pick(), f)
    }

    /// ``elementAtIn(_:_:_:_:)`` with options (`Pick`).
    public mutating func elementAtInWith<S>(
        _ within: String,
        _ x: Float,
        _ y: Float,
        _ pick: Pick,
        _ f: @escaping (inout S, Picked?, inout Tx) -> Void
    ) {
        pickRead(within: within, x: x, y: y, pick: pick, f)
    }

    private mutating func pickRead<S>(
        within: String?,
        x: Float,
        y: Float,
        pick: Pick,
        _ f: @escaping (inout S, Picked?, inout Tx) -> Void
    ) {
        let cb: PickFn = { states, picked, tx in
            _ = states.withMutable { (state: inout S) in
                f(&state, picked, &tx)
            }
        }
        pickReads.append(PickRead(within: within, x: x, y: y, pick: pick, cell: PickReadCell(cb)))
    }

    /// Whether this runtime has an attached motion or tooling trace.
    public func tracing() -> Bool {
        traceCalls != nil
    }

    /// Work only a frame carries out that changes its pixels without a model change: a scroll
    /// or a text flight. A `wakeAfter` only schedules.
    func frameWork() -> Bool {
        !pickReads.isEmpty
            || !scrollToRequests.isEmpty
            || !scrollBottomRequests.isEmpty
            || !scrollPagesRequests.isEmpty
            || !scrollOffsetRequests.isEmpty
            || !keepOnScreenKeys.isEmpty
            || !textFlights.isEmpty
            || !launches.isEmpty
            || selectRequest != nil
    }

    /// An app marker on the next frame. Formatting is skipped when tracing is off.
    public mutating func traceEvent(_ event: any CustomStringConvertible) {
        traceCalls?.events.append(event.description)
    }

    /// A sample-and-hold scalar (`position`, `level`, or `phase`), e.g. `phase:recording`.
    /// No allocation when tracing is off.
    public mutating func traceChannel(_ name: String, _ kind: String, _ value: Float) {
        traceCalls?.channels.append((name, kind, value))
    }

    /// Wake the app's poll hook after an unscaled duration in seconds.
    public mutating func wakeAfter(_ seconds: TimeInterval) {
        wakes.append(seconds)
    }

    /// Wake the app's poll hook after an unscaled `Duration`.
    public mutating func wakeAfter(_ duration: Duration) {
        let secs = Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18
        wakes.append(secs)
    }

    /// Close the window after this handler, as the close button would (`App.onClose` runs).
    public mutating func closeWindow() {
        if let cur = shellRequest {
            shellRequest = max(cur, .close)
        } else {
            shellRequest = .close
        }
    }

    /// Quit the app after this handler, whether or not it keeps running without a window.
    public mutating func quit() {
        shellRequest = .quit
    }

    /// Minimize this window after this handler, as its minimize button would.
    public mutating func minimize() {
        minimizeFlag = true
    }

    /// Set this window's title after this handler, in its title bar and the Window menu.
    public mutating func setTitle(_ title: String) {
        titleString = title
    }

    /// Open `url` in the system's default handler once this handler's frame is done.
    public mutating func openUrl(_ url: String) throws {
        let checked = try checkOpenUrl(url)
        openUrls.append(OpenUrlLink(url: checked, sameTab: false))
    }

    /// ``openUrl(_:)``, but on web the link replaces this page instead of opening a tab.
    public mutating func openUrlSameTab(_ url: String) throws {
        let checked = try checkOpenUrlSameTab(url)
        openUrls.append(OpenUrlLink(url: checked, sameTab: true))
    }

    /// Resize this window's content to `size` points on this change's spring.
    public mutating func resizeWindow(_ size: (Float, Float)) {
        frameRequest(WindowFrameRequest(size: size, animate: true, center: false))
    }

    /// ``resizeWindow(_:)`` without the animation.
    public mutating func resizeWindowInstant(_ size: (Float, Float)) {
        frameRequest(WindowFrameRequest(size: size, animate: false, center: false))
    }

    /// Centre the window on its screen as AppKit's `center` does.
    public mutating func centerWindow() {
        frameRequest(WindowFrameRequest(size: nil, animate: false, center: true))
    }

    private mutating func frameRequest(_ request: WindowFrameRequest) {
        windowFrameRequest = (windowFrameRequest ?? WindowFrameRequest()).merge(request)
    }

    /// Drop keyboard focus, as a click on empty space does.
    public mutating func blur() {
        blurFlag = true
    }

    /// The `El.selectable` text selection as this event arrived.
    public func textSelection() -> TextSelection? {
        currentSelection
    }

    /// Select bytes `range` of the `El.selectable` text named `key` after this handler's commit.
    public mutating func selectText(_ key: String, _ range: Range<Int>) {
        selectRequest = .range(key, range)
        selectFromChange = false
    }

    /// Select all of the `El.selectable` text named `key`, or every selectable text inside it
    /// that shares the first one's `El.selectionGroup`.
    public mutating func selectAllText(_ key: String) {
        selectRequest = .all(key)
        selectFromChange = false
    }

    /// Clear the `El.selectable` text selection, as a click elsewhere does.
    public mutating func clearTextSelection() {
        selectRequest = .clear
        selectFromChange = false
    }

    /// Switch this window between linear and sRGB (gamma-space) blending from the next frame.
    public mutating func setSrgbBlend(_ enabled: Bool) {
        srgbBlendRequest = enabled
    }

    /// Rasterise and place this window's glyphs in `mode` from the next frame.
    public mutating func setFontSmoothing(_ mode: FontSmoothing) {
        fontSmoothingRequest = mode
    }

    /// Put `sans` and `mono` behind the `Family.sans` and `Family.mono` slots of every window and overlay.
    public mutating func setFontFamilies(_ sans: String, _ mono: String) {
        fontFamiliesRequest = (sans, mono)
    }

    /// This handler changed only `Live` values, or nothing else the view reads, so its event doesn't
    /// re-run the view or lay it out.
    public mutating func liveOnly() {
        liveOnlyFlag = true
    }

    /// A handler that declined its event (`taken` false) takes back its `liveOnly`.
    static func took(_ taken: Bool, _ tx: inout Tx) -> Bool {
        if !taken {
            tx.liveOnlyFlag = false
        }
        return taken
    }

    /// Apply this change with no animation (direct manipulation): layout snaps, and any
    /// newly mounted or removed elements enter or unmount at once.
    public mutating func instant() {
        instantFlag = true
    }

    /// Animate this change even where the runtime would apply it at once, as it does a drag's moves.
    public mutating func animated() {
        instantFlag = false
    }

    /// Animate this change's layout with `spring` instead of each element's own.
    public mutating func motion(_ spring: Spring) {
        motionSpring = spring
        motionCurveAnim = nil
    }

    /// Animate this change's layout on `anim` instead of each element's own spring.
    public mutating func motionCurve(_ anim: some AnimExt) {
        let converted = anim.intoAnim()
        switch converted.curve {
        case .spring(let s):
            motionSpring = s
        default:
            motionSpring = Spring.new(max(converted.curve.logicalDuration(), 0.01), 0.0)
        }
        motionCurveAnim = converted
    }

    /// Rows pinned to a stick-to-bottom viewport's bottom ride its edge through this change.
    public mutating func followEdge() {
        followEdgeFlag = true
    }

    /// Apply this change with no animation and land every running track: growth, reveals and
    /// follow-the-end.
    public mutating func settle() {
        instantFlag = true
        settleFlag = true
    }

    /// Animate this change's colours with `spring` (a theme change uses `tok.motion.CALM`).
    public mutating func colorMotion(_ spring: Spring) {
        colorMotionSpring = spring
    }

    public mutating func relayout() {
        relayoutFlag = true
    }

    public mutating func focus(_ key: String) {
        focusedKey = key
    }

    public mutating func copy(_ text: String) {
        copyWrite = .text(text)
    }

    public mutating func paste() {
        pasteFlag = true
    }

    public mutating func flyText(_ source: String, _ target: String) {
        textFlights.append((source, target))
    }

    public mutating func launch(_ source: String, _ destination: String) {
        launches.append((source, destination))
    }
}
