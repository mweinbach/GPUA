// Ported from: crates/rune/src/tooling/perf_warn/launch.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! How long launch took to put the first frame up, split into the app's parts (`main` before
//! `run`, `init` and the first view build) and Rune's (window, GPU and drawing). Warns once
//! when the app's parts pass 100 ms: they are what `on_ready` can take off the first frame.

#if canImport(Darwin)
import Darwin
import Foundation
#elseif canImport(Glibc)
import Glibc
import Foundation
#elseif canImport(Android)
import Android
import Foundation
#elseif canImport(Musl)
import Musl
import Foundation
#elseif os(Windows)
import ucrt
import Foundation
#endif

let PERF_LAUNCH_APP_MS: Double = 100.0

private struct PerfLaunchState {
    var run: (RuneInstant, Double?)? = nil
    var initSec: Double? = nil
    var viewSec: Double? = nil
    var done: Bool = false
}

private let launchStateLock = LiveLock()
// PORT NOTE: Synchronized via `launchStateLock`, mirroring `LAUNCH: Mutex<Launch>` in `launch.rs`.
nonisolated(unsafe) private var globalLaunchState = PerfLaunchState()

@inline(__always)
func perfLaunchRunStarts() {
    #if DEBUG && !os(WASI)
    let age = perfProcessAgeSeconds()
    launchStateLock.withLock {
        if globalLaunchState.run == nil {
            globalLaunchState.run = (RuneInstant.now(), age)
        }
    }
    #endif
}

@inline(__always)
func perfLaunchInit<T>(_ f: () -> T) -> T {
    #if DEBUG && !os(WASI)
    let start = RuneInstant.now()
    #endif
    let out = perfTimed("init", f)
    #if DEBUG && !os(WASI)
    let elapsed = start.elapsedSeconds()
    launchStateLock.withLock {
        if globalLaunchState.run != nil && globalLaunchState.initSec == nil {
            globalLaunchState.initSec = elapsed
        }
    }
    #endif
    return out
}

struct PerfFirstView {
    private var start: RuneInstant?

    @inline(__always)
    static func start(_ first: Bool) -> PerfFirstView {
        #if DEBUG && !os(WASI)
        return PerfFirstView(start: first ? RuneInstant.now() : nil)
        #else
        _ = first
        return PerfFirstView(start: nil)
        #endif
    }

    @inline(__always)
    func end() {
        #if DEBUG && !os(WASI)
        guard let s = start else { return }
        let elapsed = s.elapsedSeconds()
        launchStateLock.withLock {
            if globalLaunchState.run != nil && globalLaunchState.viewSec == nil {
                globalLaunchState.viewSec = elapsed
            }
        }
        #endif
    }
}

@inline(__always)
func perfLaunchFirstFrame() {
    #if DEBUG && !os(WASI)
    let message: String? = launchStateLock.withLock {
        guard !globalLaunchState.done, let (runAt, ageSec) = globalLaunchState.run else {
            return nil
        }
        globalLaunchState.done = true
        let setup = (ageSec ?? 0.0) * 1000.0
        let initMs = (globalLaunchState.initSec ?? 0.0) * 1000.0
        let viewMs = (globalLaunchState.viewSec ?? 0.0) * 1000.0
        let total = setup + runAt.elapsedSeconds() * 1000.0
        return perfLaunchReport(setup: setup, initMs: initMs, view: viewMs, total: total)
    }
    if let message {
        perfWarnOnce("first frame") { message }
    }
    #endif
}

private func fmtLaunch0(_ v: Double) -> String {
    "\(Int64(v.rounded()))"
}

/// The warning for a first frame `total` ms after the process started, `setup` ms of it in
/// `main` before `run`, `initMs` in `init` and `view` in the first view build; `nil` while the
/// app's parts stay under `PERF_LAUNCH_APP_MS`.
func perfLaunchReport(setup: Double, initMs: Double, view: Double, total: Double) -> String? {
    if setup + initMs + view <= PERF_LAUNCH_APP_MS {
        return nil
    }
    let runeMs = max(total - setup - initMs - view, 0.0)
    let parts: [(Double, String)] = [
        (setup, "setup in `main` before `run`"),
        (initMs, "`init`"),
        (view, "the first `view`"),
    ]
    var slowest = parts[0]
    for p in parts.dropFirst() {
        if p.0 >= slowest.0 {
            slowest = p
        }
    }
    return "first frame took \(fmtLaunch0(total)) ms (setup \(fmtLaunch0(setup)) ms, init \(fmtLaunch0(initMs)) ms, first view \(fmtLaunch0(view)) ms, window and GPU \(fmtLaunch0(runeMs)) ms); the slowest is \(slowest.1): start slow work from `on_ready`"
}

func perfProcessAgeSeconds() -> Double? {
    #if os(macOS)
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    let got = withUnsafeMutablePointer(to: &info) { ptr in
        proc_pidinfo(getpid(), PROC_PIDTBSDINFO, 0, ptr, size)
    }
    guard got == size else { return nil }
    let startSec = Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000.0
    let nowSec = Date().timeIntervalSince1970
    let delta = nowSec - startSec
    return delta >= 0.0 ? delta : nil
    #elseif os(Linux)
    guard let stat = try? String(contentsOfFile: "/proc/self/stat", encoding: .utf8),
          let closeParen = stat.lastIndex(of: ")")
    else { return nil }
    let rest = stat[stat.index(after: closeParen)...]
    let fields = rest.split(whereSeparator: { $0.isWhitespace })
    guard fields.count > 19,
          let startTicks = Double(fields[19])
    else { return nil }
    let clkTck = Double(sysconf(Int32(_SC_CLK_TCK)))
    guard clkTck > 0.0,
          let uptimeStr = try? String(contentsOfFile: "/proc/uptime", encoding: .utf8),
          let firstToken = uptimeStr.split(whereSeparator: { $0.isWhitespace }).first,
          let upSec = Double(firstToken)
    else { return nil }
    return max(upSec - startTicks / clkTck, 0.0)
    #else
    return nil
    #endif
}
