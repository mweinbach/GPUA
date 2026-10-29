// Ported from: crates/gpui_linux/src/linux/x11/event.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux)
import GPUI

public enum ButtonOrScroll: Equatable, Sendable {
    case button(MouseButton)
    case scroll(ScrollDirection)
}

public enum ScrollDirection: Equatable, Sendable {
    case up
    case down
    case left
    case right
}

public func buttonOrScrollFromEventDetail(_ detail: UInt32) -> ButtonOrScroll? {
    switch detail {
    case 1:
        return .button(.left)
    case 2:
        return .button(.middle)
    case 3:
        return .button(.right)
    case 4:
        return .scroll(.up)
    case 5:
        return .scroll(.down)
    case 6:
        return .scroll(.left)
    case 7:
        return .scroll(.right)
    case 8:
        return .button(.navigate(.back))
    case 9:
        return .button(.navigate(.forward))
    default:
        return nil
    }
}

// X11 standard modifier masks
public let x11ShiftMask: UInt32 = 1 << 0
public let x11LockMask: UInt32 = 1 << 1
public let x11ControlMask: UInt32 = 1 << 2
public let x11Mod1Mask: UInt32 = 1 << 3 // Alt
public let x11Mod2Mask: UInt32 = 1 << 4
public let x11Mod3Mask: UInt32 = 1 << 5
public let x11Mod4Mask: UInt32 = 1 << 6 // Super / Platform
public let x11Mod5Mask: UInt32 = 1 << 7

public func modifiersFromState(_ state: UInt32) -> Modifiers {
    Modifiers(
        control: (state & x11ControlMask) != 0,
        alt: (state & x11Mod1Mask) != 0,
        shift: (state & x11ShiftMask) != 0,
        platform: (state & x11Mod4Mask) != 0,
        function: false
    )
}

public struct XInputModifierInfo: Sendable, Equatable {
    public var effective: UInt32

    public init(effective: UInt32 = 0) {
        self.effective = effective
    }
}

public func modifiersFromXinputInfo(_ modifierInfo: XInputModifierInfo) -> Modifiers {
    modifiersFromXinputInfo(effective: modifierInfo.effective)
}

public func modifiersFromXinputInfo(effective: UInt32) -> Modifiers {
    Modifiers(
        control: (effective & x11ControlMask) != 0,
        alt: (effective & x11Mod1Mask) != 0,
        shift: (effective & x11ShiftMask) != 0,
        platform: (effective & x11Mod4Mask) != 0,
        function: false
    )
}

public func pressedButtonFromMask(_ buttonMask: UInt32) -> MouseButton? {
    if (buttonMask & 2) == 2 {
        return .left
    } else if (buttonMask & 4) == 4 {
        return .middle
    } else if (buttonMask & 8) == 8 {
        return .right
    } else {
        return nil
    }
}

public func getValuatorAxisIndex(_ valuatorMask: [UInt32], _ valuatorNumber: UInt16) -> Int? {
    if bitIsSetInVec(valuatorMask, valuatorNumber) {
        return Int(popcountUptoBitIndex(valuatorMask, valuatorNumber))
    } else {
        return nil
    }
}

private func popcountUptoBitIndex(_ bitVec: [UInt32], _ bitIndex: UInt16) -> UInt32 {
    let arrayIndex = Int(bitIndex) / 32
    let popcount: UInt32
    if arrayIndex < bitVec.count {
        popcount = UInt32(keepBitsUpto(bitVec[arrayIndex], bitIndex % 32).nonzeroBitCount)
    } else {
        popcount = 0
    }

    if arrayIndex == 0 {
        return popcount
    } else {
        let leadingCount = bitVec.prefix(arrayIndex).reduce(0 as UInt32) { $0 + UInt32($1.nonzeroBitCount) }
        return popcount + leadingCount
    }
}

private func bitIsSetInVec(_ bitVec: [UInt32], _ bitIndex: UInt16) -> Bool {
    let arrayIndex = Int(bitIndex) / 32
    guard arrayIndex < bitVec.count else { return false }
    return bitIsSet(bitVec[arrayIndex], bitIndex % 32)
}

private func bitIsSet(_ bits: UInt32, _ bitIndex: UInt16) -> Bool {
    (bits & (1 << UInt32(bitIndex))) != 0
}

private func keepBitsUpto(_ bits: UInt32, _ bitIndex: UInt16) -> UInt32 {
    if bitIndex == 0 {
        return 0
    } else if bitIndex >= 32 {
        return UInt32.max
    } else {
        return bits & ((1 << UInt32(bitIndex)) - 1)
    }
}
#endif
