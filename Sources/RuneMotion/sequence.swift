// Ported from: crates/rune-motion/src/sequence.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

/// A full pose at elapsed seconds. Easing belongs to the segment arriving here.
public struct Beat: Sendable, Equatable {
    public var at: Double
    public var opacity: Float
    public var scale: Float
    public var easing: Easing

    public init(
        at: Double,
        opacity: Float = 1.0,
        scale: Float = 1.0,
        easing: Easing = .easeInOut
    ) {
        self.at = at
        self.opacity = opacity
        self.scale = scale
        self.easing = easing
    }

    public init(_ at: Double) {
        self.init(at: at)
    }

    public static func new(_ at: Double) -> Beat {
        Beat(at: at)
    }

    public func opacity(_ value: Float) -> Beat {
        var copy = self
        copy.opacity = value
        return copy
    }

    public func scale(_ value: Float) -> Beat {
        var copy = self
        copy.scale = value
        return copy
    }

    public func easing(_ easing: Easing) -> Beat {
        var copy = self
        copy.easing = easing
        return copy
    }
}

/// A one-shot sequence. Starts at zero, holds its final pose, and has no app callbacks.
/// Use a new element key to replay.
public struct Sequence: Sendable, Equatable {
    // PORT NOTE: `[Beat]` replaces Rust `&'static [Beat]` with value-type array storage.
    private var frames: [Beat]
    var delaySeconds: Double

    public init(_ frames: [Beat]) {
        precondition(
            frames.count >= 2 && frames[0].at == 0.0,
            "keyframes need at least two poses, starting at zero"
        )
        for i in 0..<(frames.count - 1) {
            precondition(
                frames[i + 1].at.isFinite && frames[i + 1].at > frames[i].at,
                "keyframe times must increase"
            )
        }
        for p in frames {
            precondition(
                p.opacity.isFinite && p.scale.isFinite && p.scale >= 0.0,
                "invalid keyframe pose"
            )
        }
        self.frames = frames
        self.delaySeconds = 0.0
    }

    public static func new(_ frames: [Beat]) -> Sequence {
        Sequence(frames)
    }

    public func delay(_ seconds: Double) -> Sequence {
        precondition(seconds.isFinite && seconds >= 0.0)
        var copy = self
        copy.delaySeconds = seconds
        return copy
    }

    public func duration() -> Double {
        frames[frames.count - 1].at
    }

    func sample(_ elapsed: Double) -> Beat {
        if elapsed <= 0.0 {
            return frames[0]
        }
        var foundIndex: Int?
        for i in 0..<(frames.count - 1) {
            if elapsed < frames[i + 1].at {
                foundIndex = i
                break
            }
        }
        guard let idx = foundIndex else {
            return frames[frames.count - 1]
        }
        let a = frames[idx]
        let b = frames[idx + 1]
        let t = b.easing.eval(Float((elapsed - a.at) / (b.at - a.at)))
        return Beat(
            at: elapsed,
            opacity: a.opacity + (b.opacity - a.opacity) * t,
            scale: max(a.scale + (b.scale - a.scale) * t, 0.0),
            easing: b.easing
        )
    }
}
