// Ported from: crates/gpui_metal/src/gpui_metal.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if canImport(Metal)
@_exported import struct GPUI.DevicePixels
@_exported import struct GPUI.GpuSpecs
@_exported import struct GPUI.Hsla
@_exported import struct GPUI.Image
@_exported import struct GPUI.Point
@_exported import struct GPUI.ScaledPixels
@_exported import struct GPUI.Scene
@_exported import struct GPUI.Size

// PORT NOTE: All public types (`MetalAtlas`, `Context`, `InstanceBufferPool`,
// `MetalRenderer`, `Renderer`, `SharedRenderResources`, `SurfaceRenderer`, and
// `newRenderer`) live in the `GPUIMetal` module namespace directly, matching
// upstream `pub use` re-exports in `crates/gpui_metal/src/gpui_metal.rs`.
#endif
