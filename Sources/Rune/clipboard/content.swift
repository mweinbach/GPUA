// Ported from: crates/rune/src/clipboard/content.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! What a copy writes and a paste reads: `ClipboardContent` and its `ClipboardImage`.

#if !os(WASI)
import Foundation
#endif

/// The largest image a paste carries, as PNG. A bigger one is left out, and the paste
/// carries the clipboard's other forms.
public let MAX_IMAGE_BYTES: Int = 32 * 1024 * 1024

/// The most pixels a pasted image may have (64 MP, e.g. an 8K screenshot: 256 MiB of RGBA).
let MAX_IMAGE_PIXELS: UInt64 = 64 * 1024 * 1024

func validImageSize(_ width: UInt32, _ height: UInt32) -> Bool {
    width > 0 && height > 0 && UInt64(width) * UInt64(height) <= MAX_IMAGE_PIXELS
}

/// An image as PNG bytes: one to copy, or one a paste found in whatever form the clipboard held
/// it (TIFF on macOS, a DIB on Windows). Cheap to clone. Debug output shows only its size.
public struct ClipboardImage: Sendable, Equatable, CustomDebugStringConvertible {
    private let pngBytes: [UInt8]
    private let imageSize: (UInt32, UInt32)

    public var width: UInt32 { imageSize.0 }
    public var height: UInt32 { imageSize.1 }
    public var rgba: [UInt8] {
        toRgba()?.2 ?? []
    }

    private init(pngBytes: [UInt8], size: (UInt32, UInt32)) {
        self.pngBytes = pngBytes
        self.imageSize = size
    }

    /// Spine compatibility initializer encoding 8-bit RGBA pixels as PNG.
    public init(width: UInt32, height: UInt32, rgba: [UInt8]) {
        if let encoded = Self.fromRgba(width, height, rgba) {
            self = encoded
        } else {
            self.pngBytes = []
            self.imageSize = (width, height)
        }
    }

    /// PNG bytes, or `nil` when they don't start with a PNG header or pass `MAX_IMAGE_BYTES`.
    public static func fromPng(_ png: [UInt8]) -> ClipboardImage? {
        let sig: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let ihdr: [UInt8] = [0x49, 0x48, 0x44, 0x52]
        if png.count > MAX_IMAGE_BYTES || png.count < 24 {
            return nil
        }
        if Array(png[0..<8]) != sig || Array(png[12..<16]) != ihdr {
            return nil
        }
        let be = { (at: Int) -> UInt32 in
            (UInt32(png[at]) << 24)
                | (UInt32(png[at + 1]) << 16)
                | (UInt32(png[at + 2]) << 8)
                | UInt32(png[at + 3])
        }
        let w = be(16)
        let h = be(20)
        guard validImageSize(w, h) else { return nil }
        return ClipboardImage(pngBytes: png, size: (w, h))
    }

    /// Encodes 8-bit RGBA pixels, row by row, as PNG.
    static func fromRgba(_ width: UInt32, _ height: UInt32, _ rgba: [UInt8]) -> ClipboardImage? {
        guard validImageSize(width, height),
              let png = encodePng(width, height, rgba) else {
            return nil
        }
        return fromPng(png)
    }

    /// Decodes the PNG to 8-bit RGBA, for clipboards that take pixels.
    func toRgba() -> (UInt32, UInt32, [UInt8])? {
        decodePng(pngBytes)
    }

    /// The PNG file's bytes, ready to save, upload or decode.
    public func png() -> [UInt8] {
        pngBytes
    }

    /// Width and height in pixels, from the PNG header.
    public func size() -> (UInt32, UInt32) {
        imageSize
    }

    public static func == (lhs: ClipboardImage, rhs: ClipboardImage) -> Bool {
        lhs.imageSize == rhs.imageSize && lhs.pngBytes == rhs.pngBytes
    }

    public var debugDescription: String {
        "ClipboardImage { size: (\(imageSize.0), \(imageSize.1)), bytes: \(pngBytes.count) }"
    }
}

/// What a copy puts on the clipboard, or what a paste found there: plain text, and optionally
/// HTML, RTF, an image and files. Debug output never includes its contents.
public struct ClipboardContent: Sendable, Equatable, CustomDebugStringConvertible {
    var plain: String
    private var htmlValue: String?
    private var rtfValue: String?
    private var imageValue: ClipboardImage?
    private var filesValue: [String]
    var ownPills: Bool = false

    public init(text: String = "", html: String? = nil, rtf: String? = nil, image: ClipboardImage? = nil) {
        self.plain = text
        self.htmlValue = html
        self.rtfValue = rtf
        self.imageValue = image
        self.filesValue = []
        self.ownPills = false
    }

    public init(_ text: String) {
        self.init(text: text)
    }

    /// Plain text, the form every app can paste. Empty when only other forms carry content.
    public static func new(_ text: String) -> ClipboardContent {
        ClipboardContent(text: text)
    }

    /// Adds an HTML form (a fragment or a document), for apps that paste formatted text.
    public func withHtml(_ html: String) -> ClipboardContent {
        var copy = self
        copy.htmlValue = html
        return copy
    }

    /// Adds an RTF form, for apps that read RTF but not HTML.
    public func withRtf(_ rtf: String) -> ClipboardContent {
        var copy = self
        copy.rtfValue = rtf
        return copy
    }

    /// Adds an image.
    public func withImage(_ image: ClipboardImage) -> ClipboardContent {
        var copy = self
        copy.imageValue = image
        return copy
    }

    /// Adds files, so a paste into a file manager copies them. Paths should be absolute.
    public func withFiles(_ files: [String]) -> ClipboardContent {
        var copy = self
        copy.filesValue.append(contentsOf: files)
        return copy
    }

    #if !os(WASI)
    /// Convenience overload accepting `URL` file paths.
    public func withFiles(_ files: [URL]) -> ClipboardContent {
        var copy = self
        copy.filesValue.append(contentsOf: files.map(\.path))
        return copy
    }
    #endif

    public func text() -> String { plain }
    public func html() -> String? { htmlValue }
    public func rtf() -> String? { rtfValue }
    public func image() -> ClipboardImage? { imageValue }
    public func files() -> [String] { filesValue }

    /// HTML, RTF, an image or files beside the text.
    public func isRich() -> Bool {
        htmlValue != nil || rtfValue != nil || imageValue != nil || !filesValue.isEmpty
    }

    /// No text and no other form.
    public func isEmpty() -> Bool {
        plain.isEmpty && !isRich()
    }

    /// Content from another app: its HTML sanitised.
    func untrusted() -> ClipboardContent {
        var copy = self
        if let h = copy.htmlValue {
            copy.htmlValue = sanitizeHtml(h)
        }
        return copy
    }

    func hasOwnPills() -> Bool {
        ownPills
    }

    /// Text, HTML and RTF only, for a rich text target: no image or files to decode or list.
    func textForms() -> ClipboardContent? {
        let had = !isEmpty()
        var copy = self
        copy.imageValue = nil
        copy.filesValue.removeAll()
        return (!had || !copy.isEmpty()) ? copy : nil
    }

    /// Plain consumers take it: it has text, or nothing else.
    public func hasPlain() -> Bool {
        !plain.isEmpty || !isRich()
    }

    public static func == (lhs: ClipboardContent, rhs: ClipboardContent) -> Bool {
        lhs.plain == rhs.plain
            && lhs.htmlValue == rhs.htmlValue
            && lhs.rtfValue == rhs.rtfValue
            && lhs.imageValue == rhs.imageValue
            && lhs.filesValue == rhs.filesValue
    }

    public var debugDescription: String {
        let htmlLen = htmlValue.map { String($0.utf8.count) } ?? "nil"
        let rtfLen = rtfValue.map { String($0.utf8.count) } ?? "nil"
        let imgDesc = imageValue.map(\.debugDescription) ?? "nil"
        return "ClipboardContent { text: \(plain.utf8.count), html: \(htmlLen), rtf: \(rtfLen), image: \(imgDesc), files: \(filesValue.count) }"
    }
}
