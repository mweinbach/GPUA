// Swift-only: Android multi-touch, stylus/mouse, pinch/rotation, and fling scroll momentum translation per ADR-0012

import Foundation
import GPUI

// MARK: - Android NDK Motion Constants (<android/input.h>)

/// Android `AMOTION_EVENT_ACTION_*` constants from `<android/input.h>`.
public enum AndroidMotionAction {
    public static let mask: Int32 = 0xFF
    public static let pointerIndexMask: Int32 = 0xFF00
    public static let pointerIndexShift: Int32 = 8

    public static let down: Int32 = 0
    public static let up: Int32 = 1
    public static let move: Int32 = 2
    public static let cancel: Int32 = 3
    public static let outside: Int32 = 4
    public static let pointerDown: Int32 = 5
    public static let pointerUp: Int32 = 6
    public static let hoverMove: Int32 = 7
    public static let scroll: Int32 = 8
    public static let hoverEnter: Int32 = 9
    public static let hoverExit: Int32 = 10
    public static let buttonPress: Int32 = 11
    public static let buttonRelease: Int32 = 12

    /// Splits a raw `MotionEvent.action` integer into `(maskedAction, actionPointerIndex)`.
    public static func decode(_ rawAction: Int32) -> (action: Int32, pointerIndex: Int) {
        let masked = rawAction & mask
        let index = Int((rawAction & pointerIndexMask) >> pointerIndexShift)
        return (masked, max(0, index))
    }

    /// Composes a combined pointer action integer for `ACTION_POINTER_DOWN` / `ACTION_POINTER_UP`.
    public static func encode(action: Int32, pointerIndex: Int) -> Int32 {
        (action & mask) | (Int32(max(0, pointerIndex)) << pointerIndexShift)
    }
}

/// Android `AMOTION_EVENT_BUTTON_*` bitmask constants from `<android/input.h>`.
public enum AndroidMotionButton {
    public static let primary: Int32 = 1 << 0
    public static let secondary: Int32 = 1 << 1
    public static let tertiary: Int32 = 1 << 2
    public static let back: Int32 = 1 << 3
    public static let forward: Int32 = 1 << 4
    public static let stylusPrimary: Int32 = 1 << 5
    public static let stylusSecondary: Int32 = 1 << 6
}

/// Android `AMOTION_EVENT_TOOL_TYPE_*` constants from `<android/input.h>`.
public enum AndroidMotionToolType {
    public static let unknown: Int32 = 0
    public static let finger: Int32 = 1
    public static let stylus: Int32 = 2
    public static let mouse: Int32 = 3
    public static let eraser: Int32 = 4
    public static let palm: Int32 = 5
}

/// Single pointer sample from an Android `MotionEvent` / `AInputEvent`.
public struct AndroidPointerSample: Sendable, Equatable {
    public var pointerId: Int32
    public var xPx: Float
    public var yPx: Float
    public var pressure: Float
    public var toolType: Int32

    public init(
        pointerId: Int32 = 0,
        xPx: Float,
        yPx: Float,
        pressure: Float = 1.0,
        toolType: Int32 = AndroidMotionToolType.finger
    ) {
        self.pointerId = pointerId
        self.xPx = xPx
        self.yPx = yPx
        self.pressure = pressure
        self.toolType = toolType
    }

    /// Converts physical pixel coordinates into GPUI logical `Pixels`.
    public func logicalPosition(scaleFactor: Float) -> Point<Pixels> {
        let scale = (scaleFactor.isFinite && scaleFactor > 0.0) ? scaleFactor : 1.0
        return Point(x: px(xPx / scale), y: px(yPx / scale))
    }
}

/// Maps Android button state bitmask to a GPUI `MouseButton`.
public func mouseButtonFromAndroidButtons(_ buttonState: Int32, toolType: Int32 = AndroidMotionToolType.finger) -> MouseButton {
    if (buttonState & (AndroidMotionButton.secondary | AndroidMotionButton.stylusSecondary)) != 0 {
        return .right
    }
    if (buttonState & AndroidMotionButton.tertiary) != 0 {
        return .middle
    }
    if (buttonState & AndroidMotionButton.back) != 0 {
        return .navigate(.back)
    }
    if (buttonState & AndroidMotionButton.forward) != 0 {
        return .navigate(.forward)
    }
    _ = toolType
    return .left
}

// MARK: - Velocity Tracker & Fling Scroll Momentum

/// Sliding-window 2D velocity estimator in logical `Pixels` per second.
public struct TouchVelocityTracker: Sendable {
    private struct Sample: Sendable {
        var position: Point<Float>
        var timestampSeconds: Double
    }

    private var samples: [Sample] = []
    private let horizonSeconds: Double = 0.10
    private let maxVelocity: Float = 8000.0

    public init() {}

    public mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }

    public mutating func addSample(position: Point<Pixels>, timestampSeconds: Double) {
        let cutoff = timestampSeconds - horizonSeconds
        samples.removeAll { $0.timestampSeconds < cutoff }
        samples.append(
            Sample(
                position: Point(x: position.x.value, y: position.y.value),
                timestampSeconds: timestampSeconds
            )
        )
    }

    /// Computes `(vx, vy)` in logical pixels/sec using weighted linear delta over recent samples.
    public func currentVelocity() -> Point<Float> {
        guard let first = samples.first, let last = samples.last, samples.count >= 2 else {
            return .zero
        }
        let dt = last.timestampSeconds - first.timestampSeconds
        guard dt >= 0.002 else {
            return .zero
        }
        let rawVx = (last.position.x - first.position.x) / Float(dt)
        let rawVy = (last.position.y - first.position.y) / Float(dt)
        let clampedVx = min(max(rawVx, -maxVelocity), maxVelocity)
        let clampedVy = min(max(rawVy, -maxVelocity), maxVelocity)
        return Point(x: clampedVx, y: clampedVy)
    }
}

/// Inertial fling scroll state driven by vsync (`AChoreographer`) after touch pan lift-off.
public struct ScrollMomentum: Sendable, Equatable {
    /// Current fling velocity in logical `Pixels` per second.
    public var velocity: Point<Float>
    /// Anchor position of the scroll gesture in logical `Pixels`.
    public var position: Point<Pixels>
    /// Per-60Hz-frame exponential retention factor (`~0.95` matches Android OverScroller feel).
    public var decelerationPerFrame: Float
    /// Minimum speed in logical `Pixels`/second below which momentum terminates.
    public var minSpeedThreshold: Float

    public init(
        velocity: Point<Float>,
        position: Point<Pixels>,
        decelerationPerFrame: Float = 0.95,
        minSpeedThreshold: Float = 15.0
    ) {
        self.velocity = velocity
        self.position = position
        self.decelerationPerFrame = decelerationPerFrame
        self.minSpeedThreshold = minSpeedThreshold
    }

    public var isActive: Bool {
        hypotFloat(velocity.x, velocity.y) >= minSpeedThreshold
    }

    /// Advances inertial scroll by `dt` seconds and emits the corresponding `ScrollWheelEvent`.
    public mutating func step(dt: Float, modifiers: Modifiers = .none()) -> ScrollWheelEvent? {
        let clampedDt = min(max(dt, 0.001), 0.1)
        let currentSpeed = hypotFloat(velocity.x, velocity.y)
        guard currentSpeed >= minSpeedThreshold else {
            velocity = .zero
            return nil
        }

        let dx = velocity.x * clampedDt
        let dy = velocity.y * clampedDt
        let decay = Float(Foundation.pow(Double(decelerationPerFrame), Double(clampedDt * 60.0)))
        velocity = Point(x: velocity.x * decay, y: velocity.y * decay)

        let nextSpeed = hypotFloat(velocity.x, velocity.y)
        let phase: TouchPhase
        if nextSpeed < minSpeedThreshold {
            velocity = .zero
            phase = .ended
        } else {
            phase = .moved
        }

        return ScrollWheelEvent(
            position: position,
            delta: .pixels(Point(x: px(dx), y: px(dy))),
            modifiers: modifiers,
            touchPhase: phase
        )
    }
}

// MARK: - Multi-Touch & Pointer Translator

/// Translates Android `MotionEvent` / `AInputEvent` sequences into GPUI `PlatformInput` events,
/// handling primary touch tracking, double-tap counting, single-finger pan + inertial fling,
/// two-finger scroll/pinch/rotation, and hardware mouse/trackpad hover/buttons/wheel.
public struct AndroidTouchInputProcessor: Sendable {
    public private(set) var lastMousePosition: Point<Pixels> = .zero
    public private(set) var scrollMomentum: ScrollMomentum?
    public private(set) var trackedPointerId: Int32?
    public private(set) var isHovering: Bool = false

    /// Logical pixel movement threshold before a single-finger touch promotes to a scroll pan.
    public var touchSlopLogicalPx: Float = 8.0
    /// Maximum inter-tap interval for multi-tap (`clickCount`) recognition.
    public var multiTapIntervalSeconds: Double = 0.35
    /// Maximum logical distance between consecutive taps for multi-tap recognition.
    public var multiTapDistanceLogicalPx: Float = 24.0
    /// Minimum fling speed (logical px/s) required to arm `ScrollMomentum` on touch release.
    public var minFlingVelocityLogicalPxPerSec: Float = 80.0

    private var touchStartPosition: Point<Pixels>?
    private var previousPanPosition: Point<Pixels>?
    private var isSingleFingerPanning: Bool = false
    private var isMultiTouchActive: Bool = false
    private var previousMultiCentroid: Point<Pixels>?
    private var previousMultiSpan: Float?
    private var previousMultiAngle: Float?

    private var currentClickCount: Int = 1
    private var lastTapTimeSeconds: Double = -100.0
    private var lastTapPosition: Point<Pixels> = .zero
    private var activeMouseButton: MouseButton?
    private var velocityTracker = TouchVelocityTracker()

    public init() {}

    /// Cancels any active inertial scroll momentum.
    public mutating func cancelMomentum() {
        scrollMomentum = nil
    }

    /// Advances inertial scroll momentum on vsync frame tick.
    public mutating func stepMomentum(dt: Float, modifiers: Modifiers = .none()) -> ScrollWheelEvent? {
        guard var momentum = scrollMomentum else {
            return nil
        }
        let event = momentum.step(dt: dt, modifiers: modifiers)
        scrollMomentum = momentum.isActive ? momentum : nil
        return event
    }

    /// Processes an Android motion event and returns ordered GPUI `PlatformInput` events.
    public mutating func processMotionEvent(
        rawAction: Int32,
        pointers: [AndroidPointerSample],
        scaleFactor: Float,
        metaState: Int32 = 0,
        buttonState: Int32 = 0,
        vScroll: Float = 0.0,
        hScroll: Float = 0.0,
        eventTimeSeconds: Double = 0.0,
        liveModifiers: Modifiers? = nil
    ) -> [PlatformInput] {
        guard !pointers.isEmpty else {
            return []
        }

        let modifiers = liveModifiers ?? modifiersFromAndroidMetaState(metaState)
        let (action, actionIndex) = AndroidMotionAction.decode(rawAction)
        let safeIndex = min(max(actionIndex, 0), pointers.count - 1)
        let actionPointer = pointers[safeIndex]

        // Route hardware mouse / trackpad pointer events through desktop mouse semantics.
        if actionPointer.toolType == AndroidMotionToolType.mouse
            || action == AndroidMotionAction.hoverEnter
            || action == AndroidMotionAction.hoverMove
            || action == AndroidMotionAction.hoverExit
            || action == AndroidMotionAction.scroll
            || action == AndroidMotionAction.buttonPress
            || action == AndroidMotionAction.buttonRelease {
            return processPointerDeviceEvent(
                action: action,
                pointer: actionPointer,
                scaleFactor: scaleFactor,
                modifiers: modifiers,
                buttonState: buttonState,
                vScroll: vScroll,
                hScroll: hScroll,
                eventTimeSeconds: eventTimeSeconds
            )
        }

        var outputs: [PlatformInput] = []

        switch action {
        case AndroidMotionAction.down:
            // Any new touch immediately halts inertial fling scrolling.
            scrollMomentum = nil
            isMultiTouchActive = false
            isSingleFingerPanning = false
            previousMultiCentroid = nil
            previousMultiSpan = nil
            previousMultiAngle = nil

            let pos = actionPointer.logicalPosition(scaleFactor: scaleFactor)
            trackedPointerId = actionPointer.pointerId
            lastMousePosition = pos
            touchStartPosition = pos
            previousPanPosition = pos

            velocityTracker.reset()
            velocityTracker.addSample(position: pos, timestampSeconds: eventTimeSeconds)

            let clickCount = computeNextClickCount(position: pos, timestampSeconds: eventTimeSeconds)
            currentClickCount = clickCount
            let button = mouseButtonFromAndroidButtons(buttonState, toolType: actionPointer.toolType)
            activeMouseButton = button

            outputs.append(
                .mouseDown(
                    MouseDownEvent(
                        button: button,
                        position: pos,
                        modifiers: modifiers,
                        clickCount: clickCount,
                        firstMouse: false
                    )
                )
            )

        case AndroidMotionAction.pointerDown:
            if pointers.count >= 2 {
                // Transition into multi-touch gesture (two-finger scroll + pinch + rotation).
                if isSingleFingerPanning {
                    outputs.append(
                        .scrollWheel(
                            ScrollWheelEvent(
                                position: lastMousePosition,
                                delta: .pixels(.zero),
                                modifiers: modifiers,
                                touchPhase: .ended
                            )
                        )
                    )
                    isSingleFingerPanning = false
                }
                isMultiTouchActive = true
                velocityTracker.reset()
                let p0 = pointers[0].logicalPosition(scaleFactor: scaleFactor)
                let p1 = pointers[1].logicalPosition(scaleFactor: scaleFactor)
                let (centroid, span, angle) = Self.twoFingerGeometry(p0, p1)
                previousMultiCentroid = centroid
                previousMultiSpan = span
                previousMultiAngle = angle
                lastMousePosition = centroid

                outputs.append(
                    .scrollWheel(
                        ScrollWheelEvent(
                            position: centroid,
                            delta: .pixels(.zero),
                            modifiers: modifiers,
                            touchPhase: .started
                        )
                    )
                )
                outputs.append(
                    .pinch(
                        PinchEvent(
                            position: centroid,
                            delta: 0.0,
                            modifiers: modifiers,
                            phase: .started
                        )
                    )
                )
            }

        case AndroidMotionAction.move:
            if pointers.count >= 2 && isMultiTouchActive {
                let p0 = pointers[0].logicalPosition(scaleFactor: scaleFactor)
                let p1 = pointers[1].logicalPosition(scaleFactor: scaleFactor)
                let (centroid, span, angle) = Self.twoFingerGeometry(p0, p1)
                lastMousePosition = centroid

                if let prevCentroid = previousMultiCentroid {
                    let dx = centroid.x.value - prevCentroid.x.value
                    let dy = centroid.y.value - prevCentroid.y.value
                    if abs(dx) > 0.01 || abs(dy) > 0.01 {
                        outputs.append(
                            .scrollWheel(
                                ScrollWheelEvent(
                                    position: centroid,
                                    delta: .pixels(Point(x: px(dx), y: px(dy))),
                                    modifiers: modifiers,
                                    touchPhase: .moved
                                )
                            )
                        )
                    }
                }

                if let prevSpan = previousMultiSpan, prevSpan > 1.0 {
                    let scaleDelta = (span / prevSpan) - 1.0
                    if abs(scaleDelta) > 0.001 {
                        outputs.append(
                            .pinch(
                                PinchEvent(
                                    position: centroid,
                                    delta: scaleDelta,
                                    modifiers: modifiers,
                                    phase: .moved
                                )
                            )
                        )
                    }
                }

                if let prevAngle = previousMultiAngle {
                    var dAngle = angle - prevAngle
                    if dAngle > .pi { dAngle -= 2.0 * .pi }
                    if dAngle < -.pi { dAngle += 2.0 * .pi }
                    if abs(dAngle) > 0.002 {
                        outputs.append(
                            .rotation(
                                RotationEvent(
                                    center: centroid,
                                    rotation: dAngle,
                                    modifiers: modifiers,
                                    touchPhase: .moved
                                )
                            )
                        )
                    }
                }

                previousMultiCentroid = centroid
                previousMultiSpan = span
                previousMultiAngle = angle
            } else if !isMultiTouchActive {
                guard let primary = findTrackedPointer(in: pointers) else {
                    break
                }
                let pos = primary.logicalPosition(scaleFactor: scaleFactor)
                lastMousePosition = pos
                velocityTracker.addSample(position: pos, timestampSeconds: eventTimeSeconds)

                let button = activeMouseButton ?? .left
                outputs.append(
                    .mouseMove(
                        MouseMoveEvent(
                            position: pos,
                            pressedButton: button,
                            modifiers: modifiers
                        )
                    )
                )

                if let start = touchStartPosition {
                    let distFromStart = hypotFloat(pos.x.value - start.x.value, pos.y.value - start.y.value)
                    if !isSingleFingerPanning && distFromStart >= touchSlopLogicalPx {
                        isSingleFingerPanning = true
                        let dx = pos.x.value - (previousPanPosition?.x.value ?? start.x.value)
                        let dy = pos.y.value - (previousPanPosition?.y.value ?? start.y.value)
                        outputs.append(
                            .scrollWheel(
                                ScrollWheelEvent(
                                    position: pos,
                                    delta: .pixels(Point(x: px(dx), y: px(dy))),
                                    modifiers: modifiers,
                                    touchPhase: .started
                                )
                            )
                        )
                    } else if isSingleFingerPanning, let prev = previousPanPosition {
                        let dx = pos.x.value - prev.x.value
                        let dy = pos.y.value - prev.y.value
                        if abs(dx) > 0.01 || abs(dy) > 0.01 {
                            outputs.append(
                                .scrollWheel(
                                    ScrollWheelEvent(
                                        position: pos,
                                        delta: .pixels(Point(x: px(dx), y: px(dy))),
                                        modifiers: modifiers,
                                        touchPhase: .moved
                                    )
                                )
                            )
                        }
                    }
                }
                previousPanPosition = pos
            }

        case AndroidMotionAction.pointerUp:
            if isMultiTouchActive && pointers.count <= 2 {
                let centroid = previousMultiCentroid ?? lastMousePosition
                outputs.append(
                    .scrollWheel(
                        ScrollWheelEvent(
                            position: centroid,
                            delta: .pixels(.zero),
                            modifiers: modifiers,
                            touchPhase: .ended
                        )
                    )
                )
                outputs.append(
                    .pinch(
                        PinchEvent(
                            position: centroid,
                            delta: 0.0,
                            modifiers: modifiers,
                            phase: .ended
                        )
                    )
                )
                previousMultiCentroid = nil
                previousMultiSpan = nil
                previousMultiAngle = nil
            }
            // If the lifted pointer was our tracked primary pointer, rebind to a remaining pointer.
            if trackedPointerId == actionPointer.pointerId {
                let remaining = pointers.enumerated().first { $0.offset != safeIndex }?.element
                trackedPointerId = remaining?.pointerId
                if let rem = remaining {
                    let remPos = rem.logicalPosition(scaleFactor: scaleFactor)
                    previousPanPosition = remPos
                    lastMousePosition = remPos
                }
            }

        case AndroidMotionAction.up:
            let pos = actionPointer.logicalPosition(scaleFactor: scaleFactor)
            lastMousePosition = pos
            velocityTracker.addSample(position: pos, timestampSeconds: eventTimeSeconds)
            let button = activeMouseButton ?? .left

            if isSingleFingerPanning {
                outputs.append(
                    .scrollWheel(
                        ScrollWheelEvent(
                            position: pos,
                            delta: .pixels(.zero),
                            modifiers: modifiers,
                            touchPhase: .ended
                        )
                    )
                )
                let velocity = velocityTracker.currentVelocity()
                let speed = hypotFloat(velocity.x, velocity.y)
                if speed >= minFlingVelocityLogicalPxPerSec {
                    scrollMomentum = ScrollMomentum(velocity: velocity, position: pos)
                }
            }

            outputs.append(
                .mouseUp(
                    MouseUpEvent(
                        button: button,
                        position: pos,
                        modifiers: modifiers,
                        clickCount: currentClickCount
                    )
                )
            )

            resetTouchTracking()

        case AndroidMotionAction.cancel, AndroidMotionAction.outside:
            let pos = lastMousePosition
            let button = activeMouseButton ?? .left
            if isSingleFingerPanning || isMultiTouchActive {
                outputs.append(
                    .scrollWheel(
                        ScrollWheelEvent(
                            position: pos,
                            delta: .pixels(.zero),
                            modifiers: modifiers,
                            touchPhase: .ended
                        )
                    )
                )
            }
            outputs.append(
                .mouseUp(
                    MouseUpEvent(
                        button: button,
                        position: pos,
                        modifiers: modifiers,
                        clickCount: 1
                    )
                )
            )
            scrollMomentum = nil
            resetTouchTracking()

        default:
            break
        }

        return outputs
    }

    // MARK: - Helpers

    private mutating func processPointerDeviceEvent(
        action: Int32,
        pointer: AndroidPointerSample,
        scaleFactor: Float,
        modifiers: Modifiers,
        buttonState: Int32,
        vScroll: Float,
        hScroll: Float,
        eventTimeSeconds: Double
    ) -> [PlatformInput] {
        let pos = pointer.logicalPosition(scaleFactor: scaleFactor)
        lastMousePosition = pos

        switch action {
        case AndroidMotionAction.hoverEnter, AndroidMotionAction.hoverMove:
            isHovering = true
            return [
                .mouseMove(
                    MouseMoveEvent(
                        position: pos,
                        pressedButton: activeMouseButton,
                        modifiers: modifiers
                    )
                )
            ]
        case AndroidMotionAction.hoverExit:
            isHovering = false
            return [
                .mouseExited(
                    MouseExitEvent(
                        position: pos,
                        pressedButton: activeMouseButton,
                        modifiers: modifiers
                    )
                )
            ]
        case AndroidMotionAction.scroll:
            return [
                .scrollWheel(
                    ScrollWheelEvent(
                        position: pos,
                        delta: .lines(Point(x: hScroll, y: vScroll)),
                        modifiers: modifiers,
                        touchPhase: .moved
                    )
                )
            ]
        case AndroidMotionAction.down, AndroidMotionAction.buttonPress:
            let button = mouseButtonFromAndroidButtons(buttonState, toolType: pointer.toolType)
            activeMouseButton = button
            let clickCount = computeNextClickCount(position: pos, timestampSeconds: eventTimeSeconds)
            currentClickCount = clickCount
            return [
                .mouseDown(
                    MouseDownEvent(
                        button: button,
                        position: pos,
                        modifiers: modifiers,
                        clickCount: clickCount,
                        firstMouse: false
                    )
                )
            ]
        case AndroidMotionAction.move:
            return [
                .mouseMove(
                    MouseMoveEvent(
                        position: pos,
                        pressedButton: activeMouseButton,
                        modifiers: modifiers
                    )
                )
            ]
        case AndroidMotionAction.up, AndroidMotionAction.buttonRelease:
            let button = activeMouseButton ?? mouseButtonFromAndroidButtons(buttonState, toolType: pointer.toolType)
            activeMouseButton = nil
            return [
                .mouseUp(
                    MouseUpEvent(
                        button: button,
                        position: pos,
                        modifiers: modifiers,
                        clickCount: currentClickCount
                    )
                )
            ]
        default:
            return []
        }
    }

    private func findTrackedPointer(in pointers: [AndroidPointerSample]) -> AndroidPointerSample? {
        if let tracked = trackedPointerId,
           let match = pointers.first(where: { $0.pointerId == tracked }) {
            return match
        }
        return pointers.first
    }

    private mutating func computeNextClickCount(position: Point<Pixels>, timestampSeconds: Double) -> Int {
        let dt = timestampSeconds - lastTapTimeSeconds
        let dist = hypotFloat(
            position.x.value - lastTapPosition.x.value,
            position.y.value - lastTapPosition.y.value
        )
        let nextCount: Int
        if dt >= 0.0 && dt <= multiTapIntervalSeconds && dist <= multiTapDistanceLogicalPx {
            nextCount = currentClickCount + 1
        } else {
            nextCount = 1
        }
        lastTapTimeSeconds = timestampSeconds
        lastTapPosition = position
        return nextCount
    }

    private mutating func resetTouchTracking() {
        trackedPointerId = nil
        touchStartPosition = nil
        previousPanPosition = nil
        isSingleFingerPanning = false
        isMultiTouchActive = false
        previousMultiCentroid = nil
        previousMultiSpan = nil
        previousMultiAngle = nil
        activeMouseButton = nil
        velocityTracker.reset()
    }

    private static func twoFingerGeometry(
        _ p0: Point<Pixels>,
        _ p1: Point<Pixels>
    ) -> (centroid: Point<Pixels>, span: Float, angle: Float) {
        let cx = (p0.x.value + p1.x.value) * 0.5
        let cy = (p0.y.value + p1.y.value) * 0.5
        let dx = p1.x.value - p0.x.value
        let dy = p1.y.value - p0.y.value
        let span = hypotFloat(dx, dy)
        let angle = Float(Foundation.atan2(Double(dy), Double(dx)))
        return (Point(x: px(cx), y: px(cy)), span, angle)
    }
}

@inline(__always)
private func hypotFloat(_ dx: Float, _ dy: Float) -> Float {
    (dx * dx + dy * dy).squareRoot()
}
