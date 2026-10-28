# 0004: Renderers: Metal, D3D11, and WebGPU via wgpu-native

- **Status:** Proposed
- **Date:** 2026-10-27

## Context

Upstream has three renderers: `gpui_metal` (macOS/iOS), a Direct3D 11 renderer inside `gpui_windows`, and `gpui_wgpu` (Linux, web), which uses the Rust `wgpu` crate with WGSL shaders. All three consume the same `Scene` primitive batches.

## Decision

- **Metal (`GPUIMetal`):** port 1:1 with Swift's Metal framework. Shaders are copied verbatim.
- **Direct3D 11 (`GPUIWindows`):** port 1:1 through Swift's `WinSDK` COM interop. HLSL is copied verbatim.
- **WebGPU (`GPUIWGPU`):** port 1:1 against the **`webgpu.h` C API**. The WGSL shaders are copied verbatim. Native implementation is **wgpu-native**, the same engine upstream uses, which gives behavioral parity:
  - Linux: Vulkan (GL fallback).
  - Android: Vulkan.
  - Web: the browser's WebGPU through JS interop, with the same Swift renderer code behind a thin binding.
- wgpu-native is consumed as a C module target (`CWebGPU`, `webgpu.h` + `wgpu.h`) that links prebuilt static libraries. Distribution (SwiftPM binary artifact bundle per SE-0482, or a fetch script + system path) gets its own follow-up ADR in Phase 5.

## Alternatives considered

- **Dawn** instead of wgpu-native: also implements `webgpu.h`, but it's heavier to build and diverges from upstream's wgpu behavior. Kept as a fallback since the API is the same.
- **Raw Vulkan renderer** for Linux/Android: no upstream to port from, and a lot more code.
- **WebGPU everywhere, including Apple and Windows:** simpler, but it throws away upstream's tuned native renderers and adds a dependency on Apple platforms. Rejected for Apple. Windows *may* use `GPUIWGPU` as a fallback.

## Consequences

Three renderers to maintain, which is exactly what upstream does. Shader struct layouts must match the Swift structs, so every GPU struct needs `MemoryLayout` tests.
