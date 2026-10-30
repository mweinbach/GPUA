// Swift-only: C bridge umbrella header for WebGPU C API
#pragma once

#include "webgpu/webgpu.h"
#include "webgpu/wgpu.h"

#ifndef WGPUSType_SurfaceSourceCanvasHTMLSelector
#define WGPUSType_SurfaceSourceCanvasHTMLSelector ((WGPUSType)0x00040001)

typedef struct WGPUSurfaceSourceCanvasHTMLSelector {
    WGPUChainedStruct chain;
    WGPUStringView selector;
} WGPUSurfaceSourceCanvasHTMLSelector WGPU_STRUCTURE_ATTRIBUTE;
#endif

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Create a WGPUSurface backed by an Android `ANativeWindow*`
 * (`WGPUSType_SurfaceSourceAndroidNativeWindow`).
 * Returns `NULL` on non-Android platforms or if `instance` / `a_native_window` is `NULL`.
 */
WGPUSurface cwebgpu_create_surface_android(WGPUInstance instance, void * WGPU_NULLABLE a_native_window);

/**
 * Create a WGPUSurface backed by a browser `<canvas>` CSS selector
 * (`WGPUSType_SurfaceSourceCanvasHTMLSelector`).
 * Returns `NULL` on non-WASI platforms or if `instance` / `selector` is `NULL`.
 */
WGPUSurface cwebgpu_create_surface_canvas(WGPUInstance instance, char const * WGPU_NULLABLE selector, size_t selector_len);

#ifdef __cplusplus
}
#endif
