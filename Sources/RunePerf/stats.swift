// Ported from: crates/rune-perf/src/stats.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation

/// Rolling 60-second / 600-sample frame statistics and anomaly log rate-limiter.
public struct Stats: Sendable {
    public internal(set) var recent: [Sample] = []
    private var total: UInt64 = 0
    private var anomalies: UInt64 = 0
    private var suppressed: UInt64 = 0
    private var maxWork: Double?
    private var maxBytes: UInt64?
    private var logSecond: UInt64 = 0
    private var logged: UInt32 = 0

    public init() {}

    @discardableResult
    public mutating func accept(_ s: Sample) -> Bool {
        total += 1
        if let v = s.frame.workMs() {
            maxWork = maxWork.map { max($0, v) } ?? v
        }
        if let v = s.frame.allocatedBytesVal {
            maxBytes = maxBytes.map { max($0, v) } ?? v
        }
        if recent.count == RECENT {
            recent.removeFirst()
        }
        recent.append(s)
        prune(s.atMs)
        guard s.anomaly() else {
            return false
        }
        anomalies += 1
        let sec = s.atMs / 1000
        if logSecond != sec {
            logSecond = sec
            logged = 0
        }
        if logged == 10 {
            suppressed += 1
            return false
        }
        logged += 1
        return true
    }

    public mutating func prune(_ now: UInt64) {
        var dropCount = 0
        for s in recent {
            let age = now >= s.atMs ? (now - s.atMs) : 0
            if age > WINDOW_MS {
                dropCount += 1
            } else {
                break
            }
        }
        if dropCount > 0 {
            recent.removeFirst(dropCount)
        }
    }

    public func json() -> JsonValue {
        func metric(_ extract: (Sample) -> Double?) -> JsonValue {
            percentiles(recent.compactMap(extract))
        }

        let timedCount = recent.filter { $0.frame.workMs() != nil }.count
        let recentAnomalies = recent
            .reversed()
            .filter { $0.anomaly() }
            .prefix(20)
            .map { $0.json() }

        return .object([
            "total": .uint(total),
            "anomalies": .uint(anomalies),
            "log_suppressed": .uint(suppressed),
            "lifetime_max_work_ms": maxWork.map { .double($0) } ?? .null,
            "lifetime_max_ui_allocated_bytes": maxBytes.map { .uint($0) } ?? .null,
            "recent_count": .int(Int64(recent.count)),
            "timed_count": .int(Int64(timedCount)),
            "window_ms": .uint(WINDOW_MS),
            "capacity": .int(Int64(RECENT)),
            "work_ms": metric { $0.frame.workMs() },
            "ui_allocated_bytes": metric { $0.frame.allocatedBytesVal.map { Double($0) } },
            "input_to_frame_ms": metric { $0.frame.inputToFrameMsVal },
            "gpu_ms": metric { $0.frame.gpuMsVal },
            "latest": recent.last?.json() ?? .null,
            "recent_anomalies": .array(recentAnomalies),
        ])
    }
}

/// Nearest-rank p50 / p95 / max summary matching upstream `rune_perf::stats::percentiles`.
public func percentiles(_ values: [Double]) -> JsonValue {
    guard !values.isEmpty else {
        return .null
    }
    var sorted = values
    sorted.sort { a, b in
        if a.isNaN && b.isNaN { return false }
        if a.isNaN { return false }
        if b.isNaN { return true }
        return a < b
    }
    func rank(_ q: Double) -> Double {
        let ceilIndex = Int((Double(sorted.count) * q).rounded(.up))
        let idx = max(0, min(sorted.count - 1, ceilIndex - 1))
        return sorted[idx]
    }
    return .object([
        "p50": .double(rank(0.5)),
        "p95": .double(rank(0.95)),
        "max": sorted.last.map { .double($0) } ?? .null,
        "count": .int(Int64(sorted.count)),
    ])
}
