// Ported from: crates/gpui_web/src/events.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
import GPUI
#if os(WASI)
import CWebSys
#endif

/// DOM `WheelEvent.deltaMode` constants.
public let DOM_DELTA_PIXEL: UInt32 = 0
public let DOM_DELTA_LINE: UInt32 = 1
public let DOM_DELTA_PAGE: UInt32 = 2

/// Bitmask flags used to pack DOM modifier keys across the Wasm host bridge.
public let WEB_MOD_CONTROL: UInt32 = 1 << 0
public let WEB_MOD_ALT: UInt32 = 1 << 1
public let WEB_MOD_SHIFT: UInt32 = 1 << 2
public let WEB_MOD_PLATFORM: UInt32 = 1 << 3
public let WEB_MOD_FUNCTION: UInt32 = 1 << 4
public let WEB_MOD_CAPSLOCK: UInt32 = 1 << 5

/// Active DOM listener registration handle retained by `WebWindow`.
public struct WebEventListeners: Sendable {
    let windowId: UInt32
    private(set) var isRegistered: Bool

    init(windowId: UInt32, isRegistered: Bool = true) {
        self.windowId = windowId
        self.isRegistered = isRegistered
    }
}

/// Tracks multi-click sequences using upstream GPUI's 400 ms / 5 px threshold.
struct ClickState: Sendable, Equatable {
    var lastPosition: Point<Pixels>
    var lastTime: Double
    var currentCount: Int

    init(
        lastPosition: Point<Pixels> = .zero,
        lastTime: Double = 0.0,
        currentCount: Int = 0
    ) {
        self.lastPosition = lastPosition
        self.lastTime = lastTime
        self.currentCount = currentCount
    }

    static func `default`() -> ClickState {
        ClickState()
    }

    mutating func registerClick(_ position: Point<Pixels>, _ time: Double) -> Int {
        let dx = position.x.value - lastPosition.x.value
        let dy = position.y.value - lastPosition.y.value
        let distance = (dx * dx + dy * dy).squareRoot()

        if (time - lastTime) < 400.0 && distance < 5.0 {
            currentCount += 1
        } else {
            currentCount = 1
        }

        lastPosition = position
        lastTime = time
        return currentCount
    }
}

// MARK: - Pure DOM -> GPUI Translation Helpers

func domKeyToGpuiKey(_ key: String) -> String {
    switch key {
    case "Enter": return "enter"
    case "Backspace": return "backspace"
    case "Tab": return "tab"
    case "Escape": return "escape"
    case "Delete": return "delete"
    case " ": return "space"
    case "ArrowLeft": return "left"
    case "ArrowRight": return "right"
    case "ArrowUp": return "up"
    case "ArrowDown": return "down"
    case "Home": return "home"
    case "End": return "end"
    case "PageUp": return "pageup"
    case "PageDown": return "pagedown"
    case "Insert": return "insert"
    case "Control": return "control"
    case "Alt": return "alt"
    case "Shift": return "shift"
    case "Meta": return "platform"
    case "CapsLock": return "capslock"
    default:
        if key.hasPrefix("F") {
            let rest = key.dropFirst()
            if let number = UInt8(rest), (1...35).contains(number) {
                return "f\(number)"
            }
        }
        return key.lowercased()
    }
}

func domMouseButtonToGpui(_ button: Int16) -> MouseButton {
    switch button {
    case 0: return .left
    case 1: return .middle
    case 2: return .right
    case 3: return .navigate(.back)
    case 4: return .navigate(.forward)
    default: return .left
    }
}

func modifiersFromFlags(_ flags: UInt32, isMac: Bool = false) -> Modifiers {
    _ = isMac
    return Modifiers(
        control: (flags & WEB_MOD_CONTROL) != 0,
        alt: (flags & WEB_MOD_ALT) != 0,
        shift: (flags & WEB_MOD_SHIFT) != 0,
        platform: (flags & WEB_MOD_PLATFORM) != 0,
        function: (flags & WEB_MOD_FUNCTION) != 0
    )
}

func capslockFromFlags(_ flags: UInt32) -> Capslock {
    Capslock(on: (flags & WEB_MOD_CAPSLOCK) != 0)
}

func isMacPlatform(platform: String? = nil, userAgent: String? = nil) -> Bool {
    if let platform, platform.contains("Mac") {
        return true
    }
    if let userAgent {
        return userAgent.contains("Mac")
    }
    #if os(WASI)
    return cwebsys_is_mac_platform()
    #elseif os(macOS)
    return true
    #else
    return false
    #endif
}

func isModifierOnlyKey(_ key: String) -> Bool {
    switch key {
    case "control", "alt", "shift", "platform", "capslock", "compose", "process":
        return true
    default:
        return false
    }
}

func computeKeyChar(
    rawKey: String,
    gpuiKey: String,
    modifiers: Modifiers
) -> String? {
    if modifiers.platform || modifiers.control {
        return nil
    }

    if isModifierOnlyKey(gpuiKey) {
        return nil
    }

    if gpuiKey == "space" {
        return " "
    }

    if rawKey.count == 1 {
        return rawKey
    }

    return nil
}

func wheelDeltaToGpui(
    deltaX: Double,
    deltaY: Double,
    deltaMode: UInt32,
    pageSize: Size<Pixels>? = nil
) -> ScrollDelta {
    if deltaMode == DOM_DELTA_LINE {
        return .lines(Point(x: Float(-deltaX), y: Float(-deltaY)))
    }
    if deltaMode == DOM_DELTA_PAGE, let pageSize, pageSize.width.value > 0, pageSize.height.value > 0 {
        return .pixels(Point(
            x: px(Float(-deltaX) * pageSize.width.value),
            y: px(Float(-deltaY) * pageSize.height.value)
        ))
    }
    return .pixels(Point(
        x: px(Float(-deltaX)),
        y: px(Float(-deltaY))
    ))
}

// MARK: - WebWindowInner Event Dispatch

extension WebWindowInner {
    public func registerEventListeners() -> WebEventListeners {
        _ = registerVisibilityChange()
        _ = registerAppearanceChange()
        return WebEventListeners(windowId: windowId, isRegistered: true)
    }

    @discardableResult
    func dispatchInput(_ input: PlatformInput) -> DispatchEventResult? {
        callbacks.input?(input)
    }

    func handlePointerDown(
        button rawButton: Int16,
        position: Point<Pixels>,
        modifiersFlags: UInt32,
        timestampMs: Double
    ) {
        #if os(WASI)
        cwebsys_focus_input(windowId)
        #endif

        let button = domMouseButtonToGpui(rawButton)
        let modifiers = modifiersFromFlags(modifiersFlags, isMac: isMac)
        pressedButton = button
        let clickCount = clickState.registerClick(position, timestampMs)

        state.mousePosition = position
        state.modifiers = modifiers

        _ = dispatchInput(.mouseDown(MouseDownEvent(
            button: button,
            position: position,
            modifiers: modifiers,
            clickCount: clickCount,
            firstMouse: false
        )))
    }

    func handlePointerUp(
        button rawButton: Int16,
        position: Point<Pixels>,
        modifiersFlags: UInt32
    ) {
        let button = domMouseButtonToGpui(rawButton)
        let modifiers = modifiersFromFlags(modifiersFlags, isMac: isMac)

        pressedButton = nil
        let clickCount = max(clickState.currentCount, 1)

        state.mousePosition = position
        state.modifiers = modifiers

        _ = dispatchInput(.mouseUp(MouseUpEvent(
            button: button,
            position: position,
            modifiers: modifiers,
            clickCount: clickCount
        )))
    }

    func handlePointerMove(
        position: Point<Pixels>,
        modifiersFlags: UInt32
    ) {
        let modifiers = modifiersFromFlags(modifiersFlags, isMac: isMac)
        let currentPressed = pressedButton

        state.mousePosition = position
        state.modifiers = modifiers

        _ = dispatchInput(.mouseMove(MouseMoveEvent(
            position: position,
            pressedButton: currentPressed,
            modifiers: modifiers
        )))
    }

    func handlePointerEnter() {
        state.isHovered = true
        callbacks.hoverStatusChange?(true)
    }

    func handlePointerLeave(
        position: Point<Pixels>,
        modifiersFlags: UInt32
    ) {
        let modifiers = modifiersFromFlags(modifiersFlags, isMac: isMac)
        let currentPressed = pressedButton

        state.mousePosition = position
        state.modifiers = modifiers
        state.isHovered = false

        _ = dispatchInput(.mouseExited(MouseExitEvent(
            position: position,
            pressedButton: currentPressed,
            modifiers: modifiers
        )))
        callbacks.hoverStatusChange?(false)
    }

    func handleWheel(
        position: Point<Pixels>,
        deltaX: Double,
        deltaY: Double,
        deltaMode: UInt32,
        modifiersFlags: UInt32
    ) {
        let modifiers = modifiersFromFlags(modifiersFlags, isMac: isMac)
        let delta = wheelDeltaToGpui(
            deltaX: deltaX,
            deltaY: deltaY,
            deltaMode: deltaMode,
            pageSize: state.bounds.size
        )

        state.modifiers = modifiers

        _ = dispatchInput(.scrollWheel(ScrollWheelEvent(
            position: position,
            delta: delta,
            modifiers: modifiers,
            touchPhase: .moved
        )))
    }

    func handleDragOver(position: Point<Pixels>) {
        state.mousePosition = position
        _ = dispatchInput(.fileDrop(.pending(position: position)))
    }

    func handleDrop(position: Point<Pixels>, fileNames: [String]) {
        state.mousePosition = position
        _ = dispatchInput(.fileDrop(.entered(
            position: position,
            paths: ExternalPaths(paths: fileNames)
        )))
        _ = dispatchInput(.fileDrop(.submit(position: position)))
    }

    func handleDragLeave() {
        _ = dispatchInput(.fileDrop(.exited))
    }

    /// Processes a DOM `keydown` event. Returns `true` if `event.preventDefault()` should be called.
    @discardableResult
    func handleKeyDown(
        rawKey: String,
        code: String = "",
        modifiersFlags: UInt32,
        isRepeat: Bool,
        eventIsComposing: Bool
    ) -> Bool {
        _ = code
        let modifiers = modifiersFromFlags(modifiersFlags, isMac: isMac)
        let capslock = capslockFromFlags(modifiersFlags)

        state.modifiers = modifiers
        state.capslock = capslock

        _ = dispatchInput(.modifiersChanged(ModifiersChangedEvent(
            modifiers: modifiers,
            capslock: capslock
        )))

        let key = domKeyToGpuiKey(rawKey)
        if isModifierOnlyKey(key) {
            return false
        }

        let keyChar = computeKeyChar(rawKey: rawKey, gpuiKey: key, modifiers: modifiers)
        let keystroke = Keystroke(
            modifiers: modifiers,
            key: key,
            keyChar: keyChar,
            nativeKeyCode: nil
        )

        let result = dispatchInput(.keyDown(KeyDownEvent(
            keystroke: keystroke,
            isHeld: isRepeat,
            preferCharacterInput: false
        )))

        if let result, !result.propagate {
            return true
        }

        if isComposing || eventIsComposing {
            return true
        }

        if modifiers.isSubset(of: .shift()), let text = keyChar {
            _ = withInputHandler { handler in
                handler.replaceTextInRange(rangeUtf16: nil, text: text)
            }
        }

        return true
    }

    /// Processes a DOM `keyup` event. Returns `true` if `event.preventDefault()` should be called.
    @discardableResult
    func handleKeyUp(
        rawKey: String,
        code: String = "",
        modifiersFlags: UInt32
    ) -> Bool {
        _ = code
        let modifiers = modifiersFromFlags(modifiersFlags, isMac: isMac)
        let capslock = capslockFromFlags(modifiersFlags)

        state.modifiers = modifiers
        state.capslock = capslock

        _ = dispatchInput(.modifiersChanged(ModifiersChangedEvent(
            modifiers: modifiers,
            capslock: capslock
        )))

        let key = domKeyToGpuiKey(rawKey)
        if isModifierOnlyKey(key) {
            return false
        }

        let keyChar = computeKeyChar(rawKey: rawKey, gpuiKey: key, modifiers: modifiers)
        let keystroke = Keystroke(
            modifiers: modifiers,
            key: key,
            keyChar: keyChar,
            nativeKeyCode: nil
        )

        _ = dispatchInput(.keyUp(KeyUpEvent(keystroke: keystroke)))
        return true
    }

    func handleCompositionStart() {
        isComposing = true
    }

    func handleCompositionUpdate(data: String) {
        isComposing = true
        _ = withInputHandler { handler in
            handler.replaceAndMarkTextInRange(
                rangeUtf16: nil,
                newText: data,
                newSelectedRange: nil
            )
        }
    }

    func handleCompositionEnd(data: String) {
        isComposing = false
        _ = withInputHandler { handler in
            handler.replaceTextInRange(rangeUtf16: nil, text: data)
            handler.unmarkText()
        }
        #if os(WASI)
        cwebsys_clear_input_value(windowId)
        #endif
    }

    func handleFocus() {
        state.isActive = true
        callbacks.activeStatusChange?(true)
    }

    func handleBlur() {
        state.isActive = false
        callbacks.activeStatusChange?(false)
    }
}
