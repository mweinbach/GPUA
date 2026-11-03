// Ported from: crates/rune/src/tooling/perf_warn/budget.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `RUNE_COMMIT_BUDGET_MS=N`: a line on stderr when a commit takes longer than `N` ms, with
//! where its time went (view, layout, text, apply) and what made the frame commit. Off unless
//! set, in any build, so it can watch a release build; while off, each phase checks one cached
//! flag. At most one line a second, counting the commits it left out.

#if !os(WASI)
import Foundation
#endif

private let budgetCacheLock = LiveLock()
// PORT NOTE: Synchronized via `budgetCacheLock`, mirroring `BUDGET: OnceLock<Option<f64>>` in `budget.rs`.
nonisolated(unsafe) private var cachedCommitBudgetInitialized: Bool = false
// PORT NOTE: Synchronized via `budgetCacheLock`.
nonisolated(unsafe) private var cachedCommitBudgetMs: Double? = nil

func perfBudgetMs() -> Double? {
    budgetCacheLock.withLock {
        if cachedCommitBudgetInitialized {
            return cachedCommitBudgetMs
        }
        cachedCommitBudgetInitialized = true
        #if !os(WASI)
        if let raw = ProcessInfo.processInfo.environment["RUNE_COMMIT_BUDGET_MS"],
           let parsed = Double(trimAsciiWhitespace(raw)),
           parsed > 0.0
        {
            cachedCommitBudgetMs = parsed
            return parsed
        }
        #endif
        cachedCommitBudgetMs = nil
        return nil
    }
}

@inline(__always)
func perfBudgetOn() -> Bool {
    perfBudgetMs() != nil
}

#if !os(WASI)
private let budgetThreadKey = "gpua.rune.perfWarn.budgetState"

private final class PerfBudgetThreadState {
    var times: [Double] = [Double](repeating: 0.0, count: INTERACTION_PHASES_COUNT)
    var depth: UInt32 = 0
    var printed: (RuneInstant, UInt32)? = nil
}

private func currentPerfBudgetThreadState() -> PerfBudgetThreadState {
    if let existing = Thread.current.threadDictionary[budgetThreadKey] as? PerfBudgetThreadState {
        return existing
    }
    let created = PerfBudgetThreadState()
    Thread.current.threadDictionary[budgetThreadKey] = created
    return created
}
#endif

func perfBudgetAdd(_ phase: ToolingProfilePhase, _ ms: Double) {
    #if !os(WASI)
    let st = currentPerfBudgetThreadState()
    st.times[phase.rawValue] += ms
    #endif
}

struct PerfBudgetCommit {
    private var state: (RuneInstant, Bool)?

    @inline(__always)
    static func start() -> PerfBudgetCommit {
        guard perfBudgetOn() else {
            return PerfBudgetCommit(state: nil)
        }
        #if !os(WASI)
        let st = currentPerfBudgetThreadState()
        let outer = (st.depth == 0)
        st.depth += 1
        if outer {
            st.times = [Double](repeating: 0.0, count: INTERACTION_PHASES_COUNT)
        }
        return PerfBudgetCommit(state: (RuneInstant.now(), outer))
        #else
        return PerfBudgetCommit(state: nil)
        #endif
    }

    @inline(__always)
    func end(_ why: UInt16) {
        guard let (start, outer) = state else { return }
        #if !os(WASI)
        let st = currentPerfBudgetThreadState()
        if st.depth > 0 {
            st.depth -= 1
        }
        guard outer, let budget = perfBudgetMs() else { return }
        let total = start.elapsedSeconds() * 1000.0
        guard total > budget else { return }
        let now = RuneInstant.now()
        let leftOut: UInt32
        if let (at, n) = st.printed {
            if now.saturatingDurationSince(at) < 1.0 {
                st.printed = (at, n + 1)
                return
            }
            leftOut = n
        } else {
            leftOut = 0
        }
        st.printed = (now, 0)
        toolingStderr(perfBudgetReport(total: total, budget: budget, times: st.times, why: why, leftOut: leftOut) + "\n")
        #endif
    }
}

private func fmtBudgetClean(_ v: Double) -> String {
    if v.rounded() == v && v.magnitude < 1e15 {
        return "\(Int64(v))"
    }
    return "\(v)"
}

private func fmtBudget1(_ v: Double) -> String {
    let tenths = Int64((v * 10.0).rounded())
    let sign = tenths < 0 ? "-" : ""
    let absTenths = abs(tenths)
    return "\(sign)\(absTenths / 10).\(absTenths % 10)"
}

/// The line for a commit that took `total` ms against `budget`, its phases timed in `times`.
func perfBudgetReport(
    total: Double,
    budget: Double,
    times: [Double],
    why: UInt16,
    leftOut: UInt32
) -> String {
    let view = times.count > 0 ? times[0] : 0.0
    let layout = times.count > 2 ? times[2] : 0.0
    let text = times.count > 3 ? times[3] : 0.0
    let apply = times.count > 5 ? times[5] : 0.0
    let parts: [(String, Double)] = [
        ("the view", view),
        ("layout", max(layout - text, 0.0)),
        ("text", text),
        ("apply", apply),
    ]
    var top: (String, Double)? = nil
    for p in parts where p.1 > 0.0 {
        if let cur = top {
            if p.1 >= cur.1 {
                top = p
            }
        } else {
            top = p
        }
    }
    let whyNames = ToolingCommitWhy.names(why)
    var line = "rune: commit took \(fmtBudget1(total)) ms, over RUNE_COMMIT_BUDGET_MS=\(fmtBudgetClean(budget)): view \(fmtBudget1(view)), layout \(fmtBudget1(layout)) (text \(fmtBudget1(text))), apply \(fmtBudget1(apply)) ms"
    if let (name, ms) = top, total > 0.0 {
        let pct = Int64((100.0 * ms / total).rounded())
        line += "; most in \(name) (\(pct)%)"
    }
    if !whyNames.isEmpty {
        line += "; committed for \(whyNames.joined(separator: ", "))"
    }
    if leftOut > 0 {
        line += " (\(leftOut) more over budget since the last line)"
    }
    return line
}
