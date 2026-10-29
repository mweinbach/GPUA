// Ported from: crates/gpui_windows/src/gpui_windows.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Windows)
import Foundation
import GPUI
import GPUICollections
import GPUIUtil
import Scheduler
import ZedUtil
#if canImport(CWinSys)
import CWinSys
#endif

// MARK: - Win32 Custom Window Messages

public let WM_USER: UInt32 = 0x0400
public let WM_APP: UInt32 = 0x8000

public let WM_GPUI_CURSOR_STYLE_CHANGED: UInt32 = WM_USER + 1
public let WM_GPUI_CLOSE_ONE_WINDOW: UInt32 = WM_USER + 2
public let WM_GPUI_TASK_DISPATCHED_ON_MAIN_THREAD: UInt32 = 0x8001
public let WM_GPUI_TASK_DISPATCHED_ON_MAIN_THREAD_LEGACY: UInt32 = WM_USER + 3
public let WM_GPUI_DOCK_MENU_ACTION: UInt32 = WM_USER + 4
public let WM_GPUI_FORCE_UPDATE_WINDOW: UInt32 = WM_USER + 5
public let WM_GPUI_KEYBOARD_LAYOUT_CHANGED: UInt32 = WM_USER + 6
public let WM_GPUI_GPU_DEVICE_LOST: UInt32 = WM_USER + 7
public let WM_GPUI_KEYDOWN: UInt32 = WM_USER + 8

// Window Class Names
public let PLATFORM_WINDOW_CLASS_NAME = "Zed::PlatformWindow"
public let WINDOW_CLASS_NAME = "Zed::Window"

#endif
