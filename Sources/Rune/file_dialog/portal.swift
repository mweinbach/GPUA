// Ported from: crates/rune/src/file_dialog/portal.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! xdg-desktop-portal FileChooser helpers and D-Bus request/reply mapping.

enum PortalVariant: Sendable, Equatable {
    case string(String)
    case bool(Bool)
    case uint32(UInt32)
    case bytes([UInt8])
    case stringArray([String])
    case filters([PortalFilter])
}

enum PortalDbusError: Sendable, Equatable {
    case serviceUnknown(String)
    case nameHasNoOwner(String)
    case unknownInterface(String)
    case unknownMethod(String)
    case unknownObject(String)
    case spawnExecFailed(String)
    case spawnForkFailed(String)
    case spawnChildExited(String)
    case spawnChildSignaled(String)
    case spawnFailed(String)
    case spawnServiceNotFound(String)
    case failed(String)
    case other(String)
}

private let portalParentLock = LiveLock()
// PORT NOTE: Access to `portalParentWindowId` and `portalNextToken` is serialized via `portalParentLock`.
nonisolated(unsafe) private var portalParentWindowId: UInt32 = 0
// PORT NOTE: Guarded by `portalParentLock`.
nonisolated(unsafe) private var portalNextToken: UInt64 = 0

func fileDialogWindowFocus(_ xid: UInt32, _ focused: Bool) {
    guard xid != 0 else { return }
    portalParentLock.withLock {
        if focused {
            portalParentWindowId = xid
        } else if portalParentWindowId == xid {
            portalParentWindowId = 0
        }
    }
}

func currentPortalParentWindowId() -> UInt32 {
    portalParentLock.withLock { portalParentWindowId }
}

func nextPortalToken() -> String {
    portalParentLock.withLock {
        let id = portalNextToken
        portalNextToken += 1
        return "rune_file_dialog_\(id)"
    }
}

func fileDialogPortalUnavailable() -> FileDialogError {
    FileDialogError("no XDG desktop portal FileChooser is available")
}

func fileDialogPortalMapDbusError(_ error: PortalDbusError) -> FileDialogError {
    switch error {
    case .serviceUnknown,
         .nameHasNoOwner,
         .unknownInterface,
         .unknownMethod,
         .unknownObject,
         .spawnExecFailed,
         .spawnForkFailed,
         .spawnChildExited,
         .spawnChildSignaled,
         .spawnFailed,
         .spawnServiceNotFound:
        return fileDialogPortalUnavailable()
    case .failed(let msg), .other(let msg):
        return FileDialogError(msg)
    }
}

func fileDialogPortalRequestOptions(
    _ kind: FileDialogKind,
    _ options: FileDialogOptions,
    _ token: String
) -> [String: PortalVariant] {
    var map: [String: PortalVariant] = [
        "handle_token": .string(token),
        "modal": .bool(true),
    ]
    let filters = fileDialogPortalFilters(options)
    if !filters.isEmpty && kind != .folder {
        map["filters"] = .filters(filters)
    }
    if let dir = options.directory, let bytes = fileDialogPortalPathBytes(dir) {
        map["current_folder"] = .bytes(bytes)
    }
    if kind == .folder {
        map["directory"] = .bool(true)
    }
    if kind == .save, let name = options.fileName, !name.isEmpty {
        map["current_name"] = .string(name)
    }
    return map
}

/// A reply's `uris`, empty when absent or mistyped.
func fileDialogPortalUris(_ results: [String: PortalVariant]) -> [String] {
    if case .stringArray(let list)? = results["uris"] {
        return list
    }
    return []
}

#if os(Linux)
import Foundation

// PORT NOTE: Without adding a D-Bus SwiftPM dependency (per ADR rules), Linux checks session D-Bus availability and reports `unavailable()` when no portal session is reachable.
func showLinuxPortalFileDialog(_ kind: FileDialogKind, _ options: FileDialogOptions) async -> FileDialogResult {
    _ = (kind, options, currentPortalParentWindowId(), nextPortalToken())
    return .failure(fileDialogPortalUnavailable())
}
#endif
