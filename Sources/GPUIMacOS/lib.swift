// Ported from: crates/gpui_macos/src/lib.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(macOS)
import AppKit
import Carbon.HIToolbox
import CoreFoundation
import CoreGraphics
import Foundation
import GPUI
import GPUIMetal

public typealias RendererContext = GPUIMetal.Context
public typealias Renderer = GPUIMetal.Renderer

/// Returns the macOS `Platform` implementation.
public func currentPlatform(headless: Bool = false) -> MacPlatform {
    MacPlatform.new(headless: headless)
}

// MARK: - NSRange Conversions

extension NSRange {
    /// Returns `{NSNotFound, 0}` matching upstream `NSRange::invalid()`.
    static var invalid: NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    /// Returns whether this range is valid (`location != NSNotFound`).
    var isValid: Bool {
        location != NSNotFound
    }

    /// Converts an `NSRange` into a Swift `Range<Int>` if valid.
    func toRange() -> Range<Int>? {
        guard location != NSNotFound, location >= 0, length >= 0 else {
            return nil
        }
        return location ..< (location + length)
    }

    /// Creates an `NSRange` from a Swift `Range<Int>`.
    init(gpuiRange range: Range<Int>) {
        self.init(location: range.lowerBound, length: range.count)
    }
}

// MARK: - Carbon Text Input Source Helpers

/// Copies the current keyboard input source (`TISCopyCurrentKeyboardInputSource`).
func copyCurrentKeyboardInputSource() -> TISInputSource? {
    guard let unmanaged = TISCopyCurrentKeyboardInputSource() else {
        return nil
    }
    return unmanaged.takeRetainedValue()
}

/// Copies the current keyboard layout input source (`TISCopyCurrentKeyboardLayoutInputSource`).
func copyCurrentKeyboardLayoutInputSource() -> TISInputSource? {
    guard let unmanaged = TISCopyCurrentKeyboardLayoutInputSource() else {
        return nil
    }
    return unmanaged.takeRetainedValue()
}

/// Reads a `CFString` property from a `TISInputSource`.
func inputSourceStringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
    guard let rawPtr = TISGetInputSourceProperty(source, key) else {
        return nil
    }
    let cfStr = Unmanaged<CFString>.fromOpaque(rawPtr).takeUnretainedValue()
    return cfStr as String
}

/// Reads a `CFBoolean` property from a `TISInputSource`.
func inputSourceBoolProperty(_ source: TISInputSource, _ key: CFString) -> Bool {
    guard let rawPtr = TISGetInputSourceProperty(source, key) else {
        return false
    }
    let cfBool = Unmanaged<CFBoolean>.fromOpaque(rawPtr).takeUnretainedValue()
    return CFBooleanGetValue(cfBool)
}

/// Translates a virtual key code and Carbon modifier state via `UCKeyTranslate`.
func translateKeyWithUCKeyTranslate(
    source: TISInputSource,
    keyCode: UInt16,
    modifierKeyState: UInt32,
    keyAction: UInt16,
    translateOptions: OptionBits = OptionBits(kUCKeyTranslateNoDeadKeysMask)
) -> String? {
    guard let rawDataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
        return nil
    }
    let cfData = Unmanaged<CFData>.fromOpaque(rawDataPtr).takeUnretainedValue()
    guard let bytePtr = CFDataGetBytePtr(cfData) else {
        return nil
    }
    return bytePtr.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layoutPtr in
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 8)
        var actualLength: Int = 0
        let status = UCKeyTranslate(
            layoutPtr,
            keyCode,
            keyAction,
            modifierKeyState,
            UInt32(LMGetKbdType()),
            translateOptions,
            &deadKeyState,
            chars.count,
            &actualLength,
            &chars
        )
        guard status == noErr, actualLength > 0 else {
            return nil
        }
        return String(utf16CodeUnits: chars, count: actualLength)
    }
}
#endif
