// Swift-only: Zero-dependency C Wasm-import bridge for browser DOM and Web APIs per ADR-0013
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(__wasi__)

#define CWEBSYS_IMPORT(name) \
    __attribute__((import_module("gpui_web"), import_name(name)))

// Console logging (level: 0=error, 1=warn, 2=info, 3=debug, 4=trace)
CWEBSYS_IMPORT("cwebsys_console_log")
void cwebsys_console_log(int32_t level, const uint8_t *ptr, size_t len);

// High-resolution monotonic & wall-clock timestamps (milliseconds)
CWEBSYS_IMPORT("cwebsys_performance_now")
double cwebsys_performance_now(void);

CWEBSYS_IMPORT("cwebsys_date_now")
double cwebsys_date_now(void);

// Main-thread scheduling
CWEBSYS_IMPORT("cwebsys_schedule_timeout")
int32_t cwebsys_schedule_timeout(uint32_t callback_id, int32_t delay_ms);

CWEBSYS_IMPORT("cwebsys_queue_microtask")
void cwebsys_queue_microtask(uint32_t callback_id);

CWEBSYS_IMPORT("cwebsys_request_animation_frame")
int32_t cwebsys_request_animation_frame(uint32_t window_id);

// Browser environment & screen metrics
CWEBSYS_IMPORT("cwebsys_device_pixel_ratio")
double cwebsys_device_pixel_ratio(void);

CWEBSYS_IMPORT("cwebsys_screen_width")
int32_t cwebsys_screen_width(void);

CWEBSYS_IMPORT("cwebsys_screen_height")
int32_t cwebsys_screen_height(void);

CWEBSYS_IMPORT("cwebsys_window_inner_width")
double cwebsys_window_inner_width(void);

CWEBSYS_IMPORT("cwebsys_window_inner_height")
double cwebsys_window_inner_height(void);

CWEBSYS_IMPORT("cwebsys_prefers_dark_mode")
bool cwebsys_prefers_dark_mode(void);

CWEBSYS_IMPORT("cwebsys_is_mac_platform")
bool cwebsys_is_mac_platform(void);

CWEBSYS_IMPORT("cwebsys_has_device_pixel_support")
bool cwebsys_has_device_pixel_support(void);

CWEBSYS_IMPORT("cwebsys_document_is_visible")
bool cwebsys_document_is_visible(void);

CWEBSYS_IMPORT("cwebsys_hardware_concurrency")
int32_t cwebsys_hardware_concurrency(void);

CWEBSYS_IMPORT("cwebsys_watch_dpr_media_query")
void cwebsys_watch_dpr_media_query(
    uint32_t window_id,
    const uint8_t *query_ptr,
    size_t query_len
);

CWEBSYS_IMPORT("cwebsys_unwatch_dpr_media_query")
void cwebsys_unwatch_dpr_media_query(uint32_t window_id);

// Canvas, hidden IME input element, and window controls
CWEBSYS_IMPORT("cwebsys_create_or_bind_canvas")
int32_t cwebsys_create_or_bind_canvas(
    uint32_t window_id,
    const uint8_t *selector_ptr,
    size_t selector_len,
    bool has_device_pixel_support
);

CWEBSYS_IMPORT("cwebsys_destroy_canvas")
void cwebsys_destroy_canvas(uint32_t window_id);

CWEBSYS_IMPORT("cwebsys_canvas_client_width")
double cwebsys_canvas_client_width(uint32_t window_id);

CWEBSYS_IMPORT("cwebsys_canvas_client_height")
double cwebsys_canvas_client_height(uint32_t window_id);

CWEBSYS_IMPORT("cwebsys_canvas_width")
uint32_t cwebsys_canvas_width(uint32_t window_id);

CWEBSYS_IMPORT("cwebsys_canvas_height")
uint32_t cwebsys_canvas_height(uint32_t window_id);

CWEBSYS_IMPORT("cwebsys_set_canvas_size")
void cwebsys_set_canvas_size(uint32_t window_id, uint32_t width, uint32_t height);

CWEBSYS_IMPORT("cwebsys_set_canvas_style_size")
void cwebsys_set_canvas_style_size(uint32_t window_id, float width, float height);

CWEBSYS_IMPORT("cwebsys_focus_input")
void cwebsys_focus_input(uint32_t window_id);

CWEBSYS_IMPORT("cwebsys_clear_input_value")
void cwebsys_clear_input_value(uint32_t window_id);

CWEBSYS_IMPORT("cwebsys_set_ime_position")
void cwebsys_set_ime_position(
    uint32_t window_id,
    float x,
    float y,
    float width,
    float height
);

CWEBSYS_IMPORT("cwebsys_set_fullscreen")
void cwebsys_set_fullscreen(uint32_t window_id, bool fullscreen);

CWEBSYS_IMPORT("cwebsys_set_cursor_style")
void cwebsys_set_cursor_style(const uint8_t *style_ptr, size_t style_len);

CWEBSYS_IMPORT("cwebsys_set_document_title")
void cwebsys_set_document_title(const uint8_t *title_ptr, size_t title_len);

CWEBSYS_IMPORT("cwebsys_open_url")
bool cwebsys_open_url(const uint8_t *url_ptr, size_t url_len);

// Clipboard & keyboard layout
CWEBSYS_IMPORT("cwebsys_clipboard_write")
void cwebsys_clipboard_write(const uint8_t *text_ptr, size_t text_len);

CWEBSYS_IMPORT("cwebsys_clipboard_read")
size_t cwebsys_clipboard_read(uint8_t *buf_ptr, size_t buf_cap);

CWEBSYS_IMPORT("cwebsys_keyboard_layout_id")
size_t cwebsys_keyboard_layout_id(uint8_t *buf_ptr, size_t buf_cap);

// Browser Fetch API (redirect_mode: 0=manual, 1=follow)
CWEBSYS_IMPORT("cwebsys_fetch_start")
void cwebsys_fetch_start(
    uint32_t request_id,
    const uint8_t *method_ptr,
    size_t method_len,
    const uint8_t *url_ptr,
    size_t url_len,
    const uint8_t *headers_ptr,
    size_t headers_len,
    const uint8_t *body_ptr,
    size_t body_len,
    int32_t redirect_mode
);

// Ensures Wasm host-bridge export wrappers in CWebSys.c are retained by wasm-ld.
void cwebsys_ensure_wasm_exports(void);

#else

typedef int cwebsys_unused_t;

#endif // defined(__wasi__)

#ifdef __cplusplus
}
#endif
