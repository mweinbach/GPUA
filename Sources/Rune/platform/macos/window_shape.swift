// Ported from: crates/rune/src/platform/macos/window_shape.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Rounded corners and shadow re-sampling for transparent macOS windows.

#if os(macOS)
import AppKit
import QuartzCore
#endif

/// When to re-sample a transparent window's shadow. Drawables are numbered monotonically.
enum MacShadowResample: Sendable, Equatable {
    case idle
    /// Once the next frame presents.
    case nextFrame
    /// Once drawable `n` is on screen.
    case onScreen(UInt64)

    init() {
        self = .idle
    }

    /// Ordered in or revealed. The last presented drawable (0 for none) will do, since a
    /// reveal of cached pixels draws nothing new. A frame already awaited stays awaited.
    mutating func shown(_ last: UInt64) {
        if self == .idle {
            self = last > 0 ? .onScreen(last) : .nextFrame
        }
    }

    /// Resized, rescaled or prewarmed: only a frame drawn for the new state will do.
    mutating func redraw() {
        self = .nextFrame
    }

    /// Drawable `n` was presented.
    mutating func presented(_ n: UInt64) {
        if self == .nextFrame {
            self = .onScreen(n)
        }
    }

    mutating func hidden() {
        self = .idle
    }

    /// A run loop turn, with the newest drawable on screen. True once: re-sample now.
    mutating func turn(_ onScreen: UInt64) -> Bool {
        let isDue = due(onScreen)
        if isDue {
            self = .idle
        }
        return isDue
    }

    /// Whether the drawable it awaits is already on screen.
    func due(_ onScreen: UInt64) -> Bool {
        if case .onScreen(let n) = self {
            return onScreen >= n
        }
        return false
    }
}

#if os(macOS)
/// Rounds the window's content layer when the options ask for it and the window is
/// transparent and borderless. Runs on each native creation, after Metal adds its layer.
@MainActor
func macApplyWindowCorners(
    view: NSView,
    cornerRadius: Float?,
    cornerCurveCircular: Bool,
    transparent: Bool,
    borderless: Bool
) {
    guard transparent && borderless, let radius = cornerRadius else { return }
    view.wantsLayer = true
    guard let layer = view.layer else { return }
    layer.cornerRadius = CGFloat(radius)
    layer.cornerCurve = cornerCurveCircular ? .circular : .continuous
    layer.masksToBounds = true
}

/// Whether a window re-samples its shadow: transparent, with the system shadow on.
@MainActor
func macWindowResamples(_ window: NSWindow, transparent: Bool) -> Bool {
    transparent && window.hasShadow
}

protocol MacDrawablePresentationLog: AnyObject, Sendable {
    func lastAcquired() -> UInt64
    func onScreen() -> UInt64
    func watch(_ watching: Bool)
}

/// One window's shadow re-sampling, fed by its layer's presentation log.
@MainActor
final class MacWindowShadow {
    private let window: NSWindow
    private let log: any MacDrawablePresentationLog
    private var state: MacShadowResample = .idle
    private var last: UInt64 = 0

    init(window: NSWindow, log: any MacDrawablePresentationLog, first: Bool) {
        self.window = window
        self.log = log
        if first {
            update { $0.redraw() }
        }
    }

    func shown() {
        let prev = last
        update { $0.shown(prev) }
    }

    func redraw() {
        update { $0.redraw() }
    }

    func hidden() {
        update { $0.hidden() }
    }

    func presented() {
        let n = log.lastAcquired()
        last = n
        update { $0.presented(n) }
    }

    /// At the start of each run loop turn.
    func turn() {
        guard state != .idle else { return }
        if state.turn(log.onScreen()) {
            window.invalidateShadow()
        }
        log.watch(state != .idle)
    }

    private func update(_ f: (inout MacShadowResample) -> Void) {
        f(&state)
        log.watch(state != .idle)
        if state.due(log.onScreen()) {
            runOnMainQueue {}
        }
    }
}
#endif
