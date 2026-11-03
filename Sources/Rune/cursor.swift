// Ported from: crates/rune/src/cursor.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

/// The pointer's shape over an element (CSS `cursor`). Elements without one inherit their
/// nearest ancestor's; text fields default to ``Cursor/text``, everything else to the arrow.
///
/// A macOS overlay is rarely the key window, so it sets its cursor directly while the pointer
/// is over its hit area.
public enum Cursor: Sendable, Equatable, Hashable {
    case `default`
    case pointer
    case text
    case grab
    case grabbing
    case notAllowed
    case move
    case resizeColumn
    case resizeRow
    case ewResize
    case nsResize
    case neswResize
    case nwseResize
    /// A precise-selection cross (CSS `crosshair`), for picking a point or dragging out a rect.
    case crosshair
    /// No OS cursor (CSS `none`), for views that draw their own. It shows again as soon as the
    /// pointer leaves the element or the window, the element goes away, or the host loses the
    /// pointer: a window losing focus, an overlay hiding.
    case hidden
    /// An app's own image (CSS `url()`), such as a pencil over a canvas. The OS draws it, so
    /// it keeps up with the pointer and shows right to the window's edge. It comes and goes
    /// like any other cursor. If its PNG doesn't decode, the arrow shows instead, and that's
    /// logged once.
    case image(CursorImage)
    /// Legacy Spine alias for custom cursor images.
    case custom(CursorImage)

    public init() {
        self = .default
    }

    public static let Default: Cursor = .default
    public static let Pointer: Cursor = .pointer
    public static let Text: Cursor = .text
    public static let Grab: Cursor = .grab
    public static let Grabbing: Cursor = .grabbing
    public static let NotAllowed: Cursor = .notAllowed
    public static let Move: Cursor = .move
    public static let ResizeColumn: Cursor = .resizeColumn
    public static let ResizeRow: Cursor = .resizeRow
    public static let EwResize: Cursor = .ewResize
    public static let NsResize: Cursor = .nsResize
    public static let Crosshair: Cursor = .crosshair
    public static let Hidden: Cursor = .hidden

    public static func Image(_ image: CursorImage) -> Cursor {
        .image(image)
    }
}

/// The picture for ``Cursor/image(_:)``: a PNG drawn at 2x, so a 64x64 px PNG makes a
/// 32x32 pt cursor, and its hot spot (the point that clicks) in points from the top-left,
/// clamped into the image.
///
/// Two images are the same cursor when they have the same bytes and hot spot. Each image is
/// decoded once and its OS cursor kept, up to 32 of them; a side may be up to 256 px.
public struct CursorImage: Sendable, Equatable, Hashable, CustomDebugStringConvertible {
    public var width: UInt32
    public var height: UInt32
    public var hotspotX: UInt16
    public var hotspotY: UInt16
    public var rgba: [UInt8]

    internal var pngBytes: [UInt8]?
    internal var hotPoint: [Float]

    public init(width: UInt32, height: UInt32, hotspotX: UInt16 = 0, hotspotY: UInt16 = 0, rgba: [UInt8]) {
        self.width = width
        self.height = height
        self.hotspotX = hotspotX
        self.hotspotY = hotspotY
        self.rgba = rgba
        self.pngBytes = nil
        self.hotPoint = [Float(hotspotX), Float(hotspotY)]
    }

    private init(pngBytes: [UInt8], hot: [Float]) {
        let hx = hot.count > 0 ? hot[0] : 0.0
        let hy = hot.count > 1 ? hot[1] : 0.0
        self.width = 0
        self.height = 0
        self.hotspotX = hx.isFinite && hx > 0 ? UInt16(clamping: Int(hx)) : 0
        self.hotspotY = hy.isFinite && hy > 0 ? UInt16(clamping: Int(hy)) : 0
        self.rgba = []
        self.pngBytes = pngBytes
        self.hotPoint = [hx, hy]
    }

    /// A PNG drawn at 2x, with its hot spot in points from the top-left.
    public static func png(_ bytes: [UInt8], _ hot: [Float]) -> CursorImage {
        CursorImage(pngBytes: bytes, hot: hot)
    }

    /// Overload accepting a two-element tuple for the hot spot in points from the top-left.
    public static func png(_ bytes: [UInt8], _ hot: (Float, Float)) -> CursorImage {
        CursorImage(pngBytes: bytes, hot: [hot.0, hot.1])
    }

    internal func bytes() -> [UInt8] {
        pngBytes ?? []
    }

    internal func hot() -> [Float] {
        hotPoint
    }

    public static func == (lhs: CursorImage, rhs: CursorImage) -> Bool {
        guard lhs.hotPoint.count == 2, rhs.hotPoint.count == 2 else { return false }
        let hotMatch = lhs.hotPoint[0].bitPattern == rhs.hotPoint[0].bitPattern
            && lhs.hotPoint[1].bitPattern == rhs.hotPoint[1].bitPattern
        guard hotMatch else { return false }
        if lhs.pngBytes != nil || rhs.pngBytes != nil {
            return lhs.pngBytes == rhs.pngBytes
        }
        return lhs.width == rhs.width
            && lhs.height == rhs.height
            && lhs.hotspotX == rhs.hotspotX
            && lhs.hotspotY == rhs.hotspotY
            && lhs.rgba == rhs.rgba
    }

    public func hash(into hasher: inout Hasher) {
        if let png = pngBytes {
            hasher.combine(png.count)
            hasher.combine(hotPoint[0].bitPattern)
            hasher.combine(hotPoint[1].bitPattern)
        } else {
            hasher.combine(width)
            hasher.combine(height)
            hasher.combine(hotspotX)
            hasher.combine(hotspotY)
            hasher.combine(rgba.count)
        }
    }

    public var debugDescription: String {
        if let png = pngBytes {
            let hx = formatDebugFloat(hotPoint[0])
            let hy = formatDebugFloat(hotPoint[1])
            return "CursorImage { png_bytes: \(png.count), hot: [\(hx), \(hy)] }"
        }
        return "CursorImage { width: \(width), height: \(height), hot: [\(hotspotX), \(hotspotY)] }"
    }
}

private func formatDebugFloat(_ v: Float) -> String {
    if v.isFinite && v.rounded() == v && abs(v) < 1e7 {
        return "\(Int(v)).0"
    }
    return "\(v)"
}
