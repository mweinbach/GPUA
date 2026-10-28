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
