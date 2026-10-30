// Ported from: crates/gpui_ios/src/lib.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(iOS) || os(visionOS)
import Foundation
import GPUI
import GPUIApple
import GPUIMetal
import Security
import UIKit

// MARK: - Scroll Momentum State

/// Tracks fling deceleration state after a pan gesture ends with velocity.
///
/// The display-link frame callback calls `IosWindow.tickScrollMomentum` each
/// frame to emit synthetic `ScrollWheelEvent`s with exponentially decaying
/// velocity until it drops below threshold (or a new touch cancels it).
struct ScrollMomentum: Sendable {
    /// Current velocity in points per second (positive = content moves right/down).
    var velocityX: Float = 0.0
    var velocityY: Float = 0.0
    /// Touch position where the pan ended (used for hit-testing the scroll target).
    var position: Point<Pixels> = .zero
    /// Timestamp of the last momentum tick.
    var lastTick: ContinuousClock.Instant? = nil
    /// Whether momentum is currently active.
    var active: Bool = false

    init(
        velocityX: Float = 0.0,
        velocityY: Float = 0.0,
        position: Point<Pixels> = .zero,
        lastTick: ContinuousClock.Instant? = nil,
        active: Bool = false
    ) {
        self.velocityX = velocityX
        self.velocityY = velocityY
        self.position = position
        self.lastTick = lastTick
        self.active = active
    }
}

// MARK: - System Appearance Detection

/// Detects the current system appearance (`WindowAppearance`) from the active
/// `UIWindowScene` trait collection (falling back to `UITraitCollection.current`).
///
/// Maps `UIUserInterfaceStyle` + `UIAccessibilityContrast` to GPUI's four
/// `WindowAppearance` cases (`light`, `vibrantLight`, `dark`, `vibrantDark`).
func detectSystemAppearance() -> WindowAppearance {
    let query: @MainActor () -> WindowAppearance = {
        var traitCollection: UITraitCollection = UITraitCollection.current
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene {
                if windowScene.activationState == .foregroundActive {
                    traitCollection = windowScene.traitCollection
                    break
                }
                traitCollection = windowScene.traitCollection
            }
        }
        return windowAppearanceFromTraitCollection(traitCollection)
    }

    if Thread.isMainThread {
        return MainActor.assumeIsolated(query)
    } else {
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated(query)
        }
    }
}

/// Converts a `UITraitCollection` into GPUI's `WindowAppearance`.
@MainActor
func windowAppearanceFromTraitCollection(_ traits: UITraitCollection) -> WindowAppearance {
    let isDark = traits.userInterfaceStyle == .dark
    let isHighContrast = traits.accessibilityContrast == .high

    switch (isDark, isHighContrast) {
    case (true, true):
        return .vibrantDark
    case (true, false):
        return .dark
    case (false, true):
        return .vibrantLight
    case (false, false):
        return .light
    }
}

// MARK: - Global Platform Open-URL Registry

// PORT NOTE: Synchronized via NSLock so C entry points (`gpui_ios_handle_open_url`) and
// `IosPlatform` registration can safely coordinate URL delivery across threads.
final class IosPlatformRegistry: @unchecked Sendable {
    static let shared = IosPlatformRegistry()

    private let lock = NSLock()
    private weak var activePlatform: IosPlatform?
    private var pendingUrls: [String] = []

    private init() {}

    func register(_ platform: IosPlatform) {
        lock.lock()
        activePlatform = platform
        let queued = pendingUrls
        pendingUrls.removeAll()
        lock.unlock()

        if !queued.isEmpty {
            platform.deliverOpenUrls(queued)
        }
    }

    func unregister(_ platform: IosPlatform) {
        lock.lock()
        if activePlatform === platform {
            activePlatform = nil
        }
        lock.unlock()
    }

    func handleOpenUrl(_ url: String) {
        lock.lock()
        let platform = activePlatform
        if platform == nil {
            pendingUrls.append(url)
        }
        lock.unlock()

        if let platform {
            platform.deliverOpenUrls([url])
        }
    }
}

///Forwards an incoming URL (deep link / custom URL scheme / file open) from the
///Objective-C or Swift host `UIApplicationDelegate` / `UISceneDelegate` into GPUI.
///
///Matches upstream C ABI symbol `gpui_ios_handle_open_url(const char *url_cstr)`.
@_cdecl("gpui_ios_handle_open_url")
public func gpuiIosHandleOpenUrl(_ urlCString: UnsafePointer<CChar>?) {
    guard let urlCString else { return }
    let url = String(cString: urlCString)
    guard !url.isEmpty else { return }

    if Thread.isMainThread {
        IosPlatformRegistry.shared.handleOpenUrl(url)
    } else {
        DispatchQueue.main.async {
            IosPlatformRegistry.shared.handleOpenUrl(url)
        }
    }
}
#endif
