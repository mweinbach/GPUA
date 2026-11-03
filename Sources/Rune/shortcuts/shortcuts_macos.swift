// Ported from: crates/rune/src/shortcuts/macos.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Carbon hotkeys do not require Accessibility or Input Monitoring permission.

#if os(macOS)
import Carbon
import CoreFoundation
import Foundation

private let MAC_SHORTCUT_SIGNATURE: OSType = 0x7275_6E65 // 'rune'
private let MAC_SHORTCUT_EXISTS: Int64 = -9878 // eventHotKeyExistsErr

let MAC_CARBON_CMD: UInt32 = 1 << 8
let MAC_CARBON_SHIFT: UInt32 = 1 << 9
let MAC_CARBON_OPTION: UInt32 = 1 << 11
let MAC_CARBON_CONTROL: UInt32 = 1 << 12
private let MAC_CARBON_MODS_MASK: UInt32 = MAC_CARBON_CMD | MAC_CARBON_SHIFT | MAC_CARBON_OPTION | MAC_CARBON_CONTROL

final class MacShortcutContext {
    let sink: ShortcutSink
    var keys: [ShortcutId: EventHotKeyRef] = [:]

    init(sink: @escaping ShortcutSink) {
        self.sink = sink
    }
}

private let macHotKeyEventHandler: EventHandlerUPP = { _, eventRef, userData in
    guard let eventRef, let userData else {
        return OSStatus(eventNotHandledErr)
    }
    var hotKeyId = EventHotKeyID(signature: 0, id: 0)
    let status = GetEventParameter(
        eventRef,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyId
    )
    guard status == noErr, hotKeyId.signature == MAC_SHORTCUT_SIGNATURE else {
        return OSStatus(eventNotHandledErr)
    }
    let ctx = Unmanaged<MacShortcutContext>.fromOpaque(userData).takeUnretainedValue()
    let sid = ShortcutId(hotKeyId.id)
    guard ctx.keys[sid] != nil else {
        return OSStatus(eventNotHandledErr)
    }
    ctx.sink(sid, nil)
    return noErr
}

final class MacShortcutBackend: ShortcutBackend {
    private let handlerRef: EventHandlerRef
    private let context: MacShortcutContext

    private init(handlerRef: EventHandlerRef, context: MacShortcutContext) {
        self.handlerRef = handlerRef
        self.context = context
    }

    static func create(_ sink: @escaping ShortcutSink) -> Result<MacShortcutBackend, ShortcutError> {
        guard Thread.isMainThread else {
            return .failure(.backend("Carbon requires the main thread"))
        }
        let ctx = MacShortcutContext(sink: sink)
        let rawCtx = Unmanaged.passUnretained(ctx).toOpaque()
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var installed: EventHandlerRef? = nil
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            macHotKeyEventHandler,
            1,
            &eventType,
            rawCtx,
            &installed
        )
        switch shortcutNativeStatus(Int64(status), MAC_SHORTCUT_EXISTS) {
        case .failure(let err):
            return .failure(err)
        case .success:
            guard let installed else {
                return .failure(.backend("Carbon returned null event handler"))
            }
            return .success(MacShortcutBackend(handlerRef: installed, context: ctx))
        }
    }

    func register(_ id: ShortcutId, _ shortcut: Shortcut) -> Result<Void, ShortcutError> {
        guard let code = macShortcutKeycode(shortcut.keyName()) else {
            return .failure(.invalidAccelerator(shortcut.description))
        }
        let mods = macCarbonMods(shortcut)
        var hotKeyRef: EventHotKeyRef? = nil
        let status = RegisterEventHotKey(
            code,
            mods,
            EventHotKeyID(signature: MAC_SHORTCUT_SIGNATURE, id: id.rawValue),
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &hotKeyRef
        )
        switch shortcutNativeStatus(Int64(status), MAC_SHORTCUT_EXISTS) {
        case .failure(let err):
            return .failure(err)
        case .success:
            if let hotKeyRef {
                context.keys[id] = hotKeyRef
            }
            return .success(())
        }
    }

    func unregister(_ id: ShortcutId) -> Result<Void, ShortcutError> {
        guard let hotKeyRef = context.keys[id] else {
            return .failure(.unknownId)
        }
        let status = UnregisterEventHotKey(hotKeyRef)
        switch shortcutNativeStatus(Int64(status), MAC_SHORTCUT_EXISTS) {
        case .failure(let err):
            return .failure(err)
        case .success:
            context.keys.removeValue(forKey: id)
            return .success(())
        }
    }

    deinit {
        for (_, hotKeyRef) in context.keys {
            _ = UnregisterEventHotKey(hotKeyRef)
        }
        context.keys.removeAll()
        _ = RemoveEventHandler(handlerRef)
    }
}

func macCarbonMods(_ shortcut: Shortcut) -> UInt32 {
    var out: UInt32 = 0
    for (bit, carbon) in [
        (SHORTCUT_SUPER, MAC_CARBON_CMD),
        (SHORTCUT_SHIFT, MAC_CARBON_SHIFT),
        (SHORTCUT_ALT, MAC_CARBON_OPTION),
        (SHORTCUT_CTRL, MAC_CARBON_CONTROL),
    ] {
        if (shortcut.mods & bit) != 0 {
            out |= carbon
        }
    }
    return out
}

/// Default system shortcuts that can be named: (`com.apple.symbolichotkeys` id holding a user's
/// remapping, Carbon key code, Carbon modifiers, owner).
private let MAC_SYSTEM_SHORTCUTS: [(String?, UInt32, UInt32, String)] = [
    ("64", 49, MAC_CARBON_CMD, "Spotlight"),
    ("65", 49, MAC_CARBON_CMD | MAC_CARBON_OPTION, "Finder search"),
    ("60", 49, MAC_CARBON_CONTROL, "Input Sources"),
    ("61", 49, MAC_CARBON_CONTROL | MAC_CARBON_OPTION, "Input Sources"),
    ("28", 20, MAC_CARBON_CMD | MAC_CARBON_SHIFT, "Screenshot"),
    ("29", 20, MAC_CARBON_CONTROL | MAC_CARBON_CMD | MAC_CARBON_SHIFT, "Screenshot"),
    ("30", 21, MAC_CARBON_CMD | MAC_CARBON_SHIFT, "Screenshot"),
    ("31", 21, MAC_CARBON_CONTROL | MAC_CARBON_CMD | MAC_CARBON_SHIFT, "Screenshot"),
    ("184", 23, MAC_CARBON_CMD | MAC_CARBON_SHIFT, "Screenshot"),
    ("32", 126, MAC_CARBON_CONTROL, "Mission Control"),
    ("33", 125, MAC_CARBON_CONTROL, "Mission Control"),
    ("79", 123, MAC_CARBON_CONTROL, "Mission Control"),
    ("81", 124, MAC_CARBON_CONTROL, "Mission Control"),
    (nil, 48, MAC_CARBON_CMD, "App Switcher"),
    (nil, 48, MAC_CARBON_CMD | MAC_CARBON_SHIFT, "App Switcher"),
]

func macShortcutSystemOwner(_ shortcut: Shortcut) -> String? {
    guard Thread.isMainThread,
          let code = macShortcutKeycode(shortcut.keyName())
    else {
        return nil
    }
    let chord = (code, macCarbonMods(shortcut))
    let enabled = macEnabledSymbolicHotKeys()
    guard enabled.contains(where: { $0.0 == chord.0 && $0.1 == chord.1 }) else {
        return nil
    }
    return macNamedSymbolicShortcut(chord, macRemappedSymbolicShortcuts()) ?? "macOS"
}

func macNamedSymbolicShortcut(
    _ chord: (UInt32, UInt32),
    _ remapped: [(String, (UInt32, UInt32)?)]
) -> String? {
    for (id, defCode, defMods, owner) in MAC_SYSTEM_SHORTCUTS {
        let effective: (UInt32, UInt32)?
        if let id, let remapEntry = remapped.first(where: { $0.0 == id }) {
            effective = remapEntry.1
        } else {
            effective = (defCode, defMods)
        }
        if let eff = effective, eff.0 == chord.0 && eff.1 == chord.1 {
            return owner
        }
    }
    return nil
}

private func macEnabledSymbolicHotKeys() -> [(UInt32, UInt32)] {
    var unmanagedArray: Unmanaged<CFArray>? = nil
    guard CopySymbolicHotKeys(&unmanagedArray) == noErr,
          let cfArray = unmanagedArray?.takeRetainedValue() as? [[String: Any]]
    else {
        return []
    }
    var out: [(UInt32, UInt32)] = []
    for dict in cfArray {
        guard (dict["kHISymbolicHotKeyEnabled"] as? Bool) == true,
              let codeNum = dict["kHISymbolicHotKeyCode"] as? NSNumber,
              let modsNum = dict["kHISymbolicHotKeyModifiers"] as? NSNumber
        else {
            continue
        }
        let codeVal = codeNum.int64Value
        guard codeVal >= 0 && codeVal <= Int64(UInt32.max) else { continue }
        let modsVal = UInt32(truncatingIfNeeded: modsNum.int64Value) & MAC_CARBON_MODS_MASK
        out.append((UInt32(codeVal), modsVal))
    }
    return out
}

private func macRemappedSymbolicShortcuts() -> [(String, (UInt32, UInt32)?)] {
    guard let raw = CFPreferencesCopyAppValue(
        "AppleSymbolicHotKeys" as CFString,
        "com.apple.symbolichotkeys" as CFString
    ),
    let all = raw as? [String: Any]
    else {
        return []
    }
    var out: [(String, (UInt32, UInt32)?)] = []
    for (optId, _, _, _) in MAC_SYSTEM_SHORTCUTS {
        guard let id = optId,
              let entry = all[id] as? [String: Any]
        else {
            continue
        }
        let enabled = entry["enabled"] as? Bool
        let params = (entry["value"] as? [String: Any])?["parameters"] as? [NSNumber]
        let code = (params != nil && params!.count > 1) ? params![1].int64Value : nil
        let flags = (params != nil && params!.count > 2) ? params![2].int64Value : nil
        if let remapped = macSymbolicRemap(enabled, code, flags) {
            out.append((id, remapped))
        }
    }
    return out
}

func macSymbolicRemap(_ enabled: Bool?, _ code: Int64?, _ flags: Int64?) -> (UInt32, UInt32)?? {
    if enabled == false {
        return .some(nil)
    }
    guard let code, let flags else {
        return nil
    }
    if code == 65535 {
        return .some(nil)
    }
    return .some((UInt32(truncatingIfNeeded: code), macNsEventModsToCarbon(UInt32(truncatingIfNeeded: flags))))
}

func macNsEventModsToCarbon(_ flags: UInt32) -> UInt32 {
    var mods: UInt32 = 0
    for (bit, carbon) in [
        (UInt32(1 << 17), MAC_CARBON_SHIFT),
        (UInt32(1 << 18), MAC_CARBON_CONTROL),
        (UInt32(1 << 19), MAC_CARBON_OPTION),
        (UInt32(1 << 20), MAC_CARBON_CMD),
    ] {
        if (flags & bit) != 0 {
            mods |= carbon
        }
    }
    return mods
}

func macShortcutKeycode(_ key: String) -> UInt32? {
    switch key {
    case "a": return 0
    case "s": return 1
    case "d": return 2
    case "f": return 3
    case "h": return 4
    case "g": return 5
    case "z": return 6
    case "x": return 7
    case "c": return 8
    case "v": return 9
    case "b": return 11
    case "q": return 12
    case "w": return 13
    case "e": return 14
    case "r": return 15
    case "y": return 16
    case "t": return 17
    case "1": return 18
    case "2": return 19
    case "3": return 20
    case "4": return 21
    case "6": return 22
    case "5": return 23
    case "equal": return 24
    case "9": return 25
    case "7": return 26
    case "minus": return 27
    case "8": return 28
    case "0": return 29
    case "bracketright": return 30
    case "o": return 31
    case "u": return 32
    case "bracketleft": return 33
    case "i": return 34
    case "p": return 35
    case "enter": return 36
    case "l": return 37
    case "j": return 38
    case "quote": return 39
    case "k": return 40
    case "semicolon": return 41
    case "backslash": return 42
    case "comma": return 43
    case "slash": return 44
    case "n": return 45
    case "m": return 46
    case "period": return 47
    case "tab": return 48
    case "space": return 49
    case "backquote": return 50
    case "backspace": return 51
    case "escape": return 53
    case "f17": return 64
    case "f18": return 79
    case "f19": return 80
    case "f20": return 90
    case "f5": return 96
    case "f6": return 97
    case "f7": return 98
    case "f3": return 99
    case "f8": return 100
    case "f9": return 101
    case "f11": return 103
    case "f13": return 105
    case "f16": return 106
    case "f14": return 107
    case "f10": return 109
    case "f12": return 111
    case "f15": return 113
    case "insert": return 114
    case "home": return 115
    case "pageup": return 116
    case "delete": return 117
    case "f4": return 118
    case "end": return 119
    case "f2": return 120
    case "pagedown": return 121
    case "f1": return 122
    case "left": return 123
    case "right": return 124
    case "down": return 125
    case "up": return 126
    default: return nil
    }
}
#endif
