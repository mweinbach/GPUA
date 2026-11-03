// Ported from: crates/rune/src/open_url.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Open a link in the system's default handler: `Tx.openUrl`.
//!
//! Only `http:`, `https:` and `mailto:` links open, the same set the web build allows. Anything
//! else (`file:`, custom app schemes, `javascript:`) is refused with
//! `OpenUrlError.unsupportedScheme` before anything runs, as are empty links and links with
//! spaces or control characters.

#if os(WASI)
import CWebSys
#elseif os(macOS)
import AppKit
import Foundation
#else
import Foundation
#endif

private let OPEN_URL_MAX_LEN: Int = 8192

/// Why a link was refused or didn't open.
public enum OpenUrlError: Error, CustomStringConvertible, Sendable, Equatable {
    /// Nothing to open.
    case empty
    /// Not a link: too long, has whitespace or control characters, or lacks a scheme or host.
    case invalid
    /// A scheme other than `http`, `https` or `mailto` (lowercased).
    case unsupportedScheme(String)
    /// The system couldn't open it, or this platform has no way to.
    case failed(String)

    /// Spine compatibility alias for `.unsupportedScheme`.
    public static func disallowedScheme(_ scheme: String) -> OpenUrlError {
        .unsupportedScheme(scheme)
    }

    /// Spine compatibility alias for `.invalid`.
    public static func malformed(_ why: String) -> OpenUrlError {
        _ = why
        return .invalid
    }

    public var description: String {
        switch self {
        case .empty:
            return "empty link"
        case .invalid:
            return "not a valid link"
        case .unsupportedScheme(let s):
            return "links with the \(s): scheme can't be opened"
        case .failed(let why):
            return "couldn't open the link: \(why)"
        }
    }
}

/// Carries subsystem `Tx` callbacks (clipboard reads, popups, file dialogs, window frame requests)
/// through `Tx` without altering `Sources/Rune/el/el_tx.swift`.
// PORT NOTE: Synchronized via `LiveLock`; `Tx` clones share the box and `latchRequests` takes each entry once, matching Rust's `Rc<Cell<Option<...>>>`.
final class TxSidecarBox: @unchecked Sendable, Equatable {
    private let lock = LiveLock()
    private var entries: [Any] = []
    private var shortcutActivationToken: String? = nil

    init() {}

    func append(_ entry: Any) {
        lock.withLock {
            entries.append(entry)
        }
    }

    func setShortcutActivationToken(_ token: String?) {
        lock.withLock {
            shortcutActivationToken = token
        }
    }

    func getShortcutActivationToken() -> String? {
        lock.withLock { shortcutActivationToken }
    }

    var isEmpty: Bool {
        lock.withLock { entries.isEmpty && shortcutActivationToken == nil }
    }

    func peekFirst<T>(as type: T.Type) -> T? {
        lock.withLock {
            for entry in entries {
                if let typed = entry as? T {
                    return typed
                }
            }
            return nil
        }
    }

    func drain<T>(as type: T.Type) -> [T] {
        lock.withLock {
            var matched: [T] = []
            var remaining: [Any] = []
            for entry in entries {
                if let typed = entry as? T {
                    matched.append(typed)
                } else {
                    remaining.append(entry)
                }
            }
            entries = remaining
            return matched
        }
    }

    static func == (lhs: TxSidecarBox, rhs: TxSidecarBox) -> Bool {
        lhs === rhs
    }
}

/// A link a handler asked to open, already checked (or a sidecar carrier when `sidecar != nil`).
struct OpenUrlLink: Sendable, Equatable {
    var url: String
    var sameTab: Bool
    var sidecar: TxSidecarBox?

    init(url: String, sameTab: Bool) {
        self.url = url
        self.sameTab = sameTab
        self.sidecar = nil
    }

    init(sidecar: TxSidecarBox) {
        self.url = ""
        self.sameTab = false
        self.sidecar = sidecar
    }
}

extension Tx {
    mutating func appendSidecar(_ entry: Any) {
        if let existing = openUrls.first(where: { $0.sidecar != nil })?.sidecar {
            existing.append(entry)
        } else {
            let box = TxSidecarBox()
            box.append(entry)
            openUrls.append(OpenUrlLink(sidecar: box))
        }
    }

    func peekSidecar<T>(as type: T.Type) -> T? {
        for link in openUrls {
            if let found = link.sidecar?.peekFirst(as: type) {
                return found
            }
        }
        return nil
    }

    mutating func drainSidecar<T>(as type: T.Type) -> [T] {
        var out: [T] = []
        for link in openUrls {
            if let box = link.sidecar {
                out.append(contentsOf: box.drain(as: type))
            }
        }
        return out
    }

    mutating func setShortcutActivationToken(_ token: String?) {
        if let existing = openUrls.first(where: { $0.sidecar != nil })?.sidecar {
            existing.setShortcutActivationToken(token)
            if token == nil {
                openUrls.removeAll { $0.sidecar?.isEmpty == true }
            }
        } else if let token {
            let box = TxSidecarBox()
            box.setShortcutActivationToken(token)
            openUrls.append(OpenUrlLink(sidecar: box))
        }
    }
}

/// Per-`Runtime` host attachment storage for subsystems outside `Sources/Rune/runtime.swift`.
// PORT NOTE: Guarded by `runtimeHostLock` (`LiveLock`) with weak owner references pruned automatically.
final class RuntimeHostAttachment: @unchecked Sendable {
    weak var owner: AnyObject?
    var clipboard: MemoryClipboard? = nil
    var copyRequest: ClipboardWrite? = nil
    var clearSecretRequest: Bool = false
    var pasteRequest: String?? = nil
    var readRequests: [UInt64] = []
    var clipboardReads: [(UInt64, (States, ClipboardContent, inout Tx) -> Void)] = []
    var nextClipboardRead: UInt64 = 0
    var urlRequests: [String] = []
    var openUrlsNatively: Bool = false
    var shellRequest: Shell? = nil
    var minimizeRequest: Bool = false
    var windowTitle: String? = nil
    var windowTitleDirty: Bool = false
    var dirtyFromHost: Bool = false
    var customData: [String: Any] = [:]

    init(owner: AnyObject) {
        self.owner = owner
    }

    func startWindowTitle(_ title: String) {
        windowTitle = title
        windowTitleDirty = false
    }

    func setWindowTitle(_ title: String) {
        if windowTitle != title {
            windowTitle = title
            windowTitleDirty = true
        }
    }

    func takeWindowTitleChange() -> String? {
        guard windowTitleDirty else { return nil }
        windowTitleDirty = false
        return windowTitle
    }
}

private let runtimeHostLock = LiveLock()
// PORT NOTE: Access to `runtimeHostTable` is always serialized through `runtimeHostLock`.
nonisolated(unsafe) private var runtimeHostTable: [ObjectIdentifier: RuntimeHostAttachment] = [:]

func hostAttachment(for runtime: AnyObject) -> RuntimeHostAttachment {
    runtimeHostLock.withLock {
        let key = ObjectIdentifier(runtime)
        runtimeHostTable = runtimeHostTable.filter { $0.value.owner != nil }
        if let existing = runtimeHostTable[key] {
            return existing
        }
        let created = RuntimeHostAttachment(owner: runtime)
        runtimeHostTable[key] = created
        return created
    }
}

/// The link to open, trimmed and with a lowercase scheme, or why it can't be.
func checkOpenUrl(_ raw: String) throws(OpenUrlError) -> String {
    try checkOpenUrlLink(raw, relative: false)
}

/// `checkOpenUrl` for a same-tab link: on web a link without a scheme (`/notes/42`, `?q=a`, `#top`)
/// is relative to the page, and the browser resolves it.
func checkOpenUrlSameTab(_ raw: String) throws(OpenUrlError) -> String {
    #if os(WASI)
    return try checkOpenUrlLink(raw, relative: true)
    #else
    return try checkOpenUrlLink(raw, relative: false)
    #endif
}

func checkOpenUrlLink(_ raw: String, relative: Bool) throws(OpenUrlError) -> String {
    let trimmed = trimUnicodeWhitespace(raw)
    guard !trimmed.isEmpty else { throw .empty }
    let utf8 = Array(trimmed.utf8)
    if utf8.count > OPEN_URL_MAX_LEN || badPercent(utf8) {
        throw .invalid
    }
    for scalar in trimmed.unicodeScalars {
        if scalar.properties.isWhitespace
            || scalar.value <= 0x1F
            || (scalar.value >= 0x7F && scalar.value <= 0x9F)
        {
            throw .invalid
        }
        switch scalar {
        case "\\", "\"", "<", ">", "`", "^", "{", "|", "}":
            throw .invalid
        default:
            break
        }
    }

    if relative {
        let firstDelim = utf8.firstIndex { $0 == 0x3A || $0 == 0x2F || $0 == 0x3F || $0 == 0x23 }
        if firstDelim == nil || utf8[firstDelim!] != 0x3A /* ':' */ {
            return trimmed
        }
    }

    guard let colonByteIdx = utf8.firstIndex(of: 0x3A /* ':' */) else {
        throw .invalid
    }
    let schemeBytes = utf8[0..<colonByteIdx]
    guard let firstSchemeByte = schemeBytes.first,
          (firstSchemeByte >= 0x41 && firstSchemeByte <= 0x5A) || (firstSchemeByte >= 0x61 && firstSchemeByte <= 0x7A)
    else {
        throw .invalid
    }
    var lowerSchemeBytes: [UInt8] = []
    lowerSchemeBytes.reserveCapacity(schemeBytes.count)
    for b in schemeBytes {
        let isAlpha = (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
        let isDigit = (b >= 0x30 && b <= 0x39)
        let isAllowedPunct = (b == 0x2B /* '+' */ || b == 0x2D /* '-' */ || b == 0x2E /* '.' */)
        if !(isAlpha || isDigit || isAllowedPunct) {
            throw .invalid
        }
        lowerSchemeBytes.append((b >= 0x41 && b <= 0x5A) ? (b + 32) : b)
    }
    let scheme = String(decoding: lowerSchemeBytes, as: UTF8.self)
    let restBytes = Array(utf8[(colonByteIdx + 1)..<utf8.count])
    let rest = String(decoding: restBytes, as: UTF8.self)

    switch scheme {
    case "http", "https":
        guard restBytes.count >= 2 && restBytes[0] == 0x2F && restBytes[1] == 0x2F else {
            throw .invalid
        }
        let afterBytes = Array(restBytes[2..<restBytes.count])
        let tailStart = afterBytes.firstIndex { $0 == 0x2F || $0 == 0x3F || $0 == 0x23 } ?? afterBytes.count
        let authorityBytes = Array(afterBytes[0..<tailStart])
        let tailBytes = afterBytes[tailStart..<afterBytes.count]
        if tailBytes.contains(0x5B /* '[' */) || tailBytes.contains(0x5D /* ']' */) {
            throw .invalid
        }
        let authority = String(decoding: authorityBytes, as: UTF8.self)
        guard validAuthority(authority) else {
            throw .invalid
        }
    case "mailto":
        if restBytes.isEmpty
            || (restBytes.count >= 2 && restBytes[0] == 0x2F && restBytes[1] == 0x2F)
            || restBytes.contains(0x5B)
            || restBytes.contains(0x5D)
        {
            throw .invalid
        }
    default:
        throw .unsupportedScheme(scheme)
    }
    return "\(scheme):\(rest)"
}

private func trimUnicodeWhitespace(_ s: String) -> String {
    let scalars = Array(s.unicodeScalars)
    var start = 0
    var end = scalars.count
    while start < end && scalars[start].properties.isWhitespace { start += 1 }
    while end > start && scalars[end - 1].properties.isWhitespace { end -= 1 }
    if start == 0 && end == scalars.count { return s }
    var out = String.UnicodeScalarView()
    out.append(contentsOf: scalars[start..<end])
    return String(out)
}

private func badPercent(_ bytes: [UInt8]) -> Bool {
    var i = 0
    while i < bytes.count {
        if bytes[i] == 0x25 /* '%' */ {
            guard i + 2 < bytes.count else { return true }
            let a = bytes[i + 1]
            let b = bytes[i + 2]
            let hexA = (a >= 0x30 && a <= 0x39) || (a >= 0x41 && a <= 0x46) || (a >= 0x61 && a <= 0x66)
            let hexB = (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x46) || (b >= 0x61 && b <= 0x66)
            if !hexA || !hexB || (a == 0x30 && b == 0x30) {
                return true
            }
            i += 3
        } else {
            i += 1
        }
    }
    return false
}

private func validAuthority(_ authority: String) -> Bool {
    let bytes = Array(authority.utf8)
    let hostPortBytes: [UInt8]
    if let atIdx = bytes.lastIndex(of: 0x40 /* '@' */) {
        let userBytes = bytes[0..<atIdx]
        if userBytes.isEmpty || userBytes.contains(0x5B) || userBytes.contains(0x5D) || userBytes.contains(0x40) {
            return false
        }
        hostPortBytes = Array(bytes[(atIdx + 1)..<bytes.count])
    } else {
        hostPortBytes = bytes
    }

    let portStr: String?
    if hostPortBytes.first == 0x5B /* '[' */ {
        let rest = Array(hostPortBytes.dropFirst())
        guard let closeBracket = rest.firstIndex(of: 0x5D /* ']' */) else { return false }
        let ipv6Bytes = Array(rest[0..<closeBracket])
        let ipv6 = String(decoding: ipv6Bytes, as: UTF8.self)
        if ipv6Bytes.count < 2 || !ipv6Bytes.contains(0x3A /* ':' */) || ipv6Bytes.first == 0x2E || ipv6.contains("..") {
            return false
        }
        for c in ipv6Bytes {
            let hex = (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66)
            if !(hex || c == 0x3A || c == 0x2E) {
                return false
            }
        }
        let afterBracket = Array(rest[(closeBracket + 1)..<rest.count])
        if !afterBracket.isEmpty && afterBracket.first != 0x3A /* ':' */ {
            return false
        }
        if afterBracket.first == 0x3A {
            portStr = String(decoding: afterBracket.dropFirst(), as: UTF8.self)
        } else {
            portStr = nil
        }
    } else if hostPortBytes.contains(0x5B) || hostPortBytes.contains(0x5D) {
        return false
    } else {
        let hostBytes: ArraySlice<UInt8>
        if let colon = hostPortBytes.firstIndex(of: 0x3A /* ':' */) {
            hostBytes = hostPortBytes[0..<colon]
            portStr = String(decoding: hostPortBytes[(colon + 1)..<hostPortBytes.count], as: UTF8.self)
        } else {
            hostBytes = hostPortBytes[...]
            portStr = nil
        }
        let host = String(decoding: hostBytes, as: UTF8.self)
        if hostBytes.isEmpty || hostBytes.first == 0x2E || host.contains("..") || hostBytes.contains(0x25 /* '%' */) || hostBytes.contains(0x3A) {
            return false
        }
    }

    if let p = portStr {
        return !p.isEmpty && UInt16(p) != nil
    }
    return true
}

extension Runtime {
    /// Takes the links handlers asked to open that this runtime didn't open: all of them in a
    /// headless run or test, none in a window. Each was already checked.
    public func takeUrlRequests() -> [String] {
        let att = hostAttachment(for: self)
        let out = att.urlRequests
        att.urlRequests.removeAll()
        return out
    }

    func openHostUrls(_ links: [OpenUrlLink]) {
        let att = hostAttachment(for: self)
        for link in links where link.sidecar == nil {
            if att.openUrlsNatively {
                #if os(WASI)
                let result = openWebUrlLink(link.url, sameTab: link.sameTab)
                #else
                let result = openSystemUrl(link.url)
                #endif
                if case .failure = result {
                    // Logged on native in upstream (`eprintln!`); never fatal.
                }
            } else {
                att.urlRequests.append(link.url)
            }
        }
    }
}

#if os(WASI)
private func openWebUrlLink(_ url: String, sameTab: Bool) -> Result<Void, OpenUrlError> {
    if sameTab {
        return webOpenUrlSameTab(url)
    } else {
        return webOpenUrl(url)
    }
}

private func webOpenUrl(_ url: String) -> Result<Void, OpenUrlError> {
    let utf8 = Array(url.utf8)
    let ok = utf8.withUnsafeBufferPointer { buf in
        cwebsys_open_url(buf.baseAddress, buf.count)
    }
    return ok ? .success(()) : .failure(.failed("window.open returned null"))
}

private func webOpenUrlSameTab(_ url: String) -> Result<Void, OpenUrlError> {
    let utf8 = Array(url.utf8)
    let ok = utf8.withUnsafeBufferPointer { buf in
        cwebsys_open_url(buf.baseAddress, buf.count)
    }
    return ok ? .success(()) : .failure(.failed("navigation refused"))
}
#elseif os(macOS)
private func percentEncodeNonAscii(_ url: String) -> String {
    let bytes = Array(url.utf8)
    guard bytes.contains(where: { $0 >= 0x80 }) else { return url }
    var out = ""
    out.reserveCapacity(bytes.count + 16)
    let hexDigits = Array("0123456789ABCDEF".utf8)
    for b in bytes {
        if b < 0x80 {
            out.unicodeScalars.append(UnicodeScalar(b))
        } else {
            out.append("%")
            out.unicodeScalars.append(UnicodeScalar(hexDigits[Int(b >> 4)]))
            out.unicodeScalars.append(UnicodeScalar(hexDigits[Int(b & 0x0F)]))
        }
    }
    return out
}

func openSystemUrl(_ url: String) -> Result<Void, OpenUrlError> {
    let ascii = percentEncodeNonAscii(url)
    guard let nsUrl = URL(string: ascii) else {
        return .failure(.invalid)
    }
    if NSWorkspace.shared.open(nsUrl) {
        return .success(())
    }
    return .failure(.failed("no app opened it"))
}
#elseif os(Linux)
func openSystemUrl(_ url: String) -> Result<Void, OpenUrlError> {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    proc.arguments = ["xdg-open", url]
    proc.standardInput = FileHandle.nullDevice
    proc.standardOutput = FileHandle.nullDevice
    proc.standardError = FileHandle.nullDevice
    do {
        try proc.run()
        Thread.detachNewThread {
            proc.waitUntilExit()
        }
        return .success(())
    } catch {
        return .failure(.failed(String(describing: error)))
    }
}
#else
func openSystemUrl(_ url: String) -> Result<Void, OpenUrlError> {
    _ = url
    return .failure(.failed("this platform can't open links"))
}
#endif
