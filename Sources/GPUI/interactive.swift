// Ported from: crates/gpui/src/interactive.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

/// An event from a platform input source.
public protocol InputEvent: Sendable {
    /// Convert this event into the platform input enum.
    func toPlatformInput() -> PlatformInput
}

/// A key event from the platform.
public protocol KeyEvent: InputEvent {}

/// A mouse event from the platform.
public protocol MouseEvent: InputEvent {}

/// The key down event equivalent for the platform.
public struct KeyDownEvent: KeyEvent, Sendable, Equatable {
    /// The keystroke that was generated.
    public var keystroke: Keystroke

    /// Whether the key is currently held down.
    public var isHeld: Bool

    /// Whether to prefer character input over keybindings for this keystroke.
    public var preferCharacterInput: Bool

    public init(
        keystroke: Keystroke,
        isHeld: Bool = false,
        preferCharacterInput: Bool = false
    ) {
        self.keystroke = keystroke
        self.isHeld = isHeld
        self.preferCharacterInput = preferCharacterInput
    }

    public func toPlatformInput() -> PlatformInput {
        .keyDown(self)
    }
}

/// The key up event equivalent for the platform.
public struct KeyUpEvent: KeyEvent, Sendable, Equatable {
    /// The keystroke that was released.
    public var keystroke: Keystroke

    public init(keystroke: Keystroke) {
        self.keystroke = keystroke
    }

    public func toPlatformInput() -> PlatformInput {
        .keyUp(self)
    }
}

/// The modifiers changed event equivalent for the platform.
public struct ModifiersChangedEvent: KeyEvent, Sendable, Equatable {
    /// The new state of the modifier keys.
    public var modifiers: Modifiers

    /// The new state of the capslock key.
    public var capslock: Capslock

    public init(modifiers: Modifiers = Modifiers.none(), capslock: Capslock = Capslock()) {
        self.modifiers = modifiers
        self.capslock = capslock
    }

    public func toPlatformInput() -> PlatformInput {
        .modifiersChanged(self)
    }
}

/// The phase of a touch motion event.
public enum TouchPhase: Sendable, Equatable, Hashable, CaseIterable {
    case started
    case moved
    case ended
}

/// A navigation direction, such as back or forward.
public enum NavigationDirection: Sendable, Equatable, Hashable, CaseIterable {
    case back
    case forward
}

/// An enum representing the mouse button that was pressed.
public enum MouseButton: Sendable, Equatable, Hashable {
    case left
    case right
    case middle
    case navigate(NavigationDirection)

    public static func all() -> [MouseButton] {
        [
            .left,
            .right,
            .middle,
            .navigate(.back),
            .navigate(.forward),
        ]
    }
}

/// A mouse down event from the platform.
public struct MouseDownEvent: MouseEvent, Sendable, Equatable {
    public var button: MouseButton
    public var position: Point<Pixels>
    public var modifiers: Modifiers
    public var clickCount: Int
    public var firstMouse: Bool

    public init(
        button: MouseButton = .left,
        position: Point<Pixels> = .zero,
        modifiers: Modifiers = Modifiers.none(),
        clickCount: Int = 1,
        firstMouse: Bool = false
    ) {
        self.button = button
        self.position = position
        self.modifiers = modifiers
        self.clickCount = clickCount
        self.firstMouse = firstMouse
    }

    public var isFocusing: Bool {
        button == .left
    }

    public func toPlatformInput() -> PlatformInput {
        .mouseDown(self)
    }
}

/// A mouse up event from the platform.
public struct MouseUpEvent: MouseEvent, Sendable, Equatable {
    public var button: MouseButton
    public var position: Point<Pixels>
    public var modifiers: Modifiers
    public var clickCount: Int

    public init(
        button: MouseButton = .left,
        position: Point<Pixels> = .zero,
        modifiers: Modifiers = Modifiers.none(),
        clickCount: Int = 1
    ) {
        self.button = button
        self.position = position
        self.modifiers = modifiers
        self.clickCount = clickCount
    }

    public var isFocusing: Bool {
        button == .left
    }

    public func toPlatformInput() -> PlatformInput {
        .mouseUp(self)
    }
}

/// A click event, generated when a mouse button is pressed and released.
public struct MouseClickEvent: Sendable, Equatable {
    public var down: MouseDownEvent
    public var up: MouseUpEvent

    public init(down: MouseDownEvent = MouseDownEvent(), up: MouseUpEvent = MouseUpEvent()) {
        self.down = down
        self.up = up
    }
}

/// The stage of a pressure click event.
public enum PressureStage: Sendable, Equatable, Hashable, CaseIterable {
    case zero
    case normal
    case force
}

/// A mouse pressure event from the platform.
public struct MousePressureEvent: MouseEvent, Sendable, Equatable {
    public var pressure: Float
    public var stage: PressureStage
    public var position: Point<Pixels>
    public var modifiers: Modifiers

    public init(
        pressure: Float = 0,
        stage: PressureStage = .zero,
        position: Point<Pixels> = .zero,
        modifiers: Modifiers = Modifiers.none()
    ) {
        self.pressure = pressure
        self.stage = stage
        self.position = position
        self.modifiers = modifiers
    }

    public func toPlatformInput() -> PlatformInput {
        .mousePressure(self)
    }
}

/// An enum representing the keyboard button that was pressed for a click event.
public enum KeyboardButton: Sendable, Equatable, Hashable, CaseIterable {
    case enter
    case space
}

/// A click event that was generated by a keyboard button being pressed and released.
public struct KeyboardClickEvent: Sendable, Equatable {
    public var button: KeyboardButton
    public var bounds: Bounds<Pixels>

    public init(button: KeyboardButton = .enter, bounds: Bounds<Pixels> = .zero) {
        self.button = button
        self.bounds = bounds
    }
}

/// A click event, generated when a mouse button or keyboard button is pressed and released.
public enum ClickEvent: Sendable, Equatable {
    case mouse(MouseClickEvent)
    case keyboard(KeyboardClickEvent)

    public var modifiers: Modifiers {
        switch self {
        case .keyboard:
            return Modifiers.none()
        case .mouse(let event):
            return event.up.modifiers
        }
    }

    public var position: Point<Pixels> {
        switch self {
        case .keyboard(let event):
            return event.bounds.bottomLeft
        case .mouse(let event):
            return event.up.position
        }
    }

    public var mousePosition: Point<Pixels>? {
        switch self {
        case .keyboard:
            return nil
        case .mouse(let event):
            return event.up.position
        }
    }

    public var isRightClick: Bool {
        switch self {
        case .keyboard:
            return false
        case .mouse(let event):
            return event.down.button == .right && event.up.button == .right
        }
    }

    public var isMiddleClick: Bool {
        switch self {
        case .keyboard:
            return false
        case .mouse(let event):
            return event.down.button == .middle && event.up.button == .middle
        }
    }

    public var standardClick: Bool {
        switch self {
        case .keyboard:
            return true
        case .mouse(let event):
            return event.down.button == .left && event.up.button == .left
        }
    }

    public var firstFocus: Bool {
        switch self {
        case .keyboard:
            return false
        case .mouse(let event):
            return event.down.firstMouse
        }
    }

    public var clickCount: Int {
        switch self {
        case .keyboard:
            return 1
        case .mouse(let event):
            return event.up.clickCount
        }
    }

    public var isKeyboard: Bool {
        switch self {
        case .keyboard:
            return true
        case .mouse:
            return false
        }
    }
}

/// A mouse move event from the platform.
public struct MouseMoveEvent: MouseEvent, Sendable, Equatable {
    public var position: Point<Pixels>
    public var pressedButton: MouseButton?
    public var modifiers: Modifiers

    public init(
        position: Point<Pixels> = .zero,
        pressedButton: MouseButton? = nil,
        modifiers: Modifiers = Modifiers.none()
    ) {
        self.position = position
        self.pressedButton = pressedButton
        self.modifiers = modifiers
    }

    public var dragging: Bool {
        pressedButton == .left
    }

    public func toPlatformInput() -> PlatformInput {
        .mouseMove(self)
    }
}

/// The scroll delta for a scroll wheel event.
public enum ScrollDelta: Sendable, Equatable {
    case pixels(Point<Pixels>)
    case lines(Point<Float>)

    public var precise: Bool {
        switch self {
        case .pixels:
            return true
        case .lines:
            return false
        }
    }

    public func pixelDelta(lineHeight: Pixels) -> Point<Pixels> {
        switch self {
        case .pixels(let delta):
            return delta
        case .lines(let delta):
            return Point(x: lineHeight * delta.x, y: lineHeight * delta.y)
        }
    }

    public func coalesce(_ other: ScrollDelta) -> ScrollDelta {
        switch (self, other) {
        case (.pixels(let a), .pixels(let b)):
            let x = (a.x.value.sign == b.x.value.sign) ? a.x + b.x : b.x
            let y = (a.y.value.sign == b.y.value.sign) ? a.y + b.y : b.y
            return .pixels(Point(x: x, y: y))

        case (.lines(let a), .lines(let b)):
            let x = (a.x.sign == b.x.sign) ? a.x + b.x : b.x
            let y = (a.y.sign == b.y.sign) ? a.y + b.y : b.y
            return .lines(Point(x: x, y: y))

        default:
            return other
        }
    }
}

/// A mouse wheel event from the platform.
public struct ScrollWheelEvent: MouseEvent, Sendable, Equatable {
    public var position: Point<Pixels>
    public var delta: ScrollDelta
    public var modifiers: Modifiers
    public var touchPhase: TouchPhase

    public init(
        position: Point<Pixels> = .zero,
        delta: ScrollDelta = .lines(.zero),
        modifiers: Modifiers = Modifiers.none(),
        touchPhase: TouchPhase = .moved
    ) {
        self.position = position
        self.delta = delta
        self.modifiers = modifiers
        self.touchPhase = touchPhase
    }

    public func toPlatformInput() -> PlatformInput {
        .scrollWheel(self)
    }
}

/// A pinch gesture event from the platform.
public struct PinchEvent: MouseEvent, Sendable, Equatable {
    public var position: Point<Pixels>
    public var delta: Float
    public var modifiers: Modifiers
    public var phase: TouchPhase

    public init(
        position: Point<Pixels> = .zero,
        delta: Float = 0,
        modifiers: Modifiers = Modifiers.none(),
        phase: TouchPhase = .moved
    ) {
        self.position = position
        self.delta = delta
        self.modifiers = modifiers
        self.phase = phase
    }

    public func toPlatformInput() -> PlatformInput {
        .pinch(self)
    }
}

/// A rotation gesture event from the platform.
public struct RotationEvent: MouseEvent, Sendable, Equatable {
    public var center: Point<Pixels>
    public var rotation: Float
    public var modifiers: Modifiers
    public var touchPhase: TouchPhase

    public init(
        center: Point<Pixels> = .zero,
        rotation: Float = 0,
        modifiers: Modifiers = Modifiers.none(),
        touchPhase: TouchPhase = .moved
    ) {
        self.center = center
        self.rotation = rotation
        self.modifiers = modifiers
        self.touchPhase = touchPhase
    }

    public func toPlatformInput() -> PlatformInput {
        .rotation(self)
    }
}

/// A mouse exit event from the platform.
public struct MouseExitEvent: MouseEvent, Sendable, Equatable {
    public var position: Point<Pixels>
    public var pressedButton: MouseButton?
    public var modifiers: Modifiers

    public init(
        position: Point<Pixels> = .zero,
        pressedButton: MouseButton? = nil,
        modifiers: Modifiers = Modifiers.none()
    ) {
        self.position = position
        self.pressedButton = pressedButton
        self.modifiers = modifiers
    }

    public func toPlatformInput() -> PlatformInput {
        .mouseExited(self)
    }
}

/// A collection of paths from the platform, such as from a file drop.
public struct ExternalPaths: Sendable, Equatable {
    public var paths: [String]

    public init(paths: [String] = []) {
        self.paths = paths
    }
}

/// A file drop event from the platform.
public enum FileDropEvent: MouseEvent, Sendable, Equatable {
    case entered(position: Point<Pixels>, paths: ExternalPaths)
    case pending(position: Point<Pixels>)
    case submit(position: Point<Pixels>)
    case exited

    public func toPlatformInput() -> PlatformInput {
        .fileDrop(self)
    }
}

/// An enum corresponding to all kinds of platform input events.
public enum PlatformInput: Sendable, Equatable {
    case keyDown(KeyDownEvent)
    case keyUp(KeyUpEvent)
    case modifiersChanged(ModifiersChangedEvent)
    case mouseDown(MouseDownEvent)
    case mouseUp(MouseUpEvent)
    case mousePressure(MousePressureEvent)
    case mouseMove(MouseMoveEvent)
    case mouseExited(MouseExitEvent)
    case scrollWheel(ScrollWheelEvent)
    case pinch(PinchEvent)
    case rotation(RotationEvent)
    case fileDrop(FileDropEvent)

    public var mouseEvent: (any MouseEvent)? {
        switch self {
        case .keyDown, .keyUp, .modifiersChanged:
            return nil
        case .mouseDown(let e):
            return e
        case .mouseUp(let e):
            return e
        case .mousePressure(let e):
            return e
        case .mouseMove(let e):
            return e
        case .mouseExited(let e):
            return e
        case .scrollWheel(let e):
            return e
        case .pinch(let e):
            return e
        case .rotation(let e):
            return e
        case .fileDrop(let e):
            return e
        }
    }

    public var keyboardEvent: (any KeyEvent)? {
        switch self {
        case .keyDown(let e):
            return e
        case .keyUp(let e):
            return e
        case .modifiersChanged(let e):
            return e
        default:
            return nil
        }
    }
}
