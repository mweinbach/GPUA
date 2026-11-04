// Ported from: crates/rune/src/tooling/interaction.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Interaction timing: input-to-present latency, phase split, cause classification, and per-signature rollups.

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

let INTERACTION_PHASES_COUNT = 6

enum ToolingProfilePhase: Int, Sendable {
    case view = 0
    case commit = 1
    case layout = 2
    case text = 3
    case paint = 4
    case apply = 5
}

enum ToolingCommitWhy {
    static let POLL: UInt16 = 1
    static let INPUT: UInt16 = 2
    static let LAYOUT: UInt16 = 4
    static let READ: UInt16 = 8
    static let DIRTY: UInt16 = 16
    static let RELAYOUT: UInt16 = 32
    static let SETTLE: UInt16 = 64
    static let VIRTUAL: UInt16 = 128
    static let ROUTE: UInt16 = 256

    static let NAMES = ["poll", "input", "layout", "read", "dirty", "relayout", "settle", "virtual", "route"]

    static func names(_ bits: UInt16) -> [String] {
        NAMES.enumerated().compactMap { i, name in
            (bits & (1 << i)) != 0 ? name : nil
        }
    }
}

/// Thread CPU time in milliseconds, when the OS exposes it (`crates/rune/src/frame/profile.rs:cpu_ms`).
func toolingThreadCpuMs() -> Double? {
    frameCpuMs()
}

let INTERACTION_SLOW_MS: Double = 1000.0 / 60.0
private let interactionRollupEvery: Double = 60.0
private let interactionSlowPerSecond: UInt32 = 10

let INTERACTION_PHASE_NAMES: [String] = [
    "rune.view_ms",
    "rune.commit_ms",
    "rune.layout_ms",
    "rune.text_ms",
    "rune.paint_ms",
    "rune.apply_ms",
]

#if !os(WASI)
private let interactionThreadKey = "gpua.rune.interaction.threadState"

private final class InteractionThreadBox {
    var active: Bool = false
    var times: [Double] = [Double](repeating: 0.0, count: INTERACTION_PHASES_COUNT)
    var sentSlowForTests: [InteractionSlow] = []
    var sentFramesForTests: [InteractionSlowFrame] = []
    var overloadedForTests: Bool? = nil
}

private func currentInteractionThreadBox() -> InteractionThreadBox {
    if let existing = Thread.current.threadDictionary[interactionThreadKey] as? InteractionThreadBox {
        return existing
    }
    let created = InteractionThreadBox()
    Thread.current.threadDictionary[interactionThreadKey] = created
    return created
}
#endif

func interactionOn() -> Bool {
    interactionGateOn()
}

func interactionActive() -> Bool {
    #if os(WASI)
    return false
    #else
    guard let box = Thread.current.threadDictionary[interactionThreadKey] as? InteractionThreadBox else {
        return false
    }
    return box.active
    #endif
}

func interactionAddPhase(_ phase: ToolingProfilePhase, _ ms: Double) {
    #if !os(WASI)
    let box = currentInteractionThreadBox()
    if box.active {
        box.times[phase.rawValue] += ms
    }
    #endif
}

private let slowMsCacheLock = LiveLock()
// PORT NOTE: Synchronized via `slowMsCacheLock`, mirroring `MS: OnceLock<f64>`.
nonisolated(unsafe) private var cachedSlowMs: Double? = nil

func interactionSlowThresholdMs() -> Double {
    slowMsCacheLock.withLock {
        if let existing = cachedSlowMs { return existing }
        #if !os(WASI)
        if let raw = ProcessInfo.processInfo.environment["RUNE_PERF_SLOW_MS"],
           let parsed = Double(trimAsciiWhitespace(raw)), parsed > 0.0
        {
            cachedSlowMs = parsed
            return parsed
        }
        #endif
        cachedSlowMs = INTERACTION_SLOW_MS
        return INTERACTION_SLOW_MS
    }
}

struct InteractionNote: Sendable {
    var route: InteractionName
    var control: InteractionName
    var action: String
    var rank: UInt8
}

struct InteractionSlow: Sendable {
    var route: String
    var control: String
    var action: String
    var arrived: RuneInstant
    var frameStart: RuneInstant
    var built: RuneInstant
    var submitted: RuneInstant
    var present: RuneInstant
    var handlerMs: Double
    var phases: [Double]
    var why: UInt16
    var commits: UInt32
    var shaped: UInt32
    var nodes: Int
    var reused: Int
    var rebuilt: [(String, Int)]
    var cpuMs: Double?
    var cause: InteractionCause
    var stacks: InteractionStacks?
}

struct InteractionSlowFrame: Sendable {
    var start: RuneInstant
    var built: RuneInstant
    var why: UInt16
    var nodes: Int
    var cause: InteractionCause
    var stacks: InteractionStacks
}

struct InteractionTimed: Sendable {
    var arrived: RuneInstant
    var frameStart: RuneInstant
    var handlerMs: Double
    var note: InteractionNote
    var why: UInt16
    var commits: UInt32
    var built: (RuneInstant, [Double], UInt32)?
    var cpu: (Double?, Double?)
    var stacks: InteractionStacks?
}

struct InteractionFinished: Sendable {
    var timed: InteractionTimed
    var built: RuneInstant
    var phases: [Double]
    var shaped: UInt32
    var submitted: RuneInstant
    var present: RuneInstant
    var cause: InteractionCause?
    var slow: Bool
}

final class InteractionTracker {
    var names = InteractionNames()
    var rollup = InteractionRollup()
    private var rolledSince: RuneInstant? = nil
    private var frameStart: RuneInstant? = nil
    private var began: (RuneInstant, Double?)? = nil
    var breachedSignatures: Set<UInt64> = []
    private var frameWhy: UInt16 = 0
    var timed: InteractionTimed? = nil
    var reused: [(Int, Int)] = []
    private var sentWindow: (RuneInstant?, UInt32) = (nil, 0)

    init() {}

    func frameBegins(queued: Bool) -> InteractionFinished? {
        var finished: InteractionFinished? = nil
        if let existingBuilt = timed?.built?.0 {
            finished = finish(submitted: existingBuilt, presentsAt: nil)
        }
        let now = RuneInstant.now()
        frameStart = queued ? now : nil
        began = (now, queued ? toolingThreadCpuMs() : nil)
        frameWhy = 0
        interactionWatchdogArm()
        return finished
    }

    func breached(_ note: InteractionNote) -> Bool {
        !breachedSignatures.isEmpty
            && breachedSignatures.contains(interactionSignature(note.route, note.control, note.action))
    }

    func noted(_ note: InteractionNote, at: RuneInstant?, started: RuneInstant, handlerSeconds: Double) {
        let fStart = frameStart ?? started
        frameStart = fStart
        let rawArrived = at ?? fStart
        let arrived = rawArrived < fStart ? rawArrived : fStart
        if var t = timed, t.built == nil {
            if arrived < t.arrived { t.arrived = arrived }
            t.handlerMs += handlerSeconds * 1000.0
            if note.rank > t.note.rank { t.note = note }
            timed = t
        } else {
            let cpuStart = began?.1 ?? toolingThreadCpuMs()
            timed = InteractionTimed(
                arrived: arrived,
                frameStart: fStart,
                handlerMs: handlerSeconds * 1000.0,
                note: note,
                why: 0,
                commits: 0,
                built: nil,
                cpu: (cpuStart, nil),
                stacks: nil
            )
            #if !os(WASI)
            let box = currentInteractionThreadBox()
            box.times = [Double](repeating: 0.0, count: INTERACTION_PHASES_COUNT)
            box.active = true
            #endif
        }
    }

    func committed(_ why: UInt16) {
        frameWhy |= why
        if var t = timed, t.built == nil {
            t.why |= why
            t.commits += 1
            timed = t
        }
    }

    func built(shaped: UInt32, nodes: Int) -> InteractionSlowFrame? {
        let why = frameWhy
        frameStart = nil
        let stacks = interactionWatchdogDisarm()
        let beg = began
        began = nil
        guard var t = timed, t.built == nil else {
            guard let start = beg?.0, let stacks else { return nil }
            let builtNow = RuneInstant.now()
            let work = builtNow.saturatingDurationSince(start) * 1000.0
            let cause = interactionCause(
                workMs: work,
                slowMs: interactionSlowThresholdMs(),
                cpuMs: nil,
                stacks: stacks,
                overloaded: interactionOverloaded()
            )
            return work > interactionSlowThresholdMs()
                ? InteractionSlowFrame(start: start, built: builtNow, why: why, nodes: nodes, cause: cause, stacks: stacks)
                : nil
        }
        let phases: [Double]
        #if !os(WASI)
        let box = currentInteractionThreadBox()
        phases = box.times
        box.times = [Double](repeating: 0.0, count: INTERACTION_PHASES_COUNT)
        box.active = false
        #else
        phases = [Double](repeating: 0.0, count: INTERACTION_PHASES_COUNT)
        #endif
        t.built = (RuneInstant.now(), phases, shaped)
        if let fromCpu = t.cpu.0, let toCpu = toolingThreadCpuMs() {
            t.cpu.1 = max(toCpu - fromCpu, 0.0)
        }
        t.stacks = stacks
        timed = t
        return nil
    }

    func finish(submitted: RuneInstant, presentsAt: RuneInstant?) -> InteractionFinished? {
        guard let t = timed, let (builtAt, phases, shaped) = t.built else { return nil }
        timed = nil
        let sub = submitted >= builtAt ? submitted : builtAt
        let pres: RuneInstant
        if let p = presentsAt {
            pres = p >= sub ? p : sub
        } else {
            pres = sub
        }
        let total = pres.saturatingDurationSince(t.arrived) * 1000.0
        let work = sub.saturatingDurationSince(t.frameStart) * 1000.0
        let slowThresh = interactionSlowThresholdMs()
        let over = total > slowThresh || work > slowThresh
        let cause: InteractionCause? = over
            ? interactionCause(
                workMs: work,
                slowMs: slowThresh,
                cpuMs: t.cpu.1,
                stacks: t.stacks,
                overloaded: interactionOverloaded()
            )
            : nil
        let contended = (cause == .schedulerWait)
        let note = t.note
        rollup.add(
            route: note.route,
            control: note.control,
            action: note.action,
            ms: total,
            slow: over && !contended,
            contended: contended
        )
        if over && !contended {
            breachedSignatures.insert(interactionSignature(note.route, note.control, note.action))
        }
        let sendSlow = over && allow(now: pres)
        if rolledSince == nil {
            rolledSince = t.arrived
        }
        return InteractionFinished(
            timed: t,
            built: builtAt,
            phases: phases,
            shaped: shaped,
            submitted: sub,
            present: pres,
            cause: cause,
            slow: sendSlow
        )
    }

    private func allow(now: RuneInstant) -> Bool {
        if let at = sentWindow.0, now.saturatingDurationSince(at) < 1.0 {
            let n = sentWindow.1
            sentWindow.1 = n + 1
            return n < interactionSlowPerSecond
        }
        sentWindow = (now, 1)
        return true
    }

    func roll(force: Bool) {
        guard let from = rolledSince else { return }
        let to = RuneInstant.now()
        if rollup.isEmpty || (!force && to.saturatingDurationSince(from) < interactionRollupEvery) {
            return
        }
        _ = interactionExportSend(.rollup(rolls: rollup.take(), from: from, to: to))
        rolledSince = nil
    }

    deinit {
        if rolledSince != nil {
            roll(force: true)
        }
    }
}

private func interactionOverloaded() -> Bool {
    #if !os(WASI)
    if let box = Thread.current.threadDictionary[interactionThreadKey] as? InteractionThreadBox,
       let override = box.overloadedForTests
    {
        return override
    }
    #endif
    return perfRunqOverloaded()
}

func interactionSendFrame(_ frame: InteractionSlowFrame) {
    #if !os(WASI)
    if interactionGateIsTestMode() {
        currentInteractionThreadBox().sentFramesForTests.append(frame)
        return
    }
    #endif
    _ = interactionExportSend(.frame(frame))
}

func interactionSendSlow(_ slow: InteractionSlow) {
    #if !os(WASI)
    if interactionGateIsTestMode() {
        currentInteractionThreadBox().sentSlowForTests.append(slow)
        return
    }
    #endif
    _ = interactionExportSend(.slow(slow))
}

func interactionFlush() {
    if interactionOn() {
        interactionExportFlush(1.0)
    }
}

func interactionTakeSentSlowForTests() -> [InteractionSlow] {
    #if os(WASI)
    return []
    #else
    let box = currentInteractionThreadBox()
    let out = box.sentSlowForTests
    box.sentSlowForTests.removeAll()
    return out
    #endif
}

func interactionTakeSentFramesForTests() -> [InteractionSlowFrame] {
    #if os(WASI)
    return []
    #else
    let box = currentInteractionThreadBox()
    let out = box.sentFramesForTests
    box.sentFramesForTests.removeAll()
    return out
    #endif
}

func interactionSetOverloadedForTests(_ overloaded: Bool?) {
    #if !os(WASI)
    currentInteractionThreadBox().overloadedForTests = overloaded
    #endif
}

private let interactionPageAreaShare: Float = 0.5

extension Runtime {
    func hostInteractionTracker() -> InteractionTracker {
        windowHostState(for: self).perfWatch.interaction
    }

    func hostInteractionNote(action: String, rank: UInt8, path: String?) -> InteractionNote? {
        guard interactionOn() else { return nil }
        let hs = windowHostState(for: self)
        let elems = hs.lastElements
        let atIdx = path.flatMap { p in elems.firstIndex(where: { $0.path == p || $0.key == p }) }
        let pagePath: String? = atIdx.flatMap { idx in
            let minArea = max(viewport.0 * viewport.1 * interactionPageAreaShare, 1.0)
            var cur: Int? = idx
            while let i = cur, i < elems.count {
                let e = elems[i]
                if e.key != nil, e.target.count >= 4, e.target[2] * e.target[3] >= minArea {
                    return e.path
                }
                cur = e.parent
            }
            return nil
        }
        let resolvedPath = atIdx.map { elems[$0].path } ?? path
        let control = resolvedPath.map { hs.perfWatch.interaction.names.control($0) } ?? hs.perfWatch.interaction.names.fixed("window")
        let route = hs.perfWatch.interaction.names.route(pagePath, nil)
        let note = InteractionNote(route: route, control: control, action: action, rank: rank)
        if hs.perfWatch.interaction.breached(note) {
            interactionWatchdogHurry()
        }
        return note
    }

    func hostInteractionRan(note: InteractionNote, started: RuneInstant, inputArrivedAt: RuneInstant? = nil) {
        let hs = windowHostState(for: self)
        let handlerSecs = started.elapsedSeconds()
        hs.perfWatch.interaction.noted(note, at: inputArrivedAt, started: started, handlerSeconds: handlerSecs)
        hs.perfWatch.cause |= ToolingCommitWhy.INPUT
    }

    func hostInteractionFrameBegins(queued: Bool) {
        guard interactionOn() else { return }
        let hs = windowHostState(for: self)
        if let finished = hs.perfWatch.interaction.frameBegins(queued: queued) {
            hostInteractionFinished(finished)
        }
    }

    func hostInteractionBuilt() {
        guard interactionOn() else { return }
        let hs = windowHostState(for: self)
        if let frame = hs.perfWatch.interaction.built(shaped: 0, nodes: hs.lastElements.count) {
            interactionSendFrame(frame)
        }
    }

    func hostInteractionPresented(submitted: RuneInstant, presentsAt: RuneInstant? = nil) {
        guard interactionOn() else { return }
        let hs = windowHostState(for: self)
        if let finished = hs.perfWatch.interaction.finish(submitted: submitted, presentsAt: presentsAt) {
            hostInteractionFinished(finished)
        }
    }

    func hostInteractionFlush() {
        guard interactionOn() else { return }
        let hs = windowHostState(for: self)
        if let finished = hs.perfWatch.interaction.frameBegins(queued: false) {
            hostInteractionFinished(finished)
        }
        hs.perfWatch.interaction.roll(force: true)
        interactionFlush()
    }

    private func hostInteractionFinished(_ f: InteractionFinished) {
        let hs = windowHostState(for: self)
        let tracker = hs.perfWatch.interaction
        if f.slow {
            let rebuilt = hostRebuiltSubtrees(hs)
            let reusedCount = tracker.reused.reduce(0) { $0 + $1.1 }
            interactionSendSlow(
                InteractionSlow(
                    route: f.timed.note.route.text,
                    control: f.timed.note.control.text,
                    action: f.timed.note.action,
                    arrived: f.timed.arrived,
                    frameStart: f.timed.frameStart,
                    built: f.built,
                    submitted: f.submitted,
                    present: f.present,
                    handlerMs: f.timed.handlerMs,
                    phases: f.phases,
                    why: f.timed.why,
                    commits: f.timed.commits,
                    shaped: f.shaped,
                    nodes: hs.lastElements.count,
                    reused: reusedCount,
                    rebuilt: rebuilt,
                    cpuMs: f.timed.cpu.1,
                    cause: f.cause ?? .queued,
                    stacks: f.timed.stacks
                )
            )
        }
        tracker.reused.removeAll()
        tracker.roll(force: false)
    }

    private func hostRebuiltSubtrees(_ hs: RuntimeWindowHostState) -> [(String, Int)] {
        let elems = hs.lastElements
        let n = elems.count
        guard n > 0 else { return [] }
        var isReused = [Bool](repeating: false, count: n)
        for (start, len) in hs.perfWatch.interaction.reused {
            for j in start..<min(start + len, n) where j >= 0 {
                isReused[j] = true
            }
        }
        var count = [Int](repeating: 0, count: n)
        for i in 0..<n where !isReused[i] {
            var cur: Int? = i
            while let j = cur, j < n {
                if elems[j].key != nil {
                    count[j] += 1
                }
                cur = elems[j].parent
            }
        }
        var inner = [Int](repeating: 0, count: n)
        for i in 0..<n where count[i] > 0 && elems[i].key != nil {
            var cur = elems[i].parent
            while let j = cur, j < n {
                if elems[j].key != nil {
                    inner[j] = max(inner[j], count[i])
                    break
                }
                cur = elems[j].parent
            }
        }
        var top: [Int] = []
        for i in 0..<n where count[i] > 0 && elems[i].key != nil {
            if Double(inner[i]) < 0.9 * Double(count[i]) {
                top.append(i)
            }
        }
        top.sort { count[$0] > count[$1] }
        if top.count > 3 { top.removeSubrange(3...) }
        return top.map { idx in
            (hs.perfWatch.interaction.names.control(elems[idx].path).text, count[idx])
        }
    }
}
