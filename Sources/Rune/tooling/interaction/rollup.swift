// Ported from: crates/rune/src/tooling/interaction/rollup.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Per-signature exponential latency histogram (`0.1 ms`..`~750 ms` at `15%` resolution).

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(Musl)
import Musl
#elseif os(Windows)
import ucrt
#elseif os(WASI)
import WASILibc
#endif

private let interactionBuckets = 64
private let interactionFirstMs = 0.1
private let interactionStep = 1.15

struct InteractionRoll: Sendable {
    var route: InteractionName
    var control: InteractionName
    var action: String
    var count: UInt32
    var slow: UInt32
    var contended: UInt32
    var maxMs: Double
    var buckets: [UInt32]

    init(route: InteractionName, control: InteractionName, action: String) {
        self.route = route
        self.control = control
        self.action = action
        self.count = 0
        self.slow = 0
        self.contended = 0
        self.maxMs = 0.0
        self.buckets = [UInt32](repeating: 0, count: interactionBuckets)
    }

    func quantile(_ q: Double) -> Double {
        let rawRank = UInt32(max(1.0, ceil(q * Double(count))))
        let rank = min(max(rawRank, 1), max(count, 1))
        var seen: UInt32 = 0
        for (i, n) in buckets.enumerated() {
            seen += n
            if seen >= rank {
                return min(interactionBucketUpper(i), maxMs)
            }
        }
        return maxMs
    }
}

private func interactionBucket(_ ms: Double) -> Int {
    if ms <= interactionFirstMs { return 0 }
    let raw = ceil(log(ms / interactionFirstMs) / log(interactionStep))
    return Int(min(max(raw, 0.0), Double(interactionBuckets - 1)))
}

private func interactionBucketUpper(_ i: Int) -> Double {
    interactionFirstMs * pow(interactionStep, Double(i))
}

@inline(__always)
private func rotateLeft64(_ x: UInt64, _ shift: UInt64) -> UInt64 {
    let s = shift & 63
    return s == 0 ? x : ((x << s) | (x >> (64 - s)))
}

func interactionSignature(_ route: InteractionName, _ control: InteractionName, _ action: String) -> UInt64 {
    route.hash ^ rotateLeft64(control.hash, 21) ^ rotateLeft64(interactionFxHash(action), 42)
}

struct InteractionRollup {
    private var rolls: [UInt64: InteractionRoll] = [:]

    init() {}

    mutating func add(
        route: InteractionName,
        control: InteractionName,
        action: String,
        ms: Double,
        slow: Bool,
        contended: Bool
    ) {
        let sig = interactionSignature(route, control, action)
        var roll = rolls[sig] ?? InteractionRoll(route: route, control: control, action: action)
        roll.count += 1
        if slow { roll.slow += 1 }
        if contended { roll.contended += 1 }
        roll.maxMs = max(roll.maxMs, ms)
        roll.buckets[interactionBucket(ms)] += 1
        rolls[sig] = roll
    }

    var isEmpty: Bool {
        rolls.isEmpty
    }

    mutating func take() -> [InteractionRoll] {
        let out = Array(rolls.values)
        rolls.removeAll()
        return out
    }
}
