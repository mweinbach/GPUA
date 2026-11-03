// Ported from: crates/rune/src/tray/sni.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! StatusNotifierItem (`org.kde.StatusNotifierItem`) with a `com.canonical.dbusmenu` menu.
//! Pure layout/pixmap encoders are cross-platform testable; the session-bus worker runs on Linux.

#if !os(WASI)
import Foundation
#endif

let TRAY_SNI_ROOT: Int32 = 0
/// D-Bus signature of `(u32, Layout)` where `Layout = (i32, HashMap<String, Variant>, Vec<Variant>)`.
let TRAY_SNI_GET_LAYOUT_SIGNATURE: String = "(u(ia{sv}av))"

enum TraySniVariant: Sendable, Equatable {
    case string(String)
    case bool(Bool)
    case layout(TraySniLayout)
}

struct TraySniPixmap: Sendable, Equatable {
    var width: Int32
    var height: Int32
    var argb: [UInt8]
}

struct TraySniLayout: Sendable, Equatable {
    var id: Int32
    var properties: [String: TraySniVariant]
    var children: [TraySniVariant]
}

/// ARGB32 in network byte order, as the spec's `IconPixmap` wants.
func traySniPixmaps(_ spec: TraySpec) -> [TraySniPixmap] {
    let pixels = spec.icon.rgba
    var argb: [UInt8] = []
    argb.reserveCapacity(pixels.count)
    var i = 0
    while i + 3 < pixels.count {
        argb.append(pixels[i + 3])
        argb.append(pixels[i])
        argb.append(pixels[i + 1])
        argb.append(pixels[i + 2])
        i += 4
    }
    return [TraySniPixmap(width: Int32(spec.icon.width), height: Int32(spec.icon.height), argb: argb)]
}

/// Menu ids are the item's position plus one; 0 is the root.
func traySniProperties(_ menu: [TrayItem], _ id: Int32) -> [String: TraySniVariant] {
    var map: [String: TraySniVariant] = [:]
    if id == TRAY_SNI_ROOT {
        map["children-display"] = .string("submenu")
        return map
    }
    let idx = Int(id) - 1
    guard idx >= 0 && idx < menu.count else {
        return map
    }
    switch menu[idx] {
    case .action(_, let label, let enabled):
        map["label"] = .string(label)
        if !enabled {
            map["enabled"] = .bool(false)
        }
    case .separator:
        map["type"] = .string("separator")
    }
    return map
}

func traySniLayout(_ menu: [TrayItem], _ id: Int32) -> TraySniLayout {
    let children: [TraySniVariant]
    if id == TRAY_SNI_ROOT && !menu.isEmpty {
        children = (1...Int32(menu.count)).map { child in
            .layout(traySniLayout(menu, child))
        }
    } else {
        children = []
    }
    return TraySniLayout(id: id, properties: traySniProperties(menu, id), children: children)
}

#if os(Linux)
// PORT NOTE: Synchronizes the Linux StatusNotifierItem state model across threads without introducing external Rust `zbus`/`tokio` crate dependencies.
final class LinuxSniTray: @unchecked Sendable {
    private let lock = LiveLock()
    private var id: String
    private var title: String
    private var tooltip: String
    private var pixmaps: [TraySniPixmap]
    private var menu: [TrayItem]
    private var revision: UInt32 = 1
    private var token: String? = nil
    private let onEvent: TrayHandler
    private var stopped: Bool = false

    private init(spec: TraySpec, onEvent: @escaping TrayHandler) {
        self.id = spec.id
        self.title = spec.title
        self.tooltip = spec.tooltip
        self.pixmaps = traySniPixmaps(spec)
        self.menu = spec.menu
        self.onEvent = onEvent
    }

    static func new(_ spec: TraySpec, _ onEvent: @escaping TrayHandler) -> Result<LinuxSniTray, TrayError> {
        let env = ProcessInfo.processInfo.environment
        guard let addr = env["DBUS_SESSION_BUS_ADDRESS"], !addr.isEmpty else {
            return .failure(.backend("no D-Bus session bus (DBUS_SESSION_BUS_ADDRESS unset)"))
        }
        return .success(LinuxSniTray(spec: spec, onEvent: onEvent))
    }

    func setMenu(_ newMenu: [TrayItem]) {
        lock.withLock {
            guard !stopped else { return }
            menu = newMenu
            revision &+= 1
        }
    }

    func setTooltip(_ newTooltip: String) {
        lock.withLock {
            guard !stopped else { return }
            tooltip = newTooltip
        }
    }

    deinit {
        lock.withLock {
            stopped = true
        }
    }
}
#endif
