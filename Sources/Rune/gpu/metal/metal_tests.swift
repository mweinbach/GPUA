// Ported from: crates/rune/src/gpu/metal/tests.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Shared readback helper (`metalReadBuffer`) used by `Tests/RuneTests/gpu/metal/metal_tests.swift`.

/// Maps `buffer`, waits indefinitely on `device`, reads back all bytes, and unmaps.
public func metalReadBuffer(_ device: MetalDevice, _ buffer: MetalBuffer) -> [UInt8] {
    buffer.mapAsync { _ in }
    _ = device.poll(.waitIndefinitely())
    let out = buffer.getMappedRange()
    buffer.unmap()
    return out
}
