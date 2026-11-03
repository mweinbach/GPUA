// Ported from: crates/rune/src/tooling/perf_warn.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Debug-only warnings for app code that works but runs slow: a `virtualize` list that builds
//! every row to mount a few, a callback that blocks the main thread, a `poll` that says it
//! changed what shows when nothing did, a window that keeps drawing while idle, a slow first
//! frame, something that commits the view on most frames of a scroll, an app stepping its own
//! scroll glide, and a `memo` whose root already had another key.

#if !os(WASI)
import Foundation
#endif

let PERF_OVERBUILD_ROWS: Int = 200
let PERF_OVERBUILD_RATIO: Int = 4

/// A window's commit watch: what the commit underway is for (`RUNE_COMMIT_BUDGET_MS` prints
/// it), and the commit warnings' meters.
final class PerfWatch {
    var cause: UInt16 = 0
    let meter = PerfCommitMeter()
    let interaction = InteractionTracker()

    init() {}
}

private let perfWarnLock = LiveLock()
// PORT NOTE: Synchronized via `perfWarnLock`, mirroring `ON: OnceLock<bool>` and `WARNED: Mutex<Option<HashSet<String>>>` in `perf_warn.rs`.
nonisolated(unsafe) private var cachedPerfWarnEnabled: Bool? = nil
// PORT NOTE: Synchronized via `perfWarnLock`.
nonisolated(unsafe) private var warnedSites = Set<String>()

func perfWarnEnabled() -> Bool {
    perfWarnLock.withLock {
        if let existing = cachedPerfWarnEnabled {
            return existing
        }
        #if !os(WASI)
        if let val = ProcessInfo.processInfo.environment["RUNE_PERF_WARN"] {
            let on = (val != "0")
            cachedPerfWarnEnabled = on
            return on
        }
        #endif
        cachedPerfWarnEnabled = true
        return true
    }
}

#if !os(WASI)
private let perfWarnLogThreadKey = "gpua.rune.perfWarn.threadLog"

private final class PerfWarnThreadLog {
    var testScopeId: String? = nil
    var messages: [String] = []
}

private func currentPerfWarnThreadLog() -> PerfWarnThreadLog {
    if let existing = Thread.current.threadDictionary[perfWarnLogThreadKey] as? PerfWarnThreadLog {
        return existing
    }
    let created = PerfWarnThreadLog()
    Thread.current.threadDictionary[perfWarnLogThreadKey] = created
    return created
}
#endif

private let perfWarnScopeCounterLock = LiveLock()
// PORT NOTE: Synchronized via `perfWarnScopeCounterLock` so unit tests get isolated per-thread/per-test warn sites, matching `#[cfg(test)] format!("{:?} {site}", thread::current().id())` in `perf_warn.rs`.
nonisolated(unsafe) private var nextPerfWarnScopeId: UInt64 = 0

/// Drains warnings emitted on the current thread since the last call, and activates per-thread site isolation for tests.
func perfWarnTakeLogForTests(newScope: Bool = false) -> [String] {
    #if os(WASI)
    _ = newScope
    return []
    #else
    let box = currentPerfWarnThreadLog()
    if box.testScopeId == nil || newScope {
        let id = perfWarnScopeCounterLock.withLock { () -> UInt64 in
            nextPerfWarnScopeId += 1
            return nextPerfWarnScopeId
        }
        box.testScopeId = "test-\(id)"
    }
    let out = box.messages
    box.messages.removeAll()
    return out
    #endif
}

/// Prints `message` the first time `site` warns.
func perfWarnOnce(_ site: String, _ message: () -> String) {
    guard perfWarnEnabled() else { return }
    #if !os(WASI)
    let logBox = currentPerfWarnThreadLog()
    let scopedSite: String
    if let scope = logBox.testScopeId {
        scopedSite = "\(scope) \(site)"
    } else {
        scopedSite = site
    }
    #else
    let scopedSite = site
    #endif

    let isFirst = perfWarnLock.withLock {
        warnedSites.insert(scopedSite).inserted
    }
    guard isFirst else { return }
    let formatted = "rune: \(message()). (debug builds only; RUNE_PERF_WARN=0 silences)"
    #if !os(WASI)
    if logBox.testScopeId != nil {
        logBox.messages.append(formatted)
    }
    #endif
    toolingStderr(formatted + "\n")
}

/// A `virtualize` list at `path`, set up at `site`, was handed `built` rows and mounts `mounted` of them.
func perfWarnOverbuilt(path: String, site: String?, built: Int, mounted: Int) {
    guard built > PERF_OVERBUILD_ROWS, built > PERF_OVERBUILD_RATIO * mounted else { return }
    let siteSuffix = site.map { " (.virtualize at \($0))" } ?? ""
    perfWarnOnce("overbuild \(path)") {
        "virtualized list \(toolingEscapeJsonString(path))\(siteSuffix) built \(built) rows to mount \(mounted): build only the mounted rows with `.virtual_rows(count, estimated_row_height, key, build)`"
    }
}

/// `memo(id, ..)`, called at `site`, built a root already keyed `existing` and renamed it `id`.
func perfWarnMemoKeyReplaced(id: String, existing: String, site: String) {
    guard existing != id else { return }
    perfWarnOnce("memo key \(site)") {
        "`memo(\(toolingEscapeJsonString(id)), ..)` at \(site) replaced its root's key \(toolingEscapeJsonString(existing)) with \(toolingEscapeJsonString(id)): look it up by \(toolingEscapeJsonString(id)), or key the memo with the id you want"
    }
}

/// Times one app callback on the main thread: `end` warns when it spent most of its time blocked rather than computing.
struct PerfStall {
    private var start: (RuneInstant, Double, Double?)?

    @inline(__always)
    static func start() -> PerfStall {
        guard perfWarnEnabled(), let cpu = toolingThreadCpuMs() else {
            return PerfStall(start: nil)
        }
        return PerfStall(start: (RuneInstant.now(), cpu, perfRunqWaitMs()))
    }

    @inline(__always)
    func end(_ what: () -> (String, String)) {
        guard let (wallAt, cpuStart, waitStart) = start else { return }
        let wall = wallAt.elapsedSeconds() * 1000.0
        guard wall > PERF_STALL_MS else { return }
        let cpu = toolingThreadCpuMs().map { max($0 - cpuStart, 0.0) } ?? 0.0
        let waited: Double? = waitStart.flatMap { ws in
            perfRunqWaitMs().map { max($0 - ws, 0.0) }
        }
        let loaded = (waited == nil) && perfRunqOverloaded()
        guard let blocked = perfRunqBlockedMs(wall: wall, cpu: cpu, wait: waited, loaded: loaded) else {
            return
        }
        let (site, name) = what()
        perfWarnOnce("stall \(site)") {
            let queued: String
            if let w = waited, w >= 1.0 {
                queued = ", waited \(Int64(w.rounded())) ms for a core"
            } else {
                queued = ""
            }
            return "\(name) blocked \(Int64(blocked.rounded())) ms (CPU \(Int64(cpu.rounded())) ms\(queued)) on the main thread: move IO off it with `rune::Latest` or a thread"
        }
    }
}

/// Runs `f`, an app callback named `name` (a call site of its own), under a `PerfStall`.
@inline(__always)
func perfTimed<T>(_ name: String, _ f: () -> T) -> T {
    let stall = PerfStall.start()
    let out = f()
    stall.end {
        let display = name.contains(" ") ? name : "`\(name)`"
        return (name, display)
    }
    return out
}

/// A handler's site: its name and the element's path with the digits taken out, so the rows of
/// one list share it.
func perfHandlerSite(_ name: String, _ path: String) -> String {
    let stripped = String(path.filter { !($0 >= "0" && $0 <= "9") })
    return "\(name) \(stripped)"
}
