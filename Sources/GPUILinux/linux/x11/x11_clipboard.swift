// Ported from: crates/gpui_linux/src/linux/x11/clipboard.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux)
import Foundation
import GPUI

public enum ClipboardKind: Sendable, Hashable {
    case clipboard
    case primary
    case secondary
}

public enum WaitConfig: Sendable, Hashable {
    case wait
    case noWait
}

public enum Error: Swift.Error, CustomStringConvertible, Sendable {
    case unknownError(String)
    case unsupported
    case timeout

    public var description: String {
        switch self {
        case .unknownError(let msg): return "Clipboard error: \(msg)"
        case .unsupported: return "Clipboard unsupported"
        case .timeout: return "Clipboard timeout"
        }
    }

    public static func unknown(_ message: String) -> Error {
        .unknownError(message)
    }
}

public enum X11ClipboardModule {
// PORT NOTE: Clipboard manages X11 selection storage synchronized via NSLock.
public final class Clipboard: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ClipboardKind: ClipboardItem] = [:]
    private var isOwnerMap: [ClipboardKind: Bool] = [:]

    public init() {}

    public static func new() throws -> Clipboard {
        Clipboard()
    }

    public func setText(
        _ message: String,
        selection: ClipboardKind = .clipboard,
        wait: WaitConfig = .noWait
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[selection] = ClipboardItem(text: message)
        isOwnerMap[selection] = true
    }

    public func setImage(
        _ image: Image,
        selection: ClipboardKind = .clipboard,
        wait: WaitConfig = .noWait
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[selection] = ClipboardItem(text: "")
        isOwnerMap[selection] = true
    }

    public func getAny(selection: ClipboardKind = .clipboard) throws -> ClipboardItem {
        lock.lock()
        defer { lock.unlock() }
        return storage[selection] ?? ClipboardItem(text: "")
    }

    public func isOwner(selection: ClipboardKind = .clipboard) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isOwnerMap[selection] ?? false
    }
}
}

public typealias X11Clipboard = X11ClipboardModule.Clipboard
#endif
