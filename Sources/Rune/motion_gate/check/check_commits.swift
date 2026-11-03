// Ported from: crates/rune/src/motion_gate/check/commits.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `scroll-commit`: an app running its whole view on most frames of a scroll. Rune moves a
//! scroll's content, mounts a virtual list's rows and paints hover with no commit, so a scroll
//! that commits on most frames is the app asking: its `poll`, a handler or a layout read.

private let motionGateMinScrollCommits: Int = 6

func motionGateScrollCommits(_ rec: MotionGateRecording, _ out: inout [MotionGateFinding]) {
    let share = motionGateRule("scroll-commit")
    var k = 0
    while k < rec.scrolled.count {
        if !rec.scrolled[k].0 {
            k += 1
            continue
        }
        let from = k
        while k < rec.scrolled.count && rec.scrolled[k].0 {
            k += 1
        }
        let runLen = k - from
        var committed: [Int] = []
        var why: UInt16 = 0
        for f in from..<k where rec.scrolled[f].1 != 0 {
            committed.append(f)
            why |= rec.scrolled[f].1
        }
        if committed.count < motionGateMinScrollCommits || Float(committed.count) < share * Float(runLen) {
            continue
        }
        let whyNames = CommitWhy.names(why).joined(separator: ", ")
        out.append(MotionGateFinding(
            kind: "scroll-commit",
            element: "frame",
            frame: committed[0],
            detail: "ran the view on \(committed.count) of the \(runLen) frames of a scroll (\(whyNames)): the debug build's `rune:` warning names the site"
        ))
    }
}
