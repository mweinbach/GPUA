// Ported from: crates/gpui_web/src/display.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
import GPUI
#if os(WASI)
import CWebSys
#endif

// PORT NOTE: WASM is single-threaded on the browser main thread, and non-WASI fallback properties are immutable or value-returned, matching upstream unsafe impl Send/Sync for WebDisplay.
public final class WebDisplay: PlatformDisplay, @unchecked Sendable, CustomDebugStringConvertible {
    private let displayId: DisplayId
    private let displayUuid: UUID
    private let fallbackScreenSize: Size<Pixels>
    private let fallbackViewportSize: Size<Pixels>

    public init(
        screenSize: Size<Pixels> = Size(width: px(1920.0), height: px(1080.0)),
        viewportSize: Size<Pixels> = Size(width: px(1920.0), height: px(1080.0))
    ) {
        self.displayId = DisplayId(1)
        self.displayUuid = UUID()
        self.fallbackScreenSize = screenSize
        self.fallbackViewportSize = viewportSize
    }

    public static func new() -> WebDisplay {
        WebDisplay()
    }

    public var debugDescription: String {
        "WebDisplay(id: \(displayId.rawValue), uuid: \(displayUuid))"
    }

    private func screenSize() -> Size<Pixels> {
        #if os(WASI)
        let rawWidth = cwebsys_screen_width()
        let rawHeight = cwebsys_screen_height()
        let width = rawWidth > 0 ? Float(rawWidth) : fallbackScreenSize.width.value
        let height = rawHeight > 0 ? Float(rawHeight) : fallbackScreenSize.height.value
        return Size(width: px(width), height: px(height))
        #else
        return fallbackScreenSize
        #endif
    }

    private func viewportSize() -> Size<Pixels> {
        #if os(WASI)
        let rawWidth = cwebsys_window_inner_width()
        let rawHeight = cwebsys_window_inner_height()
        let width = rawWidth > 0.0 ? Float(rawWidth) : fallbackViewportSize.width.value
        let height = rawHeight > 0.0 ? Float(rawHeight) : fallbackViewportSize.height.value
        return Size(width: px(width), height: px(height))
        #else
        return fallbackViewportSize
        #endif
    }

    public func id() -> DisplayId {
        displayId
    }

    public func uuid() throws -> UUID {
        displayUuid
    }

    public func bounds() -> Bounds<Pixels> {
        let size = screenSize()
        return Bounds(origin: .zero, size: size)
    }

    public func visibleBounds() -> Bounds<Pixels> {
        let size = viewportSize()
        return Bounds(origin: .zero, size: size)
    }

    public func defaultBounds() -> Bounds<Pixels> {
        let visible = visibleBounds()
        let width = visible.size.width * Float(0.75)
        let height = visible.size.height * Float(0.75)
        let originX: Pixels = (visible.size.width - width) / Float(2.0)
        let originY: Pixels = (visible.size.height - height) / Float(2.0)
        return Bounds(
            origin: Point(x: originX, y: originY),
            size: Size(width: width, height: height)
        )
    }
}
