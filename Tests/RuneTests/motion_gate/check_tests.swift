// Tests ported from: crates/rune/src/motion_gate/check_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Testing
@testable import Rune

private func makeRec(_ tracks: [(String, [(Int, [Float], Float)])], _ frames: Int) -> MotionGateRecording {
    var r = MotionGateRecording.new((1000.0, 1000.0), 120.0)
    r.frames = frames
    for (path, fs) in tracks {
        let i = r.track(path, nil)
        r.tracks[i].frames = fs.map { (k, rect, op) in
            (k, MotionGateSnap(rect: rect, vis: rect, op: op, scale: 1.0, flags: MG_INK, phase: .nan, scrolled: [0.0, 0.0]))
        }
    }
    return r
}

private func findingKinds(_ r: MotionGateRecording) -> [String] {
    motionGateCheck(r).map(\.kind)
}

/// A list's content, scrolled into a 400 pt viewport at the window's top, and rows in it: each
/// track's rect per frame, its visible part the rect cut to the viewport.
private func makeScrolledList(_ tracks: [(String, [[Float]])]) -> MotionGateRecording {
    var r = MotionGateRecording.new((1000.0, 1000.0), 120.0)
    r.frames = 60
    for (path, rects) in tracks {
        let parent: Int? = {
            guard let slash = path.lastIndex(of: "/") else { return nil }
            let p = String(path[..<slash])
            return r.tracks.firstIndex(where: { $0.path == p })
        }()
        let i = r.track(path, parent)
        r.tracks[i].frames = rects.enumerated().map { (k, rect) in
            let y0 = max(rect[1], 0.0)
            let y1 = min(rect[1] + rect[3], 400.0)
            let vis: [Float] = [rect[0], y0, rect[2], max(y1 - y0, 0.0)]
            return (k, MotionGateSnap(rect: rect, vis: vis, op: 1.0, scale: 1.0, flags: MG_INK, phase: .nan, scrolled: [0.0, 600.0]))
        }
    }
    return r
}

@Suite("MotionGateCheckTests")
struct MotionGateCheckTests {
    @Test("A spring passes and a snap jumps")
    func aSpringPassesAndASnapJumps() {
        let smooth: [(Int, [Float], Float)] = (0..<60).map { k in
            let p = 1.0 - Float(exp(-Double(k) / 8.0))
            return (k, [0.0, 300.0 - 200.0 * p, 100.0, 40.0], 1.0)
        }
        #expect(findingKinds(makeRec([("a", smooth)], 60)).isEmpty)

        let snap: [(Int, [Float], Float)] = (0..<60).map { k in
            (k, [0.0, k < 30 ? 300.0 : 100.0, 100.0, 40.0], 1.0)
        }
        #expect(findingKinds(makeRec([("a", snap)], 60)) == ["jump"])

        // Gliding at 4 pt a frame, then lurching to 20.
        var y: Float = 0.0
        let lurch: [(Int, [Float], Float)] = (0..<60).map { k in
            if k > 0 && k < 40 {
                y += (k < 20) ? 4.0 : 20.0
            }
            return (k, [0.0, y, 100.0, 40.0], 1.0)
        }
        #expect(findingKinds(makeRec([("a", lurch)], 60)) == ["jerk"])
    }

    @Test("An instant toggle is reported where the height changed")
    func anInstantToggleIsReportedWhereTheHeightChanged() {
        let group: [(Int, [Float], Float)] = (0..<60).map { k in
            (k, [0.0, 100.0, 100.0, k < 30 ? 28.0 : 84.0], 1.0)
        }
        let below: [(Int, [Float], Float)] = (0..<60).map { k in
            (k, [0.0, k < 30 ? 128.0 : 184.0, 100.0, 40.0], 1.0)
        }
        var r = makeRec([("g", group), ("b", below)], 60)
        #expect(findingKinds(r) == ["jump", "jump"])
        r.inputs.append((30, "tap"))
        let f = motionGateCheck(r)
        #expect(f.count == 1)
        #expect(f.first?.kind == "jump")
        #expect(f.first?.element == "g")
    }

    @Test("Pops, overshoot, reversal, and flicker")
    func popsOvershootReversalAndFlicker() {
        let pop: [(Int, [Float], Float)] = (20..<60).map { k in (k, [0.0, 0.0, 100.0, 40.0], 1.0) }
        #expect(findingKinds(makeRec([("a", pop)], 60)) == ["pop-in"])

        let gone: [(Int, [Float], Float)] = (0..<20).map { k in (k, [0.0, 0.0, 100.0, 40.0], 1.0) }
        #expect(findingKinds(makeRec([("a", gone)], 60)) == ["pop-out"])

        let over: [(Int, [Float], Float)] = (0..<60).map { k in
            let t = Double(k) / 8.0
            let y = 100.0 + 100.0 * Float(1.0 - exp(-t) * cos(t * 1.5))
            return (k, [0.0, y, 100.0, 40.0], 1.0)
        }
        #expect(findingKinds(makeRec([("a", over)], 60)).contains("overshoot"))

        let dogleg: [(Int, [Float], Float)] = (0..<60).map { k in
            let t = Float(k) / 59.0
            let y = 100.0 - 40.0 * min(t * 3.0, 1.0) * (1.0 - t) * 4.0 + 200.0 * t * t
            return (k, [0.0, y, 100.0, 40.0], 1.0)
        }
        #expect(findingKinds(makeRec([("a", dogleg)], 60)).contains("reversal"))

        let blink: [(Int, [Float], Float)] = (0..<60).map { k in
            (k, [0.0, 0.0, 100.0, 40.0], (20..<24).contains(k) ? 0.3 : 1.0)
        }
        #expect(findingKinds(makeRec([("a", blink)], 60)) == ["flicker"])

        // A container whose contents are all hidden draws nothing as it dips.
        var r = makeRec([("a", blink)], 60)
        for idx in r.tracks[0].frames.indices {
            r.tracks[0].frames[idx].1.flags = 0
        }
        #expect(findingKinds(r).isEmpty)
    }

    @Test("Words that swap in place are a text-swap, while a ticking count or streaming growth is not")
    func wordsThatSwapInPlaceAreATextSwapButATickingCountIsNot() {
        let still: [(Int, [Float], Float)] = (0..<60).map { k in (k, [0.0, 0.0, 100.0, 20.0], 1.0) }
        func withWords(_ words: [(Int, String)]) -> [String] {
            var r = makeRec([("a", still)], 60)
            r.tracks[0].words = words
            return findingKinds(r)
        }
        #expect(withWords([(0, "Read backoff.ts"), (30, "Grep retryBudget")]) == ["text-swap"])
        #expect(withWords([(0, "9s"), (30, "10s")]).isEmpty)
        #expect(withWords([(0, "Looks"), (30, "Looks right")]).isEmpty)
    }

    @Test("A loop that restarts jumps and a finished run goes quiet")
    func aLoopThatRestartsJumpsAndAFinishedRunGoesQuiet() {
        let still: [(Int, [Float], Float)] = (0..<120).map { k in (k, [0.0, 0.0, 100.0, 20.0], 1.0) }
        func looping(_ restart: Int?) -> MotionGateRecording {
            var r = makeRec([("a", still)], 120)
            for idx in r.tracks[0].frames.indices {
                let k = r.tracks[0].frames[idx].0
                let t: Int
                if let at = restart, k >= at {
                    t = k - at
                } else {
                    t = k
                }
                let raw = (Float(t) / 144.0).truncatingRemainder(dividingBy: 1.0)
                r.tracks[0].frames[idx].1.phase = raw < 0.0 ? raw + 1.0 : raw
            }
            return r
        }
        #expect(findingKinds(looping(nil)).isEmpty)
        #expect(findingKinds(looping(60)) == ["loop-jump"])

        let longStill: [(Int, [Float], Float)] = (0..<300).map { k in (k, [0.0, 0.0, 100.0, 20.0], 1.0) }
        var r = makeRec([("a", longStill)], 300)
        r.quietFrom = 100
        r.awake = (0..<300).map { $0 < 180 }
        #expect(findingKinds(r).isEmpty)
        r.awake[260] = true
        #expect(findingKinds(r) == ["wakes-after-end"])
    }

    @Test("A row that loses its key remounts while one that becomes another element does not")
    func aRowThatLosesItsKeyRemountsButOneThatBecomesAnotherElementDoesNot() {
        func fade(_ from: Int, _ to: Int, _ out: Bool) -> [(Int, [Float], Float)] {
            (from..<to).map { k in
                let op: Float
                if out && k >= 30 {
                    op = 1.0 - Float(k - 29) / 10.0
                } else if !out {
                    op = min(Float(k - 29) / 10.0, 1.0)
                } else {
                    op = 1.0
                }
                return (k, [0.0, 0.0, 300.0, 20.0], op)
            }
        }
        func found(_ old: String, _ new: String) -> Bool {
            var r = makeRec([(old, fade(0, 40, true)), (new, fade(30, 60, false))], 60)
            for idx in r.tracks[0].frames.indices where r.tracks[0].frames[idx].0 >= 30 {
                r.tracks[0].frames[idx].1.flags |= MG_EXITING
            }
            for idx in r.tracks.indices {
                r.tracks[idx].text = "Got it, I'll look."
            }
            return findingKinds(r).contains("remount")
        }
        #expect(found("list/row-0/label", "list/row-1/label"))
        #expect(!found("tray/pending/label", "list/row/text"))
    }

    @Test("A pinned scroll that stops following is unpinned unless someone scrolled")
    func aPinnedScrollThatStopsFollowingIsUnpinnedUnlessSomeoneScrolled() {
        let view: [(Int, [Float], Float)] = (0..<60).map { k in (k, [0.0, 0.0, 100.0, 200.0], 1.0) }
        func grows(_ follows: Bool) -> [(Int, [Float], Float)] {
            (0..<60).map { k in
                let h = 400.0 + Float(max(k - 30, 0))
                return (k, [0.0, follows ? 200.0 - h : -200.0, 100.0, h], 1.0)
            }
        }
        func unpinned(_ follows: Bool, _ input: String?) -> Bool {
            var r = makeRec([("scroll", view), ("scroll/content", grows(follows))], 60)
            r.tracks[1].parent = 0
            for idx in r.tracks[1].frames.indices {
                r.tracks[1].frames[idx].1.vis = [0.0, 0.0, 100.0, 200.0]
            }
            if let what = input {
                r.inputs.append((31, what))
            }
            return findingKinds(r).contains("unpinned")
        }
        #expect(!unpinned(true, nil))
        #expect(unpinned(false, nil))
        #expect(unpinned(false, "event (3 left)"))
        #expect(!unpinned(false, "scroll up"))
    }

    @Test("A second sibling under one key shows twice")
    func aSecondSiblingUnderOneKeyShowsTwice() {
        func makeRow(_ y: Float) -> [(Int, [Float], Float)] {
            (0..<60).map { k in (k, [0.0, y, 100.0, 20.0], 1.0) }
        }
        #expect(findingKinds(makeRec([("list/row-7", makeRow(0.0))], 60)).isEmpty)
        #expect(findingKinds(makeRec([("list/row-7", makeRow(0.0)), ("list/row-7#dup1", makeRow(20.0))], 60)) == ["twice"])
    }

    @Test("A flight that lands under a clip lands unseen")
    func aFlightThatLandsUnderAClipLandsUnseen() {
        let flight: [(Int, [Float], Float)] = (0..<60).map { k in
            let t = min(Float(k) / 30.0, 1.0)
            return (k, [0.0, 100.0 + 300.0 * t * t * (3.0 - 2.0 * t), 100.0, 40.0], 1.0)
        }
        func landed(_ clipped: Bool, _ moved: Bool) -> [String] {
            let fs: [(Int, [Float], Float)] = moved
                ? flight
                : (0..<60).map { k in (k, [0.0, 400.0, 100.0, 40.0], 1.0) }
            var r = makeRec([("flight", fs)], 60)
            if clipped {
                for idx in r.tracks[0].frames.indices where r.tracks[0].frames[idx].0 >= 40 {
                    r.tracks[0].frames[idx].1.vis = [0.0, 0.0, 0.0, 0.0]
                }
            }
            return findingKinds(r)
        }
        #expect(landed(false, true).isEmpty)
        #expect(landed(true, true) == ["lands-unseen"])
        #expect(landed(true, false).isEmpty)
    }

    @Test("Where counts roll, a ticking count is a text-swap unless its digits roll")
    func whereCountsRollATickingCountIsATextSwapButARollingLabelIsNot() {
        let still: [(Int, [Float], Float)] = (0..<60).map { k in (k, [0.0, 0.0, 100.0, 20.0], 1.0) }
        var r = makeRec([("count", still)], 60)
        r.tracks[0].words = [(0, "9s"), (30, "10s")]
        #expect(findingKinds(r).isEmpty)
        r.countsRoll = true
        #expect(findingKinds(r) == ["text-swap"])

        let glyph = r.track("count/digit-1", 0)
        r.tracks[glyph].frames = (0..<60).map { k in
            (k, MotionGateSnap(rect: [0.0, 0.0, 8.0, 20.0], vis: [0.0, 0.0, 8.0, 20.0], op: 1.0, scale: 1.0, flags: MG_INK, phase: .nan, scrolled: [0.0, 0.0]))
        }
        #expect(findingKinds(r).isEmpty)
    }

    @Test("Motion inside a scroll is judged against the scroll")
    func motionInsideAScrollIsJudgedAgainstTheScroll() {
        func offset(_ k: Int) -> Float { 2.0 * Float(k) }
        func run(_ own: (Int) -> Float, _ flags: UInt8, _ told: Bool) -> [String] {
            let fs: [(Int, [Float], Float)] = (0..<60).map { k in
                (k, [0.0, 300.0 + own(k) - offset(k), 100.0, 40.0], 1.0)
            }
            var r = makeRec([("list/node", fs)], 60)
            for idx in r.tracks[0].frames.indices {
                let k = r.tracks[0].frames[idx].0
                r.tracks[0].frames[idx].1.flags |= flags
                if told {
                    r.tracks[0].frames[idx].1.scrolled = [0.0, offset(k)]
                }
            }
            return findingKinds(r)
        }

        let glide: (Int) -> Float = { k in 60.0 * (1.0 - Float(exp(-Double(k) / 8.0))) }
        #expect(run(glide, 0, false) == ["reversal"])
        #expect(run(glide, 0, true).isEmpty)
        #expect(run(glide, MG_SCROLLING, true).isEmpty)

        let wobble: (Int) -> Float = { k in 2.5 * Float(sin(Double(k) * 0.6)) }
        #expect(run(wobble, 0, false).isEmpty)
        #expect(run(wobble, 0, true) == ["jiggle"])
        #expect(run(wobble, MG_SCROLLING, true) == ["jiggle"])
    }

    @Test("A jump is what shows jumping")
    func aJumpIsWhatShowsJumping() {
        func at(_ k: Int, _ a: [Float], _ b: [Float]) -> [Float] { k < 30 ? a : b }
        func still(_ rect: [Float]) -> [[Float]] { Array(repeating: rect, count: 60) }

        let list = still([0.0, -600.0, 100.0, 2000.0])
        let row: [[Float]] = (0..<60).map { k in at(k, [0.0, 100.0, 100.0, 40.0], [0.0, 200.0, 100.0, 40.0]) }
        #expect(findingKinds(makeScrolledList([("list", list), ("list/row", row)])) == ["jump"])

        let content1: [[Float]] = (0..<60).map { k in at(k, [0.0, -1100.0, 100.0, 1500.0], [0.0, -200.0, 100.0, 600.0]) }
        let fold: [[Float]] = (0..<60).map { k in at(k, [0.0, -900.0, 100.0, 1200.0], [0.0, 0.0, 100.0, 300.0]) }
        func shown(_ y: Float) -> [[Float]] { still([0.0, y, 100.0, 40.0]) }
        let r = makeScrolledList([
            ("list", content1),
            ("list/fold", fold),
            ("list/fold/a", shown(100.0)),
            ("list/fold/b", shown(200.0)),
            ("list/c", shown(320.0)),
        ])
        #expect(findingKinds(r).isEmpty)

        let content2: [[Float]] = (0..<60).map { k in at(k, [0.0, -600.0, 100.0, 2000.0], [0.0, -500.0, 100.0, 2000.0]) }
        func movedRow(_ y: Float) -> [[Float]] {
            (0..<60).map { k in at(k, [0.0, y, 100.0, 40.0], [0.0, y + 100.0, 100.0, 40.0]) }
        }
        #expect(
            findingKinds(makeScrolledList([
                ("list", content2),
                ("list/a", movedRow(0.0)),
                ("list/b", movedRow(100.0)),
                ("list/c", movedRow(200.0)),
            ])) == ["offset-jump"]
        )
    }
}
