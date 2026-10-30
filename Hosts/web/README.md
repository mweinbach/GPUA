# GPUA Web Host (`Hosts/web`)

Port of `.upstream/gpui/hosts/web/hello_web/` for Swift WebAssembly (`wasm32-unknown-wasip1`) per [ADR-0013](../../docs/adr/0013-web-wasm-bridge.md).

## Architecture

- **`CWebSys`** (`Sources/CWebSys/`): Zero-dependency C Wasm-import bridge (`import_module("gpui_web")`) for browser DOM, `<canvas>`, `ResizeObserver`, `requestAnimationFrame`, `matchMedia`, keyboard/mouse/IME events, clipboard, timers, and `fetch()`.
- **`CWebGPU` + `GPUIWGPU`**: Shares the full WGSL pipeline and sprite atlas with Linux/Android over browser `navigator.gpu` WebGPU (`import_module("wgpu")`).
- **`GPUIWeb`** (`Sources/GPUIWeb/`): 1:1 port of `crates/gpui_web/src/*` (`WebPlatform`, `WebWindow`, `WebDispatcher`, `WebDisplay`, `WebKeyboardLayout`, `FetchHttpClient`, `WindowEnvironmentState`, `initLogging`, and DOM event/IME translation).
- **`gpui_web_runtime.js`**: Self-contained ES module providing `wasi_snapshot_preview1`, `gpui_web`, and `wgpu` browser imports with zero npm/bundler dependencies.

## Building & Running Locally

1. Install the official Swift 6.3 WebAssembly SDK:
   ```sh
   swift sdk list # verify swift-6.3.3-RELEASE_wasm (or swift-6.3-RELEASE_wasm) is installed
   ```

2. Cross-compile `gpui-examples` for `wasm32-unknown-wasip1`:
   ```sh
   swift build --swift-sdk swift-6.3.3-RELEASE_wasm --product gpui-examples
   cp .build/wasm32-unknown-wasip1/debug/gpui-examples.wasm Hosts/web/gpui-examples.wasm
   ```

3. Serve `Hosts/web/` over HTTP and open in a WebGPU-capable browser (Chrome/Edge 113+, Safari 18+, Firefox Nightly):
   ```sh
   python3 -m http.server 8080 --directory Hosts/web
   ```
   Then visit `http://localhost:8080/?example=hello_world`.
