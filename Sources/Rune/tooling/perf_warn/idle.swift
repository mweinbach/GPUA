// Ported from: crates/rune/src/tooling/perf_warn/idle.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The idle meters: a `poll` that says it changed what shows when nothing did, and a window that
//! keeps drawing the same frame while nothing asks it to.

let PERF_POLL_FRAMES: UInt32 = 30
let PERF_IDLE_FRAMES: UInt32 = 120
let PERF_IDLE_SECS: Double = 2.0

struct PerfDrawn {
    var instances: [UInt8]
    var key: UInt64
    var opaque: Bool
}

private struct PerfIdleStart {
    var quiet: Bool
    var timer: Bool
    var live: Bool
}

private func fmtIdle1(_ v: Double) -> String {
    let tenths = Int64((v * 10.0).rounded())
    let sign = tenths < 0 ? "-" : ""
    let absTenths = abs(tenths)
    return "\(sign)\(absTenths / 10).\(absTenths % 10)"
}

/// One window's idle meters.
final class PerfIdleMeter {
    private var frame: PerfIdleStart? = nil
    private var polledFlag: Bool = false
    private var last: ([UInt8], UInt64)? = nil
    private var pollStreak: UInt32 = 0
    private var idleFrom: Double = 0.0
    private var idleFrames: UInt32 = 0
    private var woken: (Bool, Bool, Bool) = (false, false, false)

    init() {}

    @inline(__always)
    func polled(_ changed: Bool) -> Bool {
        if changed {
            polledFlag = true
        }
        return changed
    }

    func begins(quiet: Bool, timer: Bool, live: Bool) {
        frame = PerfIdleStart(quiet: quiet, timer: timer, live: live)
    }

    func ends(clock: Double, animating: Bool, drawn: PerfDrawn, name: () -> String?) {
        guard let start = frame else { return }
        frame = nil
        let wasPolled = polledFlag
        polledFlag = false

        let quiet = start.quiet && !drawn.opaque
        let rawSame: Bool? = quiet
            ? last.map { (bytes, key) in key == drawn.key && bytes == drawn.instances }
            : nil
        if quiet {
            last = (drawn.instances, drawn.key)
        } else {
            last = nil
        }
        let same: Bool? = rawSame.map { $0 && !animating }

        func site() -> String {
            guard let n = name() else { return "" }
            return " \(toolingEscapeJsonString(n))"
        }

        if wasPolled, let isSame = same {
            pollStreak = isSame ? (pollStreak + 1) : 0
            if pollStreak == PERF_POLL_FRAMES {
                let win = site()
                let ofWin = win.isEmpty ? "" : " of window\(win)"
                perfWarnOnce("idle-poll\(win)") {
                    "`poll`\(ofWin) returned true but nothing changed (\(PERF_POLL_FRAMES) frames in a row); return true only when visible state changed"
                }
            }
        }

        if !quiet || animating || same == false {
            idleFrames = 0
            return
        }
        guard same != nil, start.timer || start.live else { return }
        if idleFrames == 0 || (clock - idleFrom) > PERF_IDLE_SECS {
            idleFrom = clock
            idleFrames = 0
            woken = (false, false, false)
        }
        idleFrames += 1
        if start.timer { woken.0 = true }
        if start.live { woken.1 = true }
        if wasPolled { woken.2 = true }

        if idleFrames == PERF_IDLE_FRAMES {
            let win = site()
            let by: String
            switch woken {
            case (true, _, true):
                by = "a `wake_after` loop whose `poll` returns true"
            case (true, false, false):
                by = "a `wake_after` loop"
            case (true, true, false):
                by = "a `wake_after` loop and a live value"
            case (false, _, _):
                by = "a live value"
            }
            let secs = clock - idleFrom
            perfWarnOnce("idle-draw\(win)") {
                "idle window\(win) still drawing: check `wake_after` loops (\(PERF_IDLE_FRAMES) frames in \(fmtIdle1(secs)) s with no input, motion or visible change, woken by \(by))"
            }
        }
    }
}
