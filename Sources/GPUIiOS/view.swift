// Ported from: crates/gpui_ios/src/view.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(iOS) || os(visionOS)
import CoreGraphics
import Foundation
import GPUI
import GPUIMetal
import QuartzCore
import UIKit

// MARK: - Shared Input Dispatch Helper

/// Dispatches a `PlatformInput` event into `windowState`, updating tracked pointer coordinates,
/// modifiers, and requesting a frame when dirty, matching upstream `view::dispatch_input`.
@MainActor
@discardableResult
func dispatchInput(_ windowState: IosWindowState, _ input: PlatformInput) -> DispatchEventResult {
    switch input {
    case .mouseDown(let e):
        windowState.mousePosition = e.position
        windowState.modifiers = e.modifiers
    case .mouseMove(let e):
        windowState.mousePosition = e.position
        windowState.modifiers = e.modifiers
    case .mouseUp(let e):
        windowState.mousePosition = e.position
        windowState.modifiers = e.modifiers
    case .mousePressure(let e):
        windowState.mousePosition = e.position
        windowState.modifiers = e.modifiers
    case .scrollWheel(let e):
        windowState.mousePosition = e.position
        windowState.modifiers = e.modifiers
    case .pinch(let e):
        windowState.mousePosition = e.position
        windowState.modifiers = e.modifiers
    case .rotation(let e):
        windowState.mousePosition = e.center
        windowState.modifiers = e.modifiers
    case .keyDown(let e):
        windowState.modifiers = e.keystroke.modifiers
    case .keyUp(let e):
        windowState.modifiers = e.keystroke.modifiers
    case .modifiersChanged(let e):
        windowState.modifiers = e.modifiers
        windowState.capslock = e.capslock
    case .mouseExited, .fileDrop:
        break
    }

    let result = windowState.inputCallback?(input) ?? DispatchEventResult(propagate: true, defaultPrevented: false)
    windowState.requestFrameCallback?(RequestFrameOptions())
    return result
}

// MARK: - CAMetalLayer-Backed UIView (`GPUIiOSView`)

/// Alias matching upstream Objective-C class name `GPUIView`.
public typealias GPUIView = GPUIiOSView

// PORT NOTE: Replaces upstream ObjC runtime `ClassDecl("GPUIView")` with a native Swift `UIView`
// subclass overriding `layerClass` -> `CAMetalLayer.self` (ADR-0011).

/// Native `CAMetalLayer`-backed `UIView` hosting GPUI's Metal rendering surface, multi-touch
/// tracking, pan/pinch/rotation/hover/long-press gestures, hardware keyboard `UIPress` handling,
/// drag-and-drop, and Dynamic Island / Home Indicator safe-area updates.
@MainActor
public final class GPUIiOSView: UIView {
    override public class var layerClass: AnyClass {
        CAMetalLayer.self
    }

    /// Convenience typed accessor for the view's backing `CAMetalLayer`.
    public var metalLayer: CAMetalLayer? {
        layer as? CAMetalLayer
    }

    weak var windowState: IosWindowState?

    private let gestureDelegate = GPUIGestureDelegate()
    private lazy var dropDelegate = GPUIDropDelegate(windowState: windowState)

    // Gesture tracking state
    private weak var activePrimaryTouch: UITouch?
    private var primaryTouchTapCount: Int = 1
    private var singleFingerPanLastTranslation: CGPoint = .zero
    private var twoFingerPanLastTranslation: CGPoint = .zero
    private var lastPinchScale: CGFloat = 1.0
    private var lastRotationAngle: CGFloat = 0.0
    private var traitChangeRegistration: (any UITraitChangeRegistration)?

    override public init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        isOpaque = true

        // Configure backing CAMetalLayer
        if let metalLayer = self.metalLayer {
            metalLayer.pixelFormat = .bgra8Unorm
            metalLayer.framebufferOnly = true
            metalLayer.contentsScale = window?.windowScene?.screen.scale ?? 3.0
        }

        setupGestureRecognizers()
        setupDropInteraction()
        setupTraitObservation()
    }

    func attach(windowState: IosWindowState) {
        self.windowState = windowState
        self.dropDelegate.windowState = windowState
        if let metalLayer = self.metalLayer {
            let scale = CGFloat(windowState.scaleFactor())
            metalLayer.contentsScale = scale
            metalLayer.isOpaque = windowState.backgroundAppearance == .opaque
        }
    }

    override public var canBecomeFirstResponder: Bool {
        true
    }

    // MARK: - Layout, Scale, Safe Area, and Appearance Updates

    override public func didMoveToWindow() {
        super.didMoveToWindow()
        guard let windowState else { return }
        let scale = windowState.scaleFactor()
        contentScaleFactor = CGFloat(scale)
        metalLayer?.contentsScale = CGFloat(scale)
        syncGeometryAndAppearance()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        syncGeometryAndAppearance()
    }

    override public func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        syncGeometryAndAppearance()
    }

    private func setupTraitObservation() {
        traitChangeRegistration = registerForTraitChanges(
            [UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]
        ) { (selfView: Self, _) in
            selfView.handleAppearanceTraitChange()
        }
    }

    private func handleAppearanceTraitChange() {
        guard let state = windowState else { return }
        let updated = windowAppearanceFromTraitCollection(traitCollection)
        if state.appearance != updated {
            state.appearance = updated
            state.appearanceChangedCallback?()
            state.requestFrameCallback?(RequestFrameOptions())
        }
    }

    private func syncGeometryAndAppearance() {
        guard let state = windowState else { return }
        let scale = state.scaleFactor()
        if let metalLayer = self.metalLayer {
            metalLayer.contentsScale = CGFloat(scale)
        }
        let logicalWidth = max(0.0, Float(bounds.width))
        let logicalHeight = max(0.0, Float(bounds.height))
        let drawableSize = Size(
            width: DevicePixels(Int32((logicalWidth * scale).rounded(.up))),
            height: DevicePixels(Int32((logicalHeight * scale).rounded(.up)))
        )
        state.renderer.updateDrawableSize(drawableSize)
        state.blurView?.frame = bounds

        let contentSize = state.contentSize()
        state.resizeCallback?(contentSize, scale)
        state.requestFrameCallback?(RequestFrameOptions())
    }

    // MARK: - Gesture & Drop Setup

    private func setupDropInteraction() {
        let dropInteraction = UIDropInteraction(delegate: dropDelegate)
        addInteraction(dropInteraction)
    }

    private func setupGestureRecognizers() {
        // 1. Two-finger pan / Magic Keyboard trackpad scroll
        let twoFingerPan = UIPanGestureRecognizer(
            target: self,
            action: #selector(handleTwoFingerPan(_:))
        )
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        twoFingerPan.allowedScrollTypesMask = .all
        twoFingerPan.cancelsTouchesInView = true
        twoFingerPan.delegate = gestureDelegate
        addGestureRecognizer(twoFingerPan)

        // 2. Single-finger scroll pan (with kinetic fling momentum on release)
        let singleFingerPan = UIPanGestureRecognizer(
            target: self,
            action: #selector(handleSingleFingerPan(_:))
        )
        singleFingerPan.minimumNumberOfTouches = 1
        singleFingerPan.maximumNumberOfTouches = 1
        singleFingerPan.cancelsTouchesInView = false
        singleFingerPan.delaysTouchesBegan = false
        singleFingerPan.delaysTouchesEnded = false
        singleFingerPan.delegate = gestureDelegate
        addGestureRecognizer(singleFingerPan)

        // 3. Two-finger pinch zoom
        let pinch = UIPinchGestureRecognizer(
            target: self,
            action: #selector(handlePinch(_:))
        )
        pinch.cancelsTouchesInView = false
        pinch.delegate = gestureDelegate
        addGestureRecognizer(pinch)

        // 4. Two-finger rotation
        let rotation = UIRotationGestureRecognizer(
            target: self,
            action: #selector(handleRotation(_:))
        )
        rotation.cancelsTouchesInView = false
        rotation.delegate = gestureDelegate
        addGestureRecognizer(rotation)

        // 5. Pointer / Apple Pencil hover
        let hover = UIHoverGestureRecognizer(
            target: self,
            action: #selector(handleHover(_:))
        )
        hover.delegate = gestureDelegate
        addGestureRecognizer(hover)

        // 6. Long press -> right mouse button context menu trigger
        let longPress = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.5
        longPress.cancelsTouchesInView = true
        longPress.delegate = gestureDelegate
        addGestureRecognizer(longPress)
    }

    // MARK: - Direct Touch Handling

    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let state = windowState else {
            super.touchesBegan(touches, with: event)
            return
        }

        // Any finger touching the glass immediately halts kinetic scroll momentum.
        state.cancelScrollMomentum()

        let (mods, _) = modifiersAndCapslock(from: event?.modifierFlags ?? [])
        let touch: UITouch
        if let active = activePrimaryTouch, touches.contains(active) {
            touch = active
        } else if let first = touches.first {
            activePrimaryTouch = first
            touch = first
        } else {
            return
        }

        let pos = gpuiPoint(from: touch.location(in: self))
        let clickCount = max(1, touch.tapCount)
        primaryTouchTapCount = clickCount

        _ = dispatchInput(
            state,
            .mouseDown(
                MouseDownEvent(
                    button: .left,
                    position: pos,
                    modifiers: mods,
                    clickCount: clickCount,
                    firstMouse: false
                )
            )
        )

        emitPressureIfAvailable(for: touch, at: pos, modifiers: mods, state: state)
    }

    override public func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let state = windowState else {
            super.touchesMoved(touches, with: event)
            return
        }
        guard let touch = activePrimaryTouch.flatMap({ touches.contains($0) ? $0 : nil }) ?? touches.first else {
            return
        }

        let (mods, _) = modifiersAndCapslock(from: event?.modifierFlags ?? [])
        let pos = gpuiPoint(from: touch.location(in: self))

        _ = dispatchInput(
            state,
            .mouseMove(
                MouseMoveEvent(
                    position: pos,
                    pressedButton: .left,
                    modifiers: mods
                )
            )
        )

        emitPressureIfAvailable(for: touch, at: pos, modifiers: mods, state: state)
    }

    override public func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let state = windowState else {
            super.touchesEnded(touches, with: event)
            return
        }
        guard let touch = activePrimaryTouch.flatMap({ touches.contains($0) ? $0 : nil }) ?? touches.first else {
            return
        }

        let (mods, _) = modifiersAndCapslock(from: event?.modifierFlags ?? [])
        let pos = gpuiPoint(from: touch.location(in: self))
        let clickCount = max(1, touch.tapCount > 0 ? touch.tapCount : primaryTouchTapCount)

        if touch === activePrimaryTouch {
            activePrimaryTouch = nil
        }

        _ = dispatchInput(
            state,
            .mouseUp(
                MouseUpEvent(
                    button: .left,
                    position: pos,
                    modifiers: mods,
                    clickCount: clickCount
                )
            )
        )

        // If no element claimed text input focus after the tap completed, keep `GPUIView` as
        // first responder for hardware keyboard shortcuts while dismissing the software keyboard.
        if !state.textInputSession.hasActiveHandler(), !isFirstResponder {
            _ = becomeFirstResponder()
        }
    }

    override public func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let state = windowState else {
            super.touchesCancelled(touches, with: event)
            return
        }
        guard let touch = activePrimaryTouch.flatMap({ touches.contains($0) ? $0 : nil }) ?? touches.first else {
            return
        }

        let (mods, _) = modifiersAndCapslock(from: event?.modifierFlags ?? [])
        let pos = gpuiPoint(from: touch.location(in: self))

        if touch === activePrimaryTouch {
            activePrimaryTouch = nil
        }

        _ = dispatchInput(
            state,
            .mouseUp(
                MouseUpEvent(
                    button: .left,
                    position: pos,
                    modifiers: mods,
                    clickCount: 0
                )
            )
        )
    }

    private func emitPressureIfAvailable(
        for touch: UITouch,
        at position: Point<Pixels>,
        modifiers: Modifiers,
        state: IosWindowState
    ) {
        let maxForce = touch.maximumPossibleForce
        guard maxForce > 0 else { return }
        let normalized = Float(min(max(touch.force / maxForce, 0.0), 1.0))
        let stage: PressureStage
        if normalized <= 0.01 {
            stage = .zero
        } else if normalized >= 0.75 {
            stage = .force
        } else {
            stage = .normal
        }
        _ = dispatchInput(
            state,
            .mousePressure(
                MousePressureEvent(
                    pressure: normalized,
                    stage: stage,
                    position: position,
                    modifiers: modifiers
                )
            )
        )
    }

    // MARK: - Gesture Recognizer Handlers

    @objc private func handleSingleFingerPan(_ recognizer: UIPanGestureRecognizer) {
        guard let state = windowState else { return }
        let pos = gpuiPoint(from: recognizer.location(in: self))
        let translation = recognizer.translation(in: self)
        let phase = touchPhase(from: recognizer.state)

        switch recognizer.state {
        case .began:
            state.cancelScrollMomentum()
            singleFingerPanLastTranslation = translation
            _ = dispatchInput(
                state,
                .scrollWheel(
                    ScrollWheelEvent(
                        position: pos,
                        delta: .pixels(.zero),
                        modifiers: state.modifiers,
                        touchPhase: .started
                    )
                )
            )

        case .changed:
            let dx = Float(translation.x - singleFingerPanLastTranslation.x)
            let dy = Float(translation.y - singleFingerPanLastTranslation.y)
            singleFingerPanLastTranslation = translation
            _ = dispatchInput(
                state,
                .scrollWheel(
                    ScrollWheelEvent(
                        position: pos,
                        delta: .pixels(Point(x: px(dx), y: px(dy))),
                        modifiers: state.modifiers,
                        touchPhase: .moved
                    )
                )
            )

        case .ended:
            let velocity = recognizer.velocity(in: self)
            let vx = Float(velocity.x)
            let vy = Float(velocity.y)
            let speed = hypot(vx, vy)
            if speed > 50.0 {
                state.startScrollMomentum(velocityX: vx, velocityY: vy, position: pos)
            } else {
                _ = dispatchInput(
                    state,
                    .scrollWheel(
                        ScrollWheelEvent(
                            position: pos,
                            delta: .pixels(.zero),
                            modifiers: state.modifiers,
                            touchPhase: .ended
                        )
                    )
                )
            }

        case .cancelled, .failed:
            _ = dispatchInput(
                state,
                .scrollWheel(
                    ScrollWheelEvent(
                        position: pos,
                        delta: .pixels(.zero),
                        modifiers: state.modifiers,
                        touchPhase: phase
                    )
                )
            )

        default:
            break
        }
    }

    @objc private func handleTwoFingerPan(_ recognizer: UIPanGestureRecognizer) {
        guard let state = windowState else { return }
        let pos = gpuiPoint(from: recognizer.location(in: self))
        let translation = recognizer.translation(in: self)

        switch recognizer.state {
        case .began:
            state.cancelScrollMomentum()
            twoFingerPanLastTranslation = translation
            _ = dispatchInput(
                state,
                .scrollWheel(
                    ScrollWheelEvent(
                        position: pos,
                        delta: .pixels(.zero),
                        modifiers: state.modifiers,
                        touchPhase: .started
                    )
                )
            )

        case .changed:
            let dx = Float(translation.x - twoFingerPanLastTranslation.x)
            let dy = Float(translation.y - twoFingerPanLastTranslation.y)
            twoFingerPanLastTranslation = translation
            _ = dispatchInput(
                state,
                .scrollWheel(
                    ScrollWheelEvent(
                        position: pos,
                        delta: .pixels(Point(x: px(dx), y: px(dy))),
                        modifiers: state.modifiers,
                        touchPhase: .moved
                    )
                )
            )

        case .ended:
            let velocity = recognizer.velocity(in: self)
            let vx = Float(velocity.x)
            let vy = Float(velocity.y)
            if hypot(vx, vy) > 50.0 {
                state.startScrollMomentum(velocityX: vx, velocityY: vy, position: pos)
            } else {
                _ = dispatchInput(
                    state,
                    .scrollWheel(
                        ScrollWheelEvent(
                            position: pos,
                            delta: .pixels(.zero),
                            modifiers: state.modifiers,
                            touchPhase: .ended
                        )
                    )
                )
            }

        case .cancelled, .failed:
            _ = dispatchInput(
                state,
                .scrollWheel(
                    ScrollWheelEvent(
                        position: pos,
                        delta: .pixels(.zero),
                        modifiers: state.modifiers,
                        touchPhase: .ended
                    )
                )
            )

        default:
            break
        }
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard let state = windowState else { return }
        let pos = gpuiPoint(from: recognizer.location(in: self))
        let phase = touchPhase(from: recognizer.state)

        switch recognizer.state {
        case .began:
            lastPinchScale = recognizer.scale
            _ = dispatchInput(
                state,
                .pinch(PinchEvent(position: pos, delta: 0.0, modifiers: state.modifiers, phase: .started))
            )
        case .changed:
            let delta = Float(recognizer.scale - lastPinchScale)
            lastPinchScale = recognizer.scale
            _ = dispatchInput(
                state,
                .pinch(PinchEvent(position: pos, delta: delta, modifiers: state.modifiers, phase: .moved))
            )
        case .ended, .cancelled, .failed:
            lastPinchScale = 1.0
            _ = dispatchInput(
                state,
                .pinch(PinchEvent(position: pos, delta: 0.0, modifiers: state.modifiers, phase: phase))
            )
        default:
            break
        }
    }

    @objc private func handleRotation(_ recognizer: UIRotationGestureRecognizer) {
        guard let state = windowState else { return }
        let center = gpuiPoint(from: recognizer.location(in: self))
        let phase = touchPhase(from: recognizer.state)

        switch recognizer.state {
        case .began:
            lastRotationAngle = recognizer.rotation
            _ = dispatchInput(
                state,
                .rotation(RotationEvent(center: center, rotation: 0.0, modifiers: state.modifiers, touchPhase: .started))
            )
        case .changed:
            let delta = Float(recognizer.rotation - lastRotationAngle)
            lastRotationAngle = recognizer.rotation
            _ = dispatchInput(
                state,
                .rotation(RotationEvent(center: center, rotation: delta, modifiers: state.modifiers, touchPhase: .moved))
            )
        case .ended, .cancelled, .failed:
            lastRotationAngle = 0.0
            _ = dispatchInput(
                state,
                .rotation(RotationEvent(center: center, rotation: 0.0, modifiers: state.modifiers, touchPhase: phase))
            )
        default:
            break
        }
    }

    @objc private func handleHover(_ recognizer: UIHoverGestureRecognizer) {
        guard let state = windowState else { return }
        let pos = gpuiPoint(from: recognizer.location(in: self))

        switch recognizer.state {
        case .began:
            if !state.isHovered {
                state.isHovered = true
                state.hoverStatusChangeCallback?(true)
            }
            _ = dispatchInput(
                state,
                .mouseMove(MouseMoveEvent(position: pos, pressedButton: nil, modifiers: state.modifiers))
            )
        case .changed:
            _ = dispatchInput(
                state,
                .mouseMove(MouseMoveEvent(position: pos, pressedButton: nil, modifiers: state.modifiers))
            )
        case .ended, .cancelled, .failed:
            if state.isHovered {
                state.isHovered = false
                state.hoverStatusChangeCallback?(false)
            }
            _ = dispatchInput(
                state,
                .mouseExited(MouseExitEvent(position: pos, pressedButton: nil, modifiers: state.modifiers))
            )
        default:
            break
        }
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard let state = windowState else { return }
        if recognizer.state == .began {
            let pos = gpuiPoint(from: recognizer.location(in: self))
            activePrimaryTouch = nil
            _ = dispatchInput(
                state,
                .mouseDown(
                    MouseDownEvent(
                        button: .right,
                        position: pos,
                        modifiers: state.modifiers,
                        clickCount: 1,
                        firstMouse: false
                    )
                )
            )
            _ = dispatchInput(
                state,
                .mouseUp(
                    MouseUpEvent(
                        button: .right,
                        position: pos,
                        modifiers: state.modifiers,
                        clickCount: 1
                    )
                )
            )
        }
    }

    // MARK: - Hardware Keyboard (`UIPress`) Handling

    override public func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let state = windowState else {
            super.pressesBegan(presses, with: event)
            return
        }

        var unhandled: Set<UIPress> = []
        for press in presses {
            guard let translated = translateHardwarePress(press) else {
                unhandled.insert(press)
                continue
            }

            if translated.isModifierOnly {
                _ = dispatchInput(
                    state,
                    .modifiersChanged(
                        ModifiersChangedEvent(
                            modifiers: translated.modifiers,
                            capslock: translated.capslock
                        )
                    )
                )
                continue
            }

            if let keystroke = translated.keystroke {
                let res = dispatchInput(
                    state,
                    .keyDown(
                        KeyDownEvent(
                            keystroke: keystroke,
                            isHeld: false,
                            preferCharacterInput: false
                        )
                    )
                )
                if res.propagate && !res.defaultPrevented {
                    // Allow UIKit responder chain / backing text input to handle printable text if GPUI didn't consume a shortcut.
                    unhandled.insert(press)
                }
            }
        }

        if !unhandled.isEmpty {
            super.pressesBegan(unhandled, with: event)
        }
    }

    override public func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let state = windowState else {
            super.pressesEnded(presses, with: event)
            return
        }

        var unhandled: Set<UIPress> = []
        for press in presses {
            guard let translated = translateHardwarePress(press) else {
                unhandled.insert(press)
                continue
            }

            if translated.isModifierOnly {
                _ = dispatchInput(
                    state,
                    .modifiersChanged(
                        ModifiersChangedEvent(
                            modifiers: translated.modifiers,
                            capslock: translated.capslock
                        )
                    )
                )
                continue
            }

            if let keystroke = translated.keystroke {
                _ = dispatchInput(state, .keyUp(KeyUpEvent(keystroke: keystroke)))
            }
            unhandled.insert(press)
        }

        if !unhandled.isEmpty {
            super.pressesEnded(unhandled, with: event)
        }
    }

    override public func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        super.pressesCancelled(presses, with: event)
    }
}

// MARK: - Root UIViewController (`GPUIiOSViewController`)

/// Alias matching upstream Objective-C class name `GPUIViewController`.
public typealias GPUIViewController = GPUIiOSViewController

// PORT NOTE: Replaces upstream ObjC runtime `ClassDecl("GPUIViewController")` with a native Swift
// `UIViewController` subclass hosting `GPUIiOSView` edge-to-edge (ADR-0011).

/// Full-screen `UIViewController` hosting a `GPUIiOSView` and optional system material blur backdrop.
@MainActor
public final class GPUIiOSViewController: UIViewController {
    public let gpuiView: GPUIiOSView
    weak var windowState: IosWindowState?

    public init(gpuiView: GPUIiOSView, windowState: IosWindowState? = nil) {
        self.gpuiView = gpuiView
        self.windowState = windowState
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable; use init(gpuiView:windowState:)")
    }

    override public func loadView() {
        let container = UIView(frame: gpuiView.frame)
        container.backgroundColor = .clear
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        gpuiView.frame = container.bounds
        gpuiView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(gpuiView)

        self.view = container
    }

    override public var prefersStatusBarHidden: Bool {
        false
    }

    override public var preferredStatusBarStyle: UIStatusBarStyle {
        guard let appearance = windowState?.appearance else {
            return .default
        }
        switch appearance {
        case .dark, .vibrantDark:
            return .lightContent
        case .light, .vibrantLight:
            return .darkContent
        }
    }
}
#endif
