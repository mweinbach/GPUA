// Swift-only: JNI @_cdecl entry points and array/string marshaling for dev.glasshq.gpua.GPUINative per ADR-0012

import Foundation
import GPUI
#if os(Android)
import CAndroidSys
#endif

// MARK: - Cross-Platform JNI Event Router

/// Pure-Swift marshaling helper invoked by the `@_cdecl("Java_dev_glasshq_gpua_GPUINative_*")`
/// symbols on Android and directly testable on host platforms.
public enum AndroidJniEventRouter {
    /// Marshals parallel pointer coordinate/metadata arrays from JNI into `[AndroidPointerSample]`.
    public static func buildPointerSamples(
        pointerIds: [Int32],
        xs: [Float],
        ys: [Float],
        pressures: [Float] = [],
        toolTypes: [Int32] = []
    ) -> [AndroidPointerSample] {
        let count = min(pointerIds.count, min(xs.count, ys.count))
        guard count > 0 else { return [] }
        var samples: [AndroidPointerSample] = []
        samples.reserveCapacity(count)
        for i in 0..<count {
            let pressure = i < pressures.count ? pressures[i] : 1.0
            let tool = i < toolTypes.count ? toolTypes[i] : AndroidMotionToolType.finger
            samples.append(
                AndroidPointerSample(
                    pointerId: pointerIds[i],
                    xPx: xs[i],
                    yPx: ys[i],
                    pressure: pressure,
                    toolType: tool
                )
            )
        }
        return samples
    }

    public static func onInit(
        platform: AndroidPlatform,
        density: Float,
        widthPx: Int32,
        heightPx: Int32,
        refreshRateHz: Float
    ) {
        let metrics = AndroidDisplayMetrics(
            widthPixels: widthPx,
            heightPixels: heightPx,
            density: density,
            refreshRateHz: refreshRateHz
        )
        AndroidPlatformRegistry.shared.cacheInitialMetrics(metrics)
        platform.handleNativeInit(
            density: density,
            widthPx: widthPx,
            heightPx: heightPx,
            refreshRateHz: refreshRateHz
        )
    }

    @discardableResult
    public static func onTouchEvent(
        platform: AndroidPlatform,
        action: Int32,
        pointerIds: [Int32],
        xs: [Float],
        ys: [Float],
        pressures: [Float],
        toolTypes: [Int32],
        metaState: Int32,
        buttonState: Int32,
        vScroll: Float,
        hScroll: Float,
        eventTimeMillis: Int64
    ) -> [PlatformInput] {
        let samples = buildPointerSamples(
            pointerIds: pointerIds,
            xs: xs,
            ys: ys,
            pressures: pressures,
            toolTypes: toolTypes
        )
        return platform.handleTouchEvent(
            rawAction: action,
            pointers: samples,
            metaState: metaState,
            buttonState: buttonState,
            vScroll: vScroll,
            hScroll: hScroll,
            eventTimeSeconds: Double(eventTimeMillis) / 1000.0
        )
    }

    public static func onKeyEvent(
        platform: AndroidPlatform,
        action: Int32,
        keyCode: Int32,
        metaState: Int32,
        repeatCount: Int32,
        unicodeChar: Int32,
        scanCode: Int32
    ) -> Bool {
        let emitted = platform.handleKeyEvent(
            action: action,
            keyCode: keyCode,
            metaState: metaState,
            repeatCount: repeatCount,
            unicodeChar: unicodeChar,
            scanCode: scanCode
        )
        return !emitted.isEmpty
    }
}

// MARK: - Android JNI C-ABI Exports

#if os(Android)

private let jniAbortMode: jint = 2 // JNI_ABORT: release read-only primitive array buffer without copy-back

private func extractJString(_ env: UnsafeMutablePointer<JNIEnv?>, _ jstr: jstring?) -> String? {
    guard let jstr, let utfPtr = candroid_jni_get_string_utf_chars(env, jstr) else {
        return nil
    }
    defer {
        candroid_jni_release_string_utf_chars(env, jstr, utfPtr)
    }
    return String(cString: utfPtr)
}

private func extractIntArray(_ env: UnsafeMutablePointer<JNIEnv?>, _ array: jintArray?) -> [Int32] {
    guard let array else { return [] }
    let len = Int(candroid_jni_get_array_length(env, array))
    guard len > 0, let ptr = candroid_jni_get_int_array_elements(env, array) else {
        return []
    }
    defer {
        candroid_jni_release_int_array_elements(env, array, ptr, jniAbortMode)
    }
    return Array(UnsafeBufferPointer(start: ptr, count: len))
}

private func extractFloatArray(_ env: UnsafeMutablePointer<JNIEnv?>, _ array: jfloatArray?) -> [Float] {
    guard let array else { return [] }
    let len = Int(candroid_jni_get_array_length(env, array))
    guard len > 0, let ptr = candroid_jni_get_float_array_elements(env, array) else {
        return []
    }
    defer {
        candroid_jni_release_float_array_elements(env, array, ptr, jniAbortMode)
    }
    return Array(UnsafeBufferPointer(start: ptr, count: len))
}

@_cdecl("Java_dev_glasshq_gpua_GPUINative_nativeInit")
public func gpuaJniNativeInit(
    _ env: UnsafeMutablePointer<JNIEnv?>,
    _ clazz: jclass?,
    _ density: jfloat,
    _ widthPx: jint,
    _ heightPx: jint,
    _ refreshRateHz: jfloat
) {
    candroid_jni_register_host(env, clazz)
    let platform = AndroidPlatformRegistry.shared.ensurePlatform()
    AndroidJniEventRouter.onInit(
        platform: platform,
        density: density,
        widthPx: widthPx,
        heightPx: heightPx,
        refreshRateHz: refreshRateHz
    )
    AndroidAppBootstrap.shared.launchIfNeeded()
}

@_cdecl("Java_dev_glasshq_gpua_GPUINative_nativeOnSurfaceCreated")
public func gpuaJniNativeOnSurfaceCreated(
    _ env: UnsafeMutablePointer<JNIEnv?>,
    _ clazz: jclass?,
    _ surface: jobject?,
    _ widthPx: jint,
    _ heightPx: jint,
    _ format: jint
) {
    _ = clazz
    guard let nativeWindow = candroid_native_window_from_surface(env, surface) else {
        androidLog(.error, "ANativeWindow_fromSurface returned null")
        return
    }
    // ANativeWindow_fromSurface returns an acquired (+1) reference; release our local reference
    // after AndroidPlatform retains its own reference.
    defer {
        candroid_native_window_release(nativeWindow)
    }
    let platform = AndroidPlatformRegistry.shared.ensurePlatform()
    platform.handleSurfaceCreated(
        nativeWindow: nativeWindow,
        widthPx: widthPx,
        heightPx: heightPx,
        format: format
    )
}

@_cdecl("Java_dev_glasshq_gpua_GPUINative_nativeOnSurfaceChanged")
public func gpuaJniNativeOnSurfaceChanged(
    _ env: UnsafeMutablePointer<JNIEnv?>,
    _ clazz: jclass?,
    _ format: jint,
    _ widthPx: jint,
    _ heightPx: jint,
    _ density: jfloat,
    _ refreshRateHz: jfloat
) {
    _ = env
    _ = clazz
    let platform = AndroidPlatformRegistry.shared.ensurePlatform()
    platform.handleSurfaceChanged(
        widthPx: widthPx,
        heightPx: heightPx,
        format: format,
        density: density > 0 ? density : nil,
        refreshRateHz: refreshRateHz > 0 ? refreshRateHz : nil
    )
}

@_cdecl("Java_dev_glasshq_gpua_GPUINative_nativeOnSurfaceDestroyed")
public func gpuaJniNativeOnSurfaceDestroyed(
    _ env: UnsafeMutablePointer<JNIEnv?>,
    _ clazz: jclass?
) {
    _ = env
    _ = clazz
    AndroidPlatformRegistry.shared.clearCachedSurface()
    AndroidPlatformRegistry.shared.currentPlatform?.handleSurfaceDestroyed()
}

@_cdecl("Java_dev_glasshq_gpua_GPUINative_nativeOnTouchEvent")
public func gpuaJniNativeOnTouchEvent(
    _ env: UnsafeMutablePointer<JNIEnv?>,
    _ clazz: jclass?,
    _ action: jint,
    _ pointerIds: jintArray?,
    _ xs: jfloatArray?,
    _ ys: jfloatArray?,
    _ pressures: jfloatArray?,
    _ toolTypes: jintArray?,
    _ metaState: jint,
    _ buttonState: jint,
    _ vScroll: jfloat,
    _ hScroll: jfloat,
    _ eventTimeMillis: jlong
) {
    _ = clazz
    let platform = AndroidPlatformRegistry.shared.ensurePlatform()
    let ids = extractIntArray(env, pointerIds)
    let xCoords = extractFloatArray(env, xs)
    let yCoords = extractFloatArray(env, ys)
    let pressVals = extractFloatArray(env, pressures)
    let tools = extractIntArray(env, toolTypes)

    _ = AndroidJniEventRouter.onTouchEvent(
        platform: platform,
        action: action,
        pointerIds: ids,
        xs: xCoords,
        ys: yCoords,
        pressures: pressVals,
        toolTypes: tools,
        metaState: metaState,
        buttonState: buttonState,
        vScroll: vScroll,
        hScroll: hScroll,
        eventTimeMillis: eventTimeMillis
    )
}

@_cdecl("Java_dev_glasshq_gpua_GPUINative_nativeOnKeyEvent")
public func gpuaJniNativeOnKeyEvent(
    _ env: UnsafeMutablePointer<JNIEnv?>,
    _ clazz: jclass?,
    _ action: jint,
    _ keyCode: jint,
    _ metaState: jint,
    _ repeatCount: jint,
    _ unicodeChar: jint,
    _ scanCode: jint
) -> jboolean {
    _ = env
    _ = clazz
    let platform = AndroidPlatformRegistry.shared.ensurePlatform()
    let handled = AndroidJniEventRouter.onKeyEvent(
        platform: platform,
        action: action,
        keyCode: keyCode,
        metaState: metaState,
        repeatCount: repeatCount,
        unicodeChar: unicodeChar,
        scanCode: scanCode
    )
    return handled ? 1 : 0
}

@_cdecl("Java_dev_glasshq_gpua_GPUINative_nativeOnInsetsChanged")
public func gpuaJniNativeOnInsetsChanged(
    _ env: UnsafeMutablePointer<JNIEnv?>,
    _ clazz: jclass?,
    _ topPx: jint,
    _ leftPx: jint,
    _ bottomPx: jint,
    _ rightPx: jint
) {
    _ = env
    _ = clazz
    let platform = AndroidPlatformRegistry.shared.ensurePlatform()
    platform.handleInsetsChanged(
        topPx: topPx,
        leftPx: leftPx,
        bottomPx: bottomPx,
        rightPx: rightPx
    )
}

@_cdecl("Java_dev_glasshq_gpua_GPUINative_nativeOnAppearanceChanged")
public func gpuaJniNativeOnAppearanceChanged(
    _ env: UnsafeMutablePointer<JNIEnv?>,
    _ clazz: jclass?,
    _ isDark: jboolean
) {
    _ = env
    _ = clazz
    let dark = isDark != 0
    AndroidPlatformRegistry.shared.cacheAppearance(dark ? .dark : .light)
    if AndroidPlatformRegistry.shared.currentPlatform == nil {
        _ = AndroidPlatformRegistry.shared.ensurePlatform()
    }
}

@_cdecl("Java_dev_glasshq_gpua_GPUINative_nativeOnLifecycleState")
public func gpuaJniNativeOnLifecycleState(
    _ env: UnsafeMutablePointer<JNIEnv?>,
    _ clazz: jclass?,
    _ state: jint
) {
    _ = env
    _ = clazz
    let phase = AndroidLifecyclePhase(rawState: state)
    AndroidPlatformRegistry.shared.cacheLifecyclePhase(phase)
    if AndroidPlatformRegistry.shared.currentPlatform == nil && phase != .destroyed {
        let platform = AndroidPlatformRegistry.shared.ensurePlatform()
        platform.handleLifecycleState(phase)
    }
}

@_cdecl("Java_dev_glasshq_gpua_GPUINative_nativeOnFrame")
public func gpuaJniNativeOnFrame(
    _ env: UnsafeMutablePointer<JNIEnv?>,
    _ clazz: jclass?,
    _ frameTimeNanos: jlong
) {
    _ = env
    _ = clazz
    AndroidPlatformRegistry.shared.currentPlatform?.handleFrame(frameTimeNanos: frameTimeNanos)
}

@_cdecl("Java_dev_glasshq_gpua_GPUINative_nativeCommitText")
public func gpuaJniNativeCommitText(
    _ env: UnsafeMutablePointer<JNIEnv?>,
    _ clazz: jclass?,
    _ text: jstring?
) {
    _ = clazz
    guard let committed = extractJString(env, text), !committed.isEmpty else {
        return
    }
    let platform = AndroidPlatformRegistry.shared.ensurePlatform()
    platform.handleCommitText(committed)
}

@_cdecl("Java_dev_glasshq_gpua_GPUINative_nativeSetComposingText")
public func gpuaJniNativeSetComposingText(
    _ env: UnsafeMutablePointer<JNIEnv?>,
    _ clazz: jclass?,
    _ text: jstring?
) {
    _ = clazz
    let composing = extractJString(env, text) ?? ""
    let platform = AndroidPlatformRegistry.shared.ensurePlatform()
    platform.handleSetComposingText(composing)
}

@_cdecl("Java_dev_glasshq_gpua_GPUINative_nativeFinishComposingText")
public func gpuaJniNativeFinishComposingText(
    _ env: UnsafeMutablePointer<JNIEnv?>,
    _ clazz: jclass?
) {
    _ = env
    _ = clazz
    let platform = AndroidPlatformRegistry.shared.ensurePlatform()
    platform.handleFinishComposingText()
}

@_cdecl("Java_dev_glasshq_gpua_GPUINative_nativeDeleteSurroundingText")
public func gpuaJniNativeDeleteSurroundingText(
    _ env: UnsafeMutablePointer<JNIEnv?>,
    _ clazz: jclass?,
    _ beforeLength: jint,
    _ afterLength: jint
) {
    _ = env
    _ = clazz
    let platform = AndroidPlatformRegistry.shared.ensurePlatform()
    platform.handleDeleteSurroundingText(
        beforeLength: Int(beforeLength),
        afterLength: Int(afterLength)
    )
}

@_cdecl("Java_dev_glasshq_gpua_GPUINative_nativeOnThermalStatusChanged")
public func gpuaJniNativeOnThermalStatusChanged(
    _ env: UnsafeMutablePointer<JNIEnv?>,
    _ clazz: jclass?,
    _ status: jint
) {
    _ = env
    _ = clazz
    AndroidPlatformRegistry.shared.currentPlatform?.handleThermalStatus(status)
}

@_cdecl("Java_dev_glasshq_gpua_GPUINative_nativeOnOpenUrl")
public func gpuaJniNativeOnOpenUrl(
    _ env: UnsafeMutablePointer<JNIEnv?>,
    _ clazz: jclass?,
    _ url: jstring?
) {
    _ = clazz
    guard let urlString = extractJString(env, url), !urlString.isEmpty else {
        return
    }
    AndroidPlatformRegistry.shared.enqueueIncomingUrls([urlString])
}

#endif
