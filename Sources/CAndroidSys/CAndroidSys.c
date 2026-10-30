// Swift-only: C interop implementation for Android NDK system libraries per ADR-0012
#include "CAndroidSys.h"

#if defined(__ANDROID__)
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// MARK: - Logging & Thread Identification

int candroid_log_print(int prio, const char* _Nonnull tag, const char* _Nonnull message) {
    return __android_log_print(prio, tag, "%s", message);
}

bool candroid_is_main_thread(void) {
    return getpid() == gettid();
}

// MARK: - ALooper & Wake Pipe Wrappers

struct CAndroidWakePipe {
    int read_fd;
    int write_fd;
    ALooper* looper;
    candroid_looper_wake_callback_t callback;
    void* context;
};

ALooper* _Nullable candroid_looper_for_thread(void) {
    return ALooper_forThread();
}

ALooper* _Nullable candroid_looper_prepare(int opts) {
    return ALooper_prepare(opts);
}

void candroid_looper_acquire(ALooper* _Nonnull looper) {
    ALooper_acquire(looper);
}

void candroid_looper_release(ALooper* _Nonnull looper) {
    ALooper_release(looper);
}

void candroid_looper_wake(ALooper* _Nonnull looper) {
    ALooper_wake(looper);
}

int candroid_looper_poll_once(
    int timeoutMillis,
    int* _Nullable outFd,
    int* _Nullable outEvents,
    void* _Nullable * _Nullable outData
) {
    return ALooper_pollOnce(timeoutMillis, outFd, outEvents, outData);
}

static int candroid_wake_pipe_looper_cb(int fd, int events, void* data) {
    (void)fd;
    CAndroidWakePipe* pipe_handle = (CAndroidWakePipe*)data;
    if (pipe_handle == NULL) {
        return 0;
    }
    if ((events & ALOOPER_EVENT_INPUT) != 0) {
        candroid_wake_pipe_drain(pipe_handle);
        if (pipe_handle->callback != NULL) {
            pipe_handle->callback(pipe_handle->context);
        }
    }
    if ((events & (ALOOPER_EVENT_ERROR | ALOOPER_EVENT_HANGUP | ALOOPER_EVENT_INVALID)) != 0) {
        return 0;
    }
    return 1;
}

static int candroid_set_nonblocking_cloexec(int fd) {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags >= 0) {
        (void)fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    }
    int fd_flags = fcntl(fd, F_GETFD, 0);
    if (fd_flags >= 0) {
        (void)fcntl(fd, F_SETFD, fd_flags | FD_CLOEXEC);
    }
    return 0;
}

CAndroidWakePipe* _Nullable candroid_wake_pipe_create(
    ALooper* _Nullable looper,
    candroid_looper_wake_callback_t _Nullable callback,
    void* _Nullable context
) {
    int fds[2] = {-1, -1};
    if (pipe(fds) != 0) {
        return NULL;
    }
    candroid_set_nonblocking_cloexec(fds[0]);
    candroid_set_nonblocking_cloexec(fds[1]);

    CAndroidWakePipe* handle = (CAndroidWakePipe*)calloc(1, sizeof(CAndroidWakePipe));
    if (handle == NULL) {
        close(fds[0]);
        close(fds[1]);
        return NULL;
    }
    handle->read_fd = fds[0];
    handle->write_fd = fds[1];
    handle->looper = NULL;
    handle->callback = callback;
    handle->context = context;

    if (looper != NULL) {
        (void)candroid_wake_pipe_attach_looper(handle, looper);
    }
    return handle;
}

int candroid_wake_pipe_attach_looper(
    CAndroidWakePipe* _Nonnull pipe_handle,
    ALooper* _Nonnull looper
) {
    if (pipe_handle->looper == looper) {
        return 1;
    }
    if (pipe_handle->looper != NULL) {
        ALooper_removeFd(pipe_handle->looper, pipe_handle->read_fd);
        ALooper_release(pipe_handle->looper);
        pipe_handle->looper = NULL;
    }
    ALooper_acquire(looper);
    int rc = ALooper_addFd(
        looper,
        pipe_handle->read_fd,
        ALOOPER_POLL_CALLBACK,
        ALOOPER_EVENT_INPUT,
        candroid_wake_pipe_looper_cb,
        pipe_handle
    );
    if (rc == 1) {
        pipe_handle->looper = looper;
    } else {
        ALooper_release(looper);
    }
    return rc;
}

void candroid_wake_pipe_signal(CAndroidWakePipe* _Nonnull pipe_handle) {
    if (pipe_handle->write_fd >= 0) {
        uint8_t byte = 1;
        ssize_t written;
        do {
            written = write(pipe_handle->write_fd, &byte, 1);
        } while (written < 0 && errno == EINTR);
    }
    if (pipe_handle->looper != NULL) {
        ALooper_wake(pipe_handle->looper);
    }
}

void candroid_wake_pipe_drain(CAndroidWakePipe* _Nonnull pipe_handle) {
    if (pipe_handle->read_fd < 0) {
        return;
    }
    uint8_t buf[64];
    for (;;) {
        ssize_t n = read(pipe_handle->read_fd, buf, sizeof(buf));
        if (n > 0) {
            continue;
        }
        if (n < 0 && errno == EINTR) {
            continue;
        }
        break;
    }
}

int candroid_wake_pipe_get_read_fd(const CAndroidWakePipe* _Nonnull pipe_handle) {
    return pipe_handle->read_fd;
}

void candroid_wake_pipe_destroy(CAndroidWakePipe* _Nullable pipe_handle) {
    if (pipe_handle == NULL) {
        return;
    }
    if (pipe_handle->looper != NULL) {
        ALooper_removeFd(pipe_handle->looper, pipe_handle->read_fd);
        ALooper_release(pipe_handle->looper);
        pipe_handle->looper = NULL;
    }
    if (pipe_handle->read_fd >= 0) {
        close(pipe_handle->read_fd);
        pipe_handle->read_fd = -1;
    }
    if (pipe_handle->write_fd >= 0) {
        close(pipe_handle->write_fd);
        pipe_handle->write_fd = -1;
    }
    free(pipe_handle);
}

// MARK: - ANativeWindow Wrappers

ANativeWindow* _Nullable candroid_native_window_from_surface(
    JNIEnv _Nullable * _Nonnull env,
    jobject _Nullable surface
) {
    if (surface == NULL) {
        return NULL;
    }
    return ANativeWindow_fromSurface(env, surface);
}

void candroid_native_window_acquire(ANativeWindow* _Nonnull window) {
    ANativeWindow_acquire(window);
}

void candroid_native_window_release(ANativeWindow* _Nonnull window) {
    ANativeWindow_release(window);
}

int32_t candroid_native_window_get_width(ANativeWindow* _Nonnull window) {
    return ANativeWindow_getWidth(window);
}

int32_t candroid_native_window_get_height(ANativeWindow* _Nonnull window) {
    return ANativeWindow_getHeight(window);
}

int32_t candroid_native_window_get_format(ANativeWindow* _Nonnull window) {
    return ANativeWindow_getFormat(window);
}

int32_t candroid_native_window_set_buffers_geometry(
    ANativeWindow* _Nonnull window,
    int32_t width,
    int32_t height,
    int32_t format
) {
    return ANativeWindow_setBuffersGeometry(window, width, height, format);
}

// MARK: - AChoreographer Wrappers (API 29+)

AChoreographer* _Nullable candroid_choreographer_get_instance(void) {
    return AChoreographer_getInstance();
}

void candroid_choreographer_post_frame_callback64(
    AChoreographer* _Nonnull choreographer,
    candroid_choreographer_callback_t _Nonnull callback,
    void* _Nullable data
) {
    AChoreographer_postFrameCallback64(choreographer, callback, data);
}

void candroid_choreographer_post_frame_callback_delayed64(
    AChoreographer* _Nonnull choreographer,
    candroid_choreographer_callback_t _Nonnull callback,
    void* _Nullable data,
    uint32_t delayMillis
) {
    AChoreographer_postFrameCallbackDelayed64(choreographer, callback, data, delayMillis);
}

// MARK: - System Font Discovery & Matching (API 29+)

ASystemFontIterator* _Nullable candroid_system_font_iterator_open(void) {
    return ASystemFontIterator_open();
}

AFont* _Nullable candroid_system_font_iterator_next(ASystemFontIterator* _Nonnull iterator) {
    return ASystemFontIterator_next(iterator);
}

void candroid_system_font_iterator_close(ASystemFontIterator* _Nullable iterator) {
    if (iterator != NULL) {
        ASystemFontIterator_close(iterator);
    }
}

const char* _Nonnull candroid_font_get_file_path(const AFont* _Nonnull font) {
    return AFont_getFontFilePath(font);
}

uint16_t candroid_font_get_weight(const AFont* _Nonnull font) {
    return AFont_getWeight(font);
}

bool candroid_font_is_italic(const AFont* _Nonnull font) {
    return AFont_isItalic(font);
}

const char* _Nullable candroid_font_get_locale(const AFont* _Nonnull font) {
    return AFont_getLocale(font);
}

size_t candroid_font_get_collection_index(const AFont* _Nonnull font) {
    return AFont_getCollectionIndex(font);
}

void candroid_font_close(AFont* _Nullable font) {
    if (font != NULL) {
        AFont_close(font);
    }
}

AFontMatcher* _Nullable candroid_font_matcher_create(void) {
    return AFontMatcher_create();
}

void candroid_font_matcher_set_style(
    AFontMatcher* _Nonnull matcher,
    uint16_t weight,
    bool italic
) {
    AFontMatcher_setStyle(matcher, weight, italic);
}

void candroid_font_matcher_set_locales(
    AFontMatcher* _Nonnull matcher,
    const char* _Nonnull languageTags
) {
    AFontMatcher_setLocales(matcher, languageTags);
}

AFont* _Nullable candroid_font_matcher_match(
    const AFontMatcher* _Nonnull matcher,
    const char* _Nonnull familyName,
    const uint16_t* _Nonnull text,
    uint32_t textLength,
    uint32_t* _Nullable runLengthOut
) {
    return AFontMatcher_match(matcher, familyName, text, textLength, runLengthOut);
}

void candroid_font_matcher_destroy(AFontMatcher* _Nullable matcher) {
    if (matcher != NULL) {
        AFontMatcher_destroy(matcher);
    }
}

// MARK: - JNI Helpers & Host Bridge

const char* _Nullable candroid_jni_get_string_utf_chars(
    JNIEnv _Nullable * _Nonnull env,
    jstring _Nullable str
) {
    if (str == NULL) {
        return NULL;
    }
    return (*env)->GetStringUTFChars(env, str, NULL);
}

void candroid_jni_release_string_utf_chars(
    JNIEnv _Nullable * _Nonnull env,
    jstring _Nullable str,
    const char* _Nullable chars
) {
    if (str != NULL && chars != NULL) {
        (*env)->ReleaseStringUTFChars(env, str, chars);
    }
}

jstring _Nullable candroid_jni_new_string_utf(
    JNIEnv _Nullable * _Nonnull env,
    const char* _Nonnull chars
) {
    return (*env)->NewStringUTF(env, chars);
}

jsize candroid_jni_get_array_length(JNIEnv _Nullable * _Nonnull env, jarray _Nullable array) {
    if (array == NULL) {
        return 0;
    }
    return (*env)->GetArrayLength(env, array);
}

jint* _Nullable candroid_jni_get_int_array_elements(
    JNIEnv _Nullable * _Nonnull env,
    jintArray _Nullable array
) {
    if (array == NULL) {
        return NULL;
    }
    return (*env)->GetIntArrayElements(env, array, NULL);
}

void candroid_jni_release_int_array_elements(
    JNIEnv _Nullable * _Nonnull env,
    jintArray _Nullable array,
    jint* _Nullable elems,
    jint mode
) {
    if (array != NULL && elems != NULL) {
        (*env)->ReleaseIntArrayElements(env, array, elems, mode);
    }
}

jfloat* _Nullable candroid_jni_get_float_array_elements(
    JNIEnv _Nullable * _Nonnull env,
    jfloatArray _Nullable array
) {
    if (array == NULL) {
        return NULL;
    }
    return (*env)->GetFloatArrayElements(env, array, NULL);
}

void candroid_jni_release_float_array_elements(
    JNIEnv _Nullable * _Nonnull env,
    jfloatArray _Nullable array,
    jfloat* _Nullable elems,
    jint mode
) {
    if (array != NULL && elems != NULL) {
        (*env)->ReleaseFloatArrayElements(env, array, elems, mode);
    }
}

static pthread_mutex_t g_host_mutex = PTHREAD_MUTEX_INITIALIZER;
static JavaVM* g_jvm = NULL;
static jclass g_host_class = NULL;

static JNIEnv _Nullable * _Nullable candroid_acquire_env(bool* _Nonnull did_attach) {
    *did_attach = false;
    if (g_jvm == NULL) {
        return NULL;
    }
    JNIEnv* env = NULL;
    jint status = (*g_jvm)->GetEnv(g_jvm, (void**)&env, JNI_VERSION_1_6);
    if (status == JNI_OK && env != NULL) {
        return env;
    }
    if (status == JNI_EDETACHED) {
        if ((*g_jvm)->AttachCurrentThread(g_jvm, &env, NULL) == JNI_OK && env != NULL) {
            *did_attach = true;
            return env;
        }
    }
    return NULL;
}

static void candroid_release_env(JNIEnv _Nullable * _Nonnull env, bool did_attach) {
    if ((*env)->ExceptionCheck(env)) {
        (*env)->ExceptionClear(env);
    }
    if (did_attach && g_jvm != NULL) {
        (*g_jvm)->DetachCurrentThread(g_jvm);
    }
}

void candroid_jni_register_host(JNIEnv _Nullable * _Nonnull env, jclass _Nullable hostClass) {
    pthread_mutex_lock(&g_host_mutex);
    if (g_jvm == NULL) {
        (void)(*env)->GetJavaVM(env, &g_jvm);
    }
    if (hostClass != NULL) {
        if (g_host_class != NULL) {
            (*env)->DeleteGlobalRef(env, g_host_class);
        }
        g_host_class = (jclass)(*env)->NewGlobalRef(env, hostClass);
    }
    pthread_mutex_unlock(&g_host_mutex);
}

bool candroid_host_set_clipboard_text(const char* _Nonnull text) {
    pthread_mutex_lock(&g_host_mutex);
    jclass cls = g_host_class;
    pthread_mutex_unlock(&g_host_mutex);
    if (cls == NULL) {
        return false;
    }
    bool did_attach = false;
    JNIEnv* env = candroid_acquire_env(&did_attach);
    if (env == NULL) {
        return false;
    }
    jmethodID mid = (*env)->GetStaticMethodID(env, cls, "hostSetClipboardText", "(Ljava/lang/String;)V");
    if ((*env)->ExceptionCheck(env) || mid == NULL) {
        candroid_release_env(env, did_attach);
        return false;
    }
    jstring jtext = (*env)->NewStringUTF(env, text);
    if (jtext != NULL) {
        (*env)->CallStaticVoidMethod(env, cls, mid, jtext);
        (*env)->DeleteLocalRef(env, jtext);
    }
    candroid_release_env(env, did_attach);
    return true;
}

bool candroid_host_get_clipboard_text(char* _Nonnull outBuf, size_t outBufCap) {
    if (outBufCap == 0) {
        return false;
    }
    outBuf[0] = '\0';
    pthread_mutex_lock(&g_host_mutex);
    jclass cls = g_host_class;
    pthread_mutex_unlock(&g_host_mutex);
    if (cls == NULL) {
        return false;
    }
    bool did_attach = false;
    JNIEnv* env = candroid_acquire_env(&did_attach);
    if (env == NULL) {
        return false;
    }
    jmethodID mid = (*env)->GetStaticMethodID(env, cls, "hostGetClipboardText", "()Ljava/lang/String;");
    if ((*env)->ExceptionCheck(env) || mid == NULL) {
        candroid_release_env(env, did_attach);
        return false;
    }
    jstring jstr = (jstring)(*env)->CallStaticObjectMethod(env, cls, mid);
    bool ok = false;
    if (!(*env)->ExceptionCheck(env) && jstr != NULL) {
        const char* utf = (*env)->GetStringUTFChars(env, jstr, NULL);
        if (utf != NULL) {
            strncpy(outBuf, utf, outBufCap - 1);
            outBuf[outBufCap - 1] = '\0';
            (*env)->ReleaseStringUTFChars(env, jstr, utf);
            ok = true;
        }
        (*env)->DeleteLocalRef(env, jstr);
    }
    candroid_release_env(env, did_attach);
    return ok;
}

bool candroid_host_open_url(const char* _Nonnull url) {
    pthread_mutex_lock(&g_host_mutex);
    jclass cls = g_host_class;
    pthread_mutex_unlock(&g_host_mutex);
    if (cls == NULL) {
        return false;
    }
    bool did_attach = false;
    JNIEnv* env = candroid_acquire_env(&did_attach);
    if (env == NULL) {
        return false;
    }
    jmethodID mid = (*env)->GetStaticMethodID(env, cls, "hostOpenUrl", "(Ljava/lang/String;)V");
    if ((*env)->ExceptionCheck(env) || mid == NULL) {
        candroid_release_env(env, did_attach);
        return false;
    }
    jstring jurl = (*env)->NewStringUTF(env, url);
    if (jurl != NULL) {
        (*env)->CallStaticVoidMethod(env, cls, mid, jurl);
        (*env)->DeleteLocalRef(env, jurl);
    }
    candroid_release_env(env, did_attach);
    return true;
}

bool candroid_host_set_ime_visible(bool visible) {
    pthread_mutex_lock(&g_host_mutex);
    jclass cls = g_host_class;
    pthread_mutex_unlock(&g_host_mutex);
    if (cls == NULL) {
        return false;
    }
    bool did_attach = false;
    JNIEnv* env = candroid_acquire_env(&did_attach);
    if (env == NULL) {
        return false;
    }
    jmethodID mid = (*env)->GetStaticMethodID(env, cls, "hostSetImeVisible", "(Z)V");
    if ((*env)->ExceptionCheck(env) || mid == NULL) {
        candroid_release_env(env, did_attach);
        return false;
    }
    (*env)->CallStaticVoidMethod(env, cls, mid, visible ? JNI_TRUE : JNI_FALSE);
    candroid_release_env(env, did_attach);
    return true;
}

bool candroid_host_request_frame(void) {
    pthread_mutex_lock(&g_host_mutex);
    jclass cls = g_host_class;
    pthread_mutex_unlock(&g_host_mutex);
    if (cls == NULL) {
        return false;
    }
    bool did_attach = false;
    JNIEnv* env = candroid_acquire_env(&did_attach);
    if (env == NULL) {
        return false;
    }
    jmethodID mid = (*env)->GetStaticMethodID(env, cls, "hostRequestFrame", "()V");
    if ((*env)->ExceptionCheck(env) || mid == NULL) {
        candroid_release_env(env, did_attach);
        return false;
    }
    (*env)->CallStaticVoidMethod(env, cls, mid);
    candroid_release_env(env, did_attach);
    return true;
}

bool candroid_host_write_credential(
    const char* _Nonnull url,
    const char* _Nonnull username,
    const char* _Nonnull passwordBase64
) {
    pthread_mutex_lock(&g_host_mutex);
    jclass cls = g_host_class;
    pthread_mutex_unlock(&g_host_mutex);
    if (cls == NULL) {
        return false;
    }
    bool did_attach = false;
    JNIEnv* env = candroid_acquire_env(&did_attach);
    if (env == NULL) {
        return false;
    }
    jmethodID mid = (*env)->GetStaticMethodID(
        env,
        cls,
        "hostWriteCredential",
        "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Z"
    );
    if ((*env)->ExceptionCheck(env) || mid == NULL) {
        candroid_release_env(env, did_attach);
        return false;
    }
    jstring jurl = (*env)->NewStringUTF(env, url);
    jstring juser = (*env)->NewStringUTF(env, username);
    jstring jpass = (*env)->NewStringUTF(env, passwordBase64);
    jboolean ok = JNI_FALSE;
    if (jurl != NULL && juser != NULL && jpass != NULL) {
        ok = (*env)->CallStaticBooleanMethod(env, cls, mid, jurl, juser, jpass);
    }
    if (jurl != NULL) (*env)->DeleteLocalRef(env, jurl);
    if (juser != NULL) (*env)->DeleteLocalRef(env, juser);
    if (jpass != NULL) (*env)->DeleteLocalRef(env, jpass);
    candroid_release_env(env, did_attach);
    return ok == JNI_TRUE;
}

bool candroid_host_read_credential(
    const char* _Nonnull url,
    char* _Nonnull outUsernameBuf,
    size_t outUsernameCap,
    char* _Nonnull outPasswordBase64Buf,
    size_t outPasswordBase64Cap
) {
    if (outUsernameCap == 0 || outPasswordBase64Cap == 0) {
        return false;
    }
    outUsernameBuf[0] = '\0';
    outPasswordBase64Buf[0] = '\0';
    pthread_mutex_lock(&g_host_mutex);
    jclass cls = g_host_class;
    pthread_mutex_unlock(&g_host_mutex);
    if (cls == NULL) {
        return false;
    }
    bool did_attach = false;
    JNIEnv* env = candroid_acquire_env(&did_attach);
    if (env == NULL) {
        return false;
    }
    jmethodID mid = (*env)->GetStaticMethodID(
        env,
        cls,
        "hostReadCredential",
        "(Ljava/lang/String;)[Ljava/lang/String;"
    );
    if ((*env)->ExceptionCheck(env) || mid == NULL) {
        candroid_release_env(env, did_attach);
        return false;
    }
    jstring jurl = (*env)->NewStringUTF(env, url);
    bool ok = false;
    if (jurl != NULL) {
        jobjectArray pair = (jobjectArray)(*env)->CallStaticObjectMethod(env, cls, mid, jurl);
        if (!(*env)->ExceptionCheck(env) && pair != NULL && (*env)->GetArrayLength(env, pair) >= 2) {
            jstring juser = (jstring)(*env)->GetObjectArrayElement(env, pair, 0);
            jstring jpass = (jstring)(*env)->GetObjectArrayElement(env, pair, 1);
            if (juser != NULL && jpass != NULL) {
                const char* u = (*env)->GetStringUTFChars(env, juser, NULL);
                const char* p = (*env)->GetStringUTFChars(env, jpass, NULL);
                if (u != NULL && p != NULL) {
                    strncpy(outUsernameBuf, u, outUsernameCap - 1);
                    outUsernameBuf[outUsernameCap - 1] = '\0';
                    strncpy(outPasswordBase64Buf, p, outPasswordBase64Cap - 1);
                    outPasswordBase64Buf[outPasswordBase64Cap - 1] = '\0';
                    ok = true;
                }
                if (u != NULL) (*env)->ReleaseStringUTFChars(env, juser, u);
                if (p != NULL) (*env)->ReleaseStringUTFChars(env, jpass, p);
            }
            if (juser != NULL) (*env)->DeleteLocalRef(env, juser);
            if (jpass != NULL) (*env)->DeleteLocalRef(env, jpass);
            (*env)->DeleteLocalRef(env, pair);
        }
        (*env)->DeleteLocalRef(env, jurl);
    }
    candroid_release_env(env, did_attach);
    return ok;
}

bool candroid_host_delete_credential(const char* _Nonnull url) {
    pthread_mutex_lock(&g_host_mutex);
    jclass cls = g_host_class;
    pthread_mutex_unlock(&g_host_mutex);
    if (cls == NULL) {
        return false;
    }
    bool did_attach = false;
    JNIEnv* env = candroid_acquire_env(&did_attach);
    if (env == NULL) {
        return false;
    }
    jmethodID mid = (*env)->GetStaticMethodID(
        env,
        cls,
        "hostDeleteCredential",
        "(Ljava/lang/String;)Z"
    );
    if ((*env)->ExceptionCheck(env) || mid == NULL) {
        candroid_release_env(env, did_attach);
        return false;
    }
    jstring jurl = (*env)->NewStringUTF(env, url);
    jboolean ok = JNI_FALSE;
    if (jurl != NULL) {
        ok = (*env)->CallStaticBooleanMethod(env, cls, mid, jurl);
        (*env)->DeleteLocalRef(env, jurl);
    }
    candroid_release_env(env, did_attach);
    return ok == JNI_TRUE;
}

bool candroid_host_finish_activity(void) {
    pthread_mutex_lock(&g_host_mutex);
    jclass cls = g_host_class;
    pthread_mutex_unlock(&g_host_mutex);
    if (cls == NULL) {
        return false;
    }
    bool did_attach = false;
    JNIEnv* env = candroid_acquire_env(&did_attach);
    if (env == NULL) {
        return false;
    }
    jmethodID mid = (*env)->GetStaticMethodID(env, cls, "hostFinishActivity", "()V");
    if ((*env)->ExceptionCheck(env) || mid == NULL) {
        candroid_release_env(env, did_attach);
        return false;
    }
    (*env)->CallStaticVoidMethod(env, cls, mid);
    candroid_release_env(env, did_attach);
    return true;
}

#endif
