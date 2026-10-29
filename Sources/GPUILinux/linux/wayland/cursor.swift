// Ported from: crates/gpui_linux/src/linux/wayland/cursor.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux)
import Foundation
import CLinuxSys
import GPUI

public let DEFAULT_CURSOR_ICON_NAME: String = "left_ptr"

public func logCursorIconWarning(_ message: String) {
    #if DEBUG
    print("[WARN] wayland: \(message)")
    #endif
}

// PORT NOTE: LoadedTheme holds the active wl_cursor_theme and associated scale/name metadata.
public final class LoadedTheme: @unchecked Sendable {
    public var theme: OpaquePointer?
    public var name: String?
    public var scaledSize: UInt32

    public init(theme: OpaquePointer? = nil, name: String? = nil, scaledSize: UInt32 = 24) {
        self.theme = theme
        self.name = name
        self.scaledSize = scaledSize
    }

    deinit {
        if let theme = theme {
            wl_cursor_theme_destroy(theme)
        }
    }
}

// PORT NOTE: Cursor manages Wayland cursor surfaces and theme loading across pointer events.
public final class Cursor: @unchecked Sendable {
    public var loadedTheme: LoadedTheme?
    public var size: UInt32
    public var scaledSize: UInt32
    public var surface: OpaquePointer?
    public var shm: OpaquePointer?
    public var connection: OpaquePointer?

    public init(
        connection: OpaquePointer? = nil,
        surface: OpaquePointer? = nil,
        shm: OpaquePointer? = nil,
        size: UInt32 = 24
    ) {
        self.loadedTheme = nil
        self.size = size
        self.scaledSize = size
        self.surface = surface
        self.shm = shm
        self.connection = connection
        setThemeInternal(nil)
    }

    public static func new(
        connection: OpaquePointer? = nil,
        surface: OpaquePointer? = nil,
        shm: OpaquePointer? = nil,
        size: UInt32 = 24
    ) -> Cursor {
        Cursor(connection: connection, surface: surface, shm: shm, size: size)
    }

    deinit {
        loadedTheme = nil
        if let surface = surface {
            wl_surface_destroy(surface)
        }
    }

    private func setThemeInternal(_ themeName: String?) {
        if let loaded = loadedTheme, loaded.name == themeName, loaded.scaledSize == scaledSize {
            return
        }

        guard let shm = shm else { return }

        let themePtr: OpaquePointer?
        if let themeName = themeName {
            themePtr = wl_cursor_theme_load(themeName, Int32(scaledSize), shm)
        } else {
            themePtr = wl_cursor_theme_load(nil, Int32(scaledSize), shm)
        }

        if let themePtr = themePtr {
            self.loadedTheme = LoadedTheme(theme: themePtr, name: themeName, scaledSize: scaledSize)
        }
    }

    public func setTheme(_ themeName: String) {
        setThemeInternal(themeName)
    }

    private func setScaledSize(_ scaledSize: UInt32) {
        self.scaledSize = scaledSize
        let themeName = loadedTheme?.name
        setThemeInternal(themeName)
    }

    public func setSize(_ size: UInt32) {
        self.size = size
        setScaledSize(size)
    }

    public func setIcon(
        _ wlPointer: OpaquePointer?,
        _ serialId: UInt32,
        _ cursorIconNames: [String],
        _ scale: Int32
    ) {
        let safeScale = max(scale, 1)
        setScaledSize(size * UInt32(safeScale))

        guard let loadedTheme = loadedTheme, let theme = loadedTheme.theme else {
            return
        }

        var cursor: UnsafeMutablePointer<wl_cursor>? = nil
        for name in cursorIconNames {
            if let c = wl_cursor_theme_get_cursor(theme, name) {
                cursor = c
                break
            }
        }

        if cursor == nil {
            if let c = wl_cursor_theme_get_cursor(theme, DEFAULT_CURSOR_ICON_NAME) {
                cursor = c
                logCursorIconWarning("Unable to get cursor icon \(cursorIconNames). Using default cursor icon: '\(DEFAULT_CURSOR_ICON_NAME)'")
            } else {
                logCursorIconWarning("Unable to fallback on default cursor icon '\(DEFAULT_CURSOR_ICON_NAME)' for theme '\(loadedTheme.name ?? "default")'")
                return
            }
        }

        guard let validCursor = cursor else { return }
        let cursorImages = validCursor.pointee.images
        guard let firstImagePtr = cursorImages?[0] else { return }
        let image = firstImagePtr.pointee
        let buffer = wl_cursor_image_get_buffer(firstImagePtr)

        if let surface = surface {
            wl_surface_set_buffer_scale(surface, safeScale)
            if let wlPointer = wlPointer {
                wl_pointer_set_cursor(
                    wlPointer,
                    serialId,
                    surface,
                    Int32(image.hotspot_x) / safeScale,
                    Int32(image.hotspot_y) / safeScale
                )
            }
            wl_surface_attach(surface, buffer, 0, 0)
            wl_surface_damage(surface, 0, 0, Int32(image.width), Int32(image.height))
            wl_surface_commit(surface)
        }
    }
}
#endif
