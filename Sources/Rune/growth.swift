// Ported from: crates/rune/src/growth.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Timeline growth: rows of a growth stack ease their heights on one spring with speed limits
//! per second, and positions are derived from the presented heights above.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(Musl)
import Musl
#elseif os(Windows)
import ucrt
#elseif os(WASI)
import WASILibc
#endif
import RuneMotion

/// One streaming-edge variant (research/18 §1). Desktop's per-frame values × 60.
public struct StreamEdge: Sendable, Equatable {
    public var name: String
    /// Largest feather height (points).
    public var maskMax: Float
    /// Smallest feather height while growing (points).
    public var floor: Float
    /// How fast the feather shrinks back (points per second).
    public var shrink: Float
    /// Multiplier on the near-target slowdown cap.
    public var catchUp: Float
    /// Multiplier on the growth spring's duration.
    public var duration: Float
    /// Clip the row at its presented height (else content overflows while it grows).
    public var clip: Bool
    /// Word fade-in duration in seconds (0 = words appear at once).
    public var wordFade: Float

    public init(
        name: String,
        maskMax: Float,
        floor: Float,
        shrink: Float,
        catchUp: Float,
        duration: Float,
        clip: Bool,
        wordFade: Float
    ) {
        self.name = name
        self.maskMax = maskMax
        self.floor = floor
        self.shrink = shrink
        self.catchUp = catchUp
        self.duration = duration
        self.clip = clip
        self.wordFade = wordFade
    }
}

public enum edge {
    public static let feather = StreamEdge(
        name: "feather",
        maskMax: 28.0,
        floor: 18.0,
        shrink: 1.8 * 60.0,
        catchUp: 1.0,
        duration: 1.0,
        clip: true,
        wordFade: 0.18
    )
    public static let fastFeather = StreamEdge(
        name: "fast-feather",
        maskMax: 12.0,
        floor: 6.0,
        shrink: 4.0 * 60.0,
        catchUp: 2.4,
        duration: 0.55,
        clip: true,
        wordFade: 0.18
    )
    public static let noMask = StreamEdge(
        name: "no-mask",
        maskMax: 0.0,
        floor: 0.0,
        shrink: 28.0 * 60.0,
        catchUp: 1.0,
        duration: 1.0,
        clip: false,
        wordFade: 0.0
    )
    public static let wordFade = StreamEdge(
        name: "word-fade",
        maskMax: 0.0,
        floor: 0.0,
        shrink: 28.0 * 60.0,
        catchUp: 1.0,
        duration: 1.0,
        clip: false,
        wordFade: 0.36
    )
    public static let all: [StreamEdge] = [feather, fastFeather, noMask, wordFade]

    public static let FEATHER = feather
    public static let FAST_FEATHER = fastFeather
    public static let NO_MASK = noMask
    public static let WORD_FADE = wordFade
    public static let ALL = all
}

/// `timeline.growth`: 0.32 s, bounce 0 (`row-growth.ts:6-14 @ 39eb86d`).
public let GROWTH: Spring = Spring.new(0.32, 0.0)

/// The farthest a whole row (`El.arrivesWhole`) glides in the spring's own duration.
public let WHOLE_REACH: Float = 300.0

/// Speed limits in points per second (Desktop's per-frame caps × 60).
public enum growthCaps {
    public static let start: Float = 1.875 * 60.0
    public static let rampPerS: Float = 28.2 // ln(1.6) * 60
    public static let max: Float = 11.5 * 60.0
    public static let maxLong: Float = 16.0 * 60.0
    public static let longDistance: Float = 240.0
    public static let carryingTail: Float = 7.5 * 60.0
    public static let near: Float = 36.0
    public static let maskGrow: Float = 5.0 * 60.0
    public static let maxDecel: Float = 1800.0
    public static let approach: Float = 14.0
    public static let approachMin: Float = 3.0
}

public let SUBSTEP: Float = 1.0 / 240.0
private let foldFeatherGrow: Float = 600.0

public struct FoldGlide: Sendable, Equatable {
    public var spring: Spring
    public var feather: Float?

    public init(spring: Spring, feather: Float? = nil) {
        self.spring = spring
        self.feather = feather
    }
}

public struct GrowTrack: Sendable {
    public var h: Float = 0.0
    public var v: Float = 0.0
    public var target: Float = 0.0
    public var age: Float = 0.0
    public var mask: Float = 0.0
    public var streaming: Bool = false
    public var whole: Bool = false
    var duration: Float = 0.0
    var span: Float = 0.0
    var glide: Spring? = nil
    var feather: Float? = nil
    var limit: Float = .infinity
    var stage: Float? = nil
    var slide: (Float, Float)? = nil
    var restore: Float = 0.0
    var give: Float? = nil

    public init() {}

    public static func settled(_ h: Float) -> GrowTrack {
        var t = GrowTrack()
        t.h = h
        t.target = h
        return t
    }

    public func moving() -> Bool {
        abs(h - target) > 1.0 / 128.0 || abs(v) > 0.5 || mask > 0.01
    }

    public mutating func retarget(_ newTarget: Float) {
        if abs(newTarget - target) > 1e-4 {
            let currentLift = lift()
            if !moving() {
                age = 0.0
            }
            target = newTarget
            span = abs(newTarget - h)
            stage = nil
            give = nil
            if glide != nil {
                if newTarget < h && h > limit {
                    h = max(limit, newTarget)
                } else if newTarget > h && newTarget > limit {
                    stage = max(limit, h)
                }
                span = abs(newTarget - h)
            }
            let d = newTarget - h
            if currentLift > 1.0 / 64.0 && abs(d) > 1.0 / 64.0 {
                slide = (currentLift * newTarget / d, -currentLift / d)
            } else {
                slide = nil
            }
        }
    }

    func lift() -> Float {
        guard let (a, b) = slide else { return 0.0 }
        return max(a + b * h, 0.0)
    }

    mutating func hideAbove(_ above: Float) -> Float {
        let pinned = lift() + h
        let cut = max(min(above, h - target), 0.0)
        h -= cut
        span = abs(target - h)
        slide = (pinned, -1.0)
        return cut
    }

    mutating func rideUp(_ rise: Float) {
        let from = lift()
        let curH = h
        let st = min(curH + max(rise, 0.0), target)
        let d = st - curH
        let end = target - st
        let b: Float = d > 1.0 / 64.0 ? (end - from) / d : 0.0
        slide = (d > 1.0 / 64.0 ? from - b * curH : end, b)
        stage = st
        span = d
    }

    func shuttingFold() -> Bool {
        glide != nil && h > target + 0.01
    }

    mutating func setKind(_ streaming: Bool, _ whole: Bool, _ foldGlide: (FoldGlide, Float)?) {
        self.streaming = streaming
        self.whole = whole
        let activeGlide = streaming ? nil : foldGlide
        self.glide = activeGlide?.0.spring
        self.feather = activeGlide?.0.feather
        self.limit = activeGlide?.1 ?? .infinity
    }

    /// Advance one fixed substep.
    public mutating func step(_ spring: Spring, _ streamEdge: StreamEdge, _ carryingTail: Bool) {
        let dt = SUBSTEP
        let effectiveSpring = spring.withDuration(max(spring.duration, duration) * max(streamEdge.duration, 0.05))
        let aim = stage ?? target
        let rem = aim - h
        if stage != nil && abs(rem) < 1.0 {
            restore += lift()
            slide = nil
            h = target
            v = 0.0
            stage = nil
        } else if abs(rem) <= 1.0 / 128.0 && abs(v) < 0.5 {
            h = target
            v = 0.0
        } else if let own = glide, !streaming {
            let (x, nv) = own.sample(h, v, aim, dt)
            let landed = (rem >= 0.0 && x >= aim) || (rem <= 0.0 && x <= aim)
            h = landed ? aim : x
            v = landed ? 0.0 : nv
            age += dt
        } else if whole {
            let stretch = max(sqrtf(span / WHOLE_REACH), 1.0)
            let wholeSpring = effectiveSpring.withDuration(effectiveSpring.duration * stretch)
            let (x, nv) = wholeSpring.sample(h, v, target, dt)
            let landed = (rem >= 0.0 && x >= target) || (rem <= 0.0 && x <= target)
            h = landed ? target : x
            v = landed ? 0.0 : nv
            age += dt
        } else {
            let (x, _) = effectiveSpring.sample(h, v, target, dt)
            var cap = abs(rem) > growthCaps.longDistance ? growthCaps.maxLong : growthCaps.max
            if carryingTail {
                cap = min(cap, growthCaps.carryingTail)
            }
            cap = min(cap, growthCaps.start * RuneMotion.math.exp(growthCaps.rampPerS * age))
            if streaming && rem > 0.0 && rem < growthCaps.near {
                cap = min(cap, (0.085 * rem + 0.65 * min(rem / 4.0, 1.0)) * 60.0 * streamEdge.catchUp)
            }
            let braking = sqrtf(2.0 * growthCaps.maxDecel * abs(rem))
            cap = max(cap, min(abs(v) - growthCaps.maxDecel * dt, braking))
            cap = min(cap, growthCaps.approach * abs(rem) + growthCaps.approachMin)
            var d = x - h
            let lim = cap * dt
            d = min(max(d, -lim), lim)
            let landed = (rem >= 0.0 && d >= rem) || (rem <= 0.0 && d <= rem)
            if landed {
                d = rem
            }
            h += d
            v = landed ? 0.0 : (d / dt)
            age += dt
        }

        let left = max(target - h, 0.0)
        let aimMask: Float = left > 0.25 ? min(streamEdge.maskMax, max(streamEdge.floor, 1.5 * left)) : 0.0
        if glide != nil && !streaming {
            let absLeft = abs(target - h)
            let riding = slide?.1 == -1.0
            let foldAim: Float = (absLeft > 0.25 && !riding)
                ? min(feather ?? streamEdge.maskMax, 1.5 * absLeft)
                : 0.0
            mask = foldAim > mask ? min(mask + foldFeatherGrow * dt, foldAim) : foldAim
        } else if aimMask > mask {
            mask = min(mask + growthCaps.maskGrow * dt, aimMask)
        } else {
            mask = max(mask - streamEdge.shrink * dt, aimMask)
        }
        if !moving() {
            slide = nil
        }
    }
}
