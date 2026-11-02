// Ported from: crates/rune/src/el/tx.rs
// Upstream commit: 5f6d53ddae78
// Port status: in-progress

//! `Tx`: what a handler may say about the commit it causes.

import Foundation
import RuneMotion

enum SelectRequest: Sendable, Equatable {
    case range(String, Range<Int>)
    case all(String)
    case clear
}

struct TraceCalls: Sendable {
    var events: [String] = []
    var channels: [(String, String, Float)] = []
}

/// What a handler asks of the window and the app (`Tx.closeWindow`, `Tx.quit`); the later variant wins.
public enum Shell: Int, Sendable, Equatable, Comparable {
    case close = 0
    case quit = 1

    public static func < (lhs: Shell, rhs: Shell) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What a handler may say about the commit it causes.
public struct Tx {
    var shortcutActivationToken: String? = nil
    var keyRepeat: Bool = false
    var inputTime: RuneInstant? = nil
    var keyBase: Character? = nil
    var focusedKey: String? = nil
    var instantFlag: Bool = false
    var motionSpring: Spring? = nil
    var motionCurveAnim: Anim? = nil
    var followEdgeFlag: Bool = false
    var colorMotionSpring: Spring? = nil
    var settleFlag: Bool = false
    var relayoutFlag: Bool = false
    var windowStepFlag: Bool = false
    var copyWrite: ClipboardWrite? = nil
    var pasteFlag: Bool = false
    var clearSecretFlag: Bool = false
    var textFlights: [(String, String)] = []
    var launches: [(String, String)] = []
    var scrollToRequests: [ScrollReveal] = []
    var scrollBottomRequests: [(String, Bool)] = []
    var scrollPagesRequests: [(String, Int32)] = []
    var scrollOffsetRequests: [ScrollRequest] = []
    var keepOnScreenKeys: [String] = []
    var wakes: [TimeInterval] = []
    var shellRequest: Shell? = nil
    var minimizeFlag: Bool = false
    var dropPointEvent: PointerEvent? = nil
    var titleString: String? = nil
    var openUrls: [OpenUrlLink] = []
    var traceCalls: TraceCalls? = nil
    var buttonPressed: PointerButton = .primary
    var heldMods: Mods = Mods()
    var srgbBlendRequest: Bool? = nil
    var fontSmoothingRequest: FontSmoothing? = nil
    var fontFamiliesRequest: (String, String)? = nil
    var blurFlag: Bool = false
    var currentSelection: TextSelection? = nil
    var selectRequest: SelectRequest? = nil
    var selectFromChange: Bool = false
    var liveOnlyFlag: Bool = false

    public init() {}

    public func tracing() -> Bool {
        traceCalls != nil
    }

    public mutating func traceEvent(_ event: any CustomStringConvertible) {
        traceCalls?.events.append(event.description)
    }

    public mutating func traceChannel(_ name: String, _ kind: String, _ value: Float) {
        traceCalls?.channels.append((name, kind, value))
    }

    public mutating func wakeAfter(_ seconds: TimeInterval) {
        wakes.append(seconds)
    }

    public mutating func closeWindow() {
        if let cur = shellRequest {
            shellRequest = max(cur, .close)
        } else {
            shellRequest = .close
        }
    }

    public mutating func quit() {
        shellRequest = .quit
    }

    public mutating func minimize() {
        minimizeFlag = true
    }

    public mutating func setTitle(_ title: String) {
        titleString = title
    }

    public mutating func openUrl(_ url: String) throws {
        let checked = try checkOpenUrl(url)
        openUrls.append(OpenUrlLink(url: checked, sameTab: false))
    }

    public mutating func openUrlSameTab(_ url: String) throws {
        let checked = try checkOpenUrlSameTab(url)
        openUrls.append(OpenUrlLink(url: checked, sameTab: true))
    }

    public mutating func blur() {
        blurFlag = true
    }

    public func textSelection() -> TextSelection? {
        currentSelection
    }

    public mutating func selectText(_ key: String, _ range: Range<Int>) {
        selectRequest = .range(key, range)
        selectFromChange = false
    }

    public mutating func selectAllText(_ key: String) {
        selectRequest = .all(key)
        selectFromChange = false
    }

    public mutating func clearTextSelection() {
        selectRequest = .clear
        selectFromChange = false
    }

    public mutating func setSrgbBlend(_ enabled: Bool) {
        srgbBlendRequest = enabled
    }

    public mutating func setFontSmoothing(_ mode: FontSmoothing) {
        fontSmoothingRequest = mode
    }

    public mutating func setFontFamilies(_ sans: String, _ mono: String) {
        fontFamiliesRequest = (sans, mono)
    }

    public mutating func liveOnly() {
        liveOnlyFlag = true
    }

    public mutating func instant() {
        instantFlag = true
    }

    public mutating func animated() {
        instantFlag = false
    }

    public mutating func motion(_ spring: Spring) {
        motionSpring = spring
        motionCurveAnim = nil
    }

    public mutating func motionCurve(_ anim: Anim) {
        switch anim.curve {
        case .spring(let s):
            motionSpring = s
        default:
            motionSpring = Spring.new(max(anim.curve.logicalDuration(), 0.01), 0.0)
        }
        motionCurveAnim = anim
    }

    public mutating func settle() {
        settleFlag = true
    }

    public mutating func relayout() {
        relayoutFlag = true
    }

    public mutating func focus(_ key: String) {
        focusedKey = key
    }

    public func focused() -> String? {
        focusedKey
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

    public mutating func scrollIntoView(_ key: String) {
        scrollToRequests.append(ScrollReveal(key: key, center: false, animated: true))
    }

    public mutating func scrollCenter(_ key: String) {
        scrollToRequests.append(ScrollReveal(key: key, center: true, animated: true))
    }

    public mutating func scrollToBottom(_ key: String, animated: Bool = true) {
        scrollBottomRequests.append((key, animated))
    }

    public mutating func scrollTo(_ key: String, _ y: Float, animated: Bool = true) {
        scrollOffsetRequests.append(ScrollRequest(key: key, x: nil, y: y, animated: animated, spring: nil))
    }
}
