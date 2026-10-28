# Platforms

Per-platform plan, toolchains, and system dependencies. Upstream crate names are given so you know which files to port from.

| | macOS | iOS / visionOS | Linux | Windows | Android | Web |
|---|---|---|---|---|---|---|
| Swift target | `GPUIMacOS` | `GPUIiOS` | `GPUILinux` | `GPUIWindows` | `GPUIAndroid` *(new)* | `GPUIWeb` |
| Upstream | `gpui_macos` | `gpui_ios` | `gpui_linux` | `gpui_windows` | — | `gpui_web` |
| Shared | `GPUIApple` | `GPUIApple` | — | — | — | — |
| Renderer | `GPUIMetal` | `GPUIMetal` | `GPUIWGPU` | D3D11 (in `GPUIWindows`) | `GPUIWGPU` | `GPUIWGPU` |
| GPU API | Metal | Metal | Vulkan (via wgpu-native) | Direct3D 11 + DirectComposition | Vulkan (via wgpu-native) | WebGPU |
| Text | CoreText | CoreText | FreeType + HarfBuzz + fontconfig | DirectWrite | FreeType + HarfBuzz | Browser / bundled |
| Toolchain | Xcode / swift.org | Xcode | swift.org (Ubuntu, Fedora, …) | swift.org Windows | Swift SDK for Android + NDK | Swift SDK for Wasm |
| Phase | 3 | 4 | 5 | 6 | 7 | 8 |

## Apple (macOS, iOS, visionOS)

- **Port:** `gpui_apple` (shared), `gpui_macos`, `gpui_ios`, `gpui_metal`, `media`.
- **Bindings:** AppKit, UIKit, Metal, QuartzCore (`CAMetalLayer`, `CADisplayLink`/`CVDisplayLink`), CoreText, CoreGraphics, CoreVideo, Security (credentials), UniformTypeIdentifiers. Import the frameworks directly; there are no `objc`/`cocoa` crate equivalents.
- **`gpui_apple/src/objc/*`** (manual runtime class building, ivars, memory) is mostly `skipped`. Swift subclasses `NSView`/`UIView` natively. Port the *behavior* into the files that use it.
- **Shaders:** `shaders.metal` is copied verbatim. First pass: compile it from source at runtime (`device.makeLibrary(source:options:)`) with the source loaded from `Bundle.module`. Later: a build-tool plugin produces a `.metallib`.
- **iOS host:** port `hosts/ios` (xcodegen `project.yml` + a tiny runner) to `Hosts/iOS`, with the runner rewritten in Swift.
- **Mac Catalyst:** compiled as part of the iOS target. Not a priority.

## Linux

- **Port:** `gpui_linux` (Wayland, X11, headless, xdg-desktop-portal), `gpui_wgpu`.
- **System libraries** (as `systemLibrary` targets with `pkgConfig`): `wayland-client`, `wayland-cursor`, `xkbcommon`, `xkbcommon-x11`, `xcb` (+ `xcb-xkb`, `xcb-randr`, …), `fontconfig`, `freetype2`, `harfbuzz`, and Vulkan loader at runtime.
- **Wayland protocols** (`xdg-shell`, `xdg-decoration`, `fractional-scale`, `viewporter`, `layer-shell`, …): generate C glue with `wayland-scanner` and vendor it as a C target (`CWaylandProtocols`).
- **D-Bus portals** (file pickers, settings): via `libdbus`/`sd-bus` C API or a Swift D-Bus package. Needs an ADR.
- **Renderer:** `GPUIWGPU` on wgpu-native. See [ADR-0004](adr/0004-renderers.md).
- **Install deps (Ubuntu):**
  ```sh
  sudo apt install libwayland-dev libxkbcommon-dev libxkbcommon-x11-dev libxcb1-dev \
      libxcb-xkb-dev libxcb-randr0-dev libfontconfig-dev libfreetype-dev libharfbuzz-dev libvulkan-dev
  ```

## Windows

- **Port:** `gpui_windows` file-for-file. Upstream already uses Direct3D 11, DirectWrite, DirectComposition, and DirectManipulation, all of which are reachable from Swift's `WinSDK` module.
- **Shaders:** `shaders.hlsl`, `alpha_correction.hlsl`, and `color_text_raster.hlsl` are copied verbatim and compiled at runtime with `D3DCompile` first. Precompiled later.
- **Manifest/resources:** upstream embeds `gpui.manifest.xml`/`gpui.rc` through `build.rs`. We'll do it with a SwiftPM build plugin or document it for app authors (DPI awareness, Common Controls v6).
- **Toolchain:** swift.org Windows installer (Visual Studio Build Tools + Windows SDK).

## Android (new backend)

There's no upstream crate, so `GPUIAndroid` is designed here. **Mirror the file shape of `gpui_linux`/`gpui_ios`** so it reads like a sibling:

```
Sources/GPUIAndroid/
  gpui_android.swift     # module root, re-exports (Swift-only)
  platform.swift         # AndroidPlatform: Platform
  dispatcher.swift       # ALooper-based main-thread dispatch + thread pool
  display.swift          # AndroidDisplay (DisplayMetrics via JNI)
  window.swift           # AndroidWindow: PlatformWindow over ANativeWindow
  events.swift           # AInputEvent / GameActivity motion & key events → PlatformInput
  keyboard.swift         # key maps, IME bridge (InputConnection via JNI)
  text_system.swift      # FreeType + HarfBuzz (shared with Linux where possible)
  lifecycle.swift        # onResume/onPause/surface created/destroyed (see gpui_ios/lifecycle.rs)
```

- **Rendering:** `GPUIWGPU` with wgpu-native's Vulkan backend on an `ANativeWindow` surface.
- **Entry:** `GameActivity` (AGDK) or `NativeActivity`. Swift exports the `android_main` equivalent. Host app is `Hosts/android` (Gradle, minimal Kotlin/Java).
- **JNI:** clipboard, IME, display metrics, and open-URL need JNI calls. Use raw JNI through a small C shim, or `swift-java`. Needs an ADR.
- **Toolchain:** Swift SDK for Android (official since Swift 6.3) + Android NDK:
  ```sh
  swift sdk install <swift.org android artifactbundle URL>
  swift build --swift-sdk aarch64-unknown-linux-android28
  ```
- **Text:** FreeType/HarfBuzz aren't public NDK APIs, so vendor them as C/C++ source targets.

## Web (Wasm)

- **Port:** `gpui_web` + `gpui_wgpu` (browser WebGPU).
- **Toolchain:** Swift SDK for Wasm. DOM/JS interop through **JavaScriptKit** (needs an ADR).
- **Host:** port `hosts/web` (HTML bootstrap) to `Hosts/web`.
- Last priority. It depends on `GPUIWGPU` being able to target browser WebGPU directly, not wgpu-native.

## CI matrix

| Job | Runner | What it checks |
|---|---|---|
| `port-check` | ubuntu | `Scripts/port.py check` (mapping, headers, status doc) |
| `macos` | macos | `swift build`, `swift test` |
| `linux` | ubuntu (swift container) | `swift build`, `swift test` |
| `windows` | windows | `swift build`, `swift test` |
| `android` | ubuntu | Cross-compile with the Swift SDK for Android (`skiptools/swift-android-action`) |
| `wasm` | ubuntu | *(later)* `swift build --swift-sdk wasm32-unknown-wasi` |
