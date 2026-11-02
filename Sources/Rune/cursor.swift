// Ported from: crates/rune/src/cursor.rs
// Upstream commit: 5f6d53ddae78
// Port status: in-progress

public struct CursorImage: Sendable, Equatable, Hashable {
    public var width: UInt32
    public var height: UInt32
    public var hotspotX: UInt16
    public var hotspotY: UInt16
    public var rgba: [UInt8]

    public init(width: UInt32, height: UInt32, hotspotX: UInt16 = 0, hotspotY: UInt16 = 0, rgba: [UInt8]) {
        self.width = width
        self.height = height
        self.hotspotX = hotspotX
        self.hotspotY = hotspotY
        self.rgba = rgba
    }
}

public enum Cursor: Sendable, Equatable, Hashable {
    case `default`
    case pointer
    case text
    case grab
    case grabbing
    case ewResize
    case nsResize
    case neswResize
    case nwseResize
    case crosshair
    case notAllowed
    case custom(CursorImage)

    public static let Default: Cursor = .default
    public static let Pointer: Cursor = .pointer
    public static let Text: Cursor = .text
    public static let Grab: Cursor = .grab
    public static let Grabbing: Cursor = .grabbing
    public static let EwResize: Cursor = .ewResize
    public static let NsResize: Cursor = .nsResize
    public static let Crosshair: Cursor = .crosshair
    public static let NotAllowed: Cursor = .notAllowed
}
