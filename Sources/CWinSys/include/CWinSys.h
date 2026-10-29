// Swift-only: C bridge umbrella header for Windows system libraries and COM interop
#pragma once

#if defined(_WIN32)
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Direct3D 11 & DXGI
int cwin_d3d11_create_device(int enable_debug, void** out_device, void** out_context, uint32_t* out_feature_level);
int cwin_d3d11_create_device_warp(int enable_debug, void** out_device, void** out_context, uint32_t* out_feature_level);
int cwin_d3d11_create_swapchain_for_hwnd(void* device, void* hwnd, uint32_t width, uint32_t height, void** out_swapchain);
int cwin_d3d11_resize_swapchain(void* swapchain, uint32_t width, uint32_t height);
int cwin_d3d11_present_swapchain(void* swapchain, uint32_t sync_interval, uint32_t flags);
int cwin_d3d11_get_swapchain_backbuffer(void* swapchain, void** out_texture);
int cwin_d3d11_create_render_target_view(void* device, void* texture, void** out_rtv);
int cwin_d3d11_compile_hlsl(const char* source, size_t source_len, const char* entry_point, const char* target, void** out_blob, char** out_error);
void cwin_d3d11_free_error_string(char* error_string);
const void* cwin_d3d_blob_get_pointer(void* blob);
size_t cwin_d3d_blob_get_size(void* blob);
int cwin_d3d11_create_vertex_shader(void* device, const void* bytecode, size_t len, void** out_shader);
int cwin_d3d11_create_pixel_shader(void* device, const void* bytecode, size_t len, void** out_shader);
int cwin_d3d11_create_structured_buffer(void* device, uint32_t stride, uint32_t element_count, int dynamic, void** out_buffer, void** out_srv);
int cwin_d3d11_create_buffer_view_range(void* device, void* buffer, uint32_t first_element, uint32_t num_elements, void** out_srv);
int cwin_d3d11_create_constant_buffer(void* device, uint32_t byte_width, void** out_buffer);
int cwin_d3d11_map_discard(void* context, void* buffer, const void* data, size_t byte_count);
int cwin_d3d11_create_texture_2d(void* device, uint32_t width, uint32_t height, uint32_t format, uint32_t bind_flags, int dynamic, void** out_texture, void** out_srv);
int cwin_d3d11_create_msaa_render_target(void* device, uint32_t width, uint32_t height, uint32_t sample_count, void** out_texture, void** out_rtv);
int cwin_d3d11_resolve_subresource(void* context, void* dst_res, uint32_t dst_subres, void* src_res, uint32_t src_subres, uint32_t format);
int cwin_d3d11_update_subresource(void* context, void* texture, uint32_t dst_x, uint32_t dst_y, uint32_t width, uint32_t height, const void* data, uint32_t row_pitch);
int cwin_d3d11_readback_texture_pixels(void* device, void* context, void* texture, uint32_t width, uint32_t height, uint32_t* out_row_pitch, int swizzle_bgra, uint8_t** out_pixels);
void cwin_d3d11_free_pixel_buffer(uint8_t* pixels);
void cwin_release_com_object(void* obj);
void cwin_addref_com_object(void* obj);

// D3D11 Pipeline State and Draw Wrappers
void cwin_d3d11_clear_render_target_view(void* context, void* rtv, const float color[4]);
void cwin_d3d11_om_set_render_targets(void* context, uint32_t num_views, void* const* rtvs, void* dsv);
int cwin_d3d11_create_blend_state(void* device, int blend_mode, void** out_state);
void cwin_d3d11_om_set_blend_state(void* context, void* blend_state, const float blend_factor[4], uint32_t sample_mask);
int cwin_d3d11_create_sampler_state(void* device, int filter_linear, int address_clamp, void** out_sampler);
void cwin_d3d11_ps_set_samplers(void* context, uint32_t start_slot, uint32_t num_samplers, void* const* samplers);
int cwin_d3d11_create_rasterizer_state(void* device, int scissor_enable, void** out_state);
void cwin_d3d11_rs_set_state(void* context, void* rasterizer_state);

struct CWinD3D11Viewport {
    float top_left_x;
    float top_left_y;
    float width;
    float height;
    float min_depth;
    float max_depth;
};

struct CWinD3D11Rect {
    int32_t left;
    int32_t top;
    int32_t right;
    int32_t bottom;
};

void cwin_d3d11_rs_set_viewports(void* context, uint32_t num_viewports, const void* viewports);
void cwin_d3d11_rs_set_scissor_rects(void* context, uint32_t num_rects, const void* rects);
void cwin_d3d11_ia_set_primitive_topology(void* context, uint32_t topology);
void cwin_d3d11_vs_set_shader(void* context, void* shader);
void cwin_d3d11_ps_set_shader(void* context, void* shader);
void cwin_d3d11_vs_set_constant_buffers(void* context, uint32_t start_slot, uint32_t num_buffers, void* const* buffers);
void cwin_d3d11_ps_set_constant_buffers(void* context, uint32_t start_slot, uint32_t num_buffers, void* const* buffers);
void cwin_d3d11_vs_set_shader_resources(void* context, uint32_t start_slot, uint32_t num_views, void* const* views);
void cwin_d3d11_ps_set_shader_resources(void* context, uint32_t start_slot, uint32_t num_views, void* const* views);
void cwin_d3d11_draw(void* context, uint32_t vertex_count, uint32_t start_vertex_location);
void cwin_d3d11_draw_instanced(void* context, uint32_t vertex_count_per_instance, uint32_t instance_count, uint32_t start_vertex_location, uint32_t start_instance_location);
void cwin_d3d11_clear_state(void* context);
void cwin_d3d11_flush(void* context);

// DirectWrite
struct CWinFontMetrics {
    float ascent;
    float descent;
    float line_gap;
    float cap_height;
    float x_height;
    float underline_position;
    float underline_thickness;
    uint16_t units_per_em;
    int is_color;
    float glyph_box_left;
    float glyph_box_bottom;
    float glyph_box_right;
    float glyph_box_top;
};

struct CWinGlyphDesignMetrics {
    float advance_width;
    float left_side_bearing;
    float right_side_bearing;
    float top_side_bearing;
    float advance_height;
    float bottom_side_bearing;
    float vertical_origin_y;
};

struct CWinShapedRunView {
    void* font_face;
    float font_size;
    uint32_t text_position;
    uint32_t string_length;
    uint32_t glyph_count;
    const uint16_t* glyph_indices;
    const float* glyph_advances;
    const float* glyph_offsets_x;
    const float* glyph_offsets_y;
    uint32_t cluster_count;
    const uint16_t* cluster_map;
    int is_color;
};

struct CWinGlyphRasterParams {
    void* font_face;
    uint16_t glyph_id;
    float font_size;
    float scale_factor;
    float subpixel_bias_x;
    float subpixel_bias_y;
    int subpixel_rendering;
    int is_emoji;
};

struct CWinGlyphRasterResult {
    int32_t left;
    int32_t top;
    int32_t width;
    int32_t height;
    uint8_t* pixels;
    uint32_t pixel_bytes;
};

int cwin_dwrite_create_factory(void** out_factory);
int cwin_dwrite_get_system_font_collection(void* factory, void** out_collection);
uint32_t cwin_dwrite_collection_get_family_count(void* collection);
int cwin_dwrite_collection_get_family_name(void* collection, uint32_t index, uint16_t* out_name, uint32_t max_chars);
int cwin_dwrite_collection_find_family(void* collection, const uint16_t* family_name, uint32_t* out_index, int* out_exists);
int cwin_dwrite_collection_get_font_face(void* collection, uint32_t family_index, uint32_t weight, uint32_t style, void** out_font_face);
int cwin_dwrite_register_in_memory_font_loader(void* factory, void** out_loader);
int cwin_dwrite_create_font_file_reference(void* loader, const void* data, size_t size, void** out_font_file);
int cwin_dwrite_create_font_set_builder(void* factory, void** out_builder);
int cwin_dwrite_font_set_builder_add_file(void* builder, void* font_file);
int cwin_dwrite_font_set_builder_create_collection(void* builder, void* factory, void** out_collection);
int cwin_dwrite_create_text_format(void* factory, const uint16_t* family_name, void* collection, uint32_t weight, uint32_t style, float font_size, void** out_format);
int cwin_dwrite_create_text_layout(void* factory, const uint16_t* text, uint32_t text_len, void* format, float max_width, float max_height, void** out_layout);
int cwin_dwrite_layout_get_metrics(void* layout, float* out_width, float* out_height, float* out_baseline);
int cwin_dwrite_create_typography(void* factory, void** out_typography);
int cwin_dwrite_typography_add_feature(void* typography, uint32_t tag, uint32_t parameter);
int cwin_dwrite_layout_set_typography(void* layout, void* typography, uint32_t start_position, uint32_t length);
int cwin_dwrite_layout_set_font_collection(void* layout, void* collection, uint32_t start_position, uint32_t length);
int cwin_dwrite_layout_set_font_family_name(void* layout, const uint16_t* family_name, uint32_t start_position, uint32_t length);
int cwin_dwrite_layout_set_font_size(void* layout, float font_size, uint32_t start_position, uint32_t length);
int cwin_dwrite_layout_set_font_weight(void* layout, uint32_t weight, uint32_t start_position, uint32_t length);
int cwin_dwrite_layout_set_font_style(void* layout, uint32_t style, uint32_t start_position, uint32_t length);
int cwin_dwrite_font_face_get_metrics(void* font_face, struct CWinFontMetrics* out_metrics);
int cwin_dwrite_font_face_get_glyph_indices(void* font_face, const uint32_t* codepoints, uint32_t count, uint16_t* out_glyph_indices);
int cwin_dwrite_font_face_get_design_glyph_metrics(void* font_face, const uint16_t* glyph_indices, uint32_t count, struct CWinGlyphDesignMetrics* out_metrics);
int cwin_dwrite_layout_extract_runs(void* layout, void** out_runs_handle, uint32_t* out_count);
int cwin_dwrite_get_extracted_run(void* runs_handle, uint32_t index, struct CWinShapedRunView* out_run);
void cwin_dwrite_free_extracted_runs(void* runs_handle);
int cwin_dwrite_rasterize_glyph(void* factory, const struct CWinGlyphRasterParams* params, struct CWinGlyphRasterResult* out_result);
void cwin_dwrite_free_raster_result(struct CWinGlyphRasterResult* result);

// Win32 Windowing, Dispatcher, Keyboard, Clipboard
int cwin_win32_register_window_class(const uint16_t* class_name, void* wndproc, void** out_atom);
void* cwin_win32_create_window(uint32_t ex_style, const uint16_t* class_name, const uint16_t* title, uint32_t style, int x, int y, int w, int h, void* parent, void* param);
void* cwin_win32_create_message_window(const uint16_t* class_name, void* wndproc, void* param);
int cwin_win32_destroy_window(void* hwnd);
intptr_t cwin_win32_def_window_proc(void* hwnd, uint32_t msg, uintptr_t wparam, intptr_t lparam);
int cwin_win32_get_window_long_ptr(void* hwnd, int index, intptr_t* out_val);
int cwin_win32_set_window_long_ptr(void* hwnd, int index, intptr_t new_val, intptr_t* out_old_val);
int cwin_win32_post_message(void* hwnd, uint32_t msg, uintptr_t wparam, intptr_t lparam);
void cwin_win32_post_quit_message(int exit_code);
int cwin_win32_get_message(void* out_msg, void* hwnd, uint32_t filter_min, uint32_t filter_max);
int cwin_win32_peek_message(void* out_msg, void* hwnd, uint32_t filter_min, uint32_t filter_max, uint32_t remove_flag);
int cwin_win32_translate_message(const void* msg);
intptr_t cwin_win32_dispatch_message(const void* msg);
void* cwin_win32_get_active_window(void);
void cwin_win32_redraw_window(void* hwnd);
int cwin_win32_get_dpi_for_window(void* hwnd, uint32_t* out_dpi);
int cwin_win32_clipboard_set_text(void* hwnd, const uint16_t* text, size_t len);
int cwin_win32_clipboard_get_text(void* hwnd, uint16_t** out_text, size_t* out_len);
void cwin_win32_clipboard_free_text(uint16_t* text);

// Win32 OLE / COM Lifecycle
int cwin_win32_ole_initialize(void);
void cwin_win32_ole_uninitialize(void);

// Win32 Display & Monitor Enumeration
struct CWinMonitorInfo {
    void* handle;
    int32_t monitor_left, monitor_top, monitor_right, monitor_bottom;
    int32_t work_left, work_top, work_right, work_bottom;
    uint32_t dpi_x, dpi_y;
    uint16_t device_name[32];
};
int cwin_win32_get_monitors(struct CWinMonitorInfo* out_monitors, uint32_t max_count, uint32_t* out_count);
void* cwin_win32_primary_monitor(void);
void* cwin_win32_monitor_from_point(int32_t x, int32_t y, uint32_t flags);
int cwin_win32_get_monitor_info(void* hmonitor, struct CWinMonitorInfo* out_info);

// Win32 DWM & VSync
int cwin_win32_dwm_flush(void);
int cwin_win32_dwm_get_refresh_interval(double* out_interval_seconds);
int cwin_win32_dwm_set_dark_mode(void* hwnd, int enabled);

// Win32 System Settings & Appearance
int cwin_win32_get_system_appearance(int* out_dark_mode);
int cwin_win32_get_wheel_scroll_lines(uint32_t* out_lines);
int cwin_win32_get_wheel_scroll_chars(uint32_t* out_chars);
int cwin_win32_should_auto_hide_scrollbars(int* out_auto_hide);

// Win32 Timer & Thread Priority
void cwin_win32_time_begin_period(uint32_t period_ms);
void cwin_win32_time_end_period(uint32_t period_ms);
void cwin_win32_set_thread_realtime(void);

// Win32 Cursor
void* cwin_win32_load_cursor(uint32_t style);
void cwin_win32_set_cursor(void* cursor);

// Win32 Credentials
int cwin_win32_cred_write(const uint16_t* target, const uint16_t* username, const uint8_t* blob, size_t blob_len);
int cwin_win32_cred_read(const uint16_t* target, uint16_t** out_username, uint8_t** out_blob, size_t* out_blob_len);
int cwin_win32_cred_delete(const uint16_t* target);
void cwin_win32_cred_free(void* ptr);

// Win32 Shell & Dialogs
int cwin_win32_shell_open(const uint16_t* path_or_url);
int cwin_win32_shell_reveal(const uint16_t* path);
int cwin_win32_file_open_dialog(void* hwnd, int allow_multi, int pick_folders, const uint16_t* ok_label, uint16_t*** out_paths, size_t* out_count);
int cwin_win32_file_save_dialog(void* hwnd, const uint16_t* initial_dir, const uint16_t* default_name, uint16_t** out_path);
void cwin_win32_free_path_list(uint16_t** paths, size_t count);

// Win32 Keyboard & Input
int cwin_win32_get_keyboard_layout_name(uint16_t* out_name, size_t max_len);
int cwin_win32_get_keyboard_layout_text(const uint16_t* layout_id, uint16_t* out_text, size_t max_len);
uint32_t cwin_win32_map_virtual_key(uint32_t uCode, uint32_t uMapType);
int cwin_win32_to_unicode(uint32_t vkey, uint32_t scan_code, const uint8_t* key_state, uint16_t* out_buffer, int buffer_size, uint32_t flags);
int16_t cwin_win32_get_key_state(int vkey);
int cwin_win32_get_keyboard_state(uint8_t* out_state_256);
uint32_t cwin_win32_get_double_click_time(void);
void cwin_win32_get_double_click_tolerance(int32_t* out_width, int32_t* out_height);
int32_t cwin_win32_get_frame_thickness_x(uint32_t dpi);
int32_t cwin_win32_get_frame_thickness_y(uint32_t dpi);
void cwin_win32_notify_frame_changed(void* hwnd);

// Win32 Window State & Manipulation
int cwin_win32_show_window(void* hwnd, int cmd_show);
int cwin_win32_is_window_visible(void* hwnd);
int cwin_win32_is_window_minimized(void* hwnd);
int cwin_win32_is_window_maximized(void* hwnd);
int cwin_win32_set_window_pos(void* hwnd, void* hwnd_insert_after, int x, int y, int cx, int cy, uint32_t flags);
int cwin_win32_get_window_rect(void* hwnd, int32_t* left, int32_t* top, int32_t* right, int32_t* bottom);
int cwin_win32_get_client_rect(void* hwnd, int32_t* left, int32_t* top, int32_t* right, int32_t* bottom);
int cwin_win32_set_window_text(void* hwnd, const uint16_t* title);
int cwin_win32_get_window_text(void* hwnd, uint16_t* out_text, int max_chars);
int cwin_win32_set_foreground_window(void* hwnd);
int cwin_win32_set_active_window(void* hwnd);
int cwin_win32_set_focus(void* hwnd);
int cwin_win32_get_cursor_pos(int32_t* x, int32_t* y);
int cwin_win32_screen_to_client(void* hwnd, int32_t* x, int32_t* y);
int cwin_win32_validate_rect(void* hwnd);
int cwin_win32_set_non_rude_hwnd(void* hwnd, int non_rude);
int cwin_win32_track_mouse_event(void* hwnd, uint32_t flags);
uintptr_t cwin_win32_set_timer(void* hwnd, uintptr_t id, uint32_t elapse);
int cwin_win32_kill_timer(void* hwnd, uintptr_t id);
int cwin_win32_set_window_composition_attribute(void* hwnd, uint32_t accent_state, uint32_t color);
int cwin_win32_task_dialog(void* hwnd_parent, int level, const uint16_t* instruction, const uint16_t* content, const uint16_t** button_labels, int button_count, int* out_button_index);

// Win32 Enhanced Clipboard
int cwin_win32_clipboard_open(void* hwnd);
int cwin_win32_clipboard_close(void);
int cwin_win32_clipboard_empty(void);
uint32_t cwin_win32_clipboard_register_format(const uint16_t* format_name);
int cwin_win32_clipboard_get_format_name(uint32_t format, uint16_t* out_name, size_t max_len);
int cwin_win32_clipboard_is_format_available(uint32_t format);
int cwin_win32_clipboard_count_formats(void);
uint32_t cwin_win32_clipboard_enum_formats(uint32_t format);
int cwin_win32_clipboard_set_binary_data(uint32_t format, const void* data, size_t len);
int cwin_win32_clipboard_get_binary_data(uint32_t format, void** out_data, size_t* out_len);
void cwin_win32_clipboard_free_binary_data(void* data);
int cwin_win32_clipboard_get_hdrop_files(void* hdrop, uint16_t*** out_files, size_t* out_count);
void cwin_win32_clipboard_free_hdrop_files(uint16_t** files, size_t count);
int cwin_win32_clipboard_get_files(uint16_t*** out_files, size_t* out_count);

// Win32 DirectManipulation
struct CWinDmEvent {
    int type; // 1 = scroll, 2 = pinch
    float x;
    float y;
    float delta_x;
    float delta_y;
    float scale_delta;
    int touch_phase; // 0 = started, 1 = moved, 2 = ended
};

void* cwin_dm_create_handler(void* hwnd, float scale_factor);
void cwin_dm_destroy_handler(void* handler);
void cwin_dm_set_scale_factor(void* handler, float scale_factor);
void cwin_dm_on_pointer_hit_test(void* handler, uintptr_t wparam);
void cwin_dm_update(void* handler);
int cwin_dm_drain_events(void* handler, struct CWinDmEvent* out_events, uint32_t max_count, uint32_t* out_count);

#ifdef __cplusplus
}
#endif
#else
typedef int gpua_winsys_unused_t;
#endif
