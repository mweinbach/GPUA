// Ported from: crates/gpui_macos/src/events.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(macOS)
import AppKit
import Carbon.HIToolbox
import CoreFoundation
import CoreGraphics
import Foundation
import GPUI

private let backspaceKey: UInt16 = 0x7f
private let spaceKey: UInt16 = 0x20
private let enterKey: UInt16 = 0x0d
private let numpadEnterKey: UInt16 = 0x03
let escapeKey: UInt16 = 0x1b
private let tabKey: UInt16 = 0x09
private let shiftTabKey: UInt16 = 0x19

private let noMod: UInt32 = 0
private let cmdMod: UInt32 = 1
private let shiftMod: UInt32 = 2
private let optionMod: UInt32 = 8

/// Converts a GPUI canonical key name into the corresponding macOS `NSMenuItem.keyEquivalent` string.
public func keyToNative(_ key: String) -> String {
    let code: Int
    switch key {
    case "space": code = Int(spaceKey)
    case "backspace": code = Int(backspaceKey)
    case "escape": code = Int(escapeKey)
    case "up": code = NSUpArrowFunctionKey
    case "down": code = NSDownArrowFunctionKey
    case "left": code = NSLeftArrowFunctionKey
    case "right": code = NSRightArrowFunctionKey
    case "pageup": code = NSPageUpFunctionKey
    case "pagedown": code = NSPageDownFunctionKey
    case "home": code = NSHomeFunctionKey
    case "end": code = NSEndFunctionKey
    case "delete": code = NSDeleteFunctionKey
    case "insert": code = NSHelpFunctionKey
    case "f1": code = NSF1FunctionKey
    case "f2": code = NSF2FunctionKey
    case "f3": code = NSF3FunctionKey
    case "f4": code = NSF4FunctionKey
    case "f5": code = NSF5FunctionKey
    case "f6": code = NSF6FunctionKey
    case "f7": code = NSF7FunctionKey
    case "f8": code = NSF8FunctionKey
    case "f9": code = NSF9FunctionKey
    case "f10": code = NSF10FunctionKey
    case "f11": code = NSF11FunctionKey
    case "f12": code = NSF12FunctionKey
    case "f13": code = NSF13FunctionKey
    case "f14": code = NSF14FunctionKey
    case "f15": code = NSF15FunctionKey
    case "f16": code = NSF16FunctionKey
    case "f17": code = NSF17FunctionKey
    case "f18": code = NSF18FunctionKey
    case "f19": code = NSF19FunctionKey
    case "f20": code = NSF20FunctionKey
    case "f21": code = NSF21FunctionKey
    case "f22": code = NSF22FunctionKey
    case "f23": code = NSF23FunctionKey
    case "f24": code = NSF24FunctionKey
    case "f25": code = NSF25FunctionKey
    case "f26": code = NSF26FunctionKey
    case "f27": code = NSF27FunctionKey
    case "f28": code = NSF28FunctionKey
    case "f29": code = NSF29FunctionKey
    case "f30": code = NSF30FunctionKey
    case "f31": code = NSF31FunctionKey
    case "f32": code = NSF32FunctionKey
    case "f33": code = NSF33FunctionKey
    case "f34": code = NSF34FunctionKey
    case "f35": code = NSF35FunctionKey
    default:
        return key
    }
    var utf16 = UInt16(truncatingIfNeeded: code)
    return String(utf16CodeUnits: &utf16, count: 1)
}

func shouldPreferCharacterInput(_ keystroke: Keystroke) -> Bool {
    keystroke.keyChar != nil
        && !keystroke.modifiers.control
        && !keystroke.modifiers.platform
        && !keystroke.modifiers.function
        && keystroke.key != "enter"
        && keystroke.key != "tab"
}

private func secondaryFnFlag(_ event: NSEvent) -> Bool {
    guard let cgEvent = event.cgEvent else {
        return false
    }
    return cgEvent.flags.contains(.maskSecondaryFn)
}

func readModifiers(_ event: NSEvent) -> Modifiers {
    let flags = event.modifierFlags
    return Modifiers(
        control: flags.contains(.control),
        alt: flags.contains(.option),
        shift: flags.contains(.shift),
        platform: flags.contains(.command),
        function: flags.contains(.function) || secondaryFnFlag(event)
    )
}

private func mouseButtonFromNumber(_ buttonNumber: Int) -> MouseButton? {
    switch buttonNumber {
    case 0: return .left
    case 1: return .right
    case 2: return .middle
    case 3: return .navigate(.back)
    case 4: return .navigate(.forward)
    default: return nil
    }
}

private func touchPhaseFromNative(_ phase: NSEvent.Phase) -> TouchPhase {
    if phase == .mayBegin || phase == .began {
        return .started
    } else if phase == .ended {
        return .ended
    } else {
        return .moved
    }
}

private func mousePosition(
    _ event: NSEvent,
    nativeView: NSView?,
    windowHeight: Pixels?
) -> Point<Pixels>? {
    if let view = nativeView {
        let windowPoint = event.locationInWindow
        return MainActor.assumeIsolated {
            let localPoint = view.convert(windowPoint, from: nil)
            if view.isFlipped {
                return point(px(Float(localPoint.x)), px(Float(localPoint.y)))
            } else {
                let bounds = view.bounds
                return point(px(Float(localPoint.x)), px(Float(bounds.size.height - localPoint.y)))
            }
        }
    } else if let windowHeight {
        let loc = event.locationInWindow
        return point(px(Float(loc.x)), windowHeight - px(Float(loc.y)))
    } else {
        return nil
    }
}

/// Converts an AppKit `NSEvent` into a GPUI `PlatformInput`.
func platformInputFromNative(
    _ nativeEvent: NSEvent,
    windowHeight: Pixels?,
    nativeView: NSView?
) -> PlatformInput? {
    let rawEventType = UInt64(nativeEvent.type.rawValue)
    switch rawEventType {
    case 0, 21, 32, 33, 35, 36, 37:
        return nil
    default:
        break
    }

    switch nativeEvent.type {
    case .flagsChanged:
        return .modifiersChanged(ModifiersChangedEvent(
            modifiers: readModifiers(nativeEvent),
            capslock: Capslock(on: nativeEvent.modifierFlags.contains(.capsLock))
        ))

    case .keyDown:
        let keystroke = parseKeystroke(nativeEvent)
        let preferCharacterInput = shouldPreferCharacterInput(keystroke)
        return .keyDown(KeyDownEvent(
            keystroke: keystroke,
            isHeld: nativeEvent.isARepeat,
            preferCharacterInput: preferCharacterInput
        ))

    case .keyUp:
        return .keyUp(KeyUpEvent(keystroke: parseKeystroke(nativeEvent)))

    case .leftMouseDown, .rightMouseDown, .otherMouseDown:
        guard let button = mouseButtonFromNumber(nativeEvent.buttonNumber),
              let position = mousePosition(nativeEvent, nativeView: nativeView, windowHeight: windowHeight)
        else {
            return nil
        }
        return .mouseDown(MouseDownEvent(
            button: button,
            position: position,
            modifiers: readModifiers(nativeEvent),
            clickCount: max(0, nativeEvent.clickCount),
            firstMouse: false
        ))

    case .leftMouseUp, .rightMouseUp, .otherMouseUp:
        guard let button = mouseButtonFromNumber(nativeEvent.buttonNumber),
              let position = mousePosition(nativeEvent, nativeView: nativeView, windowHeight: windowHeight)
        else {
            return nil
        }
        return .mouseUp(MouseUpEvent(
            button: button,
            position: position,
            modifiers: readModifiers(nativeEvent),
            clickCount: max(0, nativeEvent.clickCount)
        ))

    case .pressure:
        guard let position = mousePosition(nativeEvent, nativeView: nativeView, windowHeight: windowHeight) else {
            return nil
        }
        let stage: PressureStage
        switch nativeEvent.stage {
        case 1: stage = .normal
        case 2: stage = .force
        default: stage = .zero
        }
        return .mousePressure(MousePressureEvent(
            pressure: nativeEvent.pressure,
            stage: stage,
            position: position,
            modifiers: readModifiers(nativeEvent)
        ))

    case .swipe:
        guard nativeEvent.phase == .ended else {
            return nil
        }
        let direction: NavigationDirection
        if nativeEvent.deltaX > 0.0 {
            direction = .back
        } else if nativeEvent.deltaX < 0.0 {
            direction = .forward
        } else {
            return nil
        }
        guard let position = mousePosition(nativeEvent, nativeView: nativeView, windowHeight: windowHeight) else {
            return nil
        }
        return .mouseDown(MouseDownEvent(
            button: .navigate(direction),
            position: position,
            modifiers: readModifiers(nativeEvent),
            clickCount: 1,
            firstMouse: false
        ))

    case .magnify:
        guard let position = mousePosition(nativeEvent, nativeView: nativeView, windowHeight: windowHeight) else {
            return nil
        }
        return .pinch(PinchEvent(
            position: position,
            delta: Float(nativeEvent.magnification),
            modifiers: readModifiers(nativeEvent),
            phase: touchPhaseFromNative(nativeEvent.phase)
        ))

    case .scrollWheel:
        guard let position = mousePosition(nativeEvent, nativeView: nativeView, windowHeight: windowHeight) else {
            return nil
        }
        let rawX = Float(nativeEvent.scrollingDeltaX)
        let rawY = Float(nativeEvent.scrollingDeltaY)
        let delta: ScrollDelta = nativeEvent.hasPreciseScrollingDeltas
            ? .pixels(point(px(rawX), px(rawY)))
            : .lines(point(rawX, rawY))
        return .scrollWheel(ScrollWheelEvent(
            position: position,
            delta: delta,
            modifiers: readModifiers(nativeEvent),
            touchPhase: touchPhaseFromNative(nativeEvent.phase)
        ))

    case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
        guard let pressedButton = mouseButtonFromNumber(nativeEvent.buttonNumber),
              let position = mousePosition(nativeEvent, nativeView: nativeView, windowHeight: windowHeight)
        else {
            return nil
        }
        return .mouseMove(MouseMoveEvent(
            position: position,
            pressedButton: pressedButton,
            modifiers: readModifiers(nativeEvent)
        ))

    case .mouseMoved:
        guard let position = mousePosition(nativeEvent, nativeView: nativeView, windowHeight: windowHeight) else {
            return nil
        }
        return .mouseMove(MouseMoveEvent(
            position: position,
            pressedButton: nil,
            modifiers: readModifiers(nativeEvent)
        ))

    case .mouseExited:
        guard let position = mousePosition(nativeEvent, nativeView: nativeView, windowHeight: windowHeight) else {
            return nil
        }
        return .mouseExited(MouseExitEvent(
            position: position,
            pressedButton: nil,
            modifiers: readModifiers(nativeEvent)
        ))

    default:
        return nil
    }
}

func parseKeystroke(_ nativeEvent: NSEvent) -> Keystroke {
    let characters = nativeEvent.charactersIgnoringModifiers ?? ""
    var keyChar: String? = nil
    let firstChar = characters.unicodeScalars.first.map { Int($0.value) }
    let flags = nativeEvent.modifierFlags

    let control = flags.contains(.control)
    let alt = flags.contains(.option)
    var shift = flags.contains(.shift)
    let command = flags.contains(.command)
    let isFunctionCharRange = firstChar.map { (NSUpArrowFunctionKey ... NSModeSwitchFunctionKey).contains($0) } ?? false
    let function = (flags.contains(.function) || secondaryFnFlag(nativeEvent)) && !isFunctionCharRange

    let key: String
    switch firstChar {
    case Int(spaceKey):
        keyChar = " "
        key = "space"
    case Int(tabKey):
        keyChar = "\t"
        key = "tab"
    case Int(enterKey), Int(numpadEnterKey):
        keyChar = "\n"
        key = "enter"
    case Int(backspaceKey):
        key = "backspace"
    case Int(escapeKey):
        key = "escape"
    case Int(shiftTabKey):
        key = "tab"
    case NSUpArrowFunctionKey:
        key = "up"
    case NSDownArrowFunctionKey:
        key = "down"
    case NSLeftArrowFunctionKey:
        key = "left"
    case NSRightArrowFunctionKey:
        key = "right"
    case NSPageUpFunctionKey:
        key = "pageup"
    case NSPageDownFunctionKey:
        key = "pagedown"
    case NSHomeFunctionKey:
        key = "home"
    case NSEndFunctionKey:
        key = "end"
    case NSDeleteFunctionKey:
        key = "delete"
    case NSHelpFunctionKey:
        key = "insert"
    case NSF1FunctionKey: key = "f1"
    case NSF2FunctionKey: key = "f2"
    case NSF3FunctionKey: key = "f3"
    case NSF4FunctionKey: key = "f4"
    case NSF5FunctionKey: key = "f5"
    case NSF6FunctionKey: key = "f6"
    case NSF7FunctionKey: key = "f7"
    case NSF8FunctionKey: key = "f8"
    case NSF9FunctionKey: key = "f9"
    case NSF10FunctionKey: key = "f10"
    case NSF11FunctionKey: key = "f11"
    case NSF12FunctionKey: key = "f12"
    case NSF13FunctionKey: key = "f13"
    case NSF14FunctionKey: key = "f14"
    case NSF15FunctionKey: key = "f15"
    case NSF16FunctionKey: key = "f16"
    case NSF17FunctionKey: key = "f17"
    case NSF18FunctionKey: key = "f18"
    case NSF19FunctionKey: key = "f19"
    case NSF20FunctionKey: key = "f20"
    case NSF21FunctionKey: key = "f21"
    case NSF22FunctionKey: key = "f22"
    case NSF23FunctionKey: key = "f23"
    case NSF24FunctionKey: key = "f24"
    case NSF25FunctionKey: key = "f25"
    case NSF26FunctionKey: key = "f26"
    case NSF27FunctionKey: key = "f27"
    case NSF28FunctionKey: key = "f28"
    case NSF29FunctionKey: key = "f29"
    case NSF30FunctionKey: key = "f30"
    case NSF31FunctionKey: key = "f31"
    case NSF32FunctionKey: key = "f32"
    case NSF33FunctionKey: key = "f33"
    case NSF34FunctionKey: key = "f34"
    case NSF35FunctionKey: key = "f35"
    default:
        let keyCode = nativeEvent.keyCode
        var charsIgnoringModifiers = charsForModifiedKey(keyCode, modifiers: noMod)
        var charsWithShift = charsForModifiedKey(keyCode, modifiers: shiftMod)
        let useCmdLayout = alwaysUseCommandLayout()

        if command || useCmdLayout {
            let charsWithCmd = charsForModifiedKey(keyCode, modifiers: cmdMod)
            let charsWithBoth = charsForModifiedKey(keyCode, modifiers: cmdMod | shiftMod)

            if charsWithBoth != charsWithCmd {
                charsWithShift = charsWithBoth
            } else {
                let asciiUpper = asciiUppercased(charsWithCmd)
                if asciiUpper != charsWithCmd {
                    charsWithShift = asciiUpper
                }
            }
            charsIgnoringModifiers = charsWithCmd
        }

        if !control && !command && !function {
            var mods = noMod
            if shift {
                mods |= shiftMod
            }
            if alt {
                mods |= optionMod
            }
            keyChar = charsForModifiedKey(keyCode, modifiers: mods)
        }

        let isAllAsciiLower = !charsIgnoringModifiers.isEmpty && charsIgnoringModifiers.unicodeScalars.allSatisfy {
            $0.value >= 97 && $0.value <= 122
        }
        if shift && isAllAsciiLower {
            key = charsIgnoringModifiers
        } else if shift {
            shift = false
            key = charsWithShift
        } else {
            key = charsIgnoringModifiers
        }
    }

    return Keystroke(
        modifiers: Modifiers(
            control: control,
            alt: alt,
            shift: shift,
            platform: command,
            function: function
        ),
        key: key,
        keyChar: keyChar,
        nativeKeyCode: nativeEvent.keyCode
    )
}

private func asciiUppercased(_ str: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in str.unicodeScalars {
        if scalar.value >= 97 && scalar.value <= 122,
           let upper = UnicodeScalar(scalar.value - 32)
        {
            scalars.append(upper)
        } else {
            scalars.append(scalar)
        }
    }
    return String(scalars)
}

private func isAllAscii(_ str: String) -> Bool {
    str.unicodeScalars.allSatisfy { $0.isASCII }
}

private func alwaysUseCommandLayout() -> Bool {
    if isAllAscii(charsForModifiedKey(0, modifiers: noMod)) {
        return false
    }
    return isAllAscii(charsForModifiedKey(0, modifiers: cmdMod))
}

func charsForModifiedKey(_ code: CGKeyCode, modifiers: UInt32) -> String {
    let cgSpaceKey: UInt16 = 49
    let keyActionDown: UInt16 = UInt16(kUCKeyActionDown)
    let translateOptions: OptionBits = 0

    guard let keyboard = copyCurrentKeyboardLayoutInputSource(),
          let rawDataPtr = TISGetInputSourceProperty(keyboard, kTISPropertyUnicodeKeyLayoutData)
    else {
        return ""
    }

    let cfData = Unmanaged<CFData>.fromOpaque(rawDataPtr).takeUnretainedValue()
    guard let bytePtr = CFDataGetBytePtr(cfData) else {
        return ""
    }

    let keyboardType = UInt32(LMGetKbdType())
    return bytePtr.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layoutPtr in
        var deadKeyState: UInt32 = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        var bufferSize: Int = 0

        _ = UCKeyTranslate(
            layoutPtr,
            code,
            keyActionDown,
            modifiers,
            keyboardType,
            translateOptions,
            &deadKeyState,
            buffer.count,
            &bufferSize,
            &buffer
        )
        if deadKeyState != 0 {
            _ = UCKeyTranslate(
                layoutPtr,
                cgSpaceKey,
                keyActionDown,
                modifiers,
                keyboardType,
                translateOptions,
                &deadKeyState,
                buffer.count,
                &bufferSize,
                &buffer
            )
        }

        guard bufferSize > 0 else {
            return ""
        }
        return String(utf16CodeUnits: buffer, count: bufferSize)
    }
}
#endif
