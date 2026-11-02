// Ported from: crates/rune/src/system_material/mod.rs
// Upstream commit: 5f6d53ddae78
// Port status: in-progress

public let MAX_NATIVE_MATERIALS: Int = 8

public enum SystemMaterial: Sendable, Equatable, Hashable {
    case sidebar
    case hudWindow
    case menu
    case popover
    case underWindowBackground
    case titlebar

    public static let Sidebar: SystemMaterial = .sidebar
    public static let HudWindow: SystemMaterial = .hudWindow
    public static let Menu: SystemMaterial = .menu
    public static let Popover: SystemMaterial = .popover
    public static let UnderWindowBackground: SystemMaterial = .underWindowBackground
    public static let Titlebar: SystemMaterial = .titlebar
}
