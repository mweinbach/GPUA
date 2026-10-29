// Ported from: crates/gpui_windows/src/destination_list.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Windows)
import Foundation
import GPUI
#if canImport(CWinSys)
import CWinSys
#endif

public enum DestinationListError: Error, CustomStringConvertible, Sendable {
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
            self.description = (name.value == "New Window") ? SharedString("Opens a new window") : name
            self.action = action
        default:
            throw DestinationListError.unsupportedMenuItem
        }
    }

    public static func new(item: MenuItem) throws -> DockMenuItem {
        try DockMenuItem(item: item)
    }
}

public struct JumpList: Sendable {
    public var dockMenus: [DockMenuItem]
    public var recentWorkspaces: [[String]]

    public init(dockMenus: [DockMenuItem] = [], recentWorkspaces: [[String]] = []) {
        self.dockMenus = dockMenus
        self.recentWorkspaces = recentWorkspaces
    }

    public static func new() -> JumpList {
        JumpList()
    }
}

// MARK: - COM Jump List Implementation

private func createDestinationList() throws -> (destList: UnsafeMutableRawPointer, removed: [[String]]) {
    var rawList: UnsafeMutableRawPointer?
    let hrCreate = cwin_jump_list_create(&rawList)
    guard hrCreate == 0, let list = rawList else {
        throw DestinationListError.shellError("Failed to create ICustomDestinationList (HRESULT 0x\(String(UInt32(bitPattern: hrCreate), radix: 16)))")
    }

    var minSlots: UInt32 = 0
    var rawRemoved: UnsafeMutableRawPointer?
    let hrBegin = cwin_jump_list_begin_list(list, &minSlots, &rawRemoved)
    guard hrBegin == 0 else {
        cwin_release_com_object(list)
        throw DestinationListError.shellError("BeginList failed (HRESULT 0x\(String(UInt32(bitPattern: hrBegin), radix: 16)))")
    }

    var removed: [[String]] = []
    if let removedArray = rawRemoved {
        defer { cwin_release_com_object(removedArray) }
        let count = cwin_object_array_get_count(removedArray)
        removed.reserveCapacity(Int(count))
        var buffer = [UInt16](repeating: 0, count: 1024) // INFOTIPSIZE
        for i in 0..<count {
            var rawLink: UnsafeMutableRawPointer?
            if cwin_object_array_get_at(removedArray, i, &rawLink) == 0, let link = rawLink {
                defer { cwin_release_com_object(link) }
                buffer.withUnsafeMutableBufferPointer { bPtr in
                    if let base = bPtr.baseAddress,
                       cwin_shell_link_get_description(link, base, Int32(bPtr.count)) == 0 {
                        let len = bPtr.firstIndex(of: 0) ?? bPtr.count
                        let desc = String(utf16CodeUnits: base, count: len)
                        let paths = desc.components(separatedBy: "\n").filter { !$0.isEmpty }
                        removed.append(paths)
                    }
                }
            }
        }
    }

    return (destList: list, removed: removed)
}

private func addDockMenu(
    list: UnsafeMutableRawPointer,
    dockMenus: [(SharedString, SharedString)],
    exePath: String
) throws {
    var rawColl: UnsafeMutableRawPointer?
    let hrColl = cwin_object_collection_create(&rawColl)
    guard hrColl == 0, let coll = rawColl else {
        throw DestinationListError.shellError("Failed to create EnumerableObjectCollection (HRESULT 0x\(String(UInt32(bitPattern: hrColl), radix: 16)))")
    }
    defer { cwin_release_com_object(coll) }

    let exeWide = Array(exePath.utf16) + [0]
    for (idx, item) in dockMenus.enumerated() {
        let name = item.0
        let description = item.1
        let argument = "--dock-action \(idx)"
        let argWide = Array(argument.utf16) + [0]
        let descWide = Array(description.value.utf16) + [0]
        let titleWide = Array(name.value.utf16) + [0]

        var rawLink: UnsafeMutableRawPointer?
        let hrLink = cwin_shell_link_create(
            exeWide,
            argWide,
            descWide,
            nil,
            0,
            titleWide,
            &rawLink
        )
        guard hrLink == 0, let link = rawLink else { continue }
        defer { cwin_release_com_object(link) }

        _ = cwin_object_collection_add(coll, link)
    }

    let hrTasks = cwin_jump_list_add_user_tasks(list, coll)
    if hrTasks != 0 {
        throw DestinationListError.shellError("AddUserTasks failed (HRESULT 0x\(String(UInt32(bitPattern: hrTasks), radix: 16)))")
    }
}

private func addRecentFolders(
    list: UnsafeMutableRawPointer,
    entries: [[String]],
    removed: [[String]],
    exePath: String
) throws {
    var rawColl: UnsafeMutableRawPointer?
    let hrColl = cwin_object_collection_create(&rawColl)
    guard hrColl == 0, let coll = rawColl else {
        throw DestinationListError.shellError("Failed to create EnumerableObjectCollection (HRESULT 0x\(String(UInt32(bitPattern: hrColl), radix: 16)))")
    }
    defer { cwin_release_com_object(coll) }

    let exeWide = Array(exePath.utf16) + [0]
    let explorerWide = Array("explorer.exe".utf16) + [0]

    for folderPath in entries where !removed.contains(folderPath) {
        let argument = folderPath.map { "\"\($0)\"" }.joined(separator: " ")
        let description = folderPath.joined(separator: "\n")
        let display = folderPath.map { path in
            URL(fileURLWithPath: path).lastPathComponent.isEmpty
                ? path
                : URL(fileURLWithPath: path).lastPathComponent
        }.joined(separator: ", ")

        let argWide = Array(argument.utf16) + [0]
        let descWide = Array(description.utf16) + [0]
        let titleWide = Array(display.utf16) + [0]

        var rawLink: UnsafeMutableRawPointer?
        let hrLink = cwin_shell_link_create(
            exeWide,
            argWide,
            descWide,
            explorerWide,
            0,
            titleWide,
            &rawLink
        )
        guard hrLink == 0, let link = rawLink else { continue }
        defer { cwin_release_com_object(link) }

        _ = cwin_object_collection_add(coll, link)
    }

    if cwin_object_array_get_count(coll) > 0 {
        let catWide = Array("Recent Folders".utf16) + [0]
        let hrCat = cwin_jump_list_append_category(list, catWide, coll)
        let E_ACCESSDENIED: Int32 = -2147024891 // 0x80070005
        if hrCat != 0 && hrCat != E_ACCESSDENIED {
            throw DestinationListError.shellError("AppendCategory failed (HRESULT 0x\(String(UInt32(bitPattern: hrCat), radix: 16)))")
        }
    }
}

public func update_jump_list(
    recentWorkspaces: [[String]],
    dockMenus: [(SharedString, SharedString)]
) throws -> [[String]] {
    let (list, removed) = try createDestinationList()
    var committed = false
    defer {
        if !committed {
            _ = cwin_jump_list_abort(list)
        }
        cwin_release_com_object(list)
    }

    var exeBuf = [UInt16](repeating: 0, count: 4096)
    let hrExe = cwin_win32_get_module_file_name(&exeBuf, exeBuf.count)
    let exePath: String
    if hrExe == 0, let nulIdx = exeBuf.firstIndex(of: 0), nulIdx > 0 {
        exePath = String(utf16CodeUnits: exeBuf, count: nulIdx)
    } else {
        exePath = CommandLine.arguments.first ?? "gpui.exe"
    }

    try addRecentFolders(list: list, entries: recentWorkspaces, removed: removed, exePath: exePath)
    try addDockMenu(list: list, dockMenus: dockMenus, exePath: exePath)

    let hrCommit = cwin_jump_list_commit(list)
    guard hrCommit == 0 else {
        throw DestinationListError.shellError("CommitList failed (HRESULT 0x\(String(UInt32(bitPattern: hrCommit), radix: 16)))")
    }
    committed = true
    return removed
}

#endif
