// Ported from: crates/rune-perf/src/incident.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Procwatch

/// Warning-only detection rules. Growth is a suspect leak, never proof of ownership or causation.
public enum Rule: String, Codable, Equatable, Hashable, Sendable {
    case longFrames = "long-frames"
    case stall = "frame-stall"
    case memoryGrowth = "memory-growth"
    case fdGrowth = "fd-growth"

    public func id() -> String {
        rawValue
    }
}

/// Candidate performance finding before rate-limit admission.
public struct Finding: Equatable, Sendable {
    public var rule: Rule
    public var window: UInt64
    public var source: UInt64?
    public var severity: Double
    public var evidence: JsonValue

    public init(rule: Rule, window: UInt64, source: UInt64?, severity: Double, evidence: JsonValue) {
        self.rule = rule
        self.window = window
        self.source = source
        self.severity = severity
        self.evidence = evidence
    }
}

/// Schema-1 serialized incident record written to `perf-incident-NN.json`.
public struct Incident: Codable, Equatable, Sendable {
    public var schema: Int
    public var app: String
    public var build: String
    public var launch: String
    public var pid: Int32
    public var createdAtMs: UInt64
    public var rule: String
    public var window: UInt64
    public var source: UInt64?
    public var evidence: JsonValue
    public var history: [JsonValue]
    public var droppedSamples: UInt64

    enum CodingKeys: String, CodingKey {
        case schema
        case app
        case build
        case launch
        case pid
        case createdAtMs = "created_at_ms"
        case rule
        case window
        case source
        case evidence
        case history
        case droppedSamples = "dropped_samples"
    }

    public init(
        schema: Int = 1,
        app: String,
        build: String,
        launch: String,
        pid: Int32,
        createdAtMs: UInt64,
        rule: String,
        window: UInt64,
        source: UInt64?,
        evidence: JsonValue,
        history: [JsonValue],
        droppedSamples: UInt64
    ) {
        self.schema = schema
        self.app = app
        self.build = build
        self.launch = launch
        self.pid = pid
        self.createdAtMs = createdAtMs
        self.rule = rule
        self.window = window
        self.source = source
        self.evidence = evidence
        self.history = history
        self.droppedSamples = droppedSamples
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schema, forKey: .schema)
        try container.encode(app, forKey: .app)
        try container.encode(build, forKey: .build)
        try container.encode(launch, forKey: .launch)
        try container.encode(pid, forKey: .pid)
        try container.encode(createdAtMs, forKey: .createdAtMs)
        try container.encode(rule, forKey: .rule)
        try container.encode(window, forKey: .window)
        if let source {
            try container.encode(source, forKey: .source)
        } else {
            try container.encodeNil(forKey: .source)
        }
        try container.encode(evidence, forKey: .evidence)
        try container.encode(history, forKey: .history)
        try container.encode(droppedSamples, forKey: .droppedSamples)
    }
}

private struct Sent: Sendable {
    var rule: Rule
    var window: UInt64
    var source: UInt64?
    var at: UInt64
    var severity: Double
}

private struct Floor: Sendable {
    var minute: UInt64
    var memory: UInt64?
    var fds: UInt64?
}

@inline(__always)
private func saturatingSub(_ a: UInt64, _ b: UInt64) -> UInt64 {
    a >= b ? (a - b) : 0
}

/// Bounded frame and process incident detector with per-key worsening cooldown.
public struct Detector: Sendable {
    private var sent: [Sent] = []
    private var floors: [Floor] = []
    public var suppressed: UInt64 = 0
    private var lastSent: UInt64?

    public init() {}

    public func frame(_ s: Sample, _ stats: Stats) -> Finding? {
        guard let work = s.frame.workMs() else {
            return nil
        }
        let rule: Rule
        if work >= 250.0 {
            rule = .stall
        } else if work >= SLOW_MS {
            var count = 0
            for p in stats.recent.reversed() {
                if saturatingSub(s.atMs, p.atMs) > 1000 {
                    break
                }
                if p.frame.windowId == s.frame.windowId,
                   p.frame.sourceVal == s.frame.sourceVal,
                   let t = p.frame.workMs(),
                   t >= SLOW_MS
                {
                    count += 1
                    if count >= 3 {
                        break
                    }
                }
            }
            if count < 3 {
                return nil
            }
            rule = .longFrames
        } else {
            return nil
        }

        return Finding(
            rule: rule,
            window: s.frame.windowId,
            source: s.frame.sourceVal,
            severity: work,
            evidence: .object([
                "frame": s.json(),
                "confidence": .string("measured work; cause unknown"),
                "next_measurement": .string("capture update/compositor phases for this window and source"),
            ])
        )
    }

    public mutating func process(_ now: UInt64, _ p: Usage) -> [Finding] {
        let minute = now / 60_000
        let fds = p.fds.map { UInt64($0) }
        if let back = floors.last, minute > back.minute + 1 {
            floors.removeAll(keepingCapacity: true)
        }
        if let lastIdx = floors.indices.last, floors[lastIdx].minute == minute {
            // A missing read invalidates this minute, rather than bridging an evidence gap.
            if let a = floors[lastIdx].memory, let b = p.footprint {
                floors[lastIdx].memory = min(a, b)
            } else {
                floors[lastIdx].memory = nil
            }
            if let a = floors[lastIdx].fds, let b = fds {
                floors[lastIdx].fds = min(a, b)
            } else {
                floors[lastIdx].fds = nil
            }
        } else {
            if floors.count == 6 {
                floors.removeFirst()
            }
            floors.append(Floor(minute: minute, memory: p.footprint, fds: fds))
        }

        // Five completed minute floors, excluding the in-progress minute.
        guard floors.count >= 6 else {
            return []
        }

        var out: [Finding] = []
        let checks: [(Rule, UInt64)] = [(.memoryGrowth, UInt64(64) << 20), (.fdGrowth, 32)]
        for (rule, minimum) in checks {
            var values: [UInt64] = []
            values.reserveCapacity(5)
            var complete = true
            for i in 0..<5 {
                let v = (rule == .memoryGrowth) ? floors[i].memory : floors[i].fds
                guard let unwrapped = v else {
                    complete = false
                    break
                }
                values.append(unwrapped)
            }
            guard complete else { continue }

            let delta = saturatingSub(values[4], values[0])
            let strictlyRising = (0..<4).allSatisfy { values[$0 + 1] > values[$0] }
            if strictlyRising && delta >= minimum && Double(delta) >= Double(values[0]) * 0.2 {
                out.append(
                    Finding(
                        rule: rule,
                        window: 0,
                        source: nil,
                        severity: Double(values[4]),
                        evidence: .object([
                            "minute_floors": .array(values.map { .uint($0) }),
                            "growth": .uint(delta),
                            "confidence": .string("suspected growth, not a proven leak"),
                            "next_measurement": .string("repeat view open/close cycles; check whether footprint and descriptors plateau"),
                        ])
                    )
                )
            }
        }
        return out
    }

    public mutating func admit(_ now: UInt64, _ f: Finding) -> Bool {
        let old = sent.first { $0.rule == f.rule && $0.window == f.window && $0.source == f.source }
        if let last = lastSent, saturatingSub(now, last) < 2000 {
            suppressed += 1
            return false
        }
        if let old, saturatingSub(now, old.at) < 60_000 || f.severity < old.severity * 1.25 {
            suppressed += 1
            return false
        }
        sent.removeAll { $0.rule == f.rule && $0.window == f.window && $0.source == f.source }
        if sent.count == 64 {
            sent.removeFirst()
        }
        sent.append(Sent(rule: f.rule, window: f.window, source: f.source, at: now, severity: f.severity))
        lastSent = now
        return true
    }
}
