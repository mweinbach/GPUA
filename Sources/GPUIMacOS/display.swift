// Ported from: crates/gpui_macos/src/display.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(macOS)
import AppKit
import ApplicationServices
import CoreFoundation
import CoreGraphics
import Foundation
import GPUI

/// Represents a physical or virtual macOS display backed by `CGDirectDisplayID`.
public final class MacDisplay: PlatformDisplay, Sendable, Equatable, Hashable, CustomDebugStringConvertible {
    public let displayId: CGDirectDisplayID

    public init(_ displayId: CGDirectDisplayID) {
        self.displayId = displayId
    }

    public var debugDescription: String {
        "MacDisplay(\(displayId))"
    }

    public static func == (lhs: MacDisplay, rhs: MacDisplay) -> Bool {
        lhs.displayId == rhs.displayId
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(displayId)
    }

    /// Finds the active display with the given `DisplayId`.
    public static func findById(_ id: DisplayId) -> MacDisplay? {
        all().first { $0.id() == id }
    }

    /// Returns the primary display (the display containing the menu bar and AppKit origin).
    public static func primary() -> MacDisplay {
        if Thread.isMainThread, let firstScreen = NSScreen.screens.first,
           let number = screenNumber(for: firstScreen)
        {
            return MacDisplay(number)
        }
        return MacDisplay(CGMainDisplayID())
    }

    /// Returns all currently active displays on the system.
    public static func all() -> [MacDisplay] {
        var displayIds = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        let err = CGGetActiveDisplayList(UInt32(displayIds.count), &displayIds, &count)
        guard err == .success else {
            return [MacDisplay(CGMainDisplayID())]
        }
        return displayIds.prefix(Int(count)).map { MacDisplay($0) }
    }

    public func id() -> DisplayId {
        DisplayId(displayId)
    }

    /// Returns the persistent hardware UUID for this display.
    public func uuid() throws -> UUID {
        guard let cfUuidUnmanaged = CGDisplayCreateUUIDFromDisplayID(displayId) else {
            throw NSError(
                domain: "GPUIMacOS.MacDisplay",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "CGDisplayCreateUUIDFromDisplayID returned nil for display \(displayId)"]
            )
        }
        let cfUuid = cfUuidUnmanaged.takeRetainedValue()
        let bytes = CFUUIDGetUUIDBytes(cfUuid)
        return UUID(uuid: (
            bytes.byte0, bytes.byte1, bytes.byte2, bytes.byte3,
            bytes.byte4, bytes.byte5, bytes.byte6, bytes.byte7,
            bytes.byte8, bytes.byte9, bytes.byte10, bytes.byte11,
            bytes.byte12, bytes.byte13, bytes.byte14, bytes.byte15
        ))
    }

    /// Returns the display's full bounds in GPUI top-left coordinates.
    public func bounds() -> Bounds<Pixels> {
        let cgBounds = CGDisplayBounds(displayId)
        return Bounds(
            origin: .zero,
            size: size(px(Float(cgBounds.size.width)), px(Float(cgBounds.size.height)))
        )
    }

    /// Returns the display's visible bounds (excluding the menu bar and Dock) in GPUI top-left coordinates.
    public func visibleBounds() -> Bounds<Pixels> {
        let computeOnMain: () -> Bounds<Pixels> = {
            guard let screen = self.nsScreen() else {
                return self.bounds()
            }
            let screenFrame = screen.frame
            let visibleFrame = screen.visibleFrame
            let originY = screenFrame.size.height - visibleFrame.origin.y - visibleFrame.size.height + screenFrame.origin.y
            return Bounds(
                origin: point(
                    px(Float(visibleFrame.origin.x - screenFrame.origin.x)),
                    px(Float(originY))
                ),
                size: size(
                    px(Float(visibleFrame.size.width)),
                    px(Float(visibleFrame.size.height))
                )
            )
        }

        if Thread.isMainThread {
            return computeOnMain()
        } else {
            return DispatchQueue.main.sync(execute: computeOnMain)
        }
    }

    func nsScreen() -> NSScreen? {
        for screen in NSScreen.screens {
            if Self.screenNumber(for: screen) == displayId {
                return screen
            }
        }
        return nil
    }

    static func screenNumber(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return CGDirectDisplayID(number.uint32Value)
        }
        return nil
    }
}
#endif
