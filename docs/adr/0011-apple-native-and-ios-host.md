# 0011: Apple Native Backends (`GPUIMetal`, `GPUIApple`, `GPUIMacOS`, `GPUIiOS`) and iOS Host Shell

- **Status:** Accepted
- **Date:** 2026-10-30

## Context

Upstream GPUI splits Apple platform support across four crates and one host shell:
- `crates/gpui_metal`: Metal 2 renderer (`MetalAtlas`, `MetalRenderer`, `SurfaceRenderer`, `SharedRenderResources`, `InstanceBufferPool`) with `shaders.metal` and a `build.rs` that invokes `cbindgen` to generate `scene.h` before compiling `shaders.metallib` or stitching `stitched_shaders.metal`.
- `crates/gpui_apple`: Shared AppKit/UIKit attachment, callback ivar naming, and manual Objective-C runtime pointer helpers (`objc::class`, `objc::ivar`, `objc::memory`, `objc::strings`).
- `crates/gpui_macos`: Native AppKit windowing (`NSApplication`, `NSWindow`, `NSView`, `CAMetalLayer`, `NSTextInputClient` IME), `CVDisplayLink`/`CADisplayLink`, `NSPasteboard`, CoreText `PlatformTextSystem` + OpenType feature mapping, `ScreenCaptureKit` capture, menus, and file dialogs.
- `crates/gpui_ios`: Native UIKit windowing (`UIWindow`, `UIView`, `UIViewController`, `CAMetalLayer`), `CADisplayLink`, `UIScreen`, CoreText `PlatformTextSystem`, multi-touch & gesture recognizers, `UITextInput` session/backed view/traits, `UIDragInteraction`/`UIDropInteraction`, lifecycle notifications, and C FFI demo bridge, paired with `hosts/ios/` (`xcodegen` `project.yml`, `Entitlements.plist`, `runner/`).

In SwiftPM (`Package.swift`), library targets cannot invoke custom `cbindgen` or `xcrun metal` build scripts without non-portable build plugins, whereas Apple's `MTLDevice.makeLibrary(source:options:)` compiles Metal Shading Language (MSL) directly at runtime on macOS, iOS, visionOS, and Simulator. Furthermore, Swift natively subclasses `NSObject`, `NSView`, `NSWindow`, `UIView`, and `UIViewController` with Automatic Reference Counting (ARC), eliminating the unsafe manual Objective-C ivar and `msg_send!` scaffolding required in Rust.

## Decision

1. **Stitched Runtime Metal Shader Compilation in `GPUIMetal`**:
   - Keep upstream `Sources/GPUIMetal/shaders.metal` verbatim as a bundled SwiftPM resource (`.copy("shaders.metal")`).
   - Define the exact C/MSL `scene.h` header preamble (`Bounds_ScaledPixels`, `Corners_ScaledPixels`, `Edges_ScaledPixels`, `Size_DevicePixels`, `Hsla`, `ContentMask`, `AtlasTile`, `PathRasterizationVertex`, `Shadow`, `Quad`, `Underline`, `MonochromeSprite`, `PolychromeSprite`, `PathSprite`, `SurfaceBounds`, `TransformationMatrix`, `Background`, `LinearColorStop`, and `InputIndex` enums) in `GPUIMetal` and stitch `sceneHeader + "\n" + shadersMetalSource` when compiling via `device.makeLibrary(source:options:)`, with optional precompiled `.metallib` lookup first when bundled.
   - Verify exact byte-size, alignment, and field-offset parity between Swift `@frozen` GPU structs and MSL `shaders.metal` structures in `GPUIMetalTests`, plus offscreen `MTLTexture` (`BGRA8Unorm`) rendering and CPU readback (with BGRA8 → RGBA8 swizzle) for deterministic screenshot verification.
2. **Idiomatic Swift ARC & Native Subclassing in `GPUIApple`, `GPUIMacOS`, and `GPUIiOS`**:
   - Preserve the 1:1 file mapping in `Sources/GPUIApple/` while implementing safe idiomatic Swift equivalents (`Unmanaged` retain/release helpers where bridged, `NSString` conversion, `NSView`/`UIView` `addSubview`/`removeFromSuperview` attachment helpers) and native `NSObject`/`NSView`/`UIView` subclasses in `GPUIMacOS` and `GPUIiOS` rather than raw Objective-C runtime class registration (`objc_allocateClassPair` / `set_ivar`).
3. **CoreText `PlatformTextSystem` Shared Architecture**:
   - Use Apple's native `CoreText` (`CTFont`, `CTFontDescriptor`, `CTFontManagerRegisterGraphicsFont`, `CTLine`, `CTRun`) and `CoreGraphics` (`CGBitmapContext`) directly in both `GPUIMacOS/text_system.swift` and `GPUIiOS/text_system.swift`, faithfully preserving upstream UTF-8 ↔ UTF-16 index mapping, BOM/ZWNJ ligature handling, emoji color bitmap rasterization, and OpenType feature tags.
4. **Native `Hosts/iOS` XcodeGen Host Shell**:
   - Port `.upstream/gpui/hosts/ios` to `Hosts/iOS/` (`project.yml`, `Entitlements.plist`, `runner/AppMain.swift`) referencing the root SwiftPM package `../..` (`GPUI`, `GPUIPlatform`, `GPUIiOS`) directly without Cargo pre-build scripts, enabling `xcodegen generate` + `xcodebuild` Simulator builds in both local development and GitHub Actions `macos` CI.

## Alternatives Considered

- **SwiftPM Build Tool Plugin calling `xcrun metal`**: Requires Xcode Metal Toolchain component downloads on clean runners (which frequently fail in headless CI images when Metal offline compiler components aren't separately installed), whereas `MTLDevice.makeLibrary(source:options:)` uses the built-in system framework compiler present on every macOS and iOS Simulator installation.
- **Dynamic Objective-C Class Registration (`objc_allocateClassPair`) in Swift**: Unnecessary and error-prone in Swift, where `@objc` subclasses of `NSView`, `NSWindow`, `UIView`, and `UIViewController` provide type-safe ARC memory management and protocol conformance (`NSTextInputClient`, `UITextInput`).

## Consequences

- Zero external dependencies added for Apple platforms; uses system `Metal`, `MetalKit`/`QuartzCore`, `AppKit`, `UIKit`, `CoreText`, `CoreGraphics`, `CoreVideo`, and `ScreenCaptureKit`.
- Deterministic real-GPU Metal offscreen and window rendering on macOS Apple Silicon (including CI `hello_world_macos.png` screenshot verification) and full iOS Simulator build verification in CI.
