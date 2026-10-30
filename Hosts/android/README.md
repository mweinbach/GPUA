# GPUA Android Host (`Hosts/android`)

Minimal Gradle Kotlin DSL host shell for running GPUA applications on Android (`minSdk = 29`, `targetSdk = 35`) per [ADR-0012](../../docs/adr/0012-android-platform-and-jni.md).

## Architecture Overview

- **`GPUIActivity` & `GPUINative`**: Loads `libwgpu_native.so` and `libGPUIAndroid.so` (or your application's dynamic product), initializes `AndroidPlatform`, forwards `Activity` lifecycle (`onCreate`, `onStart`, `onResume`, `onPause`, `onStop`, `onDestroy`), dark/light `uiMode`, `PowerManager` thermal status, and `Intent.ACTION_VIEW` deep links over C-ABI JNI (`@_cdecl`), and exposes static host upcalls for clipboard, URL launching, soft keyboard visibility, and `Choreographer` frame scheduling.
- **`GPUISurfaceView`**: Hardware-accelerated `SurfaceView` forwarding `SurfaceHolder` callbacks (`ANativeWindow` creation, resize, and synchronous Vulkan `WGPUSurface` teardown on `surfaceDestroyed`), multi-pointer `MotionEvent` samples, `WindowInsets` safe areas (status bar, navigation bar, display cutout, IME), and `InputConnection` text commits.

## Prerequisites

1. **Swift 6.3+ Toolchain** with the official **Swift SDK for Android** installed (`swift-6.3.3-RELEASE_android`):
   ```sh
   swift sdk list
   # Verify `aarch64-unknown-linux-android29` / `x86_64-unknown-linux-android29`
   ```
2. **Android SDK (`compileSdk = 35`) & NDK r27+** configured via `ANDROID_HOME` or `Hosts/android/local.properties`.
3. **`libwgpu_native.so`** built for Android (`aarch64-linux-android` / `x86_64-linux-android`) with Vulkan enabled.

## Cross-Compiling GPUA for Android

From the repository root:

```sh
# Cross-compile for arm64-v8a (Android API 29+)
~/.swiftly/bin/swift build \
  --swift-sdk aarch64-unknown-linux-android29 \
  -c release
```

## Staging Native Libraries (`jniLibs`)

Copy your compiled Swift shared library, the Swift Android runtime libraries from the Swift Android SDK sysroot, `libc++_shared.so`, and `libwgpu_native.so` into `Hosts/android/app/src/main/jniLibs/arm64-v8a/`:

```sh
JNI_DIR="Hosts/android/app/src/main/jniLibs/arm64-v8a"
SWIFT_ANDROID_SDK="$HOME/Library/org.swift.swiftpm/swift-sdks/swift-6.3.3-RELEASE_android.artifactbundle/swift-android"

mkdir -p "$JNI_DIR"

# 1. Copy your GPUA shared library product
cp .build/aarch64-unknown-linux-android29/release/lib*.so "$JNI_DIR/"

# 2. Copy Swift Android runtime libraries & libc++_shared.so
cp "$SWIFT_ANDROID_SDK/swift-resources/usr/lib/swift-aarch64/android/"libswift*.so "$JNI_DIR/"
cp "$SWIFT_ANDROID_SDK/swift-resources/usr/lib/swift-aarch64/android/"libFoundation*.so "$JNI_DIR/"
cp "$SWIFT_ANDROID_SDK/swift-resources/usr/lib/swift-aarch64/android/"libdispatch.so "$JNI_DIR/"
cp "$SWIFT_ANDROID_SDK/swift-resources/usr/lib/swift-aarch64/android/"libBlocksRuntime.so "$JNI_DIR/"
cp "$SWIFT_ANDROID_SDK/ndk-sysroot/usr/lib/aarch64-linux-android/libc++_shared.so" "$JNI_DIR/"

# 3. Copy Vulkan-backed wgpu-native
cp /path/to/wgpu-native/android-arm64/libwgpu_native.so "$JNI_DIR/"
```

*(Repeat under `jniLibs/x86_64/` using `--swift-sdk x86_64-unknown-linux-android29` when targeting an x86_64 emulator.)*

## Building & Installing the APK

```sh
cd Hosts/android
gradle assembleDebug
gradle installDebug
```

To stream native GPUA logs from a connected device or emulator:

```sh
adb logcat -s GPUA:V AndroidRuntime:E
```
