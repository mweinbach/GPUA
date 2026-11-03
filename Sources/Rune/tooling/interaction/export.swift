// Ported from: crates/rune/src/tooling/interaction/export.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! OTLP/HTTP JSON trace serialization and background loopback exporter (`ui.interaction`, `ui.frame`, `ui.rollup`).

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

enum InteractionExportMessage: Sendable {
    case slow(InteractionSlow)
    case frame(InteractionSlowFrame)
    case rollup(rolls: [InteractionRoll], from: RuneInstant, to: RuneInstant)
    case flush(InteractionFlushWaiter)
}

// PORT NOTE: Synchronized via `LiveLock` to signal completion of `interactionFlush`.
final class InteractionFlushWaiter: @unchecked Sendable {
    private let lock = LiveLock()
    private var done = false

    func markDone() {
        lock.withLock { done = true }
    }

    func wait(timeoutSeconds: Double) {
        #if !os(WASI)
        let deadline = RuneInstant.now().adding(timeoutSeconds)
        while RuneInstant.now() < deadline {
            if lock.withLock({ done }) { return }
            Thread.sleep(forTimeInterval: 0.002)
        }
        #else
        _ = timeoutSeconds
        #endif
    }
}

private let exportIdLock = LiveLock()
// PORT NOTE: Guarded by `exportIdLock` for monotonic span/trace ID generation.
nonisolated(unsafe) private var nextExportCounter: UInt64 = 1

private func nextSpanId() -> UInt64 {
    exportIdLock.withLock {
        let c = nextExportCounter
        nextExportCounter &+= 1
        var h = c &* 0x9e37_79b9_7f4a_7c15
        h = (h ^ (h >> 30)) &* 0xbf58_476d_1ce4_e5b9
        h = (h ^ (h >> 27)) &* 0x94d0_49bb_1331_11eb
        h = h ^ (h >> 31)
        return max(h, 1)
    }
}

private func hexPad(_ v: UInt64, width: Int) -> String {
    let s = String(v, radix: 16, uppercase: false)
    if s.count >= width { return s }
    return String(repeating: "0", count: width - s.count) + s
}

private let anchorInstant = RuneInstant.now()
private let anchorUnixNs: UInt64 = {
    #if !os(WASI)
    return UInt64(max(0.0, Date().timeIntervalSince1970 * 1_000_000_000.0))
    #else
    return 0
    #endif
}()

private func unixNanos(_ t: RuneInstant) -> UInt64 {
    let deltaSecs = t.saturatingDurationSince(anchorInstant)
    if deltaSecs > 0 {
        return anchorUnixNs &+ UInt64(deltaSecs * 1_000_000_000.0)
    }
    let earlierSecs = anchorInstant.saturatingDurationSince(t)
    let sub = UInt64(earlierSecs * 1_000_000_000.0)
    return anchorUnixNs > sub ? (anchorUnixNs - sub) : 0
}

private func exportRound(_ ms: Double) -> Double {
    (ms * 1000.0).rounded() / 1000.0
}

private func exportMs(_ from: RuneInstant, _ to: RuneInstant) -> Double {
    exportRound(to.saturatingDurationSince(from) * 1000.0)
}

private func kvString(_ key: String, _ value: String) -> ToolingJson {
    .object([
        ("key", .string(key)),
        ("value", .object([("stringValue", .string(value))])),
    ])
}

private func kvInt(_ key: String, _ value: UInt64) -> ToolingJson {
    .object([
        ("key", .string(key)),
        ("value", .object([("intValue", .string("\(value)"))])),
    ])
}

private func kvDouble(_ key: String, _ value: Double) -> ToolingJson {
    .object([
        ("key", .string(key)),
        ("value", .object([("doubleValue", .number(value))])),
    ])
}

private func makeSpan(
    traceHi: UInt64,
    traceLo: UInt64,
    id: UInt64,
    parent: UInt64?,
    name: String,
    start: RuneInstant,
    end: RuneInstant,
    attrs: [ToolingJson]
) -> ToolingJson {
    let endClamped = end >= start ? end : start
    var entries: [(String, ToolingJson)] = [
        ("traceId", .string(hexPad(traceHi, width: 16) + hexPad(traceLo, width: 16))),
        ("spanId", .string(hexPad(id, width: 16))),
        ("name", .string(name)),
        ("kind", .int(1)),
        ("startTimeUnixNano", .string("\(unixNanos(start))")),
        ("endTimeUnixNano", .string("\(unixNanos(endClamped))")),
        ("attributes", .array(attrs)),
    ]
    if let p = parent {
        entries.append(("parentSpanId", .string(hexPad(p, width: 16))))
    }
    return .object(entries)
}

private func appendStackAttrs(_ s: InteractionStacks, into attrs: inout [ToolingJson]) {
    attrs.append(kvInt("rune.samples", UInt64(s.taken)))
    attrs.append(kvInt("rune.samples_waiting", UInt64(s.waiting)))
    let hotKeys = ["rune.hot.0", "rune.hot.1", "rune.hot.2"]
    for (i, (name, n)) in s.hot.prefix(3).enumerated() {
        attrs.append(kvString(hotKeys[i], "\(name) (\(n)/\(s.taken))"))
    }
    if !s.stack.isEmpty {
        attrs.append(kvString("rune.stack", s.stack.joined(separator: "\n")))
    }
}

func interactionSlowSpans(_ s: InteractionSlow) -> [ToolingJson] {
    let traceHi = nextSpanId()
    let traceLo = nextSpanId()
    let root = nextSpanId()
    var attrs: [ToolingJson] = [
        kvString("rune.route", s.route),
        kvString("rune.control", s.control),
        kvString("rune.action", s.action),
        kvString("rune.signature", "\(s.route) \(s.control) \(s.action)"),
        kvDouble("rune.input_to_present_ms", exportMs(s.arrived, s.present)),
        kvDouble("rune.work_ms", exportMs(s.frameStart, s.submitted)),
        kvInt("rune.nodes", UInt64(s.nodes)),
        kvInt("rune.reused_nodes", UInt64(s.reused)),
        kvInt("rune.commits", UInt64(s.commits)),
        kvInt("rune.shaped", UInt64(s.shaped)),
    ]
    let why = ToolingCommitWhy.names(s.why)
    if !why.isEmpty {
        attrs.append(kvString("rune.commit_why", why.joined(separator: ",")))
    }
    let rebKeys = ["rune.rebuilt.0", "rune.rebuilt.1", "rune.rebuilt.2"]
    for (i, (key, n)) in s.rebuilt.prefix(3).enumerated() {
        attrs.append(kvString(rebKeys[i], "\(key) (\(n))"))
    }
    attrs.append(kvString("rune.cause", s.cause.name))
    if let cpu = s.cpuMs {
        attrs.append(kvDouble("rune.cpu_ms", exportRound(cpu)))
    }
    if let stacks = s.stacks {
        appendStackAttrs(stacks, into: &attrs)
    }

    var out: [ToolingJson] = [
        makeSpan(traceHi: traceHi, traceLo: traceLo, id: root, parent: nil, name: "ui.interaction", start: s.arrived, end: s.present, attrs: attrs)
    ]

    var updateAttrs: [ToolingJson] = [kvDouble("rune.handler_ms", exportRound(s.handlerMs))]
    for (name, ms) in zip(INTERACTION_PHASE_NAMES, s.phases) where ms > 0.0 {
        updateAttrs.append(kvDouble(name, exportRound(ms)))
    }
    let stretches: [(String, RuneInstant, RuneInstant, [ToolingJson])] = [
        ("queue_wait", s.arrived, s.frameStart, []),
        ("update", s.frameStart, s.built, updateAttrs),
        ("encode", s.built, s.submitted, []),
        ("present_wait", s.submitted, s.present, []),
    ]
    for (name, from, to, sAttrs) in stretches where to > from {
        out.append(
            makeSpan(traceHi: traceHi, traceLo: traceLo, id: nextSpanId(), parent: root, name: name, start: from, end: to, attrs: sAttrs)
        )
    }
    return out
}

func interactionFrameSpan(_ f: InteractionSlowFrame) -> ToolingJson {
    let traceHi = nextSpanId()
    let traceLo = nextSpanId()
    var attrs: [ToolingJson] = [
        kvDouble("rune.work_ms", exportMs(f.start, f.built)),
        kvInt("rune.nodes", UInt64(f.nodes)),
        kvString("rune.cause", f.cause.name),
    ]
    let why = ToolingCommitWhy.names(f.why)
    if !why.isEmpty {
        attrs.append(kvString("rune.commit_why", why.joined(separator: ",")))
    }
    appendStackAttrs(f.stacks, into: &attrs)
    return makeSpan(traceHi: traceHi, traceLo: traceLo, id: nextSpanId(), parent: nil, name: "ui.frame", start: f.start, end: f.built, attrs: attrs)
}

func interactionRollSpan(_ r: InteractionRoll, from: RuneInstant, to: RuneInstant) -> ToolingJson {
    let traceHi = nextSpanId()
    let traceLo = nextSpanId()
    return makeSpan(
        traceHi: traceHi,
        traceLo: traceLo,
        id: nextSpanId(),
        parent: nil,
        name: "ui.rollup",
        start: from,
        end: to,
        attrs: [
            kvString("rune.route", r.route.text),
            kvString("rune.control", r.control.text),
            kvString("rune.action", r.action),
            kvInt("rune.count", UInt64(r.count)),
            kvInt("rune.slow", UInt64(r.slow)),
            kvInt("rune.scheduler_wait", UInt64(r.contended)),
            kvDouble("rune.p50_ms", exportRound(r.quantile(0.5))),
            kvDouble("rune.p98_ms", exportRound(r.quantile(0.98))),
            kvDouble("rune.max_ms", exportRound(r.maxMs)),
        ]
    )
}

func interactionExportResource() -> ToolingJson {
    #if !os(WASI)
    let env = ProcessInfo.processInfo.environment
    let service: String
    if let s = env["OTEL_SERVICE_NAME"], !trimAsciiWhitespace(s).isEmpty {
        service = s
    } else {
        service = ProcessInfo.processInfo.processName.isEmpty ? "rune-app" : ProcessInfo.processInfo.processName
    }
    let pid = UInt64(max(0, ProcessInfo.processInfo.processIdentifier))
    #else
    let service = "rune-app"
    let pid: UInt64 = 0
    #endif
    return .object([
        ("attributes", .array([
            kvString("service.name", service),
            kvInt("process.pid", pid),
            kvString("rune.version", "0.0.1"),
        ]))
    ])
}

func interactionExportBody(resource: ToolingJson, spans: [ToolingJson]) -> String {
    ToolingJson.object([
        ("resourceSpans", .array([
            .object([
                ("resource", resource),
                ("scopeSpans", .array([
                    .object([
                        ("scope", .object([("name", .string("rune.interaction"))])),
                        ("spans", .array(spans)),
                    ])
                ])),
            ])
        ]))
    ]).serialized()
}

private let exportQueueLock = LiveLock()
// PORT NOTE: Synchronized via `exportQueueLock` for background OTLP batch sender.
nonisolated(unsafe) private var exportStarted = false
// PORT NOTE: Synchronized via `exportQueueLock` for background OTLP batch sender.
nonisolated(unsafe) private var exportMessages: [InteractionExportMessage] = []

@discardableResult
func interactionExportSend(_ message: InteractionExportMessage) -> Bool {
    #if os(WASI) || os(Android)
    _ = message
    return false
    #else
    guard let endpoint = interactionGateCollector() else { return false }
    exportQueueLock.withLock {
        exportMessages.append(message)
        if !exportStarted {
            exportStarted = true
            startExportWorker(endpoint: endpoint)
        }
    }
    return true
    #endif
}

func interactionExportFlush(_ timeoutSeconds: Double) {
    #if !os(WASI) && !os(Android)
    let isRunning = exportQueueLock.withLock { exportStarted }
    guard isRunning else { return }
    let waiter = InteractionFlushWaiter()
    if interactionExportSend(.flush(waiter)) {
        waiter.wait(timeoutSeconds: timeoutSeconds)
    }
    #else
    _ = timeoutSeconds
    #endif
}

#if !os(WASI) && !os(Android)
private func startExportWorker(endpoint: InteractionEndpoint) {
    let resource = interactionExportResource()
    let t = Thread {
        while true {
            let firstOpt: InteractionExportMessage? = exportQueueLock.withLock {
                exportMessages.isEmpty ? nil : exportMessages.removeFirst()
            }
            guard let first = firstOpt else {
                Thread.sleep(forTimeInterval: 0.01)
                continue
            }
            if case .flush = first {
                // Drain immediately
            } else {
                Thread.sleep(forTimeInterval: 0.1)
            }
            let rest: [InteractionExportMessage] = exportQueueLock.withLock {
                let r = exportMessages
                exportMessages.removeAll()
                return r
            }
            var spans: [ToolingJson] = []
            var waiters: [InteractionFlushWaiter] = []
            for m in [first] + rest {
                switch m {
                case .slow(let s): spans.append(contentsOf: interactionSlowSpans(s))
                case .frame(let f): spans.append(interactionFrameSpan(f))
                case .rollup(let rolls, let from, let to):
                    spans.append(contentsOf: rolls.map { interactionRollSpan($0, from: from, to: to) })
                case .flush(let w):
                    waiters.append(w)
                }
            }
            if !spans.isEmpty {
                postLoopbackHttp(to: endpoint, body: interactionExportBody(resource: resource, spans: spans))
            }
            for w in waiters {
                w.markDone()
            }
        }
    }
    t.name = "rune-interactions"
    t.start()
}

private func postLoopbackHttp(to endpoint: InteractionEndpoint, body: String) {
    guard let url = URL(string: "http://\(endpoint)/v1/traces") else { return }
    var req = URLRequest(url: url, timeoutInterval: 0.5)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = Data(body.utf8)
    let waiter = InteractionFlushWaiter()
    let task = URLSession.shared.dataTask(with: req) { _, _, _ in
        waiter.markDone()
    }
    task.resume()
    waiter.wait(timeoutSeconds: 0.5)
}
#endif
