// Ported from: crates/rune/src/shortcuts/windows.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! A message-only window receives `WM_HOTKEY` inside the event-loop thread.

#if os(Windows)
import WinSDK

private let WIN_ERROR_HOTKEY_ALREADY_REGISTERED: Int64 = 1409

final class WindowsShortcutBackend: ShortcutBackend {
    private let sink: ShortcutSink
    private var ids: [Int32: ShortcutId] = [:]

    private init(sink: @escaping ShortcutSink) {
        self.sink = sink
    }

    static func create(_ sink: @escaping ShortcutSink) -> Result<WindowsShortcutBackend, ShortcutError> {
        .success(WindowsShortcutBackend(sink: sink))
    }

    func register(_ id: ShortcutId, _ shortcut: Shortcut) -> Result<Void, ShortcutError> {
        guard let local = (Int32(1)...Int32(0xBFFF)).first(where: { ids[$0] == nil }) else {
            return .failure(.backend("Win32 hotkey id space exhausted"))
        }
        var mods: UINT = UINT(MOD_NOREPEAT)
        if (shortcut.mods & SHORTCUT_CTRL) != 0 { mods |= UINT(MOD_CONTROL) }
        if (shortcut.mods & SHORTCUT_ALT) != 0 { mods |= UINT(MOD_ALT) }
        if (shortcut.mods & SHORTCUT_SHIFT) != 0 { mods |= UINT(MOD_SHIFT) }
        if (shortcut.mods & SHORTCUT_SUPER) != 0 { mods |= UINT(MOD_WIN) }
        guard let scan = win32Scancode(shortcut.physicalKey()) else {
            return .failure(.invalidAccelerator(shortcut.description))
        }
        let vk = MapVirtualKeyW(scan, UINT(MAPVK_VSC_TO_VK_EX))
        guard vk != 0 else {
            return .failure(.invalidAccelerator(shortcut.description))
        }
        if RegisterHotKey(nil, local, mods, vk) == false {
            let errCode = Int64(GetLastError())
            if case .failure(let err) = shortcutNativeStatus(errCode, WIN_ERROR_HOTKEY_ALREADY_REGISTERED) {
                return .failure(err)
            }
            return .failure(.backend("RegisterHotKey failed"))
        }
        ids[local] = id
        return .success(())
    }

    func unregister(_ id: ShortcutId) -> Result<Void, ShortcutError> {
        guard let (local, _) = ids.first(where: { $0.value == id }) else {
            return .failure(.unknownId)
        }
        if UnregisterHotKey(nil, local) == false {
            let errCode = Int64(GetLastError())
            if case .failure(let err) = shortcutNativeStatus(errCode, WIN_ERROR_HOTKEY_ALREADY_REGISTERED) {
                return .failure(err)
            }
            return .failure(.backend("UnregisterHotKey failed"))
        }
        ids.removeValue(forKey: local)
        return .success(())
    }

    deinit {
        for (local, _) in ids {
            _ = UnregisterHotKey(nil, local)
        }
        ids.removeAll()
    }
}

private func win32Scancode(_ key: PhysicalKeyCode) -> UINT? {
    switch key {
    case .escape: return 0x01
    case .digit1: return 0x02
    case .digit2: return 0x03
    case .digit3: return 0x04
    case .digit4: return 0x05
    case .digit5: return 0x06
    case .digit6: return 0x07
    case .digit7: return 0x08
    case .digit8: return 0x09
    case .digit9: return 0x0A
    case .digit0: return 0x0B
    case .minus: return 0x0C
    case .equal: return 0x0D
    case .backspace: return 0x0E
    case .tab: return 0x0F
    case .keyQ: return 0x10
    case .keyW: return 0x11
    case .keyE: return 0x12
    case .keyR: return 0x13
    case .keyT: return 0x14
    case .keyY: return 0x15
    case .keyU: return 0x16
    case .keyI: return 0x17
    case .keyO: return 0x18
    case .keyP: return 0x19
    case .bracketLeft: return 0x1A
    case .bracketRight: return 0x1B
    case .enter: return 0x1C
    case .keyA: return 0x1E
    case .keyS: return 0x1F
    case .keyD: return 0x20
    case .keyF: return 0x21
    case .keyG: return 0x22
    case .keyH: return 0x23
    case .keyJ: return 0x24
    case .keyK: return 0x25
    case .keyL: return 0x26
    case .semicolon: return 0x27
    case .quote: return 0x28
    case .backquote: return 0x29
    case .backslash: return 0x2B
    case .keyZ: return 0x2C
    case .keyX: return 0x2D
    case .keyC: return 0x2E
    case .keyV: return 0x2F
    case .keyB: return 0x30
    case .keyN: return 0x31
    case .keyM: return 0x32
    case .comma: return 0x33
    case .period: return 0x34
    case .slash: return 0x35
    case .space: return 0x39
    case .f1: return 0x3B
    case .f2: return 0x3C
    case .f3: return 0x3D
    case .f4: return 0x3E
    case .f5: return 0x3F
    case .f6: return 0x40
    case .f7: return 0x41
    case .f8: return 0x42
    case .f9: return 0x43
    case .f10: return 0x44
    case .f11: return 0x57
    case .f12: return 0x58
    case .f13: return 0x64
    case .f14: return 0x65
    case .f15: return 0x66
    case .f16: return 0x67
    case .f17: return 0x68
    case .f18: return 0x69
    case .f19: return 0x6A
    case .f20: return 0x6B
    case .f21: return 0x6C
    case .f22: return 0x6D
    case .f23: return 0x6E
    case .f24: return 0x76
    case .home: return 0xE047
    case .arrowUp: return 0xE048
    case .pageUp: return 0xE049
    case .arrowLeft: return 0xE04B
    case .arrowRight: return 0xE04D
    case .end: return 0xE04F
    case .arrowDown: return 0xE050
    case .pageDown: return 0xE051
    case .insert: return 0xE052
    case .delete: return 0xE053
    default: return nil
    }
}
#endif
