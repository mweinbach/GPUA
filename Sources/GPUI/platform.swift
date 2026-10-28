// Ported from: crates/gpui/src/platform.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: in-progress

import Foundation
import Refineable

/// Mouse cursor styles matching CSS cursor values.
public enum CursorStyle: Sendable, Equatable, Hashable, Codable, DefaultInitializable {
    /// The default cursor.
    case arrow
    /// A text input cursor (corresponds to CSS `text`).
    case iBeam
    /// A crosshair cursor (corresponds to CSS `crosshair`).
    case crosshair
    /// A closed hand cursor (corresponds to CSS `grabbing`).
    case closedHand
    /// An open hand cursor (corresponds to CSS `grab`).
    case openHand
    /// A pointing hand cursor (corresponds to CSS `pointer`).
    case pointingHand
    /// A resize left cursor (corresponds to CSS `w-resize`).
    case resizeLeft
    /// A resize right cursor (corresponds to CSS `e-resize`).
    case resizeRight
    /// A resize cursor to the left and right (corresponds to CSS `ew-resize`).
    case resizeLeftRight
    /// A resize up cursor (corresponds to CSS `n-resize`).
    case resizeUp
    /// A resize down cursor (corresponds to CSS `s-resize`).
    case resizeDown
    /// A resize cursor up and down (corresponds to CSS `ns-resize`).
    case resizeUpDown
    /// A resize up-left cursor.
    case resizeUpLeft
    /// A resize down-right cursor.
    case resizeDownRight
    /// A resize diagonal cursor (corresponds to CSS `nwse-resize`).
    case resizeUpLeftDownRight
    /// A resize up-right cursor.
    case resizeUpRight
    /// A resize down-left cursor.
    case resizeDownLeft
    /// A resize diagonal cursor (corresponds to CSS `nesw-resize`).
    case resizeUpRightDownLeft
    /// A not allowed cursor.
    case notAllowed
    /// A wait cursor.
    case wait
    /// A progress cursor.
    case progress
    /// A copy cursor.
    case copy
    /// None (invisible cursor).
    case none

    public init() {
        self = .arrow
    }
}

// MARK: - Atlas Types

/// The unique ID of a tile within an atlas texture.
@frozen
public struct TileId: RawRepresentable, Sendable, Equatable, Hashable, Comparable, Codable {
    public var rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static func < (lhs: TileId, rhs: TileId) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The kind of content stored in an atlas texture.
@frozen
public enum AtlasTextureKind: UInt32, Sendable, Equatable, Hashable, Codable {
    case monochrome = 0
    case polychrome = 1
    case subpixel = 2
}

/// The identifier of a texture within the atlas.
@frozen
public struct AtlasTextureId: Sendable, Equatable, Hashable, Codable {
    /// The index of this texture in the atlas.
    public var index: UInt32
    /// The kind of content stored in this texture.
    public var kind: AtlasTextureKind

    public init(index: UInt32, kind: AtlasTextureKind) {
        self.index = index
        self.kind = kind
    }
}

/// A descriptor for a subregion tile within a texture atlas.
@frozen
public struct AtlasTile: Sendable, Equatable, Hashable {
    /// The texture this tile belongs to.
    public var textureId: AtlasTextureId
    /// The unique ID of this tile within its texture.
    public var tileId: TileId
    /// Padding around the tile content in pixels.
    public var padding: UInt32
    /// The bounds of this tile within the texture.
    public var bounds: Bounds<DevicePixels>

    public init(
        textureId: AtlasTextureId,
        tileId: TileId,
        padding: UInt32 = 0,
        bounds: Bounds<DevicePixels>
    ) {
        self.textureId = textureId
        self.tileId = tileId
        self.padding = padding
        self.bounds = bounds
    }
}

