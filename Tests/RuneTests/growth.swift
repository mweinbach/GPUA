// Tests ported from: crates/rune/src/growth.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import RuneMotion
import Testing
@testable import Rune

private let foldSpring = Spring.new(0.18, 0.0)

private func runTrack(_ fps: Float, _ dist: Float) -> [(Float, Float)] {
    var t = GrowTrack.settled(0.0)
    t.retarget(dist)
    var acc: Float = 0.0
    var out: [(Float, Float)] = []
    let dt: Float = 1.0 / fps
    let steps = Int(2.0 * fps)
    for k in 1...steps {
        acc += dt
        while acc >= SUBSTEP - 1e-6 {
            t.step(GROWTH, Rune.edge.FEATHER, false)
            acc -= SUBSTEP
        }
        out.append((Float(k) * dt, t.h))
    }
    return out
}

private func runFold(_ from: Float, _ to: Float, _ secs: Float) -> (GrowTrack, [(Float, Float)]) {
    var t = GrowTrack.settled(from)
    t.whole = true
    t.duration = 1.0
    t.setKind(false, true, (FoldGlide(spring: foldSpring, feather: nil), 900.0))
    t.retarget(to)
    var out: [(Float, Float)] = [(0.0, t.h)]
    let steps = Int(secs * 120.0)
    for k in 1...steps {
        t.step(GROWTH, Rune.edge.FEATHER, false)
        t.step(GROWTH, Rune.edge.FEATHER, false)
        out.append((Float(k) / 120.0, t.h))
    }
    return (t, out)
}

private func heightAt(_ hs: [(Float, Float)], _ secs: Float) -> Float {
    hs[Int((secs * 120.0).rounded())].1
}

@Suite("GrowthTests")
struct GrowthTests {
    @Test("same curve at 30 60 120 fps")
    func sameCurveAt30And120Fps() {
        let a = runTrack(30.0, 457.0)
        let c = runTrack(120.0, 457.0)
        for (time, h) in a {
            let match = c.first { abs($0.0 - time) < 1e-3 }!
            #expect(abs(h - match.1) < 0.5)
        }
    }

    @Test("monotone and capped")
    func monotoneAndCapped() {
        let r = runTrack(120.0, 900.0)
        var prev: Float = 0.0
        for (_, h) in r {
            #expect(h >= prev - 1e-4)
            #expect(h - prev <= growthCaps.maxLong / 120.0 + 0.01)
            prev = h
        }
        #expect(abs(r.last!.1 - 900.0) < 0.5)
    }

    @Test("a whole row glides on the spring alone")
    func wholeRowGlidesOnSpringAlone() {
        var t = GrowTrack.settled(0.0)
        t.whole = true
        t.retarget(900.0)
        var prev: Float = 0.0
        var speeds: [Float] = []
        for _ in 0..<180 {
            for _ in 0..<2 {
                t.step(GROWTH, Rune.edge.FEATHER, true)
            }
            #expect(t.h >= prev - 1e-4 && t.h <= 900.0)
            speeds.append(t.h - prev)
            prev = t.h
        }
        let sumAt: (Float) -> Float = { s in
            speeds.prefix(Int(s * 120.0)).reduce(0.0, +)
        }
        #expect(sumAt(0.6) > 0.98 * 900.0)
        #expect(!t.moving())

        var peak = 0
        var peakVal: Float = 0.0
        for (i, v) in speeds.enumerated() where v > peakVal {
            peak = i
            peakVal = v
        }
        for i in 0..<peak {
            #expect(speeds[i + 1] >= speeds[i] - 1e-3)
        }
        for i in peak..<(speeds.count - 1) {
            #expect(speeds[i + 1] <= speeds[i] + 1.0 / 128.0)
        }
    }

    @Test("a far whole glide opens no harder than its reach")
    func farWholeGlideOpensNoHarderThanReach() {
        func maxJerk(_ dist: Float) -> Float {
            var t = GrowTrack.settled(0.0)
            t.whole = true
            t.retarget(dist)
            var prev: Float = 0.0
            var step: Float = 0.0
            var most: Float = 0.0
            for _ in 0..<360 {
                t.step(GROWTH, Rune.edge.FEATHER, false)
                t.step(GROWTH, Rune.edge.FEATHER, false)
                most = max(most, abs(t.h - prev - step))
                step = t.h - prev
                prev = t.h
            }
            #expect(!t.moving())
            return most
        }
        let omega: Float = (2.0 * .pi) / GROWTH.duration
        let most = WHOLE_REACH * omega * omega / (120.0 * 120.0)
        #expect(maxJerk(WHOLE_REACH / 2.0) < 0.6 * most)
        for dist: Float in [WHOLE_REACH, 900.0, 3600.0] {
            #expect(maxJerk(dist) <= most)
        }
    }

    @Test("eases into target")
    func easesIntoTarget() {
        for streaming in [false, true] {
            var t = GrowTrack.settled(0.0)
            t.streaming = streaming
            t.retarget(300.0)
            var speeds: [Float] = []
            var prev: Float = 0.0
            for _ in 0..<120 {
                for _ in 0..<4 {
                    t.step(GROWTH, Rune.edge.FEATHER, false)
                }
                speeds.append(t.h - prev)
                prev = t.h
            }
            for i in 0..<(speeds.count - 1) {
                #expect(!(speeds[i] >= 0.5 && speeds[i + 1] <= 0.15 * speeds[i]))
            }
        }
    }

    @Test("a fold glides on its own spring however far")
    func foldGlidesOnOwnSpringHoweverFar() {
        for (from, to): (Float, Float) in [(40.0, 640.0), (640.0, 40.0), (40.0, 900.0)] {
            let (t, hs) = runFold(from, to, 0.5)
            let left = abs(heightAt(hs, foldSpring.duration) - to)
            #expect(left < 0.02 * abs(to - from))
            #expect(!t.moving())
            for i in 0..<(hs.count - 1) {
                #expect((hs[i + 1].1 - hs[i].1) * (to - from) >= -1e-3)
            }
            let lo = min(from, to) - 1e-3
            let hi = max(from, to) + 1e-3
            #expect(hs.allSatisfy { $0.1 >= lo && $0.1 <= hi })
        }
    }

    @Test("a fold past the window moves only what shows")
    func foldPastWindowMovesOnlyWhatShows() {
        let (shutTrack, shutHs) = runFold(3040.0, 40.0, 0.5)
        #expect(shutHs[0].1 == 900.0)
        #expect(heightAt(shutHs, foldSpring.duration) < 40.0 + 18.0)
        #expect(!shutTrack.moving() && shutTrack.h == 40.0)

        let (openTrack, openHs) = runFold(40.0, 3040.0, 0.5)
        #expect(!openTrack.moving() && openTrack.h == 3040.0)
        let jump = openHs.firstIndex { $0.1 > 900.0 }!
        #expect(openHs[jump - 1].1 > 898.0 && openHs[jump].1 == 3040.0)
        #expect(heightAt(openHs, foldSpring.duration) > 900.0 - 18.0)
        #expect(openHs[jump].0 < 0.3)
    }

    @Test("a fold feathers its moving edge both ways")
    func foldFeathersMovingEdgeBothWays() {
        for (from, to): (Float, Float) in [(40.0, 640.0), (640.0, 40.0)] {
            var t = GrowTrack.settled(from)
            t.whole = true
            t.setKind(false, true, (FoldGlide(spring: foldSpring, feather: 20.0), .infinity))
            t.retarget(to)
            var masks: [Float] = []
            for _ in 0..<120 {
                t.step(GROWTH, Rune.edge.FEATHER, false)
                t.step(GROWTH, Rune.edge.FEATHER, false)
                masks.append(t.mask)
            }
            let peak = masks.max() ?? 0.0
            #expect(abs(peak - 20.0) < 1e-3)
            #expect(masks[0] < 6.0)
            for i in 0..<(masks.count - 1) {
                #expect(abs(masks[i + 1] - masks[i]) < 6.0)
            }
            #expect(masks.last == 0.0)
        }
    }

    @Test("a fold reversed mid glide keeps its velocity")
    func foldReversedMidGlideKeepsVelocity() {
        var t = GrowTrack.settled(640.0)
        t.whole = true
        t.setKind(false, true, (FoldGlide(spring: foldSpring, feather: nil), 900.0))
        t.retarget(40.0)
        for _ in 0..<12 {
            t.step(GROWTH, Rune.edge.FEATHER, false)
        }
        let (h, v) = (t.h, t.v)
        #expect(v < 0.0 && h < 640.0 && h > 40.0)
        t.retarget(640.0)
        #expect(t.h == h)
        t.step(GROWTH, Rune.edge.FEATHER, false)
        #expect(t.h < h)
        var masks: [Float] = [t.mask]
        for _ in 0..<120 {
            t.step(GROWTH, Rune.edge.FEATHER, false)
            masks.append(t.mask)
        }
        for i in 0..<(masks.count - 1) {
            #expect(abs(masks[i + 1] - masks[i]) < 3.0)
        }
        #expect(masks.last == 0.0)
        #expect(!t.moving() && t.h == 640.0)
    }

    @Test("retarget keeps velocity")
    func retargetKeepsVelocity() {
        var t = GrowTrack.settled(0.0)
        t.retarget(100.0)
        for _ in 0..<24 {
            t.step(GROWTH, Rune.edge.FEATHER, false)
        }
        let (h, v) = (t.h, t.v)
        t.retarget(200.0)
        t.step(GROWTH, Rune.edge.FEATHER, false)
        #expect(abs(t.v - v) < abs(v) * 0.5 + 60.0)
        #expect(t.h > h)
    }
}
