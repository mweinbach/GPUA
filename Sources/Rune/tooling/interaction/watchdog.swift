// Ported from: crates/rune/src/tooling/interaction/watchdog.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Watchdog sampler summaries (`Stacks`, `Sampled`) and frame arm/hurry/disarm hooks.

let INTERACTION_AFTER_MS: UInt32 = 12
let INTERACTION_HURRY_MS: UInt32 = 4

struct InteractionStacks: Sendable, Equatable {
    var taken: UInt32
    var waiting: UInt32
    var cpuShare: Double?
    var hot: [(String, UInt32)]
    var stack: [String]

    static func == (lhs: InteractionStacks, rhs: InteractionStacks) -> Bool {
        guard lhs.taken == rhs.taken,
              lhs.waiting == rhs.waiting,
              lhs.cpuShare == rhs.cpuShare,
              lhs.stack == rhs.stack,
              lhs.hot.count == rhs.hot.count
        else { return false }
        for i in lhs.hot.indices {
            if lhs.hot[i].0 != rhs.hot[i].0 || lhs.hot[i].1 != rhs.hot[i].1 { return false }
        }
        return true
    }

    static func of(_ samples: [InteractionSampled]) -> InteractionStacks? {
        guard let first = samples.first, let last = samples.last else { return nil }
        func spot(_ s: InteractionSampled) -> String? {
            (s.frames.first(where: \.app) ?? s.frames.first)?.name
        }
        var hot: [(String, UInt32)] = []
        for s in samples {
            guard let name = spot(s) else { continue }
            if let idx = hot.firstIndex(where: { $0.0 == name }) {
                hot[idx].1 += 1
            } else {
                hot.append((name, 1))
            }
        }
        hot.sort { $0.1 > $1.1 }
        let top = hot.first?.0
        let stack: [String]
        if let top, let matched = samples.first(where: { spot($0) == top }) {
            stack = Array(matched.frames.prefix(16).map(\.name))
        } else {
            stack = []
        }
        if hot.count > 3 {
            hot.removeSubrange(3...)
        }
        let wallUs = last.atNs > first.atNs ? (last.atNs - first.atNs) / 1000 : 0
        let cpuShare: Double?
        if samples.count >= 2 && wallUs > 0 {
            let cpuDelta = last.cpuUs > first.cpuUs ? (last.cpuUs - first.cpuUs) : 0
            cpuShare = Double(cpuDelta) / Double(wallUs)
        } else {
            cpuShare = nil
        }
        return InteractionStacks(
            taken: UInt32(samples.count),
            waiting: UInt32(samples.filter(\.waiting).count),
            cpuShare: cpuShare,
            hot: hot,
            stack: stack
        )
    }
}

struct InteractionSampled: Sendable {
    var frames: [InteractionStackFrame]
    var waiting: Bool
    var cpuUs: UInt64
    var atNs: UInt64
}

func interactionWatchdogArm() {}
func interactionWatchdogHurry() {}
func interactionWatchdogDisarm() -> InteractionStacks? { nil }
