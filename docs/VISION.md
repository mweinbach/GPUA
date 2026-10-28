# Vision

## The pitch

**Write your UI once in Swift and ship it, GPU-rendered and native-fast, on macOS, iOS, Windows, Linux, Android, and the web.**

GPUA does this by porting [GPUI](https://github.com/Glass-HQ/gpui), the framework that renders the Zed editor at 120 fps, to Swift faithfully, file by file. It is distributed as a plain SwiftPM package.

## Goals

1. **Faithful port.** Same architecture, same semantics, same file layout as upstream GPUI. A GPUI user should feel at home, and the GPUI docs and examples should translate line by line.
2. **One SwiftPM package, every platform.** Add `.package(url: "https://github.com/mweinbach/GPUA", …)`, `import GPUI`, and build with the standard Swift toolchain for each target (Xcode/swift on Apple, swift.org toolchains on Linux/Windows, the Swift SDK for Android, the Swift SDK for Wasm).
3. **Native rendering performance.** Metal on Apple, Direct3D on Windows, Vulkan through WebGPU on Linux and Android, and WebGPU in browsers. The target is frame times comparable to Rust GPUI on the same hardware.
4. **Upstream-trackable.** Pinning, per-file provenance headers, and `Scripts/port.py stale` keep re-syncing with upstream cheap.
5. **Swift 6 native.** Strict concurrency, typed throws where useful, Swift Testing, DocC, and macros where upstream uses proc macros.
6. **Embeddable.** A GPUA surface can live inside an existing AppKit/UIKit app (Glass-HQ's `hosted_views`/`composite_hosts`), and later inside an Android `SurfaceView` or a Win32 HWND.

## Non-goals

- **Not a SwiftUI clone or SwiftUI backend.** GPUA's API is GPUI's API: entities, `Render`, `div()`, and fluent styling. Result-builder sugar may come later as an *additive* layer, never as a replacement.
- **Not a redesign.** We don't "fix" GPUI's architecture during the port. Improvements go upstream first, or into a clearly separate layer after parity.
- **Not native widgets.** Like GPUI, GPUA draws its own UI. Native views can be embedded, but there's no wrapping of `NSButton`/`UIButton`/Win32 controls as the primary model.
- **Not Zed.** We port `gpui` and the crates it needs, not the editor or Zed's `ui` component library. A component library could be a separate package later.
- **Not a Rust FFI wrapper.** No Rust toolchain in the build. Everything is Swift, plus C/C++ only where a platform or graphics library requires it.

## Success criteria

| Milestone | Definition |
|---|---|
| **M1: Foundations** | `GPUICollections`, `SumTree`, `Refineable`, `Scheduler`, `Taffy`, and the GPUI value types (geometry, color, style) are ported, with upstream tests passing on macOS, Linux, and Windows CI. |
| **M2: Headless GPUI** | The app/entity/window/element pipeline runs on `TestPlatform`. Upstream `#[gpui::test]` suites for entities, key dispatch, and elements pass. A `Scene` can be produced and snapshot-tested. |
| **M3: Hello, macOS** | `swift run gpui-examples hello_world` opens a Metal-rendered window on macOS that matches the Rust version pixel-for-pixel (within AA tolerance). |
| **M4: Mobile** | The iOS demo set from `gpui_examples/src/ios.rs` runs on device and simulator. |
| **M5: Desktop parity** | Linux (Wayland + X11) and Windows run the full example gallery. |
| **M6: Android** | The example gallery runs on an Android device through the new `GPUIAndroid` backend. |
| **M7: Web** | `hello_world` runs in a browser through the Wasm SDK + WebGPU. |
| **1.0** | All ported files are `verified`, the upstream sync cadence is established, the public API is documented with DocC, and examples and templates exist for each platform. |
