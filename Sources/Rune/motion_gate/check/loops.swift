// Ported from: crates/rune/src/motion_gate/check/loops.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Which tracks loop: motion that keeps going of its own accord, its wraps and turns its design.

func motionGatePlaysOut(_ t: MotionGateTrack) -> Bool {
    guard t.frames.count >= 2 else { return false }
    for i in 0..<(t.frames.count - 1) {
        if t.frames[i].1.phase == 1.0 && t.frames[i + 1].1.phase == 1.0 {
            return true
        }
    }
    return false
}

func motionGatePeriodicPhase(_ t: MotionGateTrack, _ n: Int) -> Bool {
    let ph: [(Int, Float)] = t.frames.compactMap { f in
        f.1.phase.isNaN ? nil : (f.0, f.1.phase)
    }
    guard ph.count >= 2 else { return false }
    var wraps = false
    var lastStepDiffers = false
    for i in 0..<(ph.count - 1) where ph[i + 1].0 == ph[i].0 + 1 {
        if ph[i + 1].1 < ph[i].1 - 0.5 {
            wraps = true
        }
        lastStepDiffers = (ph[i + 1].1 != ph[i].1)
    }
    let toEnd = (ph.last?.0.advanced(by: 1) == n) && lastStepDiffers
    return (wraps || toEnd) && !motionGatePlaysOut(t)
}

private func remEuclid1(_ x: Float) -> Float {
    let r = x.truncatingRemainder(dividingBy: 1.0)
    return r < 0.0 ? r + 1.0 : r
}

func motionGateLoops(_ rec: MotionGateRecording) -> Set<Int> {
    let tr = rec.tracks
    let answer = Int(0.5 * rec.hz)
    func answering(_ k: Int) -> Bool {
        rec.inputs.contains { inp in inp.0 <= k && k <= inp.0 + answer }
    }
    func changed(_ a: MotionGateSnap, _ b: MotionGateSnap) -> Bool {
        for i in 0..<4 where abs(a.rect[i] - b.rect[i]) > 0.01 {
            return true
        }
        return abs(a.op - b.op) > 0.002
    }

    var busy = Array(repeating: 0, count: tr.count)
    var groupBusy: [Int: Set<Int>] = [:]
    for (i, t) in tr.enumerated() where t.frames.count >= 2 {
        for j in 0..<(t.frames.count - 1) {
            let w0 = t.frames[j]
            let w1 = t.frames[j + 1]
            if w1.0 == w0.0 + 1 && changed(w0.1, w1.1) {
                busy[i] += 1
                if let p = t.parent {
                    groupBusy[p, default: []].insert(w1.0)
                }
            }
        }
    }

    func turns(_ t: MotionGateTrack, _ eps: Float, _ sample: (MotionGateSnap) -> Float) -> Int {
        guard let first = t.frames.first else { return 0 }
        var count = 0
        var last = sample(first.1)
        var dir: Float = 0.0
        for f in t.frames.dropFirst() {
            let x = sample(f.1)
            if abs(x - last) > eps {
                let s: Float = (x - last) >= 0 ? 1.0 : -1.0
                if dir != 0.0 && s != dir && !answering(f.0) {
                    count += 1
                }
                dir = s
                last = x
            }
        }
        return count
    }

    func periodic(_ t: MotionGateTrack) -> Bool {
        if turns(t, 0.01, { $0.op }) >= 4 { return true }
        for a in 0..<4 where turns(t, 0.25, { $0.rect[a] }) >= 4 {
            return true
        }
        return false
    }

    func busyMost(_ i: Int, _ frames: Int) -> Bool {
        tr[i].frames.count >= 60 && frames * 10 >= tr[i].frames.count * 6
    }

    var loops = Set<Int>()
    for i in 0..<tr.count {
        if motionGatePeriodicPhase(tr[i], rec.frames) || (busyMost(i, busy[i]) && periodic(tr[i])) {
            loops.insert(i)
        }
    }
    for (p, ks) in groupBusy {
        if busyMost(p, ks.count) && tr.contains(where: { $0.parent == p && $0.frames.count >= 2 && periodic($0) }) {
            for c in 0..<tr.count where tr[c].parent == p {
                loops.insert(c)
            }
        }
    }
    while true {
        var more: [Int] = []
        for i in 0..<tr.count where !loops.contains(i) {
            if let p = tr[i].parent, loops.contains(p) {
                more.append(i)
            }
        }
        if more.isEmpty { break }
        for m in more { loops.insert(m) }
    }
    return loops
}

func motionGateLoopJumps(_ rec: MotionGateRecording, _ out: inout [MotionGateFinding]) {
    let blink = Int(0.1 * rec.hz)
    let jumpThresh = motionGateRule("loop-jump")
    for t in rec.tracks where !motionGatePlaysOut(t) {
        let ph: [(Int, Float)] = t.frames.compactMap { f in
            f.1.phase.isNaN ? nil : (f.0, f.1.phase)
        }
        guard ph.count >= 3 else { continue }
        var steps: [(Int, Int, Float)] = []
        for i in 0..<(ph.count - 1) {
            let gap = ph[i + 1].0 - ph[i].0
            if gap <= blink {
                steps.append((ph[i + 1].0, gap, remEuclid1(ph[i + 1].1 - ph[i].1)))
            }
        }
        guard steps.count >= 2 else { continue }
        var moving: [(Int, Int, Float)] = []
        for i in 0..<(steps.count - 1) where steps[i].2 > 0.0 && steps[i + 1].2 > 0.0 {
            moving.append(steps[i + 1])
        }
        var sorted: [Float] = moving.compactMap { $0.1 == 1 ? $0.2 : nil }
        guard sorted.count >= 4 else { continue }
        sorted.sort()
        let usual = sorted[sorted.count / 2]

        for (k, frames, d) in moving {
            let x = remEuclid1(d - Float(frames) * usual)
            let off = min(x, 1.0 - x)
            if off > jumpThresh {
                let over = frames > 1 ? " over \(frames) frames" : ""
                out.append(MotionGateFinding(
                    kind: "loop-jump",
                    element: motionGateShort(t.path),
                    frame: k,
                    detail: "phase stepped \(mgFmt(d, 3))\(over) where it steps \(mgFmt(usual, 3)) a frame"
                ))
                break
            }
        }
    }
}
