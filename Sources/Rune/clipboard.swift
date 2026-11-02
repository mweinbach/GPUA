// Ported from: crates/rune/src/clipboard.rs
// Upstream commit: 5f6d53ddae78
// Port status: in-progress

public struct ClipboardImage: Sendable, Equatable {
    public var width: UInt32
    public var height: UInt32
    public var rgba: [UInt8]

    public init(width: UInt32, height: UInt32, rgba: [UInt8]) {
        self.width = width
        self.height = height
        self.rgba = rgba
    }
}

public struct ClipboardContent: Sendable, Equatable {
    private var plain: String
    private var htmlValue: String?
    private var rtfValue: String?
    private var imageValue: ClipboardImage?

    public init(text: String = "", html: String? = nil, rtf: String? = nil, image: ClipboardImage? = nil) {
        self.plain = text
        self.htmlValue = html
        self.rtfValue = rtf
        self.imageValue = image
    }

    public func hasPlain() -> Bool { !plain.isEmpty }
    public func text() -> String { plain }
    public func html() -> String? { htmlValue }
    public func rtf() -> String? { rtfValue }
    public func image() -> ClipboardImage? { imageValue }
}

public enum SecretState: Sendable, Equatable, Hashable {
    case copied
    case cleared
}

public struct SecretCopy: Sendable, Equatable {
    public var text: String
    public var ttlSeconds: Double

    public init(text: String, ttlSeconds: Double = 45.0) {
        self.text = text
        self.ttlSeconds = ttlSeconds
    }
}

public enum ClipboardWrite: Sendable, Equatable {
    case text(String)
    case rich(text: String, html: String?)
    case image(ClipboardImage)
    case secret(SecretCopy)
}
