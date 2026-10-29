// Ported from: crates/gpui_wgpu/src/gpui_wgpu.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux) || os(Windows) || os(Android) || os(WASI)
@_exported import CWebGPU
@_exported import GPUI
@_exported import GPUICollections
@_exported import GPUIUtil

#endif
