// Ported from: crates/gpui_web/src/gpui_web.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
import GPUI

#if os(WASI)
// MARK: - Wasm Host Bridge Exports (`gpui_web_*`)

private func decodeUtf8Slice(_ ptr: UnsafePointer<UInt8>?, _ len: Int) -> String {
    guard let ptr, len > 0 else { return "" }
    let buffer = UnsafeBufferPointer(start: ptr, count: len)
    return String(decoding: buffer, as: UTF8.self)
}

private func copyBytes(_ ptr: UnsafePointer<UInt8>?, _ len: Int) -> Data {
    guard let ptr, len > 0 else { return Data() }
    return Data(bytes: ptr, count: len)
}

@_cdecl("gpui_web_impl_alloc")
public func gpuiWebAlloc(_ size: Int) -> UnsafeMutablePointer<UInt8>? {
    guard size > 0 else { return nil }
    let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
    ptr.initialize(repeating: 0, count: size)
    return ptr
}

@_cdecl("gpui_web_impl_free")
public func gpuiWebFree(_ ptr: UnsafeMutablePointer<UInt8>?, _ size: Int) {
    guard let ptr, size > 0 else { return }
    ptr.deinitialize(count: size)
    ptr.deallocate()
}

@_cdecl("gpui_web_impl_on_timer")
public func gpuiWebOnTimer(_ callbackId: UInt32) {
    WebCallbackRegistry.shared.invoke(callbackId)
}

@_cdecl("gpui_web_impl_on_microtask")
public func gpuiWebOnMicrotask(_ callbackId: UInt32) {
    WebCallbackRegistry.shared.invoke(callbackId)
}

@_cdecl("gpui_web_impl_on_animation_frame")
public func gpuiWebOnAnimationFrame(_ windowId: UInt32, _ timestampMs: Double) {
    _ = timestampMs
    WebWindowRegistry.shared.lookup(windowId)?.handleAnimationFrame()
}

@_cdecl("gpui_web_impl_on_resize")
public func gpuiWebOnResize(
    _ windowId: UInt32,
    _ physicalWidth: UInt32,
    _ physicalHeight: UInt32,
    _ logicalWidth: Float,
    _ logicalHeight: Float,
    _ dpr: Double
) {
    WebWindowRegistry.shared.lookup(windowId)?.handleResizeObserver(
        physicalWidth: physicalWidth,
        physicalHeight: physicalHeight,
        logicalWidth: logicalWidth,
        logicalHeight: logicalHeight,
        dpr: dpr
    )
}

@_cdecl("gpui_web_impl_on_dpr_change")
public func gpuiWebOnDprChange(_ windowId: UInt32, _ dpr: Double) {
    _ = dpr
    WebWindowRegistry.shared.lookup(windowId)?.handleDprMediaQueryChange()
}

@_cdecl("gpui_web_impl_on_appearance_change")
public func gpuiWebOnAppearanceChange(_ windowId: UInt32, _ isDark: Int32) {
    _ = isDark
    WebWindowRegistry.shared.lookup(windowId)?.handleAppearanceChange()
}

@_cdecl("gpui_web_impl_on_visibility_change")
public func gpuiWebOnVisibilityChange(_ windowId: UInt32, _ isVisible: Int32) {
    WebWindowRegistry.shared.lookup(windowId)?.handleVisibilityChange(isVisible: isVisible != 0)
}

@_cdecl("gpui_web_impl_on_pointer_event")
public func gpuiWebOnPointerEvent(
    _ windowId: UInt32,
    _ kind: Int32,
    _ button: Int32,
    _ offsetX: Float,
    _ offsetY: Float,
    _ modifiers: UInt32,
    _ timestampMs: Double
) {
    guard let inner = WebWindowRegistry.shared.lookup(windowId) else { return }
    let pos = Point(x: px(offsetX), y: px(offsetY))
    switch kind {
    case 0:
        inner.handlePointerDown(
            button: Int16(clamping: button),
            position: pos,
            modifiersFlags: modifiers,
            timestampMs: timestampMs
        )
    case 1:
        inner.handlePointerUp(
            button: Int16(clamping: button),
            position: pos,
            modifiersFlags: modifiers
        )
    case 2:
        inner.handlePointerMove(position: pos, modifiersFlags: modifiers)
    case 3:
        inner.handlePointerLeave(position: pos, modifiersFlags: modifiers)
    case 4:
        inner.handlePointerEnter()
    default:
        break
    }
}

@_cdecl("gpui_web_impl_on_wheel_event")
public func gpuiWebOnWheelEvent(
    _ windowId: UInt32,
    _ offsetX: Float,
    _ offsetY: Float,
    _ deltaX: Double,
    _ deltaY: Double,
    _ deltaMode: UInt32,
    _ modifiers: UInt32
) {
    guard let inner = WebWindowRegistry.shared.lookup(windowId) else { return }
    inner.handleWheel(
        position: Point(x: px(offsetX), y: px(offsetY)),
        deltaX: deltaX,
        deltaY: deltaY,
        deltaMode: deltaMode,
        modifiersFlags: modifiers
    )
}

@_cdecl("gpui_web_impl_on_key_event")
public func gpuiWebOnKeyEvent(
    _ windowId: UInt32,
    _ kind: Int32,
    _ keyPtr: UnsafePointer<UInt8>?,
    _ keyLen: Int,
    _ codePtr: UnsafePointer<UInt8>?,
    _ codeLen: Int,
    _ modifiers: UInt32,
    _ repeatFlag: Int32,
    _ isComposing: Int32
) -> Int32 {
    guard let inner = WebWindowRegistry.shared.lookup(windowId) else { return 0 }
    let rawKey = decodeUtf8Slice(keyPtr, keyLen)
    let code = decodeUtf8Slice(codePtr, codeLen)
    let preventDefault: Bool
    if kind == 0 {
        preventDefault = inner.handleKeyDown(
            rawKey: rawKey,
            code: code,
            modifiersFlags: modifiers,
            isRepeat: repeatFlag != 0,
            eventIsComposing: isComposing != 0
        )
    } else {
        preventDefault = inner.handleKeyUp(
            rawKey: rawKey,
            code: code,
            modifiersFlags: modifiers
        )
    }
    return preventDefault ? 1 : 0
}

@_cdecl("gpui_web_impl_on_composition_event")
public func gpuiWebOnCompositionEvent(
    _ windowId: UInt32,
    _ kind: Int32,
    _ dataPtr: UnsafePointer<UInt8>?,
    _ dataLen: Int
) {
    guard let inner = WebWindowRegistry.shared.lookup(windowId) else { return }
    let data = decodeUtf8Slice(dataPtr, dataLen)
    switch kind {
    case 0:
        inner.handleCompositionStart()
    case 1:
        inner.handleCompositionUpdate(data: data)
    case 2:
        inner.handleCompositionEnd(data: data)
    default:
        break
    }
}

@_cdecl("gpui_web_impl_on_focus_event")
public func gpuiWebOnFocusEvent(_ windowId: UInt32, _ focused: Int32) {
    guard let inner = WebWindowRegistry.shared.lookup(windowId) else { return }
    if focused != 0 {
        inner.handleFocus()
    } else {
        inner.handleBlur()
    }
}

@_cdecl("gpui_web_impl_on_file_drop_event")
public func gpuiWebOnFileDropEvent(
    _ windowId: UInt32,
    _ kind: Int32,
    _ offsetX: Float,
    _ offsetY: Float,
    _ pathsPtr: UnsafePointer<UInt8>?,
    _ pathsLen: Int
) {
    guard let inner = WebWindowRegistry.shared.lookup(windowId) else { return }
    let pos = Point(x: px(offsetX), y: px(offsetY))
    switch kind {
    case 0:
        inner.handleDragOver(position: pos)
    case 1:
        let rawPaths = decodeUtf8Slice(pathsPtr, pathsLen)
        let fileNames = rawPaths.isEmpty ? [] : rawPaths.components(separatedBy: "\n")
        inner.handleDrop(position: pos, fileNames: fileNames)
    case 2:
        inner.handleDragLeave()
    default:
        break
    }
}

@_cdecl("gpui_web_impl_on_fetch_complete")
public func gpuiWebOnFetchComplete(
    _ requestId: UInt32,
    _ status: Int32,
    _ headersPtr: UnsafePointer<UInt8>?,
    _ headersLen: Int,
    _ bodyPtr: UnsafePointer<UInt8>?,
    _ bodyLen: Int,
    _ errorPtr: UnsafePointer<UInt8>?,
    _ errorLen: Int
) {
    let encodedHeaders = copyBytes(headersPtr, headersLen)
    let body = copyBytes(bodyPtr, bodyLen)
    let errorMsg = errorLen > 0 ? decodeUtf8Slice(errorPtr, errorLen) : nil
    FetchContinuationRegistry.shared.complete(
        requestId: requestId,
        status: status,
        encodedHeaders: encodedHeaders,
        body: body,
        errorMessage: errorMsg
    )
}
#endif
