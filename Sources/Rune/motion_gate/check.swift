// Ported from: crates/rune/src/motion_gate/check.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Frame-by-frame motion checks over a run's element tree.

#if !os(WASI)
import Foundation
#endif

/// One finding kind, its threshold and what it means.
public struct MotionGateRule: Sendable, Equatable {
    public let kind: String
    public let threshold: Float
    public let means: String

    public init(kind: String, threshold: Float, means: String) {
        self.kind = kind
        self.threshold = threshold
        self.means = means
    }
}

public let MOTION_GATE_RULES: [MotionGateRule] = [
    MotionGateRule(kind: "pop-in", threshold: 0.5, means: "mounts at or above this opacity, at full size, with no fade, growth or scale (and no ancestor transitioning)"),
    MotionGateRule(kind: "pop-out", threshold: 0.5, means: "unmounts at or above this opacity: it vanished instead of leaving"),
    MotionGateRule(kind: "cut-exit", threshold: 0.05, means: "unmounts above this opacity, below pop-out's: a fade cut short"),
    MotionGateRule(kind: "jump", threshold: 2.0, means: "an edge moves at least this many pt in one frame between still frames, where it shows (its visible part, or what it holds that shows, moves with it, or it brings what it holds into view with no input)"),
    MotionGateRule(kind: "offset-jump", threshold: 2.0, means: "a jump of a scroll's content: every row in it moved by the same delta in one frame"),
    MotionGateRule(kind: "appear-then-jump", threshold: 2.0, means: "mounts, then moves at least this many pt on its next frame"),
    MotionGateRule(kind: "jerk", threshold: 10.0, means: "a moving edge's per-frame step changes by more than this many pt from one frame to the next"),
    MotionGateRule(kind: "reversal", threshold: 1.0, means: "a travelling edge heads this many pt the wrong way and turns back, with no input mid-flight (one monotonic path)"),
    MotionGateRule(kind: "overshoot", threshold: 1.0, means: "passes where it comes to rest by this many pt (bounce 0)"),
    MotionGateRule(kind: "jiggle", threshold: 1.0, means: "an edge reverses twice or more within one motion, over at least this many pt"),
    MotionGateRule(kind: "text-swap", threshold: 0.5, means: "a text element's words change in one frame at or above this opacity, with no roll or crossfade (streaming text excepted)"),
    MotionGateRule(kind: "fade-snap", threshold: 0.5, means: "a mounted element's opacity steps by at least this in one frame: it blinks on or off instead of fading"),
    MotionGateRule(kind: "flicker", threshold: 0.3, means: "opacity dips by at least this much and comes back within 0.3 s, or an element vanishes and comes back at its place"),
    MotionGateRule(kind: "faint", threshold: 0.25, means: "geometry checks skip frames fainter than this opacity: a row fading out can't be seen to lurch"),
    MotionGateRule(kind: "load-motion", threshold: 1.0, means: "a row that loaded with the view moves or fades by more than this after its first frame (no animation on load)"),
    MotionGateRule(kind: "never-settles", threshold: 0.05, means: "still changing by more than this in the last half second of the run, long after the last input (loops excepted)"),
    MotionGateRule(kind: "loop-jump", threshold: 0.03, means: "a loop's phase steps this many periods off its usual step in one frame: it restarted or skipped (a remount, or a new loop where one was running)"),
    MotionGateRule(kind: "wakes-after-end", threshold: 1.0, means: "still asking for frames this many seconds after the cell's motion ended (a run that finished)"),
    MotionGateRule(kind: "lands-unseen", threshold: 40.0, means: "travels at least this many pt in plain view, then its clip cuts it from view in one frame where it rests: it flew somewhere you can't see"),
    MotionGateRule(kind: "remount", threshold: 2.0, means: "words start leaving while the same words mount elsewhere within this many frames: one thing fades out at its old place as its copy fades in (its row lost its key)"),
    MotionGateRule(kind: "unpinned", threshold: 2.0, means: "a scroll pinned to its end has its content's bottom this many pt below the viewport with no input since: it stopped following"),
    MotionGateRule(kind: "scroll-commit", threshold: 0.25, means: "the app ran its view (its `poll`, a handler or a layout read) on 6 or more of a scroll's frames and at least this share of them: a scroll needs no commit, so each one is a frame's whole view rebuilt mid-gesture"),
    MotionGateRule(kind: "twice", threshold: 0.0, means: "two siblings share one key (Rune's `#dup`), so one thing shows twice, as an optimistic copy beside the server's"),
]

func motionGateTicks(_ old: String, _ new: String) -> Bool {
    func shape(_ t: String) -> String {
        var out = ""
        for ch in t {
            if !(ch >= "0" && ch <= "9") {
                out.append(ch)
            } else if !out.hasSuffix("#") {
                out.append("#")
            }
        }
        return out
    }
    return shape(old) == shape(new)
}

public func motionGateRule(_ kind: String) -> Float {
    MOTION_GATE_RULES.first(where: { $0.kind == kind })?.threshold ?? .infinity
}

let MG_EXITING: UInt8 = 1
let MG_SCROLLING: UInt8 = 2
let MG_GROWING: UInt8 = 4
let MG_LIVE: UInt8 = 8
let MG_VIRTUAL: UInt8 = 16
let MG_TEXT: UInt8 = 32
let MG_INK: UInt8 = 128

public struct MotionGateSnap: Sendable, Equatable {
    public var rect: [Float]
    public var vis: [Float]
    public var op: Float
    public var scale: Float
    public var flags: UInt8
    public var phase: Float
    public var scrolled: [Float]

    public init(
        rect: [Float] = [0, 0, 0, 0],
        vis: [Float] = [0, 0, 0, 0],
        op: Float = 1.0,
        scale: Float = 1.0,
        flags: UInt8 = 0,
        phase: Float = .nan,
        scrolled: [Float] = [0, 0]
    ) {
        self.rect = rect
        self.vis = vis
        self.op = op
        self.scale = scale
        self.flags = flags
        self.phase = phase
        self.scrolled = scrolled
    }
}

public struct MotionGateTrack: Sendable {
    public var path: String
    public var parent: Int?
    public var frames: [(Int, MotionGateSnap)]
    public var text: String?
    public var words: [(Int, String)]

    public init(
        path: String,
        parent: Int? = nil,
        frames: [(Int, MotionGateSnap)] = [],
        text: String? = nil,
        words: [(Int, String)] = []
    ) {
        self.path = path
        self.parent = parent
        self.frames = frames
        self.text = text
        self.words = words
    }

    func at(_ k: Int) -> MotionGateSnap? {
        var lo = 0
        var hi = frames.count
        while lo < hi {
            let mid = (lo + hi) / 2
            let fk = frames[mid].0
            if fk == k {
                return frames[mid].1
            } else if fk < k {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return nil
    }
}

public struct MotionGateRecording: Sendable {
    public var size: (Float, Float)
    public var hz: Double
    public var tracks: [MotionGateTrack]
    var index: [String: Int]
    public var inputs: [(Int, String)]
    public var frames: Int
    public var start: Int
    public var loads: [Int]
    public var awake: [Bool]
    public var quietFrom: Int?
    public var countsRoll: Bool
    var scrolled: [(Bool, UInt16)]

    public init(size: (Float, Float) = (0, 0), hz: Double = 60.0) {
        self.size = size
        self.hz = hz
        self.tracks = []
        self.index = [:]
        self.inputs = []
        self.frames = 0
        self.start = 0
        self.loads = []
        self.awake = []
        self.quietFrom = nil
        self.countsRoll = false
        self.scrolled = []
    }

    public static func new(_ size: (Float, Float), _ hz: Double) -> MotionGateRecording {
        MotionGateRecording(size: size, hz: hz)
    }

    mutating func commits(_ scrolling: Bool, _ why: UInt16) {
        let mask = CommitWhy.POLL | CommitWhy.INPUT | CommitWhy.LAYOUT | CommitWhy.READ
        scrolled.append((scrolling, why & mask))
    }

    mutating func track(_ path: String, _ parent: Int?) -> Int {
        if let existing = index[path] {
            return existing
        }
        let i = tracks.count
        tracks.append(MotionGateTrack(path: path, parent: parent))
        index[path] = i
        return i
    }

    public mutating func input(_ what: String) {
        inputs.append((frames, what))
    }

    public mutating func sample(_ els: [ElementInfo]) {
        let k = frames
        frames += 1
        var live = Set<String>()
        for e in els where !e.exiting {
            live.insert(e.path)
        }
        var ids = Array(repeating: Int.max, count: els.count)
        var ink = Array(repeating: false, count: els.count)
        var parentOf = Array(repeating: false, count: els.count)
        for e in els {
            if let p = e.parent, p >= 0 && p < els.count {
                parentOf[p] = true
            }
        }
        for i in stride(from: els.count - 1, through: 0, by: -1) {
            let e = els[i]
            let hasText = (e.text != nil && !(e.text!.isEmpty))
            let paints = e.fill.a > 0.01 || hasText || !parentOf[i]
            if paints && e.opacity > 0.02 {
                ink[i] = true
            }
            if ink[i], let p = e.parent, p >= 0 && p < els.count {
                ink[p] = true
            }
        }
        for (i, e) in els.enumerated() {
            let path = (e.exiting && live.contains(e.path)) ? "\(e.path) (leaving)" : e.path
            let parent: Int? = e.parent.flatMap { p in
                guard p >= 0 && p < ids.count && ids[p] != Int.max else { return nil }
                return ids[p]
            }
            let t = track(path, parent)
            ids[i] = t
            var flags: UInt8 = 0
            if e.exiting { flags |= MG_EXITING }
            if e.scrolling { flags |= MG_SCROLLING }
            if e.inGrowingRow || e.revealing { flags |= MG_GROWING }
            if e.liveIntent != 0 { flags |= MG_LIVE }
            if e.virtualExtent { flags |= MG_VIRTUAL }
            if e.role == "text" { flags |= MG_TEXT }
            if ink[i] { flags |= MG_INK }

            if tracks[t].frames.last?.0 == k {
                continue
            }
            if tracks[t].parent == nil {
                tracks[t].parent = parent
            }
            if tracks[t].text == nil, let txt = e.text, !txt.isEmpty {
                tracks[t].text = txt
            }
            if let words = e.text, !words.isEmpty, !e.focusable {
                if tracks[t].words.last?.1 != words {
                    tracks[t].words.append((k, words))
                }
            }
            let ph: Float = e.loopPhase.map { Float($0) } ?? .nan
            tracks[t].frames.append((
                k,
                MotionGateSnap(
                    rect: e.rect,
                    vis: e.visible,
                    op: e.opacity,
                    scale: e.scale,
                    flags: flags,
                    phase: ph,
                    scrolled: e.scrolled
                )
            ))
        }
    }
}

public struct MotionGateFinding: Sendable, Equatable, CustomStringConvertible {
    public var kind: String
    public var element: String
    public var frame: Int
    public var detail: String

    public init(kind: String, element: String, frame: Int, detail: String) {
        self.kind = kind
        self.element = element
        self.frame = frame
        self.detail = detail
    }

    public var description: String {
        "\(mgPadRight(kind, 16)) \(mgPadRight(element, 44)) @\(mgPadRight(String(frame), 4)) \(detail)"
    }
}

public func motionGateShort(_ path: String) -> String {
    let segs = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    let keyed = segs.indices.filter { !segs[$0].hasPrefix("#") }
    let from = max(0, keyed.count - 2)
    let start = from < keyed.count ? keyed[from] : 0
    return segs[start...].joined(separator: "/")
}

private func mgArea(_ r: [Float]) -> Float {
    max(r[2], 0.0) * max(r[3], 0.0)
}

private func mgOnWindow(_ r: [Float], _ size: (Float, Float)) -> [Float] {
    let x0 = max(r[0], 0.0)
    let y0 = max(r[1], 0.0)
    let x1 = min(r[0] + r[2], size.0)
    let y1 = min(r[1] + r[3], size.1)
    return [x0, y0, max(x1 - x0, 0.0), max(y1 - y0, 0.0)]
}

private func mgSeen(_ s: MotionGateSnap, _ size: (Float, Float)) -> Bool {
    s.op > 0.02 && mgArea(mgOnWindow(s.vis, size)) >= 1.0
}

private func mgEdge(_ s: MotionGateSnap, _ axis: Int) -> Float {
    s.rect[axis]
}

private func mgShownEdge(_ s: MotionGateSnap, _ axis: Int, _ size: (Float, Float)) -> Float {
    let r = mgOnWindow(s.vis, size)
    let clamped: [Float] = [min(r[0], size.0), min(r[1], size.1), r[2], r[3]]
    return clamped[axis]
}

private func mgOwnEdge(_ s: MotionGateSnap, _ axis: Int) -> Float {
    s.rect[axis] + (axis < s.scrolled.count ? s.scrolled[axis] : 0.0)
}

private let mgAxes = ["x", "y", "w", "h"]

private func mgLastSeg(_ path: String) -> String {
    if let idx = path.lastIndex(of: "/") {
        return String(path[path.index(after: idx)...])
    }
    return path
}

func mgFmt(_ v: Float, _ decimals: Int, signed: Bool = false, width: Int = 0) -> String {
    if v.isNaN { return mgPadLeft("NaN", width) }
    if v.isInfinite { return mgPadLeft(v < 0 ? "-inf" : (signed ? "+inf" : "inf"), width) }
    var mult: Double = 1.0
    for _ in 0..<decimals { mult *= 10.0 }
    let neg = v < 0.0 || (v == 0.0 && v.sign == .minus)
    let rounded = (abs(Double(v)) * mult).rounded()
    let intTotal = Int64(rounded)
    let signStr: String
    if neg && intTotal > 0 {
        signStr = "-"
    } else if signed {
        signStr = "+"
    } else {
        signStr = ""
    }
    let s: String
    if decimals <= 0 {
        s = "\(signStr)\(intTotal)"
    } else {
        let div = Int64(mult)
        let whole = intTotal / div
        let frac = intTotal % div
        let fracStr = mgPadLeft(String(frac), decimals, pad: "0")
        s = "\(signStr)\(whole).\(fracStr)"
    }
    return mgPadLeft(s, width)
}

func mgPadLeft(_ s: String, _ width: Int, pad: Character = " ") -> String {
    let count = s.count
    guard count < width else { return s }
    return String(repeating: pad, count: width - count) + s
}

func mgPadRight(_ s: String, _ width: Int, pad: Character = " ") -> String {
    let count = s.count
    guard count < width else { return s }
    return s + String(repeating: pad, count: width - count)
}

public func motionGateCheck(_ rec: MotionGateRecording) -> [MotionGateFinding] {
    let size = rec.size
    let n = rec.frames
    let tr = rec.tracks
    var out: [MotionGateFinding] = []
    let inputFrames = rec.inputs.map(\.0)
    func inputBetween(_ a: Int, _ b: Int) -> Bool {
        inputFrames.contains { $0 >= a && $0 <= b }
    }
    func born(_ t: MotionGateTrack) -> Int? { t.frames.first?.0 }
    let parents = Set(tr.compactMap(\.parent))
    func died(_ t: MotionGateTrack) -> Int? {
        guard let last = t.frames.last?.0, last + 1 < n else { return nil }
        return last + 1
    }
    func gaps(_ t: MotionGateTrack) -> [(Int, Int)] {
        guard t.frames.count >= 2 else { return [] }
        var res: [(Int, Int)] = []
        for i in 0..<(t.frames.count - 1) {
            if t.frames[i + 1].0 != t.frames[i].0 + 1 {
                res.append((t.frames[i].0 + 1, t.frames[i + 1].0))
            }
        }
        return res
    }
    func transitioning(_ tIdx: Int, _ a: Int, _ b: Int) -> Bool {
        var p = tr[tIdx].parent
        let startK = max(0, a - 1)
        while let i = p {
            if startK <= b {
                let snaps = (startK...b).compactMap { tr[i].at($0) }
                if snaps.count >= 2 {
                    for j in 0..<(snaps.count - 1) {
                        if abs(snaps[j].op - snaps[j + 1].op) > 0.005 || abs(snaps[j].scale - snaps[j + 1].scale) > 0.001 {
                            return true
                        }
                    }
                }
                if snaps.contains(where: { ($0.flags & (MG_GROWING | MG_EXITING)) != 0 }) {
                    return true
                }
            }
            p = tr[i].parent
        }
        return false
    }

    let loops = motionGateLoops(rec)

    var births: [Int: [Int]] = [:]
    var deaths: [Int: [Int]] = [:]
    for (i, t) in tr.enumerated() {
        var bks: [Int] = []
        if let b = born(t) { bks.append(b) }
        for g in gaps(t) { bks.append(g.1) }
        for k in bks where k > rec.start { births[k, default: []].append(i) }

        var dks: [Int] = []
        if let d = died(t) { dks.append(d) }
        for g in gaps(t) { dks.append(g.0) }
        for k in dks where k > rec.start { deaths[k, default: []].append(i) }
    }

    func outermost(_ ids: [Int]) -> [Int] {
        let set = Set(ids)
        return ids.filter { i in
            var p = tr[i].parent
            while let j = p {
                if set.contains(j) { return false }
                p = tr[j].parent
            }
            return true
        }
    }

    var left: [Int: [(Int, MotionGateSnap)]] = [:]
    for k in deaths.keys.sorted() {
        for i in outermost(deaths[k] ?? []) {
            guard let last = tr[i].at(k - 1) else { continue }
            if !mgSeen(last, size) || mgArea(last.vis) < 16.0 || loops.contains(i) || (last.flags & MG_VIRTUAL) != 0 {
                continue
            }
            if let (backFrame, back) = tr[i].frames.first(where: { $0.0 > k && $0.0 <= k + 12 }) {
                if abs(back.rect[1] - last.rect[1]) < 4.0 && mgSeen(back, size) {
                    out.append(MotionGateFinding(
                        kind: "flicker",
                        element: motionGateShort(tr[i].path),
                        frame: k,
                        detail: "vanished at opacity \(mgFmt(last.op, 2)) and came back \(backFrame - k) frames later at the same place"
                    ))
                    continue
                }
            }
            if last.op >= motionGateRule("pop-out") {
                left[k, default: []].append((i, last))
                let suffix = transitioning(i, k - 1, k - 1) ? " inside a moving container" : ""
                out.append(MotionGateFinding(
                    kind: "pop-out",
                    element: motionGateShort(tr[i].path),
                    frame: k,
                    detail: "unmounted at opacity \(mgFmt(last.op, 2)), \(mgFmt(last.rect[2], 0))×\(mgFmt(last.rect[3], 0)) at (\(mgFmt(last.rect[0], 0)),\(mgFmt(last.rect[1], 0)))\(suffix)"
                ))
            } else if last.op > motionGateRule("cut-exit") {
                out.append(MotionGateFinding(
                    kind: "cut-exit",
                    element: motionGateShort(tr[i].path),
                    frame: k,
                    detail: "unmounted at opacity \(mgFmt(last.op, 2)) before its fade reached 0"
                ))
            }
        }
    }

    for k in births.keys.sorted() {
        for i in outermost(births[k] ?? []) {
            let t = tr[i]
            guard let first = t.at(k) else { continue }
            if first.op < motionGateRule("pop-in")
                || !mgSeen(first, size)
                || mgArea(mgOnWindow(first.vis, size)) < 16.0
                || (first.flags & (MG_GROWING | MG_VIRTUAL)) != 0
                || loops.contains(i)
            {
                continue
            }
            let next = ((k + 1)...(k + 2)).compactMap { t.at($0) }
            let grows = next.contains { s in
                abs(s.op - first.op) > 0.01
                    || abs(s.scale - first.scale) > 0.002
                    || abs(s.rect[2] - first.rect[2]) > 0.5
                    || abs(s.rect[3] - first.rect[3]) > 0.5
                    || abs(s.vis[2] - first.vis[2]) > 0.5
                    || abs(s.vis[3] - first.vis[3]) > 0.5
            }
            if grows || transitioning(i, k, k + 2) {
                continue
            }
            let moved: Float = next.first.map { max(abs($0.rect[0] - first.rect[0]), abs($0.rect[1] - first.rect[1])) } ?? 0.0
            let handoff = left[k]?.first { (j, _) in
                (tr[j].text != nil && tr[j].text == t.text) || mgLastSeg(tr[j].path) == mgLastSeg(t.path)
            }
            var detail = "mounted at opacity \(mgFmt(first.op, 2)), \(mgFmt(first.rect[2], 0))×\(mgFmt(first.rect[3], 0)) at (\(mgFmt(first.rect[0], 0)),\(mgFmt(first.rect[1], 0))) with no transition"
            if let (j, s) = handoff {
                detail += "; replaces \(motionGateShort(tr[j].path)) which vanished from (\(mgFmt(s.rect[0], 0)),\(mgFmt(s.rect[1], 0))) this frame (identity lost)"
            }
            if moved >= motionGateRule("appear-then-jump") {
                out.append(MotionGateFinding(
                    kind: "appear-then-jump",
                    element: motionGateShort(t.path),
                    frame: k,
                    detail: "\(detail), then moved \(mgFmt(moved, 0)) pt"
                ))
            } else {
                out.append(MotionGateFinding(
                    kind: "pop-in",
                    element: motionGateShort(t.path),
                    frame: k,
                    detail: detail
                ))
            }
        }
    }

    func riding(_ i: Int, _ k: Int, _ axis: Int, _ d: Float) -> Bool {
        if axis >= 2 { return false }
        guard let p = tr[i].parent, let a = tr[p].at(k), let b = tr[p].at(k - 1) else { return false }
        return abs(mgEdge(a, axis) - mgEdge(b, axis) - d) < 0.25
    }
    func inside(_ a: String, _ b: String) -> Bool {
        a.utf8.count > b.utf8.count && a.hasPrefix(b + "/")
    }
    func pushed(_ i: Int, _ k: Int, _ axis: Int, _ d: Float) -> Bool {
        if axis != 1 || !inputBetween(k - 1, k) { return false }
        guard let a = tr[i].at(k - 1) else { return false }
        for (j, o) in tr.enumerated() {
            if j == i || inside(tr[i].path, o.path) || inside(o.path, tr[i].path) { continue }
            guard let oa = o.at(k - 1), let ob = o.at(k) else { continue }
            if abs(abs(ob.rect[3] - oa.rect[3]) - abs(d)) > 0.25 { continue }
            let top = ob.rect[1] - oa.rect[1]
            let bottom = ob.rect[1] + ob.rect[3] - oa.rect[1] - oa.rect[3]
            let above = oa.rect[1] + oa.rect[3] <= a.rect[1] + 0.5 && abs(bottom - d) < 0.25
            let below = oa.rect[1] >= a.rect[1] + a.rect[3] - 0.5 && abs(top - d) < 0.25
            if above || below { return true }
        }
        return false
    }
    func carried(_ i: Int, _ k: Int, _ axis: Int, _ d: Float, _ enteringIn: Bool) -> Int {
        if axis >= 2 { return 0 }
        let entering = enteringIn && !inputBetween(k - 1, k)
        var count = 0
        for c in tr where inside(c.path, tr[i].path) {
            guard let a = c.at(k - 1), let b = c.at(k) else { continue }
            if !mgSeen(b, size) || abs(mgEdge(b, axis) - mgEdge(a, axis) - d) >= 0.25 { continue }
            if mgSeen(a, size) {
                if abs(mgShownEdge(b, axis, size) - mgShownEdge(a, axis, size) - d) < 0.25 {
                    count += 1
                }
            } else if entering && b.op >= motionGateRule("faint") && (b.flags & MG_INK) != 0 && (b.flags & (MG_GROWING | MG_EXITING)) == 0 {
                count += 1
            }
        }
        return count
    }

    var geo: [(Int, MotionGateFinding)] = []
    for (i, t) in tr.enumerated() {
        if loops.contains(i) || t.frames.count < 3 { continue }
        let fs = t.frames
        for axis in 0..<4 {
            let d: [Float?] = (1..<fs.count).map { j in
                fs[j].0 == fs[j - 1].0 + 1 ? (mgEdge(fs[j].1, axis) - mgEdge(fs[j - 1].1, axis)) : nil
            }
            func vd(_ j: Int) -> Float {
                fs[j].0 == fs[j - 1].0 + 1 ? (mgShownEdge(fs[j].1, axis, size) - mgShownEdge(fs[j - 1].1, axis, size)) : 0.0
            }
            func clipped(_ j: Int) -> Bool {
                mgArea(mgOnWindow(fs[j].1.vis, size)) + 1.0 < mgArea(fs[j].1.rect)
            }
            func quiet(_ j: Int) -> Bool {
                (fs[j].1.flags & (MG_LIVE | MG_VIRTUAL)) != 0 || !mgSeen(fs[j].1, size) || fs[j].1.op < motionGateRule("faint")
            }
            for j in 1..<fs.count {
                guard let step = d[j - 1] else { continue }
                let k = fs[j].0
                if k <= rec.start || quiet(j) || quiet(j - 1) || ((fs[j].1.flags & MG_GROWING) != 0 && axis == 3) {
                    continue
                }
                let scrolling = ((fs[j].1.flags | fs[j - 1].1.flags) & MG_SCROLLING) != 0
                let before: Float = j >= 2 ? (d[j - 2] ?? 0.0) : 0.0
                let after: Float = j < d.count ? (d[j] ?? 0.0) : 0.0
                let name = motionGateShort(t.path)
                func riders(_ entering: Bool) -> Int {
                    (clipped(j) || clipped(j - 1)) ? carried(i, k, axis, step, entering) : 0
                }
                if abs(step) >= motionGateRule("jump") && abs(before) < 0.5 && abs(after) < 0.5 {
                    if (scrolling && inputBetween(k - 1, k)) || riding(i, k, axis, step) || pushed(i, k, axis, step) {
                        continue
                    }
                    let riderCount = riders(true)
                    if abs(vd(j)) < motionGateRule("jump") && riderCount == 0 { continue }
                    let appeared = born(t) == fs[j - 1].0 && fs[j - 1].0 > rec.start
                    let scrollContent = axis == 1 && fs[j].1.rect[3] > fs[j].1.vis[3] + 1.0 && riderCount >= 3
                    let kind = appeared ? "appear-then-jump" : (scrollContent ? "offset-jump" : "jump")
                    let extra = scrollContent ? ", carrying \(riderCount) elements" : ""
                    geo.append((i, MotionGateFinding(
                        kind: kind,
                        element: name,
                        frame: k,
                        detail: "\(mgAxes[axis]) \(mgFmt(mgEdge(fs[j - 1].1, axis), 1)) → \(mgFmt(mgEdge(fs[j].1, axis), 1)) (\(mgFmt(step, 1, signed: true)) pt) in one frame\(extra)"
                    )))
                } else if !scrolling && abs(step - before) > motionGateRule("jerk") && abs(before) >= 0.5 && abs(step) >= 0.5 {
                    if riding(i, k, axis, step) { continue }
                    if j >= 2 && abs(vd(j) - vd(j - 1)) <= motionGateRule("jerk") && riders(false) == 0 { continue }
                    let v0 = Float(Double(before) * rec.hz)
                    let v1 = Float(Double(step) * rec.hz)
                    geo.append((i, MotionGateFinding(
                        kind: "jerk",
                        element: name,
                        frame: k,
                        detail: "\(mgAxes[axis]) step \(mgFmt(before, 1, signed: true)) → \(mgFmt(step, 1, signed: true)) pt/frame (\(mgFmt(v0, 0)) → \(mgFmt(v1, 0)) pt/s)"
                    )))
                }
            }

            let ownD: [Float?] = (1..<fs.count).map { j in
                fs[j].0 == fs[j - 1].0 + 1 ? (mgOwnEdge(fs[j].1, axis) - mgOwnEdge(fs[j - 1].1, axis)) : nil
            }
            func moving(_ j: Int) -> Bool {
                if let x = ownD[j - 1] { return abs(x) > 0.01 }
                return false
            }
            var j = 1
            while j < fs.count {
                if !moving(j) { j += 1; continue }
                let a = j
                var b = j
                while j < fs.count && ownD[j - 1] != nil && j - b <= 3 {
                    if moving(j) { b = j }
                    j += 1
                }
                j = b + 1
                if b - a + 1 < 3 { continue }
                let seg = Array(fs[(a - 1)...b])
                let (k0, k1) = (seg[0].0, seg[seg.count - 1].0)
                if k1 <= rec.start
                    || seg.allSatisfy({ !mgSeen($0.1, size) || $0.1.op < motionGateRule("faint") })
                    || seg.contains(where: { ($0.1.flags & (MG_LIVE | MG_VIRTUAL)) != 0 })
                {
                    continue
                }
                if inputBetween(k0 + 1, k1) { continue }
                let vals = seg.map { mgOwnEdge($0.1, axis) }
                let startVal = vals[0]
                let restVal = vals[vals.count - 1]
                let travel = restVal - startVal
                var signs: [Float] = []
                var last = startVal
                for v in vals.dropFirst() where abs(v - last) > 0.05 {
                    let s: Float = (v - last) >= 0 ? 1.0 : -1.0
                    if signs.last != s { signs.append(s) }
                    last = v
                }
                let reversals = max(0, signs.count - 1)
                if reversals == 0 { continue }
                let dir: Float = abs(travel) > 0.5 ? (travel >= 0 ? 1.0 : -1.0) : signs[0]
                let past = vals.reduce(Float(0.0)) { max($0, ($1 - restVal) * dir) }
                let back = vals.reduce(Float(0.0)) { max($0, (startVal - $1) * dir) }
                let maxV = vals.max() ?? startVal
                let minV = vals.min() ?? startVal
                let amp = maxV - minV
                let name = motionGateShort(t.path)
                let kind: String
                let detail: String
                if past >= motionGateRule("overshoot") && abs(travel) > 0.5 {
                    kind = "overshoot"
                    detail = "\(mgAxes[axis]) \(mgFmt(startVal, 1)) → \(mgFmt(restVal, 1)) passes its rest by \(mgFmt(past, 1)) pt (\(mgFmt(100.0 * past / abs(travel), 0))%)"
                } else if reversals >= 2 && amp >= motionGateRule("jiggle") {
                    kind = "jiggle"
                    detail = "\(mgAxes[axis]) reverses \(reversals)× over \(mgFmt(amp, 1)) pt (\(mgFmt(startVal, 1)) → \(mgFmt(restVal, 1)))"
                } else if back >= motionGateRule("reversal") {
                    kind = "reversal"
                    detail = "\(mgAxes[axis]) \(mgFmt(startVal, 1)) → \(mgFmt(restVal, 1)) heads \(mgFmt(back, 1)) pt the wrong way first"
                } else if abs(travel) <= 0.5 && amp >= motionGateRule("reversal") {
                    kind = "reversal"
                    detail = "\(mgAxes[axis]) goes \(mgFmt(amp, 1)) pt out from \(mgFmt(startVal, 1)) and back"
                } else {
                    continue
                }
                geo.append((i, MotionGateFinding(
                    kind: kind,
                    element: name,
                    frame: k0 + 1,
                    detail: "\(detail) over frames \(k0 + 1)–\(k1)"
                )))
            }
        }

        // Opacity dips that come back.
        var spans: [(Int, Int)] = []
        var j = 0
        while j < fs.count {
            let s = fs[j].1
            if fs[j].0 <= rec.start || s.op < 0.6 || (s.flags & MG_EXITING) != 0 || (s.flags & MG_INK) == 0 || !mgSeen(s, size) {
                j += 1
                continue
            }
            let horizon = fs[j].0 + Int(0.3 * rec.hz)
            var low = s.op
            var lowAt = j
            var back: Int? = nil
            var m = j + 1
            while m < fs.count && fs[m].0 <= horizon && fs[m].0 == fs[m - 1].0 + 1 {
                if fs[m].1.op < low {
                    low = fs[m].1.op
                    lowAt = m
                }
                if low <= s.op - motionGateRule("flicker") && fs[m].1.op >= s.op - 0.1 {
                    back = m
                    break
                }
                m += 1
            }
            if let mBack = back {
                let inputCount = rec.inputs.filter { $0.0 > fs[j].0 && $0.0 <= fs[mBack].0 }.count
                if inputCount >= 2 {
                    j = mBack + 1
                } else {
                    geo.append((i, MotionGateFinding(
                        kind: "flicker",
                        element: motionGateShort(t.path),
                        frame: fs[lowAt].0,
                        detail: "opacity \(mgFmt(s.op, 2)) → \(mgFmt(low, 2)) → \(mgFmt(fs[mBack].1.op, 2)) over frames \(fs[j].0)–\(fs[mBack].0)"
                    )))
                    spans.append((fs[j].0, fs[mBack].0))
                    j = mBack + 1
                }
            } else {
                j += 1
            }
        }

        // Words that change in place.
        if t.words.count >= 2 {
            for wi in 0..<(t.words.count - 1) {
                let old = t.words[wi].1
                let k = t.words[wi + 1].0
                let new = t.words[wi + 1].1
                guard k > 0, let a = t.at(k - 1), let b = t.at(k) else { continue }
                if k <= rec.start
                    || parents.contains(i)
                    || new.hasPrefix(old)
                    || old.hasPrefix(new)
                    || (!rec.countsRoll && motionGateTicks(old, new))
                {
                    continue
                }
                if ((a.flags | b.flags) & (MG_LIVE | MG_EXITING | MG_VIRTUAL)) != 0
                    || min(a.op, b.op) < motionGateRule("text-swap")
                    || !mgSeen(b, size)
                {
                    continue
                }
                geo.append((i, MotionGateFinding(
                    kind: "text-swap",
                    element: motionGateShort(t.path),
                    frame: k,
                    detail: "\"\(old)\" → \"\(new)\" in one frame"
                )))
            }
        }

        // Opacity that steps instead of fading.
        if fs.count >= 2 {
            for wi in 0..<(fs.count - 1) {
                let w0 = fs[wi]
                let w1 = fs[wi + 1]
                let a = w0.1
                let b = w1.1
                if w1.0 != w0.0 + 1 || w1.0 <= rec.start || abs(a.op - b.op) < motionGateRule("fade-snap") {
                    continue
                }
                let shown = b.op > a.op ? b : a
                if spans.contains(where: { w1.0 >= $0.0 && w1.0 <= $0.1 }) { continue }
                if !mgSeen(shown, size)
                    || (shown.flags & MG_INK) == 0
                    || mgArea(mgOnWindow(shown.vis, size)) < 16.0
                    || ((a.flags | b.flags) & (MG_EXITING | MG_VIRTUAL)) != 0
                {
                    continue
                }
                geo.append((i, MotionGateFinding(
                    kind: "fade-snap",
                    element: motionGateShort(t.path),
                    frame: w1.0,
                    detail: "opacity \(mgFmt(a.op, 2)) → \(mgFmt(b.op, 2)) in one frame"
                )))
            }
        }
    }

    // Deduplicate child findings riding parent motion.
    struct ReportedKey: Hashable {
        let track: Int
        let kind: String
        let frame: Int
    }
    let reported = Set(geo.map { ReportedKey(track: $0.0, kind: $0.1.kind, frame: $0.1.frame) })
    let parentDedupKinds: Set<String> = ["reversal", "overshoot", "jiggle", "flicker", "jerk", "fade-snap"]
    for (i, f) in geo {
        var p = tr[i].parent
        var dup = false
        while let j = p {
            if parentDedupKinds.contains(f.kind) {
                for o in 0...2 {
                    if reported.contains(ReportedKey(track: j, kind: f.kind, frame: max(0, f.frame - o)))
                        || reported.contains(ReportedKey(track: j, kind: f.kind, frame: f.frame + o))
                    {
                        dup = true
                        break
                    }
                }
                if dup { break }
            }
            p = tr[j].parent
        }
        if !dup {
            out.append(f)
        }
    }

    // Load-motion check.
    for load in rec.loads {
        let quietUntil = (inputFrames + rec.loads).filter { $0 > load + 1 }.min() ?? n
        var hits: [(Int, MotionGateFinding)] = []
        for (i, t) in tr.enumerated() {
            guard let b = born(t), b >= load, b <= load + 2, !loops.contains(i) else { continue }
            guard let first = t.at(b + 1) else { continue }
            let endK = min(quietUntil, n)
            if b + 2 < endK {
                for k in (b + 2)..<endK {
                    guard let s = t.at(k) else { break }
                    let dy = (0..<4).reduce(Float(0.0)) { max($0, abs(s.rect[$1] - first.rect[$1])) }
                    let dop = abs(s.op - first.op)
                    if (dy > motionGateRule("load-motion") || dop > 0.1) && mgSeen(s, size) {
                        let what = dy > motionGateRule("load-motion")
                            ? "moved \(mgFmt(dy, 1)) pt"
                            : "faded \(mgFmt(first.op, 2)) → \(mgFmt(s.op, 2))"
                        hits.append((i, MotionGateFinding(
                            kind: "load-motion",
                            element: motionGateShort(t.path),
                            frame: k,
                            detail: "loaded at frame \(b), then \(what) by frame \(k)"
                        )))
                        break
                    }
                }
            }
        }
        let hitSet = Set(hits.map(\.0))
        for (i, f) in hits {
            if let p = tr[i].parent, hitSet.contains(p) { continue }
            out.append(f)
        }
    }

    // Settling check.
    let lastInput = inputFrames.max() ?? 0
    let tail = Int(0.5 * rec.hz)
    if n > tail && (n - tail) > lastInput + Int(0.5 * rec.hz) {
        var still: [(Int, Float)] = []
        for (i, t) in tr.enumerated() where !loops.contains(i) {
            let fs = t.frames.filter { $0.0 >= n - tail }
            guard fs.count >= 2 else { continue }
            var moved: Float = 0.0
            for wi in 0..<(fs.count - 1) {
                var m = abs(fs[wi + 1].1.op - fs[wi].1.op)
                for a in 0..<4 {
                    m = max(m, abs(fs[wi + 1].1.rect[a] - fs[wi].1.rect[a]))
                }
                moved = max(moved, m)
            }
            if moved > motionGateRule("never-settles") && fs.contains(where: { mgSeen($0.1, size) }) {
                still.append((i, moved))
            }
        }
        let stillSet = Set(still.map(\.0))
        for (i, moved) in still {
            if let p = tr[i].parent, stillSet.contains(p) { continue }
            out.append(MotionGateFinding(
                kind: "never-settles",
                element: motionGateShort(tr[i].path),
                frame: n - tail,
                detail: "still moving \(mgFmt(moved, 2)) pt/frame in the last 0.5 s"
            ))
        }
    }

    motionGateLoopJumps(rec, &out)
    motionGateScrollCommits(rec, &out)

    // Remount check.
    let remountWindow = Int(motionGateRule("remount"))
    func leaving(_ i: Int, _ k: Int) -> Bool {
        var p: Int? = i
        while let j = p {
            if let s = tr[j].at(k), (s.flags & MG_EXITING) != 0 { return true }
            p = tr[j].parent
        }
        return false
    }
    func wordsAt(_ t: MotionGateTrack, _ k: Int) -> String? {
        t.words.reversed().first(where: { $0.0 <= k })?.1 ?? t.text
    }
    func stripLeaving(_ s: String) -> String {
        s.hasSuffix(" (leaving)") ? String(s.dropLast(10)) : s
    }
    func rekeyed(_ aRaw: String, _ bRaw: String) -> Bool {
        let a = stripLeaving(aRaw).split(separator: "/", omittingEmptySubsequences: false)
        let b = stripLeaving(bRaw).split(separator: "/", omittingEmptySubsequences: false)
        guard a.count == b.count else { return false }
        var diff = 0
        for (x, y) in zip(a, b) where x != y { diff += 1 }
        return diff == 1
    }
    for (i, t) in tr.enumerated() where t.frames.count >= 2 {
        var foundK: Int? = nil
        for wi in 0..<(t.frames.count - 1) {
            let w0 = t.frames[wi]
            let w1 = t.frames[wi + 1]
            if w1.0 == w0.0 + 1 && w0.0 > rec.start && !leaving(i, w0.0) && leaving(i, w1.0) && mgSeen(w0.1, size) {
                foundK = w1.0
                break
            }
        }
        guard let k = foundK, let words = wordsAt(t, k) else { continue }
        let trimmed = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count >= 8 else { continue }
        for (j, o) in tr.enumerated() where j != i && rekeyed(t.path, o.path) {
            if let b = born(o),
               b > rec.start,
               b + remountWindow >= k,
               b <= k + remountWindow,
               !leaving(j, b),
               wordsAt(o, b) == words
            {
                let snippet = String(words.prefix(40))
                out.append(MotionGateFinding(
                    kind: "remount",
                    element: motionGateShort(t.path),
                    frame: k,
                    detail: "\"\(snippet)\" leaves as a copy mounts at \(motionGateShort(o.path))"
                ))
                break
            }
        }
    }

    // Unpinned scroll check.
    func touched(_ a: Int, _ b: Int) -> Bool {
        rec.inputs.contains { $0.0 >= a && $0.0 <= b && !$0.1.hasPrefix("event") }
    }
    for t in tr {
        guard let pIdx = t.parent else { continue }
        let parent = tr[pIdx]
        var pinned: Int? = nil
        for (k, s) in t.frames {
            let viewport = parent.at(k).map { v in
                (0..<4).allSatisfy { abs(v.rect[$0] - s.vis[$0]) < 0.5 }
            } ?? false
            if !viewport || s.rect[3] <= s.vis[3] + 1.0 {
                pinned = nil
                continue
            }
            let below = s.rect[1] + s.rect[3] - (s.vis[1] + s.vis[3])
            if abs(below) < 0.5 {
                pinned = k
                continue
            }
            guard let p = pinned else { continue }
            if k > rec.start && below >= motionGateRule("unpinned") && !touched(p, k) {
                out.append(MotionGateFinding(
                    kind: "unpinned",
                    element: motionGateShort(t.path),
                    frame: k,
                    detail: "its end, pinned at frame \(p), is \(mgFmt(below, 1)) pt below the viewport"
                ))
                pinned = nil
            }
        }
    }

    // Duplicate sibling key (`#dup`) check.
    for t in tr where mgLastSeg(t.path).contains("#dup") {
        if let (k, _) = t.frames.first(where: { $0.1.op >= motionGateRule("faint") && $0.1.vis[2] > 0.0 && $0.1.vis[3] > 0.0 }) {
            out.append(MotionGateFinding(
                kind: "twice",
                element: motionGateShort(t.path),
                frame: k,
                detail: "a second element under its key"
            ))
        }
    }

    // Lands-unseen flight check.
    let unseenWindow = Int(1.5 * rec.hz)
    var unseen: [Int: Int] = [:]
    for (i, t) in tr.enumerated() where t.frames.count >= 2 {
        let fs = t.frames
        var hitJ: Int? = nil
        for j in 1..<fs.count {
            let (ka, a) = fs[j - 1]
            let (kb, b) = fs[j]
            let whole = a.rect[2] >= 4.0 && a.rect[3] >= 4.0 && mgArea(a.vis) >= 0.9 * mgArea(a.rect)
            let still = (0..<4).allSatisfy { abs(a.rect[$0] - b.rect[$0]) < 0.5 }
            let shown = a.op >= motionGateRule("faint") && (a.flags & MG_INK) != 0 && ((a.flags | b.flags) & MG_EXITING) == 0
            if kb != ka + 1 || !whole || !still || !shown || mgArea(mgOnWindow(b.vis, size)) >= 1.0 {
                continue
            }
            var travelled = false
            for idx in stride(from: j - 1, through: 0, by: -1) {
                let f = fs[idx]
                if f.0 + unseenWindow < ka { break }
                let sameSize = abs(f.1.rect[2] - a.rect[2]) < 1.0 && abs(f.1.rect[3] - a.rect[3]) < 1.0
                let travel = abs(f.1.rect[0] - a.rect[0]) + abs(f.1.rect[1] - a.rect[1])
                if sameSize && mgSeen(f.1, size) && travel >= motionGateRule("lands-unseen") {
                    travelled = true
                    break
                }
            }
            if travelled {
                hitJ = j
                break
            }
        }
        guard let j = hitJ else { continue }
        let k = fs[j].0
        unseen[i] = k
        if let p = t.parent, unseen[p] == k { continue }
        out.append(MotionGateFinding(
            kind: "lands-unseen",
            element: motionGateShort(t.path),
            frame: k,
            detail: "travelled in view, then its clip hid it where it rests"
        ))
    }

    if let q = rec.quietFrom {
        let from = q + Int(Double(motionGateRule("wakes-after-end")) * rec.hz)
        if from < n {
            if let k = (from..<n).first(where: { k in k < rec.awake.count && rec.awake[k] }) {
                let elapsed = Float(Double(k - q) / rec.hz)
                out.append(MotionGateFinding(
                    kind: "wakes-after-end",
                    element: "frame",
                    frame: k,
                    detail: "asked for a frame \(mgFmt(elapsed, 2)) s after the motion ended"
                ))
            }
        }
    }

    let loadSwapKinds: Set<String> = ["pop-in", "pop-out", "jump", "offset-jump", "appear-then-jump", "fade-snap"]
    out.removeAll { f in
        loadSwapKinds.contains(f.kind) && rec.loads.contains(where: { f.frame >= $0 && f.frame <= $0 + 2 })
    }
    out.sort { lhs, rhs in
        if lhs.frame != rhs.frame { return lhs.frame < rhs.frame }
        return lhs.kind < rhs.kind
    }
    return out
}

public func motionGateDump(_ rec: MotionGateRecording, _ filter: String, _ from: Int, _ to: Int) -> String {
    var out = ""
    for t in rec.tracks where t.path.contains(filter) {
        out += "\(t.path)\n"
        for (k, s) in t.frames where k >= from && k < to {
            let kStr = mgPadLeft(String(k), 4)
            let r0 = mgFmt(s.rect[0], 1, width: 7)
            let r1 = mgFmt(s.rect[1], 1, width: 7)
            let r2 = mgFmt(s.rect[2], 1, width: 6)
            let r3 = mgFmt(s.rect[3], 1, width: 6)
            let v0 = mgFmt(s.vis[0], 1, width: 6)
            let v1 = mgFmt(s.vis[1], 1, width: 6)
            let v2 = mgFmt(s.vis[2], 1, width: 6)
            let v3 = mgFmt(s.vis[3], 1, width: 6)
            let op = mgFmt(s.op, 3)
            let sc = mgFmt(s.scale, 3)
            let fl = mgPadLeft(String(s.flags, radix: 2), 2, pad: "0")
            out += "  \(kStr) [\(r0) \(r1) \(r2) \(r3)] vis [\(v0) \(v1) \(v2) \(v3)] op \(op) sc \(sc) \(fl)\n"
        }
    }
    return out
}

/// RGB contact sheet image returned by `motionGate.sheet`.
public struct MotionGateSheetImage: Sendable, Equatable {
    public let width: UInt32
    public let height: UInt32
    public var rgb: [UInt8]

    public init(width: UInt32, height: UInt32, pixel: (UInt8, UInt8, UInt8)) {
        self.width = width
        self.height = height
        let count = Int(width) * Int(height)
        var buf = [UInt8]()
        buf.reserveCapacity(count * 3)
        for _ in 0..<count {
            buf.append(pixel.0)
            buf.append(pixel.1)
            buf.append(pixel.2)
        }
        self.rgb = buf
    }

    public func pixel(_ x: UInt32, _ y: UInt32) -> [UInt8] {
        let idx = (Int(y) * Int(width) + Int(x)) * 3
        return [rgb[idx], rgb[idx + 1], rgb[idx + 2]]
    }

    mutating func putPixel(_ x: UInt32, _ y: UInt32, _ r: UInt8, _ g: UInt8, _ b: UInt8) {
        guard x < width && y < height else { return }
        let idx = (Int(y) * Int(width) + Int(x)) * 3
        rgb[idx] = r
        rgb[idx + 1] = g
        rgb[idx + 2] = b
    }

    public func pngBytes() -> [UInt8] {
        mgEncodeUncompressedRgbPng(width: width, height: height, rgb: rgb)
    }

    public func save(_ path: String) throws {
        #if !os(WASI)
        let data = Data(pngBytes())
        try data.write(to: URL(fileURLWithPath: path))
        #else
        _ = path
        #endif
    }
}

public func motionGateSheet(_ rec: MotionGateRecording, _ at: Int, _ focus: String) -> MotionGateSheetImage {
    let z: Float = 0.25
    let w = UInt32(max(0, rec.size.0 * z))
    let h = UInt32(max(0, rec.size.1 * z))
    let lo = max(0, at - 4)
    let hi = at + 4
    let frames = (lo...hi).filter { $0 < rec.frames }
    let gap: UInt32 = 6
    var img = MotionGateSheetImage(width: (w + gap) * UInt32(frames.count), height: h, pixel: (16, 18, 22))
    for (colIdx, k) in frames.enumerated() {
        let x0 = UInt32(colIdx) * (w + gap)
        if k == at && h > 0 {
            for x in x0..<(x0 + w) {
                img.putPixel(x, 0, 255, 210, 80)
            }
        }
        for t in rec.tracks {
            guard let s = t.at(k) else { continue }
            let hot = !focus.isEmpty && t.path.contains(focus)
            let a = min(max(s.op, 0.0), 1.0) * (hot ? 1.0 : 0.5)
            let ink: (Float, Float, Float) = hot ? (255.0, 70.0, 70.0) : (200.0, 205.0, 215.0)
            let x = s.vis[0] * z
            let y = s.vis[1] * z
            let rw = s.vis[2] * z
            let rh = s.vis[3] * z
            if rw < 1.0 || rh < 1.0 { continue }
            func plot(_ pxF: Float, _ pyF: Float) {
                guard pxF >= 0, pyF >= 0 else { return }
                let px = UInt32(pxF)
                let py = UInt32(pyF)
                guard px < w && py < h else { return }
                let idx = (Int(py) * Int(img.width) + Int(x0 + px)) * 3
                img.rgb[idx] = UInt8(min(max(Float(img.rgb[idx]) * (1.0 - a) + ink.0 * a, 0.0), 255.0))
                img.rgb[idx + 1] = UInt8(min(max(Float(img.rgb[idx + 1]) * (1.0 - a) + ink.1 * a, 0.0), 255.0))
                img.rgb[idx + 2] = UInt8(min(max(Float(img.rgb[idx + 2]) * (1.0 - a) + ink.2 * a, 0.0), 255.0))
            }
            let rwU = Int(UInt32(rw))
            let rhU = Int(UInt32(rh))
            for i in 0..<rwU {
                plot(x + Float(i), y)
                plot(x + Float(i), y + rh - 1.0)
            }
            for i in 0..<rhU {
                plot(x, y + Float(i))
                plot(x + rw - 1.0, y + Float(i))
            }
        }
    }
    return img
}

private func mgEncodeUncompressedRgbPng(width: UInt32, height: UInt32, rgb: [UInt8]) -> [UInt8] {
    func be32(_ v: UInt32) -> [UInt8] {
        [UInt8((v >> 24) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]
    }
    func crc32(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xffff_ffff
        for b in bytes {
            c ^= UInt32(b)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xedb8_8320 ^ (c >> 1)) : (c >> 1)
            }
        }
        return ~c
    }
    func chunk(_ type: [UInt8], _ data: [UInt8]) -> [UInt8] {
        var out = be32(UInt32(data.count))
        var body = type
        body.append(contentsOf: data)
        out.append(contentsOf: body)
        out.append(contentsOf: be32(crc32(body)))
        return out
    }
    var raw: [UInt8] = []
    let strideBytes = Int(width) * 3
    if width > 0 && height > 0 {
        raw.reserveCapacity(Int(height) * (1 + strideBytes))
        for y in 0..<Int(height) {
            raw.append(0) // filter 0 (None)
            let start = y * strideBytes
            raw.append(contentsOf: rgb[start..<(start + strideBytes)])
        }
    }
    // Uncompressed zlib stream (CMF=0x78, FLG=0x01, stored blocks, Adler-32).
    var zlib: [UInt8] = [0x78, 0x01]
    var offset = 0
    while true {
        let rem = raw.count - offset
        let blockLen = min(rem, 65535)
        let isFinal: UInt8 = (offset + blockLen >= raw.count) ? 1 : 0
        zlib.append(isFinal)
        let len16 = UInt16(blockLen)
        let nlen16 = ~len16
        zlib.append(UInt8(len16 & 0xff))
        zlib.append(UInt8(len16 >> 8))
        zlib.append(UInt8(nlen16 & 0xff))
        zlib.append(UInt8(nlen16 >> 8))
        if blockLen > 0 {
            zlib.append(contentsOf: raw[offset..<(offset + blockLen)])
        }
        offset += blockLen
        if isFinal == 1 { break }
    }
    var s1: UInt32 = 1
    var s2: UInt32 = 0
    for b in raw {
        s1 = (s1 + UInt32(b)) % 65521
        s2 = (s2 + s1) % 65521
    }
    zlib.append(contentsOf: be32((s2 << 16) | s1))

    var png: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
    var ihdr = be32(width)
    ihdr.append(contentsOf: be32(height))
    ihdr.append(contentsOf: [8, 2, 0, 0, 0]) // 8-bit RGB
    png.append(contentsOf: chunk(Array("IHDR".utf8), ihdr))
    png.append(contentsOf: chunk(Array("IDAT".utf8), zlib))
    png.append(contentsOf: chunk(Array("IEND".utf8), []))
    return png
}
