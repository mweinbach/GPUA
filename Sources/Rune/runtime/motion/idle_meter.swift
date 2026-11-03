// Ported from: crates/rune/src/runtime/motion/idle_meter.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Tracks consecutive idle vs awake frames so shells and tests know when the runtime can sleep.

struct IdleMeter: Sendable {
    var awakeFrames: UInt64 = 0
    var idleFrames: UInt64 = 0
    var consecutiveIdle: UInt32 = 0

    mutating func record(animating: Bool) {
        if animating {
            awakeFrames &+= 1
            consecutiveIdle = 0
        } else {
            idleFrames &+= 1
            consecutiveIdle &+= 1
        }
    }

    var canSleep: Bool {
        consecutiveIdle >= 2
    }
}

extension Runtime {
    public func isIdle() -> Bool {
        !animating && !dirty && !hasPendingLiveWake()
    }
}
