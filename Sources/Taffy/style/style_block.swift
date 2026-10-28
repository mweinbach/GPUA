// Ported from: src/style/block.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// Used by block layout to implement legacy behavior of `<center>` and `<div align="...">`
public enum TextAlign: Sendable, Hashable {
    /// No special legacy text align behavior.
    case auto
    /// Corresponds to `-webkit-left` or `-moz-left` in browsers
    case legacyLeft
    /// Corresponds to `-webkit-right` or `-moz-right` in browsers
    case legacyRight
    /// Corresponds to `-webkit-center` or `-moz-center` in browsers
    case legacyCenter

    public static let `default`: TextAlign = .auto

    @inlinable
    public init() {
        self = .auto
    }
}

/// The set of styles required for a Block layout container
public protocol BlockContainerStyle: CoreStyle {
    /// Text alignment
    var textAlign: TextAlign { get }
}

/// The set of styles required for a Block layout item (child of a Block container)
public protocol BlockItemStyle: CoreStyle {
    /// Whether the item is a table. Table children are handled specially in block layout.
    var itemIsTable: Bool { get }
}
