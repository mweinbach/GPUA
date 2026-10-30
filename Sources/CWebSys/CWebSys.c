// Swift-only: Zero-dependency C Wasm-import bridge translation unit per ADR-0013
#include "CWebSys.h"

int cwebsys_anchor = 0;

#if defined(__wasi__)

#define CWEBSYS_EXPORT(name) __attribute__((export_name(name), used))

extern uint8_t *gpui_web_impl_alloc(size_t size);
extern void gpui_web_impl_free(uint8_t *ptr, size_t size);
extern void gpui_web_impl_on_timer(uint32_t callback_id);
extern void gpui_web_impl_on_microtask(uint32_t callback_id);
extern void gpui_web_impl_on_animation_frame(uint32_t window_id, double timestamp_ms);
extern void gpui_web_impl_on_resize(
    uint32_t window_id,
    uint32_t physical_width,
    uint32_t physical_height,
    float logical_width,
    float logical_height,
    double dpr
);
extern void gpui_web_impl_on_dpr_change(uint32_t window_id, double dpr);
extern void gpui_web_impl_on_appearance_change(uint32_t window_id, int32_t is_dark);
extern void gpui_web_impl_on_visibility_change(uint32_t window_id, int32_t is_visible);
extern void gpui_web_impl_on_pointer_event(
    uint32_t window_id,
    int32_t kind,
    int32_t button,
    float offset_x,
    float offset_y,
    uint32_t modifiers,
    double timestamp_ms
);
extern void gpui_web_impl_on_wheel_event(
    uint32_t window_id,
    float offset_x,
    float offset_y,
    double delta_x,
    double delta_y,
    uint32_t delta_mode,
    uint32_t modifiers
);
extern int32_t gpui_web_impl_on_key_event(
    uint32_t window_id,
    int32_t kind,
    const uint8_t *key_ptr,
    size_t key_len,
    const uint8_t *code_ptr,
    size_t code_len,
    uint32_t modifiers,
    int32_t repeat_flag,
    int32_t is_composing
);
extern void gpui_web_impl_on_composition_event(
    uint32_t window_id,
    int32_t kind,
    const uint8_t *data_ptr,
    size_t data_len
);
extern void gpui_web_impl_on_focus_event(uint32_t window_id, int32_t focused);
extern void gpui_web_impl_on_file_drop_event(
    uint32_t window_id,
    int32_t kind,
    float offset_x,
    float offset_y,
    const uint8_t *paths_ptr,
    size_t paths_len
);
extern void gpui_web_impl_on_fetch_complete(
    uint32_t request_id,
    int32_t status,
    const uint8_t *headers_ptr,
    size_t headers_len,
    const uint8_t *body_ptr,
    size_t body_len,
    const uint8_t *error_ptr,
    size_t error_len
);

CWEBSYS_EXPORT("gpui_web_alloc")
uint8_t *gpui_web_alloc(size_t size) {
    return gpui_web_impl_alloc(size);
}

CWEBSYS_EXPORT("gpui_web_free")
void gpui_web_free(uint8_t *ptr, size_t size) {
    gpui_web_impl_free(ptr, size);
}

CWEBSYS_EXPORT("gpui_web_on_timer")
void gpui_web_on_timer(uint32_t callback_id) {
    gpui_web_impl_on_timer(callback_id);
}

CWEBSYS_EXPORT("gpui_web_on_microtask")
void gpui_web_on_microtask(uint32_t callback_id) {
    gpui_web_impl_on_microtask(callback_id);
}

CWEBSYS_EXPORT("gpui_web_on_animation_frame")
void gpui_web_on_animation_frame(uint32_t window_id, double timestamp_ms) {
    gpui_web_impl_on_animation_frame(window_id, timestamp_ms);
}

CWEBSYS_EXPORT("gpui_web_on_resize")
void gpui_web_on_resize(
    uint32_t window_id,
    uint32_t physical_width,
    uint32_t physical_height,
    float logical_width,
    float logical_height,
    double dpr
) {
    gpui_web_impl_on_resize(
        window_id,
        physical_width,
        physical_height,
        logical_width,
        logical_height,
        dpr
    );
}

CWEBSYS_EXPORT("gpui_web_on_dpr_change")
void gpui_web_on_dpr_change(uint32_t window_id, double dpr) {
    gpui_web_impl_on_dpr_change(window_id, dpr);
}

CWEBSYS_EXPORT("gpui_web_on_appearance_change")
void gpui_web_on_appearance_change(uint32_t window_id, int32_t is_dark) {
    gpui_web_impl_on_appearance_change(window_id, is_dark);
}

CWEBSYS_EXPORT("gpui_web_on_visibility_change")
void gpui_web_on_visibility_change(uint32_t window_id, int32_t is_visible) {
    gpui_web_impl_on_visibility_change(window_id, is_visible);
}

CWEBSYS_EXPORT("gpui_web_on_pointer_event")
void gpui_web_on_pointer_event(
    uint32_t window_id,
    int32_t kind,
    int32_t button,
    float offset_x,
    float offset_y,
    uint32_t modifiers,
    double timestamp_ms
) {
    gpui_web_impl_on_pointer_event(
        window_id,
        kind,
        button,
        offset_x,
        offset_y,
        modifiers,
        timestamp_ms
    );
}

CWEBSYS_EXPORT("gpui_web_on_wheel_event")
void gpui_web_on_wheel_event(
    uint32_t window_id,
    float offset_x,
    float offset_y,
    double delta_x,
    double delta_y,
    uint32_t delta_mode,
    uint32_t modifiers
) {
    gpui_web_impl_on_wheel_event(
        window_id,
        offset_x,
        offset_y,
        delta_x,
        delta_y,
        delta_mode,
        modifiers
    );
}

CWEBSYS_EXPORT("gpui_web_on_key_event")
int32_t gpui_web_on_key_event(
    uint32_t window_id,
    int32_t kind,
    const uint8_t *key_ptr,
    size_t key_len,
    const uint8_t *code_ptr,
    size_t code_len,
    uint32_t modifiers,
    int32_t repeat_flag,
    int32_t is_composing
) {
    return gpui_web_impl_on_key_event(
        window_id,
        kind,
        key_ptr,
        key_len,
        code_ptr,
        code_len,
        modifiers,
        repeat_flag,
        is_composing
    );
}

CWEBSYS_EXPORT("gpui_web_on_composition_event")
void gpui_web_on_composition_event(
    uint32_t window_id,
    int32_t kind,
    const uint8_t *data_ptr,
    size_t data_len
) {
    gpui_web_impl_on_composition_event(window_id, kind, data_ptr, data_len);
}

CWEBSYS_EXPORT("gpui_web_on_focus_event")
void gpui_web_on_focus_event(uint32_t window_id, int32_t focused) {
    gpui_web_impl_on_focus_event(window_id, focused);
}

CWEBSYS_EXPORT("gpui_web_on_file_drop_event")
void gpui_web_on_file_drop_event(
    uint32_t window_id,
    int32_t kind,
    float offset_x,
    float offset_y,
    const uint8_t *paths_ptr,
    size_t paths_len
) {
    gpui_web_impl_on_file_drop_event(
        window_id,
        kind,
        offset_x,
        offset_y,
        paths_ptr,
        paths_len
    );
}

CWEBSYS_EXPORT("gpui_web_on_fetch_complete")
void gpui_web_on_fetch_complete(
    uint32_t request_id,
    int32_t status,
    const uint8_t *headers_ptr,
    size_t headers_len,
    const uint8_t *body_ptr,
    size_t body_len,
    const uint8_t *error_ptr,
    size_t error_len
) {
    gpui_web_impl_on_fetch_complete(
        request_id,
        status,
        headers_ptr,
        headers_len,
        body_ptr,
        body_len,
        error_ptr,
        error_len
    );
}

void cwebsys_ensure_wasm_exports(void) {
    cwebsys_anchor++;
}

#endif // defined(__wasi__)
