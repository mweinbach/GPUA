// Ported from: crates/gpui_macos/src/pasteboard.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(macOS)
import AppKit
import Foundation
import GPUI
import UniformTypeIdentifiers

/// Deterministic 64-bit FNV-1a byte hash matching upstream `gpui::hash` determinism across writes/reads.
private func deterministicHash(_ bytes: some Sequence<UInt8>) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in bytes {
        hash ^= UInt64(byte)
        hash &*= 0x100000001b3
    }
    return hash
}

/// Text clipboard payload with optional hash-verified JSON metadata, matching upstream `ClipboardString`.
public struct ClipboardString: Sendable, Equatable, Hashable {
    public var text: String
    public var metadata: String?

    public init(text: String, metadata: String? = nil) {
        self.text = text
        self.metadata = metadata
    }

    public static func new(_ text: String) -> ClipboardString {
        ClipboardString(text: text, metadata: nil)
    }

    public func withJsonMetadata<T: Encodable>(_ value: T) -> ClipboardString {
        var copy = self
        if let encoded = try? JSONEncoder().encode(value),
           let json = String(data: encoded, encoding: .utf8)
        {
            copy.metadata = json
        }
        return copy
    }

    public func metadataJson<T: Decodable>(_ type: T.Type = T.self) -> T? {
        guard let metadata, let data = metadata.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    public static func textHash(_ text: String) -> UInt64 {
        deterministicHash(text.utf8)
    }
}

/// Individual clipboard entry matching upstream `gpui::ClipboardEntry`.
public enum ClipboardEntry: Sendable, Equatable {
    case string(ClipboardString)
    case image(GPUI.Image)
    case externalPaths(ExternalPaths)
}

/// Multi-entry clipboard item matching upstream `gpui::ClipboardItem` for `Pasteboard`.
public struct PasteboardItem: Sendable, Equatable {
    public var entries: [ClipboardEntry]

    public init(entries: [ClipboardEntry] = []) {
        self.entries = entries
    }

    public static func newString(_ text: String) -> PasteboardItem {
        PasteboardItem(entries: [.string(ClipboardString(text: text))])
    }

    public static func newImage(_ image: GPUI.Image) -> PasteboardItem {
        PasteboardItem(entries: [.image(image)])
    }

    public func text() -> String? {
        var combined = ""
        var found = false
        for entry in entries {
            if case .string(let s) = entry {
                combined.append(s.text)
                found = true
            }
        }
        return found ? combined : nil
    }
}

extension ImageFormat {
    fileprivate var pasteboardType: NSPasteboard.PasteboardType {
        switch self {
        case .png:
            return .png
        case .jpeg:
            return NSPasteboard.PasteboardType(UTType.jpeg.identifier)
        case .tiff:
            return .tiff
        case .webp:
            return NSPasteboard.PasteboardType(UTType.webP.identifier)
        case .gif:
            return NSPasteboard.PasteboardType(UTType.gif.identifier)
        case .bmp:
            return NSPasteboard.PasteboardType(UTType.bmp.identifier)
        case .svg:
            return NSPasteboard.PasteboardType(UTType.svg.identifier)
        case .ico:
            return NSPasteboard.PasteboardType(UTType.ico.identifier)
        }
    }
}

/// Wrapper around `NSPasteboard` supporting plain text, hash-verified JSON metadata, external file paths, and images.
// PORT NOTE: NSPasteboard access is performed on main/pasteboard contexts matching upstream Pasteboard.
public struct Pasteboard: @unchecked Sendable {
    public let inner: NSPasteboard
    private let textHashType = NSPasteboard.PasteboardType("zed-text-hash")
    private let metadataType = NSPasteboard.PasteboardType("zed-metadata")
    private let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    private let utf8PlainTextType = NSPasteboard.PasteboardType("public.utf8-plain-text")

    public init(_ inner: NSPasteboard) {
        self.inner = inner
    }

    /// Returns the macOS general pasteboard (`NSPasteboard.general`).
    public static func general() -> Pasteboard {
        Pasteboard(.general)
    }

    /// Returns the macOS Find pasteboard (`NSPasteboard(name: .find)`).
    public static func find() -> Pasteboard {
        Pasteboard(NSPasteboard(name: .find))
    }

    /// Creates an isolated pasteboard with a unique name (`NSPasteboard.withUniqueName()`).
    public static func unique() -> Pasteboard {
        Pasteboard(NSPasteboard.withUniqueName())
    }

    /// Reads a multi-entry `PasteboardItem` from the underlying `NSPasteboard`.
    public func read() -> PasteboardItem? {
        // 1. Check for external file paths first (NSFilenamesPboardType).
        if let filenames = inner.propertyList(forType: filenamesType) as? [String],
           !filenames.isEmpty
        {
            var entries: [ClipboardEntry] = [.externalPaths(ExternalPaths(paths: filenames))]
            if let stringEntry = readStringFromPasteboard() {
                entries.append(stringEntry)
            }
            return PasteboardItem(entries: entries)
        }

        // 2. Check for a plain UTF-8 string.
        if let stringEntry = readStringFromPasteboard() {
            return PasteboardItem(entries: [stringEntry])
        }

        // 3. Finally, check all supported image formats.
        for format in ImageFormat.allCases {
            if let imageItem = readImage(format) {
                return imageItem
            }
        }

        return nil
    }

    /// Writes a multi-entry `PasteboardItem` to the underlying `NSPasteboard`.
    public func write(_ item: PasteboardItem) {
        if item.entries.isEmpty {
            inner.clearContents()
            return
        }

        if item.entries.count == 1 {
            switch item.entries[0] {
            case .string(let string):
                writePlaintext(string)
            case .image(let image):
                writeImage(image)
            case .externalPaths:
                break
            }
            return
        }

        var combined = ClipboardString(text: "", metadata: nil)
        for entry in item.entries {
            if case .string(let s) = entry {
                combined.text.append(s.text)
                if combined.metadata == nil {
                    combined.metadata = s.metadata
                }
            }
        }
        writePlaintext(combined)
    }

    /// Bridges `read()` to `GPUI.ClipboardItem` for `Platform` conformance.
    public func readClipboardItem() -> ClipboardItem? {
        guard let item = read() else {
            return nil
        }
        for entry in item.entries {
            switch entry {
            case .string(let str):
                let metaData = str.metadata?.data(using: .utf8)
                return ClipboardItem(text: str.text, data: metaData)
            case .image(let img):
                return ClipboardItem(text: nil, data: Data(img.bytes))
            case .externalPaths(let paths):
                let joined = item.text() ?? paths.paths.joined(separator: "\n")
                return ClipboardItem(text: joined, data: nil)
            }
        }
        return nil
    }

    /// Bridges `GPUI.ClipboardItem` to `write(_:)` for `Platform` conformance.
    public func writeClipboardItem(_ item: ClipboardItem) {
        if let text = item.text {
            let metadata = item.data.flatMap { String(data: $0, encoding: .utf8) }
            write(PasteboardItem(entries: [.string(ClipboardString(text: text, metadata: metadata))]))
        } else if let data = item.data {
            let img = GPUI.Image(
                format: .png,
                bytes: [UInt8](data),
                id: deterministicHash(data)
            )
            write(PasteboardItem(entries: [.image(img)]))
        } else {
            write(PasteboardItem(entries: []))
        }
    }

    private func readImage(_ format: ImageFormat) -> PasteboardItem? {
        let pboardType = format.pasteboardType
        guard let types = inner.types, types.contains(pboardType),
              let data = inner.data(forType: pboardType)
        else {
            return nil
        }
        let bytes = [UInt8](data)
        let id = deterministicHash(bytes)
        return PasteboardItem(entries: [
            .image(GPUI.Image(format: format, bytes: bytes, id: id)),
        ])
    }

    private func readStringFromPasteboard() -> ClipboardEntry? {
        guard let types = inner.types, types.contains(utf8PlainTextType),
              let data = inner.data(forType: utf8PlainTextType)
        else {
            return nil
        }

        let text = String(decoding: data, as: UTF8.self)
        var metadata: String? = nil

        if let hashData = inner.data(forType: textHashType), hashData.count == 8,
           let metaData = inner.data(forType: metadataType)
        {
            var rawHash: UInt64 = 0
            for byte in hashData {
                rawHash = (rawHash << 8) | UInt64(byte)
            }
            if rawHash == ClipboardString.textHash(text) {
                metadata = String(data: metaData, encoding: .utf8)
            }
        }

        return .string(ClipboardString(text: text, metadata: metadata))
    }

    private func writePlaintext(_ string: ClipboardString) {
        inner.clearContents()
        let textData = Data(string.text.utf8)
        inner.setData(textData, forType: .string)

        if let metadata = string.metadata {
            var bigEndianHash = ClipboardString.textHash(string.text).bigEndian
            let hashData = withUnsafeBytes(of: &bigEndianHash) { Data($0) }
            inner.setData(hashData, forType: textHashType)
            inner.setData(Data(metadata.utf8), forType: metadataType)
        }
    }

    private func writeImage(_ image: GPUI.Image) {
        inner.clearContents()
        inner.setData(Data(image.bytes), forType: image.format.pasteboardType)
    }
}
#endif
