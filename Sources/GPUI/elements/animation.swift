// Ported from: crates/gpui/src/elements/animation.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Refineable
import Taffy

/// The linear easing function, or delta itself
public func linear(_ delta: Float) -> Float {
    delta
}

/// The quadratic easing function, delta * delta
public func quadratic(_ delta: Float) -> Float {
    delta * delta
}

/// The quadratic ease-in-out function, which starts and ends slowly but speeds up in the middle
public func easeInOut(_ delta: Float) -> Float {
    if delta < 0.5 {
        return 2.0 * delta * delta
    } else {
        let x = -2.0 * delta + 2.0
        return 1.0 - x * x / 2.0
    }
}

/// The Quint ease-out function, which starts quickly and decelerates to a stop
public func easeOutQuint() -> (Float) -> Float {
    { delta in
        let oneMinus = 1.0 - delta
        let p5 = oneMinus * oneMinus * oneMinus * oneMinus * oneMinus
        return 1.0 - p5
    }
}

/// Apply the given easing function, first in the forward direction and then in the reverse direction
public func bounce(_ easing: @escaping (Float) -> Float) -> (Float) -> Float {
    { delta in
        if delta < 0.5 {
            return easing(delta * 2.0)
        } else {
            return easing((1.0 - delta) * 2.0)
        }
    }
}

/// A custom easing function for pulsating alpha that slows down as it approaches 0.1
public func pulsatingBetween(_ min: Float, _ max: Float) -> (Float) -> Float {
    let range = max - min

    return { delta in
        // Use a combination of sine and cubic functions for a more natural breathing rhythm
        let t = Float(sin(Double(delta * 2.0 * Float.pi)))
        let breath = (t * t * t + t) / 2.0

        // Map the breath to our desired alpha range
        let normalizedAlpha = (breath + 1.0) / 2.0

        return min + (normalizedAlpha * range)
    }
}

/// An animation that can be applied to an element.
public struct Animation {
    /// The amount of time for which this animation should run
    public var duration: Duration
    /// Whether to repeat this animation when it finishes
    public var oneshot: bool
    /// A function that takes a delta between 0 and 1 and returns a new delta
    /// between 0 and 1 based on the given easing function.
    public var easing: (Float) -> Float

    public init(duration: Duration) {
        self.duration = duration
        self.oneshot = true
        self.easing = linear
    }

    /// Create a new animation with the given duration.
    /// By default the animation will only run once and will use a linear easing function.
    public static func new(_ duration: Duration) -> Self {
        Self(duration: duration)
    }

    /// Set the animation to loop when it finishes.
    public func `repeat`() -> Self {
        var copy = self
        copy.oneshot = false
        return copy
    }

    /// Set the easing function to use for this animation.
    public func withEasing(_ easing: @escaping (Float) -> Float) -> Self {
        var copy = self
        copy.easing = easing
        return copy
    }
}

public typealias bool = Bool

/// An extension trait for adding the animation wrapper to both Elements and Components
public protocol AnimationExt: IntoElement {
    func withAnimation(
        _ id: ElementId,
        _ animation: Animation,
        _ animator: @escaping (Self, Float) -> Self
    ) -> AnimationElement<Self>

    func withAnimations(
        _ id: ElementId,
        _ animations: [Animation],
        _ animator: @escaping (Self, Int, Float) -> Self
    ) -> AnimationElement<Self>
}

extension AnimationExt {
    public func withAnimation(
        _ id: ElementId,
        _ animation: Animation,
        _ animator: @escaping (Self, Float) -> Self
    ) -> AnimationElement<Self> {
        AnimationElement(
            id: id,
            element: self,
            animations: [animation],
            animator: { this, _, value in animator(this, value) }
        )
    }

    public func withAnimations(
        _ id: ElementId,
        _ animations: [Animation],
        _ animator: @escaping (Self, Int, Float) -> Self
    ) -> AnimationElement<Self> {
        AnimationElement(
            id: id,
            element: self,
            animations: animations,
            animator: animator
        )
    }
}

extension IntoElement {
    public func withAnimation(
        _ id: ElementId,
        _ animation: Animation,
        _ animator: @escaping (Self, Float) -> Self
    ) -> AnimationElement<Self> {
        AnimationElement(
            id: id,
            element: self,
            animations: [animation],
            animator: { this, _, value in animator(this, value) }
        )
    }

    public func withAnimations(
        _ id: ElementId,
        _ animations: [Animation],
        _ animator: @escaping (Self, Int, Float) -> Self
    ) -> AnimationElement<Self> {
        AnimationElement(
            id: id,
            element: self,
            animations: animations,
            animator: animator
        )
    }
}

public struct AnimationState {
    public var start: Date
    public var animationIx: Int

    public init(start: Date = Date(), animationIx: Int = 0) {
        self.start = start
        self.animationIx = animationIx
    }
}

/// A GPUI element that applies an animation to another element
public struct AnimationElement<E: IntoElement>: Element, IntoElement {
    public typealias RequestLayoutState = AnyElement
    public typealias PrepaintState = Void

    public var elementId: ElementId
    public var element: E?
    public var animations: [Animation]
    public var animator: (E, Int, Float) -> E

    public init(
        id: ElementId,
        element: E,
        animations: [Animation],
        animator: @escaping (E, Int, Float) -> E
    ) {
        self.elementId = id
        self.element = element
        self.animations = animations
        self.animator = animator
    }

    public func id() -> ElementId? {
        self.elementId
    }

    public func sourceLocation() -> String? {
        nil
    }

    /// Returns a new AnimationElement after applying the given function
    /// to the element being animated.
    public func mapElement(_ f: (E) -> E) -> AnimationElement<E> {
        var copy = self
        if let el = copy.element {
            copy.element = f(el)
        }
        return copy
    }

    @MainActor
    public mutating func requestLayout(
        _ globalId: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ window: inout Window,
        _ cx: inout App
    ) -> (LayoutId, AnyElement) {
        guard let globalId = globalId else {
            fatalError("AnimationElement requires a global ID")
        }

        return window.withElementState(globalId) { (state: AnimationState?, window: inout Window) -> ((LayoutId, AnyElement), AnimationState?) in
            var animState = state ?? AnimationState(start: Date(), animationIx: 0)
            let animationIx = animState.animationIx
            let anim = self.animations[animationIx]

            let durationSeconds = Float(anim.duration.components.seconds) + Float(anim.duration.components.attoseconds) / 1e18
            let elapsed = Float(Date().timeIntervalSince(animState.start))
            var delta = durationSeconds > 0 ? (elapsed / durationSeconds) : 1.0

            var done = false
            if delta > 1.0 {
                if anim.oneshot {
                    if animationIx >= self.animations.count - 1 {
                        done = true
                    } else {
                        animState.start = Date()
                        animState.animationIx += 1
                    }
                    delta = 1.0
                } else {
                    delta = delta.truncatingRemainder(dividingBy: 1.0)
                }
            }

            let easedDelta = anim.easing(delta)
            let clampedDelta = min(max(easedDelta, 0.0), 1.0)

            guard let baseElement = self.element else {
                fatalError("AnimationElement requestLayout called more than once")
            }
            self.element = nil

            var renderedElement = self.animator(baseElement, animationIx, clampedDelta).intoAnyElement()

            if !done {
                window.requestAnimationFrame()
            }

            let layoutId = renderedElement.requestLayout(&window, &cx)
            return ((layoutId, renderedElement), animState)
        }
    }

    @MainActor
    public mutating func prepaint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ element: inout AnyElement,
        _ window: inout Window,
        _ cx: inout App
    ) {
        _ = element.prepaint(&window, &cx)
    }

    @MainActor
    public mutating func paint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ element: inout AnyElement,
        _ prepaint: inout Void,
        _ window: inout Window,
        _ cx: inout App
    ) {
        element.paint(&window, &cx)
    }

    public func intoElement() -> AnimationElement<E> {
        self
    }
}
