// Ported from: crates/rune/src/shortcuts/layout_macos.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import Carbon
import CoreFoundation
import Darwin
import Foundation

private let macLayoutForcedLock = LiveLock()
// PORT NOTE: Keyed by `pthread_self()` and guarded by `macLayoutForcedLock` to provide thread-local layout overrides for tests, matching upstream `thread_local! { FORCED }`.
nonisolated(unsafe) private var macForcedLayouts: [UInt: @Sendable (UInt32, UInt32) -> String?] = [:]

/// Tests: translate labels on this thread with `layout` (Carbon key, modifiers) instead of
/// the current input source, or stop with `nil`.
func forceMacKeyboardLayout(_ layout: (@Sendable (UInt32, UInt32) -> String?)?) {
    let tid = UInt(bitPattern: pthread_self())
    macLayoutForcedLock.withLock {
        macForcedLayouts[tid] = layout
    }
}

/// The label for `key` pressed with Carbon `modifiers` (`cmdKey`, `shiftKey`, ...).
func macLayoutLabel(_ key: UInt32, _ modifiers: UInt32) -> String? {
    let tid = UInt(bitPattern: pthread_self())
    let forced = macLayoutForcedLock.withLock { macForcedLayouts[tid] }
    if let forced {
        return forced(key, modifiers)
    }
    // AppKit also calls TIS. Stay on the UI thread; background/headless callers get the US fallback.
    guard pthread_main_np() != 0 else { return nil }
    guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
        return nil
    }
    guard let rawData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
        return nil
    }
    let data = unsafeBitCast(rawData, to: CFData.self)
    guard let bytePtr = CFDataGetBytePtr(data) else {
        return nil
    }
    return bytePtr.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layoutPtr in
        macChordLabel(layoutPtr, key, modifiers)
    }
}

private let CARBON_CMD_MOD: UInt32 = 1 << 8
private let CARBON_CONTROL_MOD: UInt32 = 1 << 12

func macChordLabel(_ layout: UnsafePointer<UCKeyboardLayout>, _ key: UInt32, _ modifiers: UInt32) -> String? {
    let masked = modifiers & (CARBON_CMD_MOD | CARBON_CONTROL_MOD)
    for state in [masked, masked & ~CARBON_CONTROL_MOD, 0] {
        if let label = macTranslateKey(layout, key, state) {
            return label
        }
    }
    return nil
}

func macTranslateKey(_ layout: UnsafePointer<UCKeyboardLayout>, _ key: UInt32, _ modifiers: UInt32) -> String? {
    var chars = [UniChar](repeating: 0, count: 16)
    var actualLength: Int = 0
    var deadKeyState: UInt32 = 0
    let status = chars.withUnsafeMutableBufferPointer { buf in
        UCKeyTranslate(
            layout,
            UInt16(key),
            UInt16(kUCKeyActionDisplay),
            (modifiers >> 8) & 0xFF,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysMask),
            &deadKeyState,
            buf.count,
            &actualLength,
            buf.baseAddress!
        )
    }
    guard status == noErr, actualLength > 0, actualLength <= chars.count else {
        return nil
    }
    let str = String(utf16CodeUnits: chars, count: actualLength)
    let hasControl = str.unicodeScalars.contains { scalar in
        scalar.value < 0x20 || (scalar.value >= 0x7F && scalar.value <= 0x9F)
    }
    return hasControl ? nil : str
}
#endif
