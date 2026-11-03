// Ported from: crates/rune/src/gpu/metal/compute_tests.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Compute test helpers (`metalHalfBits`) paired with `Tests/RuneTests/gpu/metal/compute_tests.swift`.

/// Converts an `f32` in `[0, 1]` to IEEE 754 binary16 bits, matching `half_bits` in `compute_tests.rs`.
public func metalHalfBits(_ v: Float) -> UInt16 {
    if v == 0.0 { return 0 }
    let bits = v.bitPattern
    let exp = Int32((bits >> 23) & 0xff) - 127 + 15
    let mantissa = (bits >> 13) & 0x3ff
    if exp <= 0 {
        return 0
    }
    return UInt16((UInt32(exp) << 10) | mantissa)
}
