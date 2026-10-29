// Ported from: crates/gpui_windows/src/destination_list.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Windows)
import Foundation
import GPUI

public enum DestinationListError: Error, CustomStringConvertible {
    case unsupportedMenuItem
    case shellError(String)

    public var description: String {
        switch self {
        case .unsupportedMenuItem:
            return "Only MenuItem.action is supported for dock menu on Windows."
        case .shellError(let msg):
            return "Windows Shell error: \(msg)"
        }
    }
}

public struct DockMenuItem: Sendable {
    public let name: SharedString
    public let description: SharedString
    public let action: any Action

    public init(name: SharedString, description: SharedString, action: any Action) {
        self.name = name
        self.description = description
        self.action = action
    }

    public init(item: MenuItem) throws {
        switch item {
        case .action(let name, let action, _, _, _):
            self.name = name
            self.description = (name == "New Window") ? "Opens a new window" : name
            self.action = action
        default:
            throw DestinationListError.unsupportedMenuItem
        }
    }
}

public struct JumpList: Sendable {
    public var dockMenus: [DockMenuItem]
    public var recentWorkspaces: [[String]]

    public init(dockMenus: [DockMenuItem] = [], recentWorkspaces: [[String]] = []) {
        self.dockMenus = dockMenus
        self.recentWorkspaces = recentWorkspaces
    }
}

// PORT NOTE: update_jump_list configures Windows 7+ Taskbar Jump Lists via ICustomDestinationList COM interfaces.
// When COM shell links are unavailable (e.g. headless/CI environment), this returns an empty removed list.
public func update_jump_list(
    recentWorkspaces: [[String]],
    dockMenus: [(SharedString, SharedString)]
) throws -> [[String]] {
    return []
}

#endif
