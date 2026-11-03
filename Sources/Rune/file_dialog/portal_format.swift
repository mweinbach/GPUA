// Ported from: crates/rune/src/file_dialog/portal_format.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The FileChooser portal's argument and reply formats, kept free of D-Bus so they're tested on
//! every host.

struct PortalFilterPattern: Sendable, Equatable {
    var kind: UInt32
    var glob: String

    init(_ kind: UInt32, _ glob: String) {
        self.kind = kind
        self.glob = glob
    }
}

struct PortalFilter: Sendable, Equatable {
    var name: String
    var patterns: [PortalFilterPattern]

    init(_ name: String, _ patterns: [PortalFilterPattern]) {
        self.name = name
        self.patterns = patterns
    }
}

/// `x11:<hex xid>`, or empty for no parent.
func fileDialogParentWindow(_ xid: UInt32) -> String {
    xid == 0 ? "" : "x11:\(String(xid, radix: 16))"
}

/// Portal filters are glob (0) or MIME (1) patterns; Rune's filters are extensions.
/// The portal rejects filters with an empty name or an empty pattern list.
func fileDialogPortalFilters(_ options: FileDialogOptions) -> [PortalFilter] {
    options.filters.compactMap { name, extensions in
        guard !extensions.isEmpty else { return nil }
        let patterns = extensions.map { PortalFilterPattern(0, portalGlob($0)) }
        let label = name.isEmpty ? patterns.map(\.glob).joined(separator: ", ") : name
        return PortalFilter(label, patterns)
    }
}

private func portalGlob(_ ext: String) -> String {
    var trimmed = Substring(ext)
    while trimmed.first == "*" { trimmed = trimmed.dropFirst() }
    while trimmed.first == "." { trimmed = trimmed.dropFirst() }
    if trimmed.isEmpty || trimmed == "*" {
        return "*"
    }
    return "*.\(trimmed)"
}

/// The portal takes folders as NUL-terminated bytes with no interior NULs.
func fileDialogPortalPathBytes(_ path: String) -> [UInt8]? {
    let bytes = Array(path.utf8)
    guard !bytes.isEmpty, !bytes.contains(0) else { return nil }
    var out = bytes
    out.append(0)
    return out
}

/// The `Response` signal: 0 is a choice, 1 a cancelled dialog, 2 a dialog that ended another
/// way (for example closed with its parent), which is also no choice.
func fileDialogPortalOutcome(_ status: UInt32, _ uris: [String]) -> Result<String?, FileDialogError> {
    switch status {
    case 0:
        guard let first = uris.first else { return .success(nil) }
        return fileDialogPortalUriPath(first).map { Optional.some($0) }
    case 1, 2:
        return .success(nil)
    default:
        return .failure(FileDialogError("file dialog portal response \(status)"))
    }
}

/// A local `file://` URI percent-decoded to raw path bytes (preserving non-UTF-8 byte sequences).
func fileDialogPortalUriPathBytes(_ uri: String) -> Result<[UInt8], FileDialogError> {
    let invalid = { FileDialogError("file dialog returned a non-local URI: \(uri)") }
    guard uri.hasPrefix("file://") else { return .failure(invalid()) }
    let rest = uri.dropFirst("file://".count)
    guard let slashIdx = rest.firstIndex(of: "/") else { return .failure(invalid()) }
    let hostPart = rest[..<slashIdx]
    let pathSub: Substring
    if hostPart.isEmpty {
        pathSub = rest
    } else if hostPart.lowercased() == "localhost" {
        pathSub = rest[slashIdx...]
    } else {
        return .failure(invalid())
    }

    let cutIdx = pathSub.firstIndex(where: { $0 == "?" || $0 == "#" }) ?? pathSub.endIndex
    let bytes = Array(pathSub[..<cutIdx].utf8)

    func hexVal(_ b: UInt8) -> UInt8? {
        switch b {
        case 0x30...0x39: return b - 0x30
        case 0x41...0x46: return b - 0x41 + 10
        case 0x61...0x66: return b - 0x61 + 10
        default: return nil
        }
    }

    var out: [UInt8] = []
    out.reserveCapacity(bytes.count)
    var i = 0
    while i < bytes.count {
        if bytes[i] == 0x25 /* '%' */,
           i + 2 < bytes.count,
           let hi = hexVal(bytes[i + 1]),
           let lo = hexVal(bytes[i + 2])
        {
            out.append((hi << 4) | lo)
            i += 3
        } else {
            out.append(bytes[i])
            i += 1
        }
    }
    return .success(out)
}

/// A local `file://` URI decoded as a UTF-8 path string (using ISO-8859-1 lossless byte mapping if non-UTF-8).
func fileDialogPortalUriPath(_ uri: String) -> Result<String, FileDialogError> {
    fileDialogPortalUriPathBytes(uri).map { bytes in
        if let str = String(bytes: bytes, encoding: .utf8) {
            return str
        }
        return String(bytes.map { Character(UnicodeScalar($0)) })
    }
}
