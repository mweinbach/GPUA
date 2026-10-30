// Ported from: crates/gpui_ios/src/display.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(iOS) || os(visionOS)
import CoreGraphics
import Foundation
import GPUI
import UIKit

// MARK: - iOS Display

/// Represents a physical or connected screen on iOS (`UIScreen` / `UIWindowScene.screen`).
// PORT NOTE: Caches display identifier and synchronizes live `UIScreen` / safe-area queries
// onto the main actor when invoked from non-main threads so `PlatformDisplay` is thread-safe.
public final class IosDisplay: PlatformDisplay, @unchecked Sendable, Equatable, Hashable, CustomDebugStringConvertible {
    private let displayId: DisplayId
    private let screenObjectId: ObjectIdentifier?
    // PORT NOTE: Weak UIKit screen reference accessed exclusively on the main actor.
    private nonisolated(unsafe) weak var weakScreen: UIScreen?

    @MainActor
    init(displayId: DisplayId, screen: UIScreen?) {
        self.displayId = displayId
        self.screenObjectId = screen.map { ObjectIdentifier($0) }
        self.weakScreen = screen
    }

    /// Returns the primary display for the foreground active `UIWindowScene`
    /// (falling back to the first connected window scene's screen).
    public static func primary() -> IosDisplay {
        let makePrimary: @MainActor () -> IosDisplay = {
            let screen = Self.resolvePrimaryScreen()
            return IosDisplay(displayId: DisplayId(1), screen: screen)
        }

        if Thread.isMainThread {
            return MainActor.assumeIsolated(makePrimary)
        } else {
            return DispatchQueue.main.sync {
                MainActor.assumeIsolated(makePrimary)
            }
        }
    }

    /// Returns all currently connected displays across active `UIWindowScene`s.
    public static func all() -> [IosDisplay] {
        let queryAll: @MainActor () -> [IosDisplay] = {
            var screens: [UIScreen] = []
            for scene in UIApplication.shared.connectedScenes {
                #if !os(visionOS)
                if let windowScene = scene as? UIWindowScene {
                    let s = windowScene.screen
                    if !screens.contains(where: { $0 === s }) {
                        screens.append(s)
                    }
                }
                #endif
            }
            if screens.isEmpty {
                if let primaryScreen = Self.resolvePrimaryScreen() {
                    screens.append(primaryScreen)
                } else {
                    return [IosDisplay(displayId: DisplayId(1), screen: nil)]
                }
            }
            return screens.enumerated().map { idx, s in
                IosDisplay(displayId: DisplayId(UInt32(idx + 1)), screen: s)
            }
        }

        if Thread.isMainThread {
            return MainActor.assumeIsolated(queryAll)
        } else {
            return DispatchQueue.main.sync {
                MainActor.assumeIsolated(queryAll)
            }
        }
    }

    @MainActor
    private static func resolvePrimaryScreen() -> UIScreen? {
        #if os(visionOS)
        return nil
        #else
        var fallbackScreen: UIScreen?
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene {
                if windowScene.activationState == .foregroundActive {
                    return windowScene.screen
                }
                if fallbackScreen == nil {
                    fallbackScreen = windowScene.screen
                }
            }
        }
        return fallbackScreen ?? UIScreen.screens.first
        #endif
    }

    // MARK: - PlatformDisplay Conformance

    public func id() -> DisplayId {
        displayId
    }

    /// Returns a stable hardware/vendor UUID for this iOS device's display, matching upstream
    /// `IosDisplay::uuid()` (`UIDevice.currentDevice.identifierForVendor` with zero-UUID fallback).
    public func uuid() throws -> UUID {
        let queryUuid: @MainActor () -> UUID = {
            UIDevice.current.identifierForVendor
                ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")
                ?? UUID()
        }

        if Thread.isMainThread {
            return MainActor.assumeIsolated(queryUuid)
        } else {
            return DispatchQueue.main.sync {
                MainActor.assumeIsolated(queryUuid)
            }
        }
    }

    /// Returns the full screen bounds in logical points (`Pixels`).
    public func bounds() -> Bounds<Pixels> {
        let queryBounds: @MainActor () -> Bounds<Pixels> = {
            #if os(visionOS)
            for scene in UIApplication.shared.connectedScenes {
                if let windowScene = scene as? UIWindowScene,
                   let keyWin = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first {
                    let rect = keyWin.bounds
                    return Bounds(
                        origin: Point(x: px(Float(rect.origin.x)), y: px(Float(rect.origin.y))),
                        size: Size(width: px(Float(rect.size.width)), height: px(Float(rect.size.height)))
                    )
                }
            }
            return Bounds(origin: .zero, size: Size(width: px(1280.0), height: px(720.0)))
            #else
            let screen = self.weakScreen ?? Self.resolvePrimaryScreen()
            guard let rect = screen?.bounds else {
                return Bounds(origin: .zero, size: Size(width: px(393.0), height: px(852.0)))
            }
            return Bounds(
                origin: Point(x: px(Float(rect.origin.x)), y: px(Float(rect.origin.y))),
                size: Size(width: px(Float(rect.size.width)), height: px(Float(rect.size.height)))
            )
            #endif
        }

        if Thread.isMainThread {
            return MainActor.assumeIsolated(queryBounds)
        } else {
            return DispatchQueue.main.sync {
                MainActor.assumeIsolated(queryBounds)
            }
        }
    }

    /// Returns the visible screen bounds inset by the key window's `safeAreaInsets`
    /// (Dynamic Island / status bar / home indicator), matching upstream `IosDisplay::visible_bounds`.
    public func visibleBounds() -> Bounds<Pixels> {
        let queryVisible: @MainActor () -> Bounds<Pixels> = {
            let fullBounds = self.bounds()
            var matchingWindow: UIWindow?

            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                #if !os(visionOS)
                if let targetScreen = self.weakScreen, windowScene.screen !== targetScreen {
                    continue
                }
                #endif
                if let keyWin = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first {
                    matchingWindow = keyWin
                    if windowScene.activationState == .foregroundActive {
                        break
                    }
                }
            }

            guard let window = matchingWindow else {
                return fullBounds
            }

            let insets = window.safeAreaInsets
            let top = Float(insets.top)
            let left = Float(insets.left)
            let bottom = Float(insets.bottom)
            let right = Float(insets.right)

            let visibleWidth = max(0.0, fullBounds.size.width.value - left - right)
            let visibleHeight = max(0.0, fullBounds.size.height.value - top - bottom)

            return Bounds(
                origin: Point(
                    x: px(fullBounds.origin.x.value + left),
                    y: px(fullBounds.origin.y.value + top)
                ),
                size: Size(
                    width: px(visibleWidth),
                    height: px(visibleHeight)
                )
            )
        }

        if Thread.isMainThread {
            return MainActor.assumeIsolated(queryVisible)
        } else {
            return DispatchQueue.main.sync {
                MainActor.assumeIsolated(queryVisible)
            }
        }
    }

    /// Returns the screen's native scale factor (e.g. `3.0` on Pro iPhones, `2.0` on iPads).
    public func scaleFactor() -> Float {
        let queryScale: @MainActor () -> Float = {
            #if os(visionOS)
            return 2.0
            #else
            let screen = self.weakScreen ?? Self.resolvePrimaryScreen()
            let scale = Float(screen?.scale ?? 3.0)
            return scale > 0.0 ? scale : 1.0
            #endif
        }

        if Thread.isMainThread {
            return MainActor.assumeIsolated(queryScale)
        } else {
            return DispatchQueue.main.sync {
                MainActor.assumeIsolated(queryScale)
            }
        }
    }

    // MARK: - Equatable / Hashable / Debug

    public static func == (lhs: IosDisplay, rhs: IosDisplay) -> Bool {
        lhs.displayId == rhs.displayId && lhs.screenObjectId == rhs.screenObjectId
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(displayId)
        hasher.combine(screenObjectId)
    }

    public var debugDescription: String {
        "IosDisplay(id: \(displayId.rawValue), bounds: \(bounds()))"
    }
}
#endif
