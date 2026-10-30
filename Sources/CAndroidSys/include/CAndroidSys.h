// Swift-only: C interop umbrella header for Android NDK system libraries per ADR-0012
#pragma once

#if defined(__ANDROID__)
#include <jni.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <android/looper.h>
#include <android/choreographer.h>
#include <android/input.h>
#include <android/keycodes.h>
#include <android/log.h>
#include <android/font.h>
#include <android/font_matcher.h>
#include <android/system_fonts.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - Logging & Thread Identification

int candroid_log_print(int prio, const char* _Nonnull tag, const char* _Nonnull message);
bool candroid_is_main_thread(void);

// MARK: - ALooper & Wake Pipe Wrappers

typedef void (*candroid_looper_wake_callback_t)(void* _Nullable context);
typedef struct CAndroidWakePipe CAndroidWakePipe;

ALooper* _Nullable candroid_looper_for_thread(void);
ALooper* _Nullable candroid_looper_prepare(int opts);
void candroid_looper_acquire(ALooper* _Nonnull looper);
void candroid_looper_release(ALooper* _Nonnull looper);
void candroid_looper_wake(ALooper* _Nonnull looper);
int candroid_looper_poll_once(
    int timeoutMillis,
    int* _Nullable outFd,
    int* _Nullable outEvents,
    void* _Nullable * _Nullable outData
);

CAndroidWakePipe* _Nullable candroid_wake_pipe_create(
    ALooper* _Nullable looper,
    candroid_looper_wake_callback_t _Nullable callback,
    void* _Nullable context
);
int candroid_wake_pipe_attach_looper(
    CAndroidWakePipe* _Nonnull pipe_handle,
    ALooper* _Nonnull looper
);
void candroid_wake_pipe_signal(CAndroidWakePipe* _Nonnull pipe_handle);
void candroid_wake_pipe_drain(CAndroidWakePipe* _Nonnull pipe_handle);
int candroid_wake_pipe_get_read_fd(const CAndroidWakePipe* _Nonnull pipe_handle);
void candroid_wake_pipe_destroy(CAndroidWakePipe* _Nullable pipe_handle);

// MARK: - ANativeWindow Wrappers

ANativeWindow* _Nullable candroid_native_window_from_surface(
    JNIEnv _Nullable * _Nonnull env,
    jobject _Nullable surface
);
void candroid_native_window_acquire(ANativeWindow* _Nonnull window);
void candroid_native_window_release(ANativeWindow* _Nonnull window);
int32_t candroid_native_window_get_width(ANativeWindow* _Nonnull window);
int32_t candroid_native_window_get_height(ANativeWindow* _Nonnull window);
int32_t candroid_native_window_get_format(ANativeWindow* _Nonnull window);
int32_t candroid_native_window_set_buffers_geometry(
    ANativeWindow* _Nonnull window,
    int32_t width,
    int32_t height,
    int32_t format
);

// MARK: - AChoreographer Wrappers (API 29+)

typedef void (*candroid_choreographer_callback_t)(int64_t frameTimeNanos, void* _Nullable data);

AChoreographer* _Nullable candroid_choreographer_get_instance(void);
void candroid_choreographer_post_frame_callback64(
    AChoreographer* _Nonnull choreographer,
    candroid_choreographer_callback_t _Nonnull callback,
    void* _Nullable data
);
void candroid_choreographer_post_frame_callback_delayed64(
    AChoreographer* _Nonnull choreographer,
    candroid_choreographer_callback_t _Nonnull callback,
    void* _Nullable data,
    uint32_t delayMillis
);

// MARK: - System Font Discovery & Matching (API 29+)

ASystemFontIterator* _Nullable candroid_system_font_iterator_open(void);
AFont* _Nullable candroid_system_font_iterator_next(ASystemFontIterator* _Nonnull iterator);
void candroid_system_font_iterator_close(ASystemFontIterator* _Nullable iterator);

const char* _Nonnull candroid_font_get_file_path(const AFont* _Nonnull font);
uint16_t candroid_font_get_weight(const AFont* _Nonnull font);
bool candroid_font_is_italic(const AFont* _Nonnull font);
const char* _Nullable candroid_font_get_locale(const AFont* _Nonnull font);
size_t candroid_font_get_collection_index(const AFont* _Nonnull font);
void candroid_font_close(AFont* _Nullable font);

AFontMatcher* _Nullable candroid_font_matcher_create(void);
void candroid_font_matcher_set_style(
    AFontMatcher* _Nonnull matcher,
    uint16_t weight,
    bool italic
);
void candroid_font_matcher_set_locales(
    AFontMatcher* _Nonnull matcher,
    const char* _Nonnull languageTags
);
AFont* _Nullable candroid_font_matcher_match(
    const AFontMatcher* _Nonnull matcher,
    const char* _Nonnull familyName,
    const uint16_t* _Nonnull text,
    uint32_t textLength,
    uint32_t* _Nullable runLengthOut
);
void candroid_font_matcher_destroy(AFontMatcher* _Nullable matcher);

// MARK: - JNI Array/String & Host Bridge Helpers

const char* _Nullable candroid_jni_get_string_utf_chars(
    JNIEnv _Nullable * _Nonnull env,
    jstring _Nullable str
);
void candroid_jni_release_string_utf_chars(
    JNIEnv _Nullable * _Nonnull env,
    jstring _Nullable str,
    const char* _Nullable chars
);
jstring _Nullable candroid_jni_new_string_utf(
    JNIEnv _Nullable * _Nonnull env,
    const char* _Nonnull chars
);
jsize candroid_jni_get_array_length(JNIEnv _Nullable * _Nonnull env, jarray _Nullable array);
jint* _Nullable candroid_jni_get_int_array_elements(
    JNIEnv _Nullable * _Nonnull env,
    jintArray _Nullable array
);
void candroid_jni_release_int_array_elements(
    JNIEnv _Nullable * _Nonnull env,
    jintArray _Nullable array,
    jint* _Nullable elems,
    jint mode
);
jfloat* _Nullable candroid_jni_get_float_array_elements(
    JNIEnv _Nullable * _Nonnull env,
    jfloatArray _Nullable array
);
void candroid_jni_release_float_array_elements(
    JNIEnv _Nullable * _Nonnull env,
    jfloatArray _Nullable array,
    jfloat* _Nullable elems,
    jint mode
);

void candroid_jni_register_host(JNIEnv _Nullable * _Nonnull env, jclass _Nullable hostClass);
bool candroid_host_set_clipboard_text(const char* _Nonnull text);
bool candroid_host_get_clipboard_text(char* _Nonnull outBuf, size_t outBufCap);
bool candroid_host_open_url(const char* _Nonnull url);
bool candroid_host_set_ime_visible(bool visible);
bool candroid_host_request_frame(void);
bool candroid_host_write_credential(
    const char* _Nonnull url,
    const char* _Nonnull username,
    const char* _Nonnull passwordBase64
);
bool candroid_host_read_credential(
    const char* _Nonnull url,
    char* _Nonnull outUsernameBuf,
    size_t outUsernameCap,
    char* _Nonnull outPasswordBase64Buf,
    size_t outPasswordBase64Cap
);
bool candroid_host_delete_credential(const char* _Nonnull url);
bool candroid_host_finish_activity(void);

#ifdef __cplusplus
}
#endif

#else
typedef int candroid_unused_t;
#endif
