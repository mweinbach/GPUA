# 0010: Windows COM, Direct3D 11, and DirectWrite C Bridge (CWinSys)

- **Status:** Accepted
- **Date:** 2026-10-29

## Context

Upstream GPUI's Windows backend (`crates/gpui_windows`) directly targets native Windows graphics and system APIs:
- **Direct3D 11 & DXGI**: `d3d11.dll`, `dxgi.dll`, and `d3dcompiler_47.dll` for GPU device creation, flip-model swapchain presentation, dynamic structured buffers, and HLSL shader compilation.
- **DirectWrite**: `dwrite.dll` for font enumeration, typography, text layout, and glyph run rasterization.
- **Win32 & DWM**: `user32.dll`, `gdi32.dll`, `dwmapi.dll`, `imm32.dll`, `uxtheme.dll`, and `shcore.dll` for window creation, message pump handling, high-DPI scaling, clipboard management, and dark mode chrome.

Under Swift on Windows, directly importing Windows headers or utilizing Swift's standard `WinSDK` module introduces substantial architectural and compiler hurdles:
1. **C++ COM Interface Barriers**: Microsoft DirectWrite headers (`<dwrite.h>`, `<dwrite_3.h>`) are defined as C++ pure virtual classes without C-compatible vtables (`COBJMACROS`). A pure C header cannot `#include <dwrite.h>`.
2. **Swift WinSDK Import Fragility**: Raw `import WinSDK` exposes compiler-specific type definitions (e.g. `HWND` representation differences across toolchains), imports fixed-size C arrays as giant 260-element tuples, and omits essential Win32 preprocessor macros (such as `GET_X_LPARAM`).
3. **Cross-Platform Host Compilation**: GPUA must compile cleanly on developer macOS host machines as well as Linux and Android CI runners. Direct Win32 headers cannot be referenced without breaking non-Windows compilation unless carefully isolated.
4. **Headless CI & Software Rasterization**: Windows CI runners in GitHub Actions typically lack physical GPU hardware. To execute end-to-end rendering and offscreen smoke tests deterministically, the graphics subsystem requires automatic fallback to the Direct3D 11 WARP (`D3D_DRIVER_TYPE_WARP`) software rasterizer, alongside GPU-to-CPU staging texture pixel readback (`D3D11_USAGE_STAGING`).
5. **In-Memory Font Loading**: Test suites and headless fixtures require loading bundled TrueType/OpenType fonts (such as `IBMPlexSans-Regular.ttf`) directly from memory without writing temporary files to the disk filesystem. DirectWrite's `IDWriteInMemoryFontFileLoader` / custom `IDWriteFontFileLoader` enables this capability.

## Decision

1. **Introduce a Dedicated C/C++ Bridge Target `CWinSys`**:
   - Create `Sources/CWinSys/include/CWinSys.h`: A pure C99 umbrella header (`extern "C"`) declaring explicit, predictable function signatures for Direct3D 11, DXGI, D3DCompiler, DirectWrite, and Win32 facilities. Guarded by `#if defined(_WIN32)` with an empty typedef fallback on non-Windows platforms so macOS, Linux, and Android toolchains remain 100% shielded.
   - Create `Sources/CWinSys/include/module.modulemap`: Exports `CWinSys` for clean, modular Swift consumption.
   - Create `Sources/CWinSys/CWinSys.cpp`: Guarded by `#if defined(_WIN32)`, compiled natively as C++ by MSVC or Clang on Windows with **zero `.unsafeFlags`**.
2. **Implement Genuine COM Implementations**:
   - `cwin_d3d11_create_device`: Probes hardware adapter first, retries without debug flags if developer layers are absent, and automatically falls back to `D3D_DRIVER_TYPE_WARP` software rasterization if hardware acceleration is unavailable.
   - `cwin_d3d11_create_swapchain_for_hwnd`: Constructs modern flip-model `DXGI_SWAP_EFFECT_FLIP_DISCARD` swapchains with `DXGI_FORMAT_B8G8R8A8_UNORM` and automatic scaling fallback.
   - `cwin_d3d11_readback_texture_pixels`: Implements `D3D11_USAGE_STAGING` texture copy, `D3D11_MAP_READ` mapping, row pitch stride alignment, and in-place BGRA8 to RGBA8 channel swizzling for deterministic image assertions.
   - `cwin_dwrite_register_in_memory_font_loader` & `cwin_dwrite_create_font_file_reference`: Implements in-memory font file streaming via `IDWriteInMemoryFontFileLoader` (with custom `IDWriteFontFileLoader` / `IDWriteFontFileStream` fallback) for zero-disk-write typography tests.
   - Win32 helpers for window registration, window creation, message posting, DPI queries, and UTF-16 clipboard operations.
3. **Declare Package and Linker Configuration**:
   - Add target `CWinSys` in `Package.swift`.
   - Declare conditional target dependency on `CWinSys` and link required Windows system libraries (`d3d11`, `dxgi`, `d3dcompiler`, `dwrite`, `dwmapi`, `imm32`, `uxtheme`, `ole32`, `shell32`, `user32`, `gdi32`, `shcore`) on `GPUIWindows`, each guarded by `.when(platforms: [.windows])`.
   - Register `"CWinSys"` under `"swift_only_targets"` in `porting.json`.

## Alternatives Considered

- **Direct `import WinSDK` in Swift**: Rejected due to missing C++ COM definitions for DirectWrite, tuple bloat for fixed-size arrays, and cross-platform compilation incompatibilities.
- **Pure C COM Macros (`COBJMACROS`)**: Infeasible for DirectWrite, as Microsoft's `<dwrite.h>` and `<dwrite_3.h>` do not provide C vtable wrappers or macro expansions.
- **Third-Party COM Bridging Packages**: Violates GPUA's minimal dependency mandate and introduces external build-time package manager complexity on Windows.

## Consequences

- **Predictable Swift ABI**: `GPUIWindows` interacts with Windows system libraries exclusively through clean, strongly-typed C99 functions without unsafe pointer gymnastics.
- **Zero Build Warnings on Host**: Non-Windows builds compile `CWinSys` as an empty unit, ensuring macOS development and Linux/Android CI remain completely unaffected.
- **Deterministic Headless Windows CI**: D3D11 WARP fallback and staging readback enable full offscreen rendering tests and screenshot verification without physical display hardware.
- **Memory Font Loading**: DirectWrite tests can load bundled font fixtures in-memory without filesystem dependencies.
