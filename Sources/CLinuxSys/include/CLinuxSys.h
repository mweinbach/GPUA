// Swift-only: C bridge umbrella header for Linux system libraries
#pragma once

#if defined(__linux__) && !defined(__ANDROID__)
#include <wayland-client.h>
#include <wayland-cursor.h>
#include "xdg-shell-client-protocol.h"

static inline const struct wl_interface *gpua_wl_compositor_interface(void) { return &wl_compositor_interface; }
static inline const struct wl_interface *gpua_wl_subcompositor_interface(void) { return &wl_subcompositor_interface; }
static inline const struct wl_interface *gpua_wl_shm_interface(void) { return &wl_shm_interface; }
static inline const struct wl_interface *gpua_wl_seat_interface(void) { return &wl_seat_interface; }
static inline const struct wl_interface *gpua_wl_output_interface(void) { return &wl_output_interface; }
static inline const struct wl_interface *gpua_wl_data_device_manager_interface(void) { return &wl_data_device_manager_interface; }
static inline const struct wl_interface *gpua_xdg_wm_base_interface(void) { return &xdg_wm_base_interface; }
#include <X11/Xlib.h>
#include <X11/Xlib-xcb.h>
#include <xcb/xcb.h>
#include <xcb/randr.h>
#include <xcb/xinput.h>
#include <xcb/sync.h>
#include <xkbcommon/xkbcommon.h>
#include <xkbcommon/xkbcommon-x11.h>
#include <xkbcommon/xkbcommon-compose.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_OUTLINE_H
#include <harfbuzz/hb.h>
#include <harfbuzz/hb-ft.h>
#include <fontconfig/fontconfig.h>
#include <sys/epoll.h>
#include <sys/eventfd.h>
#include <sys/timerfd.h>
#endif
