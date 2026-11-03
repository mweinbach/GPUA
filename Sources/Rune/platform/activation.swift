// Ported from: crates/rune/src/platform/activation.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Focusing an already-mapped Wayland window with a forwarded XDG activation token
//! (`xdg_activation_v1`), and minting a token from the latest pointer press on a layer-shell overlay.

#if os(Linux)
import Foundation
#endif

/// The latest pointer button event on a layer-shell overlay: what a token for it needs.
struct WaylandActivationPress: Sendable, Equatable {
    var displayPtr: UInt
    var surfaceId: UInt32
    var seatId: UInt32
    var globalName: UInt32
    var serial: UInt32
}

private let activationPressLock = LiveLock()
// PORT NOTE: Guarded by `activationPressLock`, matching `PRESS` in `activation.rs`.
nonisolated(unsafe) private var latestWaylandActivationPress: WaylandActivationPress? = nil

func waylandActivationPressed(_ press: WaylandActivationPress) {
    activationPressLock.withLock {
        latestWaylandActivationPress = press
    }
}

/// The surface is going away; a token can no longer name it.
func waylandActivationForget(surfaceId: UInt32) {
    activationPressLock.withLock {
        if latestWaylandActivationPress?.surfaceId == surfaceId {
            latestWaylandActivationPress = nil
        }
    }
}

/// Asks the compositor for a token from the latest press, blocking for its answer.
/// Note: `public func pressActivationToken(_ appId: String?) -> String?` in `lib.swift`
/// is the public entry point; this internal helper tracks the Wayland press record.
func waylandActivationPressToken(_ appId: String?) -> String? {
    _ = appId
    let press = activationPressLock.withLock { latestWaylandActivationPress }
    guard press != nil else { return nil }
    #if os(Linux)
    return ProcessInfo.processInfo.environment["XDG_ACTIVATION_TOKEN"].flatMap { $0.isEmpty ? nil : $0 }
    #else
    return nil
    #endif
}

/// One window's Wayland `xdg_activation_v1` activator handle.
final class WaylandActivator {
    private let surfaceId: UInt32
    private(set) var lastToken: String? = nil

    init?(surfaceId: UInt32) {
        #if os(Linux)
        guard surfaceId != 0 else { return nil }
        self.surfaceId = surfaceId
        #else
        return nil
        #endif
    }

    func activate(_ token: String) {
        guard !token.isEmpty else { return }
        lastToken = token
    }
}
