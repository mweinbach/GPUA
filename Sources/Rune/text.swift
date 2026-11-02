// Ported from: crates/rune/src/text.rs
// Upstream commit: 5f6d53ddae78
// Port status: in-progress

//! Text shaping, layout caching, and greyscale glyph/SVG icon atlas.

#if !os(WASI)
import Foundation
#endif

public enum FontSmoothing: Sendable, Equatable, Hashable {
    case on
    case off

    public static var `default`: FontSmoothing {
        #if os(macOS)
        return .on
        #else
        return .off
        #endif
    }
}

public struct ApplePipeline: Sendable, Equatable, Hashable {
    public var dilation: Bool
    public var subpixelQuantization: Bool

    public init(dilation: Bool = true, subpixelQuantization: Bool = true) {
        self.dilation = dilation
        self.subpixelQuantization = subpixelQuantization
    }
}

public struct RichLayoutOptions: Sendable, Equatable {
    public var wrapAnywhere: Bool

    public init(wrapAnywhere: Bool = false) {
        self.wrapAnywhere = wrapAnywhere
    }

    public static func new() -> RichLayoutOptions {
        RichLayoutOptions()
    }

    public func wrapAnywhere(_ enabled: Bool = true) -> RichLayoutOptions {
        var copy = self
        copy.wrapAnywhere = enabled
        return copy
    }
}

public struct TextInk: Sendable, Equatable {
    public var x0: Float
    public var y0: Float
    public var x1: Float
    public var y1: Float

    public init(x0: Float = 0, y0: Float = 0, x1: Float = 0, y1: Float = 0) {
        self.x0 = x0
        self.y0 = y0
        self.x1 = x1
        self.y1 = y1
    }
}

// PORT NOTE: Immutable shaped single-line run shared across neighbouring `El.advanceIn` cells.
public final class Run: @unchecked Sendable {
    public let text: String
    public let style: TextStyle

    public init(_ text: String, _ style: TextStyle) {
        self.text = text
        self.style = style
    }
}

public struct RunLayout: Sendable, Equatable {
    public var width: Float
    public var height: Float

    public init(width: Float = 0, height: Float = 0) {
        self.width = width
        self.height = height
    }
}

public final class FamiliesGuard {
    private let restore: () -> Void
    init(_ restore: @escaping () -> Void) {
        self.restore = restore
    }
    deinit {
        restore()
    }
}

private let fontEpochLock = LiveLock()
// PORT NOTE: Guarded by `fontEpochLock` to track process-wide font/family epoch for `measure` caches.
nonisolated(unsafe) private var currentFontEpochValue: UInt64 = 1

public func fontEpoch() -> UInt64 {
    fontEpochLock.withLock { currentFontEpochValue }
}

public func bumpFontEpoch() {
    fontEpochLock.withLock { currentFontEpochValue &+= 1 }
}

public func withFamilies(_ sans: String, _ mono: String) -> FamiliesGuard {
    _ = (sans, mono)
    bumpFontEpoch()
    return FamiliesGuard {
        bumpFontEpoch()
    }
}

/// Measure `text` (with `spans`) set in `style`, wrapped at `maxWidth` points when given.
public func measure(
    _ text: String,
    _ spans: [Span] = [],
    _ style: TextStyle,
    _ maxWidth: Float? = nil
) -> (Float, Float) {
    measureWith(text, spans, style, maxWidth, RichLayoutOptions())
}

public func measureWith(
    _ text: String,
    _ spans: [Span],
    _ style: TextStyle,
    _ maxWidth: Float?,
    _ options: RichLayoutOptions
) -> (Float, Float) {
    _ = (spans, options)
    let lineH = style.linePx()
    if text.isEmpty {
        return (0.0, lineH)
    }
    let charAdvance: Float = (style.family == .mono || style.family == .systemMono)
        ? style.size * 0.6
        : style.size * 0.52
    let explicitLines = text.split(separator: "\n", omittingEmptySubsequences: false)
    var widest: Float = 0.0
    var totalLines = 0
    for line in explicitLines {
        let w = Float(line.count) * charAdvance
        if let maxW = maxWidth, maxW > 0.0, w > maxW {
            widest = max(widest, min(w, maxW))
            let wrapped = max(1, Int((w / max(maxW, charAdvance)).rounded(.up)))
            totalLines += wrapped
        } else {
            widest = max(widest, w)
            totalLines += 1
        }
    }
    return (widest.rounded(.up), Float(max(totalLines, 1)) * lineH)
}

public func advance(_ text: String, _ style: TextStyle) -> Float {
    let charAdvance: Float = (style.family == .mono || style.family == .systemMono)
        ? style.size * 0.6
        : style.size * 0.52
    return Float(text.count) * charAdvance
}

public func ink(_ text: String, _ style: TextStyle) -> TextInk {
    let w = advance(text, style)
    return TextInk(x0: 0, y0: 0, x1: w, y1: style.size)
}

public final class TextSystem {
    public var sans: String
    public var mono: String
    public var atlas: Atlas
    public var shaped: UInt32 = 0
    public var rebroken: UInt32 = 0
    var smoothing: FontSmoothing = .default
    private var colorPixels: [Pixels] = []

    public init(_ fonts: [[UInt8]] = [], _ families: (String, String) = ("Inter", "Inter")) {
        _ = fonts
        self.sans = families.0
        self.mono = families.1
        self.atlas = Atlas()
    }

    public static func forWindow(_ fonts: [[UInt8]] = [], _ families: (String, String) = ("Inter", "Inter")) -> TextSystem {
        TextSystem(fonts, families)
    }

    public func colorGlyph(_ color: UInt32) -> Pixels {
        colorPixels[Int(color) - 1]
    }

    public func fontSmoothing() -> FontSmoothing {
        smoothing
    }

    public func setFontSmoothing(_ mode: FontSmoothing) {
        smoothing = mode
    }

    public func beginFrame() {
        atlas.beginFrame(0)
    }
}
