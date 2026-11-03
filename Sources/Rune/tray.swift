// Ported from: crates/rune/src/tray.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! A system tray icon with a flat menu: StatusNotifierItem and `com.canonical.dbusmenu` on
//! Linux, `Shell_NotifyIcon` on its own message-only window on Windows. Each tray runs on its own
//! thread, so it needs no event loop of the app's and answers while the app's window is closed.
//! A primary click sends `TrayEvent.activate`; a secondary click opens the menu, whose picks send
//! `TrayEvent.menu`. Dropping the `Tray` removes the icon.

/// The icon as straight (not premultiplied) RGBA rows, `width × height × 4` bytes.
public struct TrayIcon: Sendable, Equatable {
    var width: UInt32
    var height: UInt32
    var rgba: [UInt8]

    public static func rgba(_ width: UInt32, _ height: UInt32, _ pixels: [UInt8]) -> TrayIcon {
        TrayIcon(width: width, height: height, rgba: pixels)
    }
}

public enum TrayItem: Sendable, Equatable {
    /// `id` comes back in `TrayEvent.menu` when it's picked.
    case action(id: String, label: String, enabled: Bool)
    case separator

    public static func action(_ id: String, _ label: String) -> TrayItem {
        .action(id: id, label: label, enabled: true)
    }

    public func enabled(_ enabled: Bool) -> TrayItem {
        switch self {
        case .action(let id, let label, _):
            return .action(id: id, label: label, enabled: enabled)
        case .separator:
            return .separator
        }
    }
}

public enum TrayEvent: Sendable, Equatable {
    /// The icon's primary click. `token` is the XDG activation token a Wayland tray host hands
    /// over with it, for showing a window with focus.
    case activate(token: String?)
    /// A menu item's `id`.
    case menu(String)
}

public struct TraySpec: Sendable, Equatable {
    /// A stable application id (Linux `Id`).
    var id: String
    var title: String
    var tooltip: String
    var icon: TrayIcon
    var menu: [TrayItem]

    public init(_ id: String, _ title: String, _ icon: TrayIcon) {
        self.id = id
        self.title = title
        self.tooltip = ""
        self.icon = icon
        self.menu = []
    }

    public static func new(_ id: String, _ title: String, _ icon: TrayIcon) -> TraySpec {
        TraySpec(id, title, icon)
    }

    public func tooltip(_ tooltip: String) -> TraySpec {
        var copy = self
        copy.tooltip = tooltip
        return copy
    }

    public func menu(_ menu: [TrayItem]) -> TraySpec {
        var copy = self
        copy.menu = menu
        return copy
    }
}

public enum TrayError: Error, CustomStringConvertible, Sendable, Equatable {
    case unsupported
    case backend(String)

    public var description: String {
        switch self {
        case .unsupported:
            return "no system tray on this platform"
        case .backend(let e):
            return e
        }
    }
}

typealias TrayHandler = @Sendable (TrayEvent) -> Void

public final class Tray: Sendable {
    #if os(Linux)
    private let native: LinuxSniTray
    private init(native: LinuxSniTray) { self.native = native }
    #elseif os(Windows)
    private let native: Win32Tray
    private init(native: Win32Tray) { self.native = native }
    #else
    private init() {}
    #endif

    public static func new(_ spec: TraySpec, _ onEvent: @escaping @Sendable (TrayEvent) -> Void) -> Result<Tray, TrayError> {
        let expectedBytes = Int(spec.icon.width) * Int(spec.icon.height) * 4
        if spec.icon.rgba.count != expectedBytes {
            return .failure(.backend("tray icon size doesn't match its pixels"))
        }
        #if os(Linux)
        return LinuxSniTray.new(spec, onEvent).map { Tray(native: $0) }
        #elseif os(Windows)
        return Win32Tray.new(spec, onEvent).map { Tray(native: $0) }
        #else
        _ = onEvent
        return .failure(.unsupported)
        #endif
    }

    public func setMenu(_ menu: [TrayItem]) {
        #if os(Linux) || os(Windows)
        native.setMenu(menu)
        #else
        _ = menu
        #endif
    }

    public func setTooltip(_ tooltip: String) {
        #if os(Linux) || os(Windows)
        native.setTooltip(tooltip)
        #else
        _ = tooltip
        #endif
    }
}
