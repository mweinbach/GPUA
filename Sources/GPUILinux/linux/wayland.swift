// Ported from: crates/gpui_linux/src/linux/wayland.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux)
import Foundation
import GPUI

public enum CursorShape: UInt32, Sendable {
    case `default` = 1
    case contextMenu = 2
    case help = 3
    case pointer = 4
    case progress = 5
    case wait = 6
    case cell = 7
    case crosshair = 8
    case text = 9
    case verticalText = 10
    case alias = 11
    case copy = 12
    case move = 13
    case noDrop = 14
    case notAllowed = 15
    case grab = 16
    case grabbing = 17
    case eResize = 18
    case nResize = 19
    case neResize = 20
    case nwResize = 21
    case sResize = 22
    case seResize = 23
    case swResize = 24
    case wResize = 25
    case ewResize = 26
    case nsResize = 27
    case neswResize = 28
    case nwseResize = 29
    case colResize = 30
    case rowResize = 31
    case allScroll = 32
    case zoomIn = 33
    case zoomOut = 34
}

public func toShape(_ style: CursorStyle) -> CursorShape {
    switch style {
    case .arrow:
        return .default
    case .iBeam:
        return .text
    case .crosshair:
        return .crosshair
    case .closedHand:
        return .grabbing
    case .openHand:
        return .grab
    case .pointingHand:
        return .pointer
    case .resizeLeft:
        return .wResize
    case .resizeRight:
        return .eResize
    case .resizeLeftRight:
        return .ewResize
    case .resizeUp:
        return .nResize
    case .resizeDown:
        return .sResize
    case .resizeUpDown:
        return .nsResize
    case .resizeUpLeft, .resizeDownRight, .resizeUpLeftDownRight:
        return .nwseResize
    case .resizeUpRight, .resizeDownLeft, .resizeUpRightDownLeft:
        return .neswResize
    case .notAllowed:
        return .notAllowed
    case .wait:
        return .wait
    case .progress:
        return .progress
    case .copy:
        return .copy
    case .none:
        return .default
    }
}
#endif
