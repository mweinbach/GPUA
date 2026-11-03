// Ported from: crates/rune/src/platform/macos/presence.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Whether a panel counts as shown, and so whether its capture exclusion is applied.
//!
//! A prewarmed panel stays ordered in at alpha zero while hidden, so its show is instant. Panels
//! join every Space, and macOS blanks a Space's Mission Control thumbnail while a window with
//! `sharingType` none is on it, even a transparent one. So the exclusion an app requests is
//! applied only while the panel is shown: from `show` (before its alpha starts rising) until a
//! hide's fade-out finishes. A show during that fade bumps the generation, so the stale fade's
//! completion changes nothing.

struct MacOverlayPresence: Sendable, Equatable {
    /// Bumped by every show and hide, so a finished fade acts only if nothing came after it.
    private var generation: UInt64 = 0
    private var shown: Bool = false
    private var requestedFlag: Bool = false

    init(requested: Bool = false) {
        self.requestedFlag = requested
    }

    static func new(_ requested: Bool) -> MacOverlayPresence {
        MacOverlayPresence(requested: requested)
    }

    /// What the app asked for, shown or not.
    func requested() -> Bool {
        requestedFlag
    }

    /// Whether `sharingType` should be none now; read-only otherwise.
    func excluded() -> Bool {
        requestedFlag && shown
    }

    mutating func request(_ exclude: Bool) {
        requestedFlag = exclude
    }

    /// A show starts. Returns its fade's generation.
    @discardableResult
    mutating func show() -> UInt64 {
        shown = true
        return bump()
    }

    /// A hide starts. Without a fade it has finished; with one, `fadeDone` finishes it.
    @discardableResult
    mutating func hide(_ fading: Bool) -> UInt64 {
        if !fading {
            shown = false
        }
        return bump()
    }

    /// The fade started as `generation` finished. False if a later show or hide replaced it.
    mutating func fadeDone(_ generation: UInt64, _ hiding: Bool) -> Bool {
        if generation != self.generation {
            return false
        }
        if hiding {
            shown = false
        }
        return true
    }

    private mutating func bump() -> UInt64 {
        generation &+= 1
        return generation
    }
}
