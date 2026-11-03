// Ported from: crates/rune/src/cursor/os.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

/// How often an image cursor is set again while it holds the pointer and nothing redraws.
internal let CURSOR_REASSERT: Duration = .milliseconds(50)

/// Standard system cursor shapes (equivalent to winit's `CursorIcon`).
internal enum OsCursorIcon: Sendable, Equatable {
    case `default`
    case pointer
    case text
    case grab
    case grabbing
    case notAllowed
    case move
    case colResize
    case rowResize
    case ewResize
    case nsResize
    case neswResize
    case nwseResize
    case crosshair
}

/// Tracks the OS cursor state a window host last applied.
internal struct OsCursor: Sendable, Equatable {
    internal var appliedActive: Bool = false
    internal var appliedCursor: Cursor = .default
    /// The scale an image cursor was last made at: a window moving to a display with another
    /// scale makes it again.
    internal var scale: Float = 0.0

    internal init() {}

    /// Evaluates whether applying `want` while `active` at `windowScale` requires updating the
    /// platform cursor, returning the `Cursor` to apply or `nil` when only reassertion is needed.
    internal mutating func step(want: Cursor, active: Bool, windowScale: Float) -> Cursor? {
        #if os(macOS)
        let resolvedScale = CURSOR_SOURCE_SCALE
        #else
        let resolvedScale = windowScale
        #endif
        let rescaled = active && isImageCursor(want) && scale != resolvedScale
        scale = resolvedScale
        var pair = (appliedActive, appliedCursor)
        let next = nextOsCursor(&pair, want, active) ?? (rescaled ? want : nil)
        appliedActive = pair.0
        appliedCursor = pair.1
        return next
    }

    /// When to set the image cursor again: while one holds the pointer, on macOS.
    internal func reassertAt(_ now: RuneInstant) -> RuneInstant? {
        #if os(macOS)
        if holdsImageCursor((appliedActive, appliedCursor)) {
            return now + CURSOR_REASSERT
        }
        #endif
        _ = now
        return nil
    }

    /// The image cursor currently holding the pointer, if any (for macOS periodic reassertion).
    internal var heldImage: CursorImage? {
        guard appliedActive else { return nil }
        switch appliedCursor {
        case .image(let img), .custom(let img):
            return img
        default:
            return nil
        }
    }
}

internal func isImageCursor(_ cursor: Cursor) -> Bool {
    switch cursor {
    case .image, .custom:
        return true
    default:
        return false
    }
}

internal func holdsImageCursor(_ applied: (Bool, Cursor)) -> Bool {
    applied.0 && isImageCursor(applied.1)
}

/// The cursor to set, if the `(active, cursor)` pair changed and the host owns the cursor or
/// just gave it up.
internal func nextOsCursor(_ applied: inout (Bool, Cursor), _ want: Cursor, _ active: Bool) -> Cursor? {
    let resolvedWant: Cursor = active ? want : .default
    let was = applied
    applied = (active, resolvedWant)
    if (was.0 != active || was.1 != resolvedWant) && (active || was.0) {
        return resolvedWant
    }
    return nil
}

/// Maps `Cursor` to its system cursor icon. An image that never became an OS cursor is the arrow.
internal func osCursorIcon(_ cursor: Cursor) -> OsCursorIcon {
    switch cursor {
    case .default, .hidden, .image, .custom:
        return .default
    case .pointer:
        return .pointer
    case .text:
        return .text
    case .grab:
        return .grab
    case .grabbing:
        return .grabbing
    case .notAllowed:
        return .notAllowed
    case .move:
        return .move
    case .resizeColumn:
        return .colResize
    case .resizeRow:
        return .rowResize
    case .ewResize:
        return .ewResize
    case .nsResize:
        return .nsResize
    case .neswResize:
        return .neswResize
    case .nwseResize:
        return .nwseResize
    case .crosshair:
        return .crosshair
    }
}
