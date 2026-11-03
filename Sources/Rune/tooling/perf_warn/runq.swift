// Ported from: crates/rune/src/tooling/perf_warn/runq.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Time a thread spent runnable but waiting for a core. A callback that was descheduled on a
//! busy machine isn't blocked, so `PerfStall` takes that time out before it judges. Interaction
//! timing (`tooling::interaction`) asks `perfRunqOverloaded()` in any build.

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

let PERF_STALL_MS: Double = 8.0
let PERF_STALL_CPU_RATIO: Double = 4.0

/// How long the calling thread has waited in a run queue, in ms, since it started. Linux reads
/// the scheduler's own count; other systems don't expose it per thread, so they get `nil`.
func perfRunqWaitMs() -> Double? {
    #if os(Linux) || os(Android)
    guard let stats = try? String(contentsOfFile: "/proc/thread-self/schedstat", encoding: .utf8) else {
        return nil
    }
    let parts = stats.split(whereSeparator: { $0.isWhitespace })
    guard parts.count >= 2, let ns = Double(parts[1]) else {
        return nil
    }
    return ns / 1e6
    #else
    return nil
    #endif
}

private let runqCacheLock = LiveLock()
// PORT NOTE: Synchronized via `runqCacheLock`, mirroring `CACHE: Mutex<Option<(Instant, bool)>>` in `runq.rs`.
nonisolated(unsafe) private var runqOverloadedCache: (RuneInstant, Bool)? = nil

/// Whether the machine has no core to spare: the 1-minute load average is at or above the core
/// count. Read at most every few seconds. Always false where there's no load average.
func perfRunqOverloaded() -> Bool {
    #if canImport(Darwin) || canImport(Glibc) || canImport(Android) || canImport(Musl)
    return runqCacheLock.withLock {
        let now = RuneInstant.now()
        if let (at, busy) = runqOverloadedCache, now.saturatingDurationSince(at) < 5.0 {
            return busy
        }
        var load: Double = 0.0
        #if canImport(Android)
        // PORT NOTE: Bionic exposes `getloadavg` starting at Android API 29; fall back to
        // `/proc/loadavg` (or `got = -1` -> `busy = false`) on older API levels.
        let got: Int32
        if #available(Android 29, *) {
            got = withUnsafeMutablePointer(to: &load) { ptr in
                getloadavg(ptr, 1)
            }
        } else if let text = try? String(contentsOfFile: "/proc/loadavg", encoding: .utf8),
            let first = text.split(whereSeparator: { $0.isWhitespace }).first,
            let parsed = Double(first)
        {
            load = parsed
            got = 1
        } else {
            got = -1
        }
        #else
        let got = withUnsafeMutablePointer(to: &load) { ptr in
            getloadavg(ptr, 1)
        }
        #endif
        let cores = Double(max(ProcessInfo.processInfo.activeProcessorCount, 1))
        let busy = (got == 1) && (load >= cores)
        runqOverloadedCache = (now, busy)
        return busy
    }
    #else
    return false
    #endif
}

/// The wall ms a callback was blocked, or `nil` when it wasn't. `wait` is the run-queue time
/// it spent when known; without it, a `loaded` machine gets the benefit of the doubt.
func perfRunqBlockedMs(wall: Double, cpu: Double, wait: Double?, loaded: Bool) -> Double? {
    if wait == nil && loaded {
        return nil
    }
    let clampedWait = min(max(wait ?? 0.0, 0.0), wall)
    let blocked = wall - clampedWait
    return (blocked > PERF_STALL_MS && blocked > PERF_STALL_CPU_RATIO * cpu) ? blocked : nil
}
