# 0004: Renderers: Metal, D3D11, and WebGPU via wgpu-native

- **Status:** Accepted
- **Date:** 2026-10-28

## Context

Upstream has three renderers: `gpui_metal` (macOS/iOS), a Direct3D 11 renderer inside `gpui_windows`, and `gpui_wgpu` (Linux, web), which uses the Rust `wgpu` crate with WGSL shaders. All three consume the same `Scene` primitive batches.

## Decision

- **Metal (`GPUIMetal`):** port 1:1 with Swift's Metal framework. Shaders are copied verbatim.
- **Direct3D 11 (`GPUIWindows`):** port 1:1 through Swift's `WinSDK` COM interop. HLSL is copied verbatim. In CI and headless testing, uses DXGI with WARP software adapter for deterministic rendering smoke tests.
- **WebGPU (`GPUIWGPU`):** port 1:1 against the **`webgpu.h` C API**. The WGSL shaders are copied verbatim. Native implementation is **wgpu-native**, the same engine upstream uses, which gives behavioral parity:
  - Linux: Vulkan (with Mesa Lavapipe software rendering for headless CI smoke tests).
  - Android: Vulkan.
  - Web: the browser's WebGPU through JS interop, with the same Swift renderer code behind a thin binding.
- **Dependencies (R5):** `wgpu-native` is accepted as an external dependency consumed as a C module target (`CWebGPU`, `webgpu.h` + `wgpu.h`). Software rasterization adapters (WARP on Windows, Lavapipe on Linux) are accepted for automated CI smoke tests.

## Alternatives considered

- **Dawn** instead of wgpu-native: also implements `webgpu.h`, but it's heavier to build and diverges from upstream's wgpu behavior. Kept as a fallback since the API is the same.
- **Raw Vulkan renderer** for Linux/Android: no upstream to port from, and a lot more code.
- **WebGPU everywhere, including Apple and Windows:** simpler, but it throws away upstream's tuned native renderers and adds a dependency on Apple platforms. Rejected for Apple. Windows *may* use `GPUIWGPU` as a fallback.

## Consequences

Three renderers to maintain, which is exactly what upstream does. Shader struct layouts must match the Swift structs, so every GPU struct needs `MemoryLayout` tests. Headless CI validation reliably tests rendering across platforms using software adapters.
