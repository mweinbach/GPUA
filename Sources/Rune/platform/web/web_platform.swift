// Ported from: crates/rune/src/platform/web/platform.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Browser platform bridge (`CWebSys` on WASI, no-op/unavailable elsewhere).

#if os(WASI)
import CWebSys
#endif

public struct WebPlatformError: Error, Sendable, Equatable, CustomStringConvertible {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

func webPlatformConsoleLog(_ level: Int32, _ message: String) {
    #if os(WASI)
    let utf8 = Array(message.utf8)
    utf8.withUnsafeBufferPointer { buf in
        cwebsys_console_log(level, buf.baseAddress, buf.count)
    }
    #else
    _ = level
    _ = message
    #endif
}

func webPlatformOpenLink(_ url: String) -> Result<Void, WebPlatformError> {
    #if os(WASI)
    let utf8 = Array(url.utf8)
    let ok = utf8.withUnsafeBufferPointer { buf in
        cwebsys_open_url(buf.baseAddress, buf.count)
    }
    return ok ? .success(()) : .failure(WebPlatformError("window.open failed"))
    #else
    _ = url
    return .failure(WebPlatformError("web platform is unavailable"))
    #endif
}

/// Resolves `url` to `(href, sameOrigin)`. Relative URLs (`/notes/42`, `?q=a`, `#top`) are on the page's origin.
func webPlatformResolveLink(_ url: String) -> Result<(String, Bool), WebPlatformError> {
    let firstDelim = url.utf8.firstIndex { $0 == 0x3A || $0 == 0x2F || $0 == 0x3F || $0 == 0x23 }
    let isRelative = firstDelim == nil || url.utf8[firstDelim!] != 0x3A
    #if os(WASI)
    return .success((url, isRelative))
    #else
    if isRelative {
        return .success((url, true))
    }
    return .success((url, false))
    #endif
}

func webPlatformAssignLink(_ href: String) -> Result<Void, WebPlatformError> {
    #if os(WASI)
    let utf8 = Array(href.utf8)
    let ok = utf8.withUnsafeBufferPointer { buf in
        cwebsys_open_url(buf.baseAddress, buf.count)
    }
    return ok ? .success(()) : .failure(WebPlatformError("location.assign failed"))
    #else
    _ = href
    return .failure(WebPlatformError("web platform is unavailable"))
    #endif
}

func webPlatformSetDocumentTitle(_ title: String) {
    #if os(WASI)
    let utf8 = Array(title.utf8)
    utf8.withUnsafeBufferPointer { buf in
        cwebsys_set_document_title(buf.baseAddress, buf.count)
    }
    #else
    _ = title
    #endif
}

func webPlatformSetCursorStyle(_ css: String) {
    #if os(WASI)
    let utf8 = Array(css.utf8)
    utf8.withUnsafeBufferPointer { buf in
        cwebsys_set_cursor_style(buf.baseAddress, buf.count)
    }
    #else
    _ = css
    #endif
}

func webPlatformDevicePixelRatio() -> Float {
    #if os(WASI)
    return Float(max(cwebsys_device_pixel_ratio(), 0.5))
    #else
    return 1.0
    #endif
}

func webPlatformPrefersDarkMode() -> Bool {
    #if os(WASI)
    return cwebsys_prefers_dark_mode()
    #else
    return false
    #endif
}

func webPlatformWindowInnerSize() -> (UInt32, UInt32) {
    #if os(WASI)
    let scale = max(cwebsys_device_pixel_ratio(), 0.5)
    let w = UInt32(max((cwebsys_window_inner_width() * scale).rounded(), 1.0))
    let h = UInt32(max((cwebsys_window_inner_height() * scale).rounded(), 1.0))
    return (w, h)
    #else
    return (800, 600)
    #endif
}
