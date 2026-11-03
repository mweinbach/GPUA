// Ported from: crates/rune/src/shortcuts/wayland.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! xdg-desktop-portal GlobalShortcuts status & error mapping.

enum WaylandShortcutDbusError: Sendable, Equatable {
    case fdoServiceUnknown(String)
    case fdoNameHasNoOwner(String)
    case fdoUnknownInterface(String)
    case fdoUnknownMethod(String)
    case fdoUnknownObject(String)
    case fdoFailed(String)
    case methodError(name: String, detail: String)
    case other(String)
}

func waylandShortcutMapDbusError(_ error: WaylandShortcutDbusError) -> ShortcutError {
    switch error {
    case .fdoServiceUnknown,
         .fdoNameHasNoOwner,
         .fdoUnknownInterface,
         .fdoUnknownMethod,
         .fdoUnknownObject:
        return .unsupported
    case .fdoFailed(let msg):
        return .backend(msg)
    case .methodError(let name, let detail):
        switch name {
        case "org.freedesktop.portal.Error.Exist":
            return .conflict
        case "org.freedesktop.portal.Error.NotAllowed",
             "org.freedesktop.portal.Error.Cancelled":
            return .permissionDenied
        case "org.freedesktop.portal.Error.InvalidArgument":
            return .invalidAccelerator(detail)
        default:
            return .backend(detail)
        }
    case .other(let msg):
        return .backend(msg)
    }
}

func waylandShortcutResponseStatus(_ status: UInt32) -> Result<Void, ShortcutError> {
    switch status {
    case 0:
        return .success(())
    case 1:
        return .failure(.permissionDenied)
    default:
        return .failure(.backend("portal response \(status)"))
    }
}

#if os(Linux)
final class WaylandShortcutBackend: ShortcutBackend {
    // PORT NOTE: Without an external D-Bus library (per ADR rules), Wayland shortcut registration reports `.unsupported` cleanly, matching upstream builds without the `dbus` feature.
    static func create(_ sink: @escaping ShortcutSink) -> Result<WaylandShortcutBackend, ShortcutError> {
        _ = sink
        return .failure(.unsupported)
    }

    func register(_ id: ShortcutId, _ shortcut: Shortcut) -> Result<Void, ShortcutError> {
        _ = (id, shortcut)
        return .failure(.unsupported)
    }

    func unregister(_ id: ShortcutId) -> Result<Void, ShortcutError> {
        _ = id
        return .failure(.unknownId)
    }
}
#endif
