// Ported from: crates/gpui_ios/src/lifecycle.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(iOS) || os(visionOS)
import Foundation
import GPUI
import UIKit

// MARK: - Notification Center Lifecycle Observers

// PORT NOTE: Replaces upstream ObjC runtime `ClassDecl` observer classes (`GPUIThermalObserver`,
// `GPUIInputModeObserver`, `GPUISceneObserver`, and keyboard frame observer) with native Swift
// `NSObject` notification observers that automatically unregister in `deinit` (ADR-0011).

/// Observes `ProcessInfo.thermalStateDidChangeNotification` and invokes the platform thermal
/// state callback on the main queue.
// PORT NOTE: Immutable callback invoked on the main queue; observer token unregistered in deinit.
final class GPUIThermalObserver: NSObject, @unchecked Sendable {
    private let callback: () -> Void
    // PORT NOTE: Assigned once in init and unregistered once in deinit via thread-safe NotificationCenter.
    private nonisolated(unsafe) var token: (any NSObjectProtocol)?

    init(callback: @escaping () -> Void) {
        self.callback = callback
        super.init()
        self.token = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.callback()
        }
    }

    deinit {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

/// Observes `UITextInputMode.currentInputModeDidChangeNotification` and defers layout refresh
/// asynchronously onto the next main run-loop turn to avoid re-entrant `activeInputModes` deadlocks.
// PORT NOTE: Immutable callback hopped onto DispatchQueue.main; observer token unregistered in deinit.
final class GPUIInputModeObserver: NSObject, @unchecked Sendable {
    private let callback: () -> Void
    // PORT NOTE: Assigned once in init and unregistered once in deinit via thread-safe NotificationCenter.
    private nonisolated(unsafe) var token: (any NSObjectProtocol)?

    init(callback: @escaping () -> Void) {
        self.callback = callback
        super.init()
        self.token = NotificationCenter.default.addObserver(
            forName: UITextInputMode.currentInputModeDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.callback()
            }
        }
    }

    deinit {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

/// Observes `UIScene` activation, deactivation, backgrounding, and foregrounding notifications
/// for an `IosWindow` so `CADisplayLink` pauses immediately when backgrounded (avoiding iOS
/// background Metal command-buffer termination) and resumes on foreground entry.
@MainActor
final class GPUISceneObserver: NSObject {
    private weak var windowState: IosWindowState?
    // PORT NOTE: Populated in init and unregistered in deinit via thread-safe NotificationCenter.
    private nonisolated(unsafe) var tokens: [any NSObjectProtocol] = []

    init(windowState: IosWindowState, scene: UIScene?) {
        self.windowState = windowState
        super.init()

        let center = NotificationCenter.default

        tokens.append(
            center.addObserver(
                forName: UIScene.didActivateNotification,
                object: scene,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleDidActivate()
                }
            }
        )

        tokens.append(
            center.addObserver(
                forName: UIScene.willDeactivateNotification,
                object: scene,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleWillDeactivate()
                }
            }
        )

        tokens.append(
            center.addObserver(
                forName: UIScene.didEnterBackgroundNotification,
                object: scene,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleDidEnterBackground()
                }
            }
        )

        tokens.append(
            center.addObserver(
                forName: UIScene.willEnterForegroundNotification,
                object: scene,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleWillEnterForeground()
                }
            }
        )
    }

    deinit {
        let center = NotificationCenter.default
        for token in tokens {
            center.removeObserver(token)
        }
    }

    private func handleDidActivate() {
        guard let state = windowState else { return }
        if !state.isActive {
            state.isActive = true
            state.activeStatusChangeCallback?(true)
        }
        state.displayLink?.start()
    }

    private func handleWillDeactivate() {
        guard let state = windowState else { return }
        if state.isActive {
            state.isActive = false
            state.activeStatusChangeCallback?(false)
        }
    }

    private func handleDidEnterBackground() {
        guard let state = windowState else { return }
        state.displayLink?.stop()
        if state.isActive {
            state.isActive = false
            state.activeStatusChangeCallback?(false)
        }
    }

    private func handleWillEnterForeground() {
        guard let state = windowState else { return }
        state.displayLink?.start()
        state.requestFrameCallback?(RequestFrameOptions())
    }
}

/// Observes `UIResponder.keyboardWillChangeFrameNotification` and `keyboardWillHideNotification`
/// to compute software keyboard overlap height in logical points (`Pixels`) for `IosWindow`.
@MainActor
final class GPUIKeyboardFrameObserver: NSObject {
    private weak var windowState: IosWindowState?
    // PORT NOTE: Populated in init and unregistered in deinit via thread-safe NotificationCenter.
    private nonisolated(unsafe) var tokens: [any NSObjectProtocol] = []

    init(windowState: IosWindowState) {
        self.windowState = windowState
        super.init()

        let center = NotificationCenter.default
        tokens.append(
            center.addObserver(
                forName: UIResponder.keyboardWillChangeFrameNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let endFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
                MainActor.assumeIsolated {
                    self?.updateKeyboardOverlap(endFrameScreenRect: endFrame)
                }
            }
        )

        tokens.append(
            center.addObserver(
                forName: UIResponder.keyboardWillHideNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.setKeyboardHeight(0.0)
                }
            }
        )
    }

    deinit {
        let center = NotificationCenter.default
        for token in tokens {
            center.removeObserver(token)
        }
    }

    private func updateKeyboardOverlap(endFrameScreenRect: CGRect?) {
        guard let state = windowState,
              let uiWindow = state.uiWindow,
              let screenRect = endFrameScreenRect else {
            return
        }
        let converted = uiWindow.convert(screenRect, from: nil)
        let windowBounds = uiWindow.bounds
        let intersection = windowBounds.intersection(converted)
        let overlapHeight: Float
        if intersection.isNull || intersection.isEmpty {
            overlapHeight = 0.0
        } else {
            overlapHeight = max(0.0, Float(intersection.height))
        }
        setKeyboardHeight(overlapHeight)
    }

    private func setKeyboardHeight(_ newHeight: Float) {
        guard let state = windowState else { return }
        let clamped = px(max(0.0, newHeight))
        if state.keyboardHeight != clamped {
            state.keyboardHeight = clamped
            let size = state.contentSize()
            let scale = state.scaleFactor()
            state.resizeCallback?(size, scale)
            state.requestFrameCallback?(RequestFrameOptions())
        }
    }
}
#endif
