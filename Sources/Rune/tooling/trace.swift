// Ported from: crates/rune/src/tooling/trace.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Motion-lint JSONL trace writer and headless element-tree JSON snapshots.

#if !os(WASI)
import Foundation
#endif
import RuneMotion

func toolingR2(_ v: Float) -> Double {
    (Double(v) * 100.0).rounded() / 100.0
}

private func toolingR3(_ v: Double) -> Double {
    (v * 1000.0).rounded() / 1000.0
}

/// A native frame's timing beyond its submission time.
struct ToolingFrameTiming: Sendable, Equatable {
    /// The display link's target, ms on the trace's clock.
    var targetMs: Double? = nil
    /// The drawable the frame presented, when present times are recorded.
    var drawable: UInt64? = nil
    /// The previous frame asked for this one right away (it wasn't idle).
    var continuous: Bool = false

    init(targetMs: Double? = nil, drawable: UInt64? = nil, continuous: Bool = false) {
        self.targetMs = targetMs
        self.drawable = drawable
        self.continuous = continuous
    }
}

/// Source of drawable presentation timestamps (`crates/rune/src/frame/present_time.rs`).
protocol ToolingPresentSource: AnyObject, Sendable {
    func take(_ out: inout [(UInt64, RuneInstant?)])
}

/// Summary of present-time pacing across a trace (`Summary::of_trace`).
struct ToolingPresentSummary: Sendable, Equatable, CustomStringConvertible {
    var frames: Int
    var presented: Int
    var bunched: Int
    var missed: Int

    var description: String {
        "rune: presents \(presented)/\(frames) frames, \(bunched) bunched, \(missed) missed"
    }

    static func ofTrace(_ text: String) -> ToolingPresentSummary? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > 1 else { return nil }
        var hz: Double = 60.0
        if let hdr = try? ToolingJson.parse(String(lines[0])), let h = hdr["hz"].doubleValue, h > 0 {
            hz = h
        }
        let periodMs = 1000.0 / hz
        var frames = 0
        var presented = 0
        var bunched = 0
        var missed = 0
        for raw in lines.dropFirst() {
            guard let obj = try? ToolingJson.parse(String(raw)) else { continue }
            frames += 1
            if obj["present_ms"].doubleValue != nil {
                presented += 1
                if let dt = obj["present_dt_ms"].doubleValue {
                    if dt < periodMs * 0.5 {
                        bunched += 1
                    } else if dt > periodMs * 1.5 {
                        missed += 1
                    }
                }
            }
        }
        return presented > 0 ? ToolingPresentSummary(frames: frames, presented: presented, bunched: bunched, missed: missed) : nil
    }
}

private final class ToolingPresents {
    private let source: any ToolingPresentSource
    private let start: RuneInstant
    private var held: [(line: String, drawable: UInt64?, continuous: Bool)] = []
    private var resolved: [UInt64: RuneInstant?] = [:]
    private var lastPresentMs: Double? = nil

    init(source: any ToolingPresentSource, start: RuneInstant) {
        self.source = source
        self.start = start
    }

    var waiting: Bool {
        drainSource()
        return held.contains { item in
            guard let d = item.drawable else { return false }
            return resolved[d] == nil
        }
    }

    private func drainSource() {
        var batch: [(UInt64, RuneInstant?)] = []
        source.take(&batch)
        for (drawable, at) in batch {
            resolved[drawable] = at
        }
    }

    func push(line: String, drawable: UInt64?, continuous: Bool, emit: (String) -> Void) {
        held.append((line: line, drawable: drawable, continuous: continuous))
        drainReady(forceAll: false, emit: emit)
    }

    func flush(emit: (String) -> Void) {
        drainReady(forceAll: true, emit: emit)
    }

    private func drainReady(forceAll: Bool, emit: (String) -> Void) {
        drainSource()
        while let first = held.first {
            if let d = first.drawable {
                if let maybeAt = resolved[d] {
                    resolved.removeValue(forKey: d)
                    held.removeFirst()
                    emitLine(first.line, presentAt: maybeAt, continuous: first.continuous, emit: emit)
                } else if forceAll {
                    held.removeFirst()
                    emitLine(first.line, presentAt: nil, continuous: first.continuous, emit: emit)
                } else {
                    break
                }
            } else {
                held.removeFirst()
                emitLine(first.line, presentAt: nil, continuous: first.continuous, emit: emit)
            }
        }
    }

    private func emitLine(_ openLine: String, presentAt: RuneInstant?, continuous: Bool, emit: (String) -> Void) {
        var line = openLine
        if let at = presentAt {
            let ms = toolingR3(at.saturatingDurationSince(start) * 1000.0)
            line += ",\"present_ms\":\(ToolingJson.number(ms).serialized())"
            if continuous, let prev = lastPresentMs {
                let dtMs = toolingR3(ms - prev)
                line += ",\"present_dt_ms\":\(ToolingJson.number(dtMs).serialized())"
            }
            lastPresentMs = ms
        } else {
            lastPresentMs = nil
        }
        line.append("}")
        emit(line)
    }
}

// MARK: - Per-Runtime Trace Annotation State

private let runtimeTraceStateKey = "gpua.rune.tooling.traceState"

// PORT NOTE: Stored per `Runtime` in `RuntimeHostAttachment` so `Tx.traceEvent` / `Tx.traceChannel` and `Trace` work without touching `Sources/Rune/runtime.swift`.
final class RuntimeToolingTraceState: @unchecked Sendable {
    var enabled: Bool = false
    var events: [String] = []
    var channels: [String: (String, Float)] = [:]
    var settledThisFrame: Bool = false
    var keyWarnings: [String]? = nil

    init() {}
}

func toolingTraceState(for runtime: AnyObject) -> RuntimeToolingTraceState {
    let att = hostAttachment(for: runtime)
    if let existing = att.customData[runtimeTraceStateKey] as? RuntimeToolingTraceState {
        return existing
    }
    let created = RuntimeToolingTraceState()
    att.customData[runtimeTraceStateKey] = created
    return created
}

/// Motion-lint JSONL trace writer (`crates/rune/src/tooling/trace.rs`).
final class ToolingTrace {
    private var lines: [String] = []
    private var ids: [String: UInt32] = [:]
    private var described: [UInt32: (String, String, String)] = [:]
    private struct ElemTraceState: Equatable {
        var q: [Int64]
        var flags: UInt32
        var vis: [Int64]
    }
    private var states: [UInt32: ElemTraceState] = [:]
    private var scrolled: [UInt32: [Int64]] = [:]
    private var effects: [UInt32: [String]] = [:]
    private let channels = TraceChannels()
    let path: String
    var all: Bool = false
    private var presents: ToolingPresents? = nil
    private var closed: Bool = false

    private init(path: String, headerLine: String) {
        self.path = path
        self.lines.append(headerLine)
        flushToDisk()
    }

    static func open(_ path: String, _ size: (Float, Float), _ fps: Double, _ scale: Float) -> ToolingTrace {
        openClock(path, size, fps, scale, "virtual")
    }

    static func openClock(_ path: String, _ size: (Float, Float), _ fps: Double, _ scale: Float, _ clock: String) -> ToolingTrace {
        var entries: [(String, ToolingJson)] = [
            ("type", .string("header")),
            ("launch", .string("rune")),
            ("width", .number(Double(size.0))),
            ("height", .number(Double(size.1))),
            ("hz", .number(fps)),
            ("scale", .number(Double(scale))),
            ("platform", .string("rune")),
            ("units", .string("pt")),
            ("clock", .string(clock)),
        ]
        if clock == "wall" {
            entries.append(("timestamp", .string("cpu-submit")))
        }
        let header = ToolingJson.object(entries).serialized()
        return ToolingTrace(path: path, headerLine: header)
    }

    func recordPresents(_ source: any ToolingPresentSource, _ start: RuneInstant) {
        self.presents = ToolingPresents(source: source, start: start)
    }

    func settlePresents(_ wait: Double = 0.05) {
        guard let presents else { return }
        let deadline = RuneInstant.now().adding(wait)
        while presents.waiting && RuneInstant.now() < deadline {
            #if !os(WASI)
            Thread.sleep(forTimeInterval: 0.002)
            #else
            break
            #endif
        }
        presents.flush { [weak self] finishedLine in
            self?.lines.append(finishedLine)
        }
        flushToDisk()
    }

    private func id(for key: String) -> UInt32 {
        if let existing = ids[key] {
            return existing
        }
        let next = UInt32(ids.count + 1)
        ids[key] = next
        return next
    }

    func frame<S>(_ rt: Runtime<S>, _ tMs: Double, _ cpuMs: Double) {
        frameTimed(rt, tMs, cpuMs, ToolingFrameTiming())
    }

    func frameTimed<S>(_ rt: Runtime<S>, _ tMs: Double, _ cpuMs: Double, _ timing: ToolingFrameTiming) {
        let hs = windowHostState(for: rt)
        let ts = toolingTraceState(for: rt)
        let els = hs.lastElements.isEmpty ? rt.elements() : hs.lastElements
        let settled = ts.settledThisFrame
        ts.settledThisFrame = false

        var metas: [ToolingJson] = []
        var changed: [ToolingJson] = []
        var scrolledRows: [ToolingJson] = []
        var seen = Set<UInt32>()

        let traceAll = self.all
        func isTraced(_ e: ElementInfo) -> Bool {
            (traceAll || e.key != nil || e.traceName != nil) && !e.virtualExtent
        }

        for e in els where isTraced(e) {
            let eid = id(for: e.path)
            let nm = e.traceName ?? e.path
            let (cls, host) = e.traceNamespace ?? ("rune", "rune")
            seen.insert(eid)
            if described[eid]?.0 != nm || described[eid]?.1 != cls || described[eid]?.2 != host {
                described[eid] = (nm, cls, host)
                var metaEntries: [(String, ToolingJson)] = [
                    ("id", .int(Int64(eid))),
                    ("cls", .string(cls)),
                    ("nm", .string(nm)),
                    ("host", .string(host)),
                    ("role", .string(e.role)),
                ]
                if let pIdx = e.parent, pIdx < els.count, isTraced(els[pIdx]) {
                    metaEntries.append(("pv", .int(Int64(id(for: els[pIdx].path)))))
                }
                metas.append(.object(metaEntries))
            }

            let effNames = ["\(nm).scale", "\(nm).blur"]
            channels.sample(effNames[0], "position", e.scale)
            channels.owner(effNames[0], eid, "ratio")
            channels.sample(effNames[1], "position", e.blur)
            channels.owner(effNames[1], eid, "pt")
            if let old = effects[eid] {
                for name in old where !effNames.contains(name) {
                    channels.remove(name)
                }
            }
            effects[eid] = effNames

            let x = e.rect.count > 0 ? e.rect[0] : 0
            let y = e.rect.count > 1 ? e.rect[1] : 0
            let w = e.rect.count > 2 ? e.rect[2] : 0
            let h = e.rect.count > 3 ? e.rect[3] : 0
            let clipped = zip(e.rect, e.visible).contains { abs($0 - $1) > 0.5 }
            var intent = e.liveIntent
            if settled {
                intent |= Intent.position | Intent.size | Intent.transition | Intent.reveal
            }
            if rt.reducedMotion {
                intent |= Intent.position | Intent.size
            }
            if e.revealing {
                intent |= Intent.reveal
            }
            if e.inGrowingRow {
                intent |= Intent.size | Intent.reveal
            }
            let elemFlags: UInt32 =
                ((e.moving || e.inGrowingRow) ? flags.animated : 0)
                | (e.scrolling ? flags.scrolling : 0)
                | (clipped ? flags.clipped : 0)
                | (intent << 8)

            let q: [Int64] = [
                Int64((Double(x) * 100.0).rounded()),
                Int64((Double(y) * 100.0).rounded()),
                Int64((Double(w) * 100.0).rounded()),
                Int64((Double(h) * 100.0).rounded()),
                Int64((Double(e.opacity) * 1000.0).rounded()),
                Int64((Double(e.radius) * 100.0).rounded()),
            ]
            let sc: [Int64] = e.scrolled.map { Int64((Double($0) * 100.0).rounded()) }
            let prevSc = scrolled[eid] ?? [0, 0]
            if prevSc != sc {
                scrolledRows.append(.array([
                    .int(Int64(eid)),
                    .number(toolingR2(e.scrolled[0])),
                    .number(toolingR2(e.scrolled[1])),
                ]))
                if sc == [0, 0] {
                    scrolled.removeValue(forKey: eid)
                } else {
                    scrolled[eid] = sc
                }
            }

            let visQ = e.visible.map { Int64((Double($0) * 100.0).rounded()) }
            let st = ElemTraceState(q: q, flags: elemFlags, vis: visQ)
            if states[eid] != st {
                states[eid] = st
                var row: [ToolingJson] = [
                    .int(Int64(eid)),
                    .number(toolingR2(x)),
                    .number(toolingR2(y)),
                    .number(toolingR2(w)),
                    .number(toolingR2(h)),
                    .number((Double(e.opacity) * 1000.0).rounded() / 1000.0),
                    .number(toolingR2(e.radius)),
                    .int(Int64(elemFlags)),
                ]
                if clipped {
                    row.append(contentsOf: e.visible.map { .number(toolingR2($0)) })
                }
                changed.append(.array(row))
            }
        }

        let gone = states.keys.filter { !seen.contains($0) }.sorted()
        var cuts: [ToolingJson] = []
        for gid in gone {
            scrolled.removeValue(forKey: gid)
            if let names = effects.removeValue(forKey: gid) {
                for n in names { channels.remove(n) }
            }
            if let old = states.removeValue(forKey: gid), settled {
                cuts.append(.array([
                    .int(Int64(gid)),
                    .number(Double(old.q[0]) / 100.0),
                    .number(Double(old.q[1]) / 100.0),
                    .number(Double(old.q[2]) / 100.0),
                    .number(Double(old.q[3]) / 100.0),
                    .int(Int64(Intent.transition | Intent.opacity)),
                    .int(0),
                ]))
            }
        }

        let (edges, posErr) = rt.scene.samplingError()
        let retarget = rt.scene.storeMut().takeRetargetAudit()
        let animating = hs.lastStats.animating
        let animBits: UInt16 = animating ? hs.animSources : 0
        let animNamesTable = [
            "tracks", "growth", "scroll", "reveal", "loop",
            "scale-settle", "video", "text-flight", "live", "virtual-fill",
        ]
        var whyJson: [ToolingJson] = []
        for (i, nm) in animNamesTable.enumerated() where (animBits & (1 << i)) != 0 {
            whyJson.append(.string(nm))
        }
        var lineEntries: [(String, ToolingJson)] = [
            ("t", .number((tMs * 1000.0).rounded() / 1000.0)),
            ("n", .int(1)),
        ]
        if rt.hostPointerCaptured() {
            lineEntries.append(("k", .int(1)))
        }
        lineEntries.append((
            "quality",
            .object([
                ("cpu_ms", .number(cpuMs)),
                ("scene_edges", .int(Int64(edges))),
                ("position_error_px", .number(Double(posErr))),
                ("retarget_lanes", .int(Int64(retarget.lanes))),
                ("velocity_error_pt_s", .number(Double(retarget.maxVelocityError))),
                ("animating", .bool(animating)),
                ("why", .array(whyJson)),
            ])
        ))
        let touched = rt.hostTouchedTracks()
        if !touched.isEmpty {
            lineEntries.append((
                "tk",
                .array(touched.map { path, propName, active in
                    let who: ToolingJson = ids[path].map { .int(Int64($0)) } ?? .string(path)
                    return .array([who, .string(propName), .int(active ? 1 : 0)])
                })
            ))
        }
        let events = ts.events
        ts.events.removeAll()
        if !events.isEmpty {
            lineEntries.append(("ev", .array(events.map { .string($0) })))
        }
        if !metas.isEmpty {
            lineEntries.append(("m", .array(metas)))
        }
        if !changed.isEmpty {
            lineEntries.append(("e", .array(changed)))
        }
        if !gone.isEmpty {
            lineEntries.append(("g", .array(gone.map { .int(Int64($0)) })))
        }
        if !scrolledRows.isEmpty {
            lineEntries.append(("sc", .array(scrolledRows)))
        }
        if !cuts.isEmpty {
            lineEntries.append(("ai", .array(cuts)))
        }

        for (name, sample) in ts.channels {
            channels.sample(name, sample.0, sample.1)
        }
        ts.channels.removeAll()

        var openLine = ToolingJson.object(lineEntries).serialized()
        if openLine.hasSuffix("}") {
            openLine.removeLast()
        }
        channels.writeJson(&openLine)
        if let target = timing.targetMs {
            openLine += ",\"target_ms\":\(ToolingJson.number(target).serialized())"
        }

        if let presents {
            presents.push(line: openLine, drawable: timing.drawable, continuous: timing.continuous) { [weak self] finished in
                self?.lines.append(finished)
            }
            flushToDisk()
            return
        }
        openLine.append("}")
        lines.append(openLine)
        flushToDisk()
    }

    func close() {
        guard !closed else { return }
        closed = true
        if presents != nil {
            settlePresents()
            if let summary = ToolingPresentSummary.ofTrace(lines.joined(separator: "\n")) {
                toolingStderr("\(summary)\n")
            }
        } else {
            flushToDisk()
        }
    }

    private func flushToDisk() {
        #if !os(WASI)
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        if !dir.path.isEmpty {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let body = lines.joined(separator: "\n") + "\n"
        try? body.write(to: url, atomically: false, encoding: .utf8)
        #endif
    }

    deinit {
        close()
    }
}

// MARK: - Element Tree JSON (`tree_json`)

func toolingTreeJson<S>(_ rt: Runtime<S>, _ realT: Double) -> ToolingJson {
    let hs = windowHostState(for: rt)
    let ts = toolingTraceState(for: rt)
    let rawEls = hs.lastElements.isEmpty ? rt.elements() : hs.lastElements
    let els: [ToolingJson] = rawEls.map { e in
        var entries: [(String, ToolingJson)] = [
            ("path", .string(e.path)),
            ("role", .string(e.role)),
            ("rect", .array(e.rect.map { .number(toolingR2($0)) })),
            ("opacity", .number((Double(e.opacity) * 1000.0).rounded() / 1000.0)),
            ("scale", .number((Double(e.scale) * 10000.0).rounded() / 10000.0)),
            ("blur", .number(toolingR2(e.blur))),
            ("focusable", .bool(e.focusable)),
            ("focused", .bool(e.focused)),
            ("focusVisible", .bool(e.focusVisible)),
            ("inert", .bool(e.inert)),
            ("loopPhase", e.loopPhase.map { .number($0) } ?? .null),
            ("fill", .string(e.fill.hex())),
        ]
        if let k = e.key { entries.append(("key", .string(k))) }
        if let l = e.label { entries.append(("label", .string(l))) }
        if let t = e.text { entries.append(("text", .string(t))) }
        if let c = e.textColor { entries.append(("color", .string(c.hex()))) }
        if let h = e.help { entries.append(("help", .string(h))) }
        if let s = e.selected { entries.append(("selected", .string(s))) }
        if let lv = e.level { entries.append(("level", .int(Int64(lv)))) }
        if let ex = e.expanded { entries.append(("expanded", .bool(ex))) }
        if e.itemSelected { entries.append(("itemSelected", .bool(true))) }
        if zip(e.rect, e.target).contains(where: { abs($0 - $1) > 0.01 }) {
            entries.append(("target", .array(e.target.map { .number(toolingR2($0)) })))
        }
        if e.moving { entries.append(("moving", .bool(true))) }
        if e.exiting { entries.append(("exiting", .bool(true))) }
        if e.hover > 0.001 { entries.append(("hover", .number(toolingR2(e.hover)))) }
        if e.press > 0.001 { entries.append(("press", .number(toolingR2(e.press)))) }
        if e.dragOut { entries.append(("dragOut", .bool(true))) }
        return .object(entries)
    }

    var treeEntries: [(String, ToolingJson)] = [
        ("t", .number(realT)),
        ("anim_t", .number(rt.t)),
        ("viewport", .array([.number(Double(rt.viewport.0)), .number(Double(rt.viewport.1))])),
        ("scale", .number(Double(rt.env.scale))),
        ("dark_system", .bool(rt.env.systemDark)),
        ("reduced_motion", .bool(rt.reducedMotion)),
        ("time_scale", .number(Double(rt.timeScale))),
        ("animating", .bool(hs.lastStats.animating)),
        ("elements", .array(els)),
        ("warnings", .array((ts.keyWarnings ?? []).map { .string($0) })),
    ]
    let att = hostAttachment(for: rt)
    if let popup = rt.hostPopupJson() {
        treeEntries.append(("popupMenu", ToolingJson.fromAny(popup)))
    }
    if let dialog = rt.hostFileDialogJson() {
        treeEntries.append(("fileDialog", ToolingJson.fromAny(dialog)))
    }
    if let title = att.windowTitle {
        treeEntries.append(("title", .string(title)))
    }
    if let (tipText, tipRect) = rt.hostHelpTooltip() {
        treeEntries.append((
            "tooltip",
            .object([
                ("text", .string(tipText)),
                ("rect", .array(tipRect.map { .number(toolingR2($0)) })),
            ])
        ))
    }
    return .object(treeEntries)
}
