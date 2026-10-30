# Platforms

Per-platform plan, toolchains, and system dependencies. Upstream crate names are given so you know which files to port from.

| | macOS | iOS / visionOS | Linux | Windows | Android | Web |
|---|---|---|---|---|---|---|
| Swift target | `GPUIMacOS` | `GPUIiOS` | `GPUILinux` | `GPUIWindows` | `GPUIAndroid` *(new)* | `GPUIWeb` |
| Upstream | `gpui_macos` | `gpui_ios` | `gpui_linux` | `gpui_windows` | — | `gpui_web` |
| Shared / C shim | `GPUIApple` | `GPUIApple` | `CLinuxSys`, `CWebGPU` | `CWinSys` | `CAndroidSys`, `CWebGPU` | `CWebSys`, `CWebGPU` |
| Renderer | `GPUIMetal` | `GPUIMetal` | `GPUIWGPU` | D3D11 (in `GPUIWindows`) | `GPUIWGPU` | `GPUIWGPU` |
| GPU API | Metal | Metal | Vulkan (via `wgpu-native`) | Direct3D 11 + DirectComposition | Vulkan (via `wgpu-native`) | Browser WebGPU (`navigator.gpu`) |
| Text | CoreText | CoreText | FreeType + HarfBuzz + Fontconfig | DirectWrite | NDK `AFontMatcher` + TrueType/OpenType rasterizer | Pure-Swift TrueType/OpenType rasterizer |
| Toolchain | Xcode / swift.org | Xcode | swift.org (Ubuntu, Fedora, …) | swift.org Windows | Swift SDK for Android + NDK | Swift SDK for Wasm (`wasm32-unknown-wasip1`) |
| Phase | 3 ✅ | 4 ✅ | 5 ✅ | 6 ✅ | 7 ✅ | 8 ✅ |

## Apple (macOS, iOS, visionOS) — [ADR-0011](adr/0011-apple-native-and-ios-host.md)

- **Ported:** `GPUIApple` (shared AppKit/UIKit host views, composite hosts, presentations), `GPUIMacOS`, `GPUIiOS`, `GPUIMetal`, `Media`.
- **Bindings:** AppKit, UIKit, Metal, QuartzCore (`CAMetalLayer`, `CADisplayLink`/`CVDisplayLink`), CoreText, CoreGraphics, CoreVideo, Security (Keychain credentials), ScreenCaptureKit, UniformTypeIdentifiers.
- **`gpui_apple/src/objc/*`** (manual Rust Objective-C runtime class building, ivars, memory) is `skipped` because Swift subclasses `NSView`/`UIView` natively under ARC.
- **Shaders:** `shaders.metal` is copied verbatim and compiled via `device.makeLibrary(source:options:)` from `Bundle.module` (with layout parity verified on GPU via `probe_scene_layouts`).
- **iOS host:** `Hosts/iOS` provides an XcodeGen `project.yml` + Swift `AppMain.swift` bridging to `@_cdecl("gpui_ios_app_start")`.

## Linux — [ADR-0008](adr/0008-linux-system-interop.md)

- **Ported:** `GPUILinux` (Wayland, X11, headless, `xdg-desktop-portal` D-Bus client), `GPUIWGPU`, `CLinuxSys`, `CWebGPU`.
- **System libraries** (loaded dynamically via `dlopen`/`dlsym` in `CLinuxSys` and `CWebGPU` with zero SwiftPM `.unsafeFlags`): `libwayland-client`, `libwayland-cursor`, `libxkbcommon`, `libxkbcommon-x11`, `libxcb` (+ `xcb-xkb`, `xcb-randr`), `libdbus-1`, `libfontconfig`, `libfreetype`, `libharfbuzz`, and `libwgpu_native` (Vulkan / Mesa Lavapipe).
- **Install deps (Ubuntu):** run `bash Scripts/install_linux_deps.sh`.

## Windows — [ADR-0009](adr/0009-windows-com-and-shaders.md)

- **Ported:** `GPUIWindows` + `CWinSys` file-for-file: Direct3D 11, DirectComposition, DirectWrite (`IDWriteFactory5` + `IDWriteFontFallback`), DirectManipulation, `ITaskbarList3` / `ICustomDestinationList`, Windows Credential Manager, and HLSL shaders (`shaders.hlsl`, `alpha_correction.hlsl`, `color_text_raster.hlsl`) compiled via `D3DCompile`.
- **Toolchain:** swift.org Windows 6.3 toolchain (Visual Studio Build Tools + Windows SDK).

## Android — [ADR-0012](adr/0012-android-platform-and-jni.md)

`GPUIAndroid` mirrors the file shape of `gpui_linux`/`gpui_ios`:

```
Sources/GPUIAndroid/
  gpui_android.swift     # module root, currentPlatform()
  platform.swift         # AndroidPlatform: Platform (Keystore credentials, URL, clipboard, thermal)
  dispatcher.swift       # ALooper wake-pipe main-thread dispatch + priority queues
  display.swift          # AndroidDisplay (DisplayMetrics + cutout safe-area insets)
  window.swift           # AndroidWindow: PlatformWindow over ANativeWindow + WgpuRenderer
  events.swift           # Touch / stylus / mouse / scroll / key event translation → PlatformInput
  keyboard.swift         # Android AKEYCODE_* keymaps + InputConnection IME composition bridge
  text_system.swift      # NDK ASystemFontIterator / AFontMatcher + TrueType/OpenType rasterizer
  lifecycle.swift        # Activity & SurfaceHolder lifecycle state machine + AChoreographer vsync
  jni.swift              # @_cdecl("Java_dev_glasshq_gpua_GPUIActivity_native*") JNI exports
```

- **Rendering:** `GPUIWGPU` with `libwgpu_native.so` Vulkan backend on an `ANativeWindow` surface.
- **Host app:** `Hosts/android` (Gradle + Kotlin `GPUIActivity` & `GPUISurfaceView` with Android Keystore AES-256-GCM credentials, `ClipboardManager`, `InputConnection`, and `WindowInsets`).
- **Toolchain:** Swift SDK for Android (API 29+):
  ```sh
  swift build --swift-sdk aarch64-unknown-linux-android29 --product gpui-examples
  ```

## Web (Wasm) — [ADR-0013](adr/0013-web-wasm-bridge.md)

- **Ported:** `GPUIWeb` + `CWebSys` + `CWebGPU` + `GPUIWGPU` (browser WebGPU).
- **Zero-dependency WASI bridge:** Instead of `JavaScriptKit`, `CWebSys` and `CWebGPU` declare `__attribute__((import_module("gpui_web")))` and `__attribute__((import_module("wgpu")))` C functions fulfilled directly by `Hosts/web/gpui_web_runtime.js`.
- **Host:** `Hosts/web/{index.html, gpui_web_runtime.js, README.md}` loads `gpui-examples.wasm`, provides a minimal WASI Preview 1 shim, bridges DOM/Fetch/Clipboard/Storage events, and maps `wgpu*` C calls onto browser `navigator.gpu`.
- **Toolchain:** Swift 6.3 Wasm SDK:
  ```sh
  swift build --swift-sdk swift-6.3-RELEASE_wasm --product gpui-examples
  ```

## CI matrix

| Job | Runner | What it checks |
|---|---|---|
| `port-check` | `ubuntu-latest` | `Scripts/port.py check` + `Scripts/test_parity.py --check` |
| `macos` | `macos-latest` | `swift build`, `swift test` (incl. Metal offscreen `hello_world_macos.png`), `Hosts/iOS` Simulator `xcodebuild` |
| `linux` | `ubuntu-latest` (`swift:6.3-noble`) | `swift build`, `xvfb-run -a swift test` (incl. Vulkan/Lavapipe `hello_world_linux.png`) |
| `windows` | `windows-latest` | `swift build`, `swift test` (incl. D3D11/WARP `hello_world_windows.png`) |
| `android` | `ubuntu-latest` | Cross-compile with the Swift 6.3 SDK for Android (`skiptools/swift-android-action`) |
| `wasm` | `ubuntu-latest` (`swift:6.3-noble`) | Build `gpui-examples.wasm` with Swift 6.3 Wasm SDK + Node.js Wasm import contract check against `Hosts/web/gpui_web_runtime.js` |
