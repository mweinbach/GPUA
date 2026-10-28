// Ported from: src/util/sys.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// Allocator-flexible data types and platform math functions.

/// Rounds to the nearest whole number.
@inlinable
@inline(__always)
public func round(_ value: Float) -> Float {
    value.rounded()
}

/// Rounds up to the nearest whole number.
@inlinable
@inline(__always)
public func ceil(_ value: Float) -> Float {
    value.rounded(.up)
}

/// Rounds down to the nearest whole number.
@inlinable
@inline(__always)
public func floor(_ value: Float) -> Float {
    value.rounded(.down)
}

/// Computes the absolute value.
@inlinable
@inline(__always)
public func abs(_ value: Float) -> Float {
    value.magnitude
}

/// Returns the largest of two f32 values, treating NaN as missing (returning the other operand).
@inlinable
@inline(__always)
public func f32_max(_ a: Float, _ b: Float) -> Float {
    if a.isNaN { return b }
    if b.isNaN { return a }
    return a > b ? a : b
}

/// Returns the smallest of two f32 values, treating NaN as missing (returning the other operand).
@inlinable
@inline(__always)
public func f32_min(_ a: Float, _ b: Float) -> Float {
    if a.isNaN { return b }
    if b.isNaN { return a }
    return a < b ? a : b
}

extension Float {
    /// Returns the largest of two f32 values, treating NaN as missing.
    @inlinable
    public func max(_ other: Float) -> Float {
        f32_max(self, other)
    }

    /// Returns the smallest of two f32 values, treating NaN as missing.
    @inlinable
    public func min(_ other: Float) -> Float {
        f32_min(self, other)
    }
}
