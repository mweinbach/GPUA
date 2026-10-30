# 0012: Android Platform Backend (`GPUIAndroid`), NDK C Bridge (`CAndroidSys`), and `wgpu-native` Dynamic Dispatch

- **Status:** Accepted
- **Date:** 2026-10-30

## Context

Upstream GPUI does not yet ship an Android crate (`porting.json` declares `GPUIAndroid` as a Swift-only platform target). Supporting Android as a first-class native Swift graphics SDK target requires:
1. **Windowing, Event Loop, and Input**: Interfacing with Android NDK C APIs (`ANativeWindow`, `ALooper`, `AChoreographer`, `AInputEvent` / motion & key events, `AAssetManager`, `<android/log.h>`, and `<jni.h>` entry points from an Android `Activity` + `SurfaceView`).
2. **GPU Presentation via `GPUIWGPU` (Vulkan)**: Per ADR-0004, Android shares `GPUIWGPU` (`wgpu-native` over Vulkan) using `WGPUSurfaceSourceAndroidNativeWindow`. However, during cross-compilation via `swift build --swift-sdk aarch64-unknown-linux-android29` (locally and in `skiptools/swift-android-action@v2`), the NDK sysroot only contains Android system libraries (`libandroid.so`, `liblog.so`, `libdl.so`, `libvulkan.so`) — `libwgpu_native.so` is packaged into the APK's `jniLibs/<abi>/` directory at app packaging time. Hard-linking `-lwgpu_native` in `Package.swift` would break `swift build` for consumers using the standard Swift Android SDK.
3. **Typography & Shaping**: Per ADR-0006, Android requires font discovery, metrics, shaping, and glyph rasterization without assuming desktop Fontconfig/X11 packages exist in the NDK sysroot. Android API 29+ provides `<android/font_matcher.h>`, `<android/font.h>`, and `<android/system_fonts.h>` in `libandroid.so`, and `GPUIWGPU` already includes an embedded clean-room TrueType/shaping fallback in `CosmicTextSystem` for in-memory fonts and cross-compile environments.
4. **App Host Shell**: Android apps launch from an APK managed by Gradle (`Hosts/android`), analogous to `Hosts/iOS` and `Hosts/web`.

## Decision

1. **Introduce Swift-Only C Target `CAndroidSys`**:
   - Create `Sources/CAndroidSys/include/CAndroidSys.h`, `Sources/CAndroidSys/include/module.modulemap`, and `Sources/CAndroidSys/CAndroidSys.c`, guarded by `#if defined(__ANDROID__)` (compiling as an empty unit on all non-Android platforms).
   - Expose clean C99 helpers wrapping `<jni.h>`, `<android/native_window.h>`, `<android/native_window_jni.h>`, `<android/looper.h>`, `<android/choreographer.h>`, `<android/input.h>`, `<android/keycodes.h>`, `<android/system_fonts.h>`, `<android/font_matcher.h>`, `<android/font.h>`, and `<android/log.h>`.
   - Link `android` and `log` via `.linkedLibrary(..., .when(platforms: [.android]))` on `GPUIAndroid`, and register `"CAndroidSys"` in `porting.json` `swift_only_targets`.
2. **Dynamic `dlopen("libwgpu_native.so")` Dispatch in `CWebGPU` on Android**:
   - Extend `Sources/CWebGPU/shim.c` under `#if defined(__ANDROID__)` to dynamically resolve all `wgpu*` C API entry points via `dlopen("libwgpu_native.so", RTLD_NOW | RTLD_LOCAL)` and `dlsym` on first use (returning safe null handles if `libwgpu_native.so` is absent in a headless unit-test process).
   - Extend `GPUIWGPU` (`wgpu_context.swift`, `wgpu_atlas.swift`, `wgpu_renderer.swift`, `readback.swift`) so `os(Android)` uses the full `WgpuContext` / `WgpuRenderer` / `WgpuAtlas` pipeline and constructs surfaces via `WGPUSType_SurfaceSourceAndroidNativeWindow` (`ANativeWindow*`).
3. **Implement `GPUIAndroid` Platform Target and `GPUIAndroidTests`**:
   - Implement `Sources/GPUIAndroid/` (`gpui_android.swift`, `platform.swift`, `dispatcher.swift` [`ALooper` pipe wakeup + background worker pool], `display.swift`, `window.swift` [`ANativeWindow` + `WgpuRenderer` + safe-area insets], `events.swift` [multi-touch `AMotionEvent` & `AKeyEvent` → `PlatformInput`], `keyboard.swift`, `text_system.swift` [NDK system font discovery + TrueType/in-memory font parser & rasterizer], `lifecycle.swift`, `jni.swift` [`@_cdecl` JNI entry points for Activity/SurfaceView lifecycle]), plus `Tests/GPUIAndroidTests/` (`crateTests("GPUIAndroid")` in `Package.swift`).
   - Wire `#elseif os(Android)` in `Sources/GPUIPlatform/gpui_platform.swift` to `AndroidPlatform(headless: headless)`.
4. **Provide `Hosts/android` Thin Host Shell**:
   - Create `Hosts/android/` (Gradle Kotlin DSL project with `GPUIActivity.kt`, `GPUISurfaceView.kt`, `AndroidManifest.xml`, and `README.md`) bridging `SurfaceHolder.Callback`, touch/key input, insets, and `Choreographer` vsync frames into `GPUIAndroid`'s JNI entry points.

## Alternatives Considered

- **Static `.linkedLibrary("wgpu_native", .when(platforms: [.android]))`**: Fails out-of-the-box `swift build` on clean Swift Android SDK installations unless every consumer manually injects prebuilt `.so` files into the SDK sysroot. Dynamic `dlopen` in `CWebGPU` preserves zero-setup `swift build` while running full hardware Vulkan when `libwgpu_native.so` is bundled in `jniLibs/`.
- **Third-Party Swift JNI Macro Packages (`swift-java`)**: Adds heavy SwiftPM dependency graph weight across all platforms; raw `<jni.h>` C helpers in `CAndroidSys` + `@_cdecl` entry points require zero external dependencies.

## Consequences

- `swift build` and `swift build --build-tests` succeed cleanly with `swift-6.3.3-RELEASE_android` locally and `skiptools/swift-android-action@v2` in CI with zero manual sysroot patching.
- `GPUIAndroid` shares 100% of `GPUIWGPU`'s WGSL shaders, atlas, and Vulkan render pipelines.
