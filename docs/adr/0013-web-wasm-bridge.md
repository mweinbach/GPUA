# 0013: Web / Wasm Backend (`GPUIWeb`), Zero-Dependency WASI Host Bridge (`CWebSys`), and Browser WebGPU

- **Status:** Accepted
- **Date:** 2026-10-30

## Context

Upstream GPUI's web backend (`crates/gpui_web`, 10 files) compiles to `wasm32-unknown-unknown` using `wasm-bindgen`, `js-sys`, `web-sys`, and `wgpu`'s browser WebGPU backend, paired with a thin HTML/Trunk host shell in `hosts/web/hello_web/`. It provides:
- `WebPlatform`, `WebDispatcher` (`setTimeout` / `MessageChannel` main-thread scheduling + worker tasks), `WebDisplay` (`window.screen` / `devicePixelRatio` / viewport metrics), `WebWindow` (`HTMLCanvasElement`, `ResizeObserver`, `requestAnimationFrame`, `matchMedia` dark-mode & reduced-motion listeners, `WindowEnvironment` DPR reconciliation), DOM pointer/wheel/keyboard/IME composition/clipboard event translation (`events.rs`, `keyboard.rs`), browser `fetch` (`BrowserHttpClient`), and `console` logging (`logging.rs`).

Swift's official WebAssembly SDK targets `wasm32-unknown-wasip1` (`#if os(WASI)`). Two architectural constraints shape the Swift port:
1. **Zero-External-Dependency Package Graph**: Adding `JavaScriptKit` to `Package.swift` would introduce an external package dependency resolved for all SwiftPM consumers (even macOS/iOS/Linux/Windows consumers, since SwiftPM resolves all `dependencies:` unconditionally regardless of target `.when(platforms: [.wasi])`).
2. **Single-Threaded WASI (`wasm32-unknown-wasip1`) Compatibility**: Standard `wasm32-unknown-wasip1` does not include Grand Central Dispatch (`DispatchQueue`, `DispatchGroup`, `DispatchSemaphore`) or POSIX `Process` spawning. Core targets (`Scheduler`, `GPUI`, `ZedUtil`) must guard GCD and `Process` calls behind `#if !os(WASI)` just as upstream Rust guards `std::process` and `block_on` behind `#[cfg(not(target_family = "wasm"))]`.

## Decision

1. **Zero-Dependency WASI Host Bridge (`CWebSys` + `CWebGPU` WASI Imports)**:
   - Create a Swift-only C target `CWebSys` (`Sources/CWebSys/include/CWebSys.h`, `Sources/CWebSys/include/module.modulemap`, `Sources/CWebSys/CWebSys.c`), guarded by `#if defined(__wasi__)` (empty on all other platforms), declaring strongly-typed C functions annotated with `__attribute__((import_module("gpui_web"), import_name("...")))` for browser DOM, canvas, `ResizeObserver`, `requestAnimationFrame`, timer/microtask scheduling, clipboard, `fetch`, `performance.now`, and `console` operations, paired with `@_cdecl` Swift exports invoked by the JS host runtime on events/frames/timers.
   - Extend `Sources/CWebGPU/shim.c` under `#if defined(__wasi__)` with `__attribute__((import_module("wgpu"), import_name("...")))` imports for the `CWebGPU` C API (`WGPUSurfaceSourceCanvasHTMLSelector`), backed by a browser `navigator.gpu` WebGPU JS runtime table in `Hosts/web/gpui_web_runtime.js`.
   - Extend `GPUIWGPU` (`wgpu_context.swift`, `wgpu_atlas.swift`, `wgpu_renderer.swift`, `readback.swift`) so `os(WASI)` shares the same WebGPU pipeline and WGSL shaders.
   - Register `"CWebSys"` in `porting.json` `swift_only_targets`.
2. **Core Target `#if !os(WASI)` Guards**:
   - Guard GCD (`DispatchQueue`, `DispatchGroup`, `DispatchSemaphore`) and `Foundation.Process` usage in `Scheduler`, `GPUI`, and `ZedUtil` with `#if !os(WASI)`, providing cooperative single-threaded queue draining on `os(WASI)` matching upstream's Wasm executor semantics.
3. **1:1 File Port of `GPUIWeb` and `Hosts/web`**:
   - Port all 10 files of `crates/gpui_web/src/*` into `Sources/GPUIWeb/*` and their inline tests into `Tests/GPUIWebTests/*`, wire `#elseif os(WASI)` + `public func webInit()` in `Sources/GPUIPlatform/gpui_platform.swift`, and port `.upstream/gpui/hosts/web/hello_web/` into `Hosts/web/` (`index.html`, `gpui_web_runtime.js`, `README.md`).
4. **Continuous Integration (`wasm` Job)**:
   - Add a `wasm` job to `.github/workflows/ci.yml` (`swift:6.3-noble` + official `swift-6.3-RELEASE_wasm` SDK) that cross-compiles `GPUIPlatform` and `GPUIExamples` for `wasm32-unknown-wasip1` on every push and PR.

## Alternatives Considered

- **`JavaScriptKit` External SwiftPM Dependency**: Rejected because SwiftPM downloads and resolves all top-level `Package.swift` `dependencies:` on every platform even when target dependencies use `.when(platforms: [.wasi])`, violating GPUA's zero-external-dependency package guarantee.
- **Skipping `GPUIWGPU` on WASI with a Separate Canvas2D Renderer**: Violates upstream fidelity (`crates/gpui_web` renders through `gpui_wgpu` over browser WebGPU).

## Consequences

- `Package.swift` remains 100% free of external SwiftPM dependencies across all 6 OS families.
- `GPUIWeb`, `GPUIWGPU`, `GPUIPlatform`, and `GPUIExamples` compile cleanly to `.wasm` via the official Swift 6.3 Wasm SDK locally and in CI, paired with a self-contained browser WebGPU runtime in `Hosts/web/`.
