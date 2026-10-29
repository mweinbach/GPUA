// Ported from: crates/gpui_linux/src/linux/x11/display.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux)
import Foundation
import GPUI
import CLinuxSys

// PORT NOTE: X11Display wraps immutable screen bounds and UUID across concurrency boundaries.
public final class X11Display: PlatformDisplay, @unchecked Sendable {
    public let screenIndex: Int
    public let displayBounds: Bounds<Pixels>
    public let displayUuid: UUID

    public init(screenIndex: Int = 0, bounds: Bounds<Pixels> = Bounds(origin: .zero, size: Size(width: px(1920), height: px(1080))), uuid: UUID = UUID()) {
        self.screenIndex = screenIndex
        self.displayBounds = bounds
        self.displayUuid = uuid
    }

    public static func new(
        connection: OpaquePointer?,
        scaleFactor: Float = 1.0,
        screenIndex: Int = 0
    ) throws -> X11Display {
        let factor = max(scaleFactor, 0.001)
        if let connection = connection {
            let setup = xcb_get_setup(connection)
            var iter = xcb_setup_roots_iterator(setup)
            var currentIndex = 0
            while iter.rem > 0 {
                if currentIndex == screenIndex, let screen = iter.data {
                    let w = Float(screen.pointee.width_in_pixels) / factor
                    let h = Float(screen.pointee.height_in_pixels) / factor
                    let bounds = Bounds(origin: .zero, size: Size(width: px(w), height: px(h)))
                    return X11Display(screenIndex: screenIndex, bounds: bounds)
                }
                xcb_screen_next(&iter)
                currentIndex += 1
            }
        }
        // Fallback default screen if connection unavailable or screenIndex not found
        let defaultBounds = Bounds(origin: .zero, size: Size(width: px(1920.0 / factor), height: px(1080.0 / factor)))
        return X11Display(screenIndex: screenIndex, bounds: defaultBounds)
    }

    public static func new(
        scaleFactor: Float = 1.0,
        screenIndex: Int = 0
    ) -> X11Display {
        let factor = max(scaleFactor, 0.001)
        let defaultBounds = Bounds(origin: .zero, size: Size(width: px(1920.0 / factor), height: px(1080.0 / factor)))
        return X11Display(screenIndex: screenIndex, bounds: defaultBounds)
    }

    public func id() -> DisplayId {
        DisplayId(UInt32(screenIndex))
    }

    public func uuid() -> UUID {
        displayUuid
    }

    public func bounds() -> Bounds<Pixels> {
        displayBounds
    }

    public func visibleBounds() -> Bounds<Pixels> {
        displayBounds
    }
}
#endif
