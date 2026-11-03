// Ported from: crates/rune/src/tooling/interaction/cause.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Whose time a slow frame took (`cpu`, `blocked`, `scheduler_wait`, `queued`).

enum InteractionCause: Sendable, Equatable {
    case cpu
    case blocked
    case schedulerWait
    case queued

    var name: String {
        switch self {
        case .cpu: return "cpu"
        case .blocked: return "blocked"
        case .schedulerWait: return "scheduler_wait"
        case .queued: return "queued"
        }
    }
}

/// Classifies a slow frame that worked `workMs`, using `cpuMs` of thread CPU when measured,
/// watchdog stack samples, and whether the machine is `overloaded`.
func interactionCause(
    workMs: Double,
    slowMs: Double,
    cpuMs: Double?,
    stacks: InteractionStacks?,
    overloaded: Bool
) -> InteractionCause {
    if workMs <= slowMs {
        return .queued
    }
    let sampled = stacks.flatMap { $0.taken > 0 ? $0 : nil }
    if let s = sampled, 2 * s.waiting > s.taken {
        return .blocked
    }
    let share: Double? = cpuMs.map { $0 / workMs } ?? sampled?.cpuShare
    if let share, share >= 0.5 {
        return .cpu
    }
    if share == nil && !overloaded {
        return .cpu
    }
    if overloaded || (sampled?.taken ?? 0) >= 2 {
        return .schedulerWait
    }
    return .blocked
}
