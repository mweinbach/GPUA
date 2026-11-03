// Ported from: crates/rune/src/frame.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Frame cadence, presentation timing, background present worker, phase profiling, and surface stats.

enum frame {
    enum clock {
        static let RESUME_STEP = Rune.RESUME_STEP
        static let MAX_GAP = Rune.MAX_GAP
        typealias Step = FrameStep
        typealias FrameClock = Rune.FrameClock

        static func split(_ gap: Double, _ running: Bool) -> FrameStep {
            frameSplit(gap, running)
        }

        @discardableResult
        static func advanceBy<S>(_ rt: Runtime<S>, _ gap: Double, running: Bool = false) -> Bool {
            frameAdvanceBy(rt, gap, running: running)
        }
    }

    enum encoded {
        typealias OnFrameEncoded = Rune.OnFrameEncoded
        typealias OnFrameDrawn<S> = Rune.OnFrameDrawn<S>
        typealias FrameEncoded = Rune.FrameEncoded
        typealias FrameOutcome = Rune.FrameOutcome
        typealias FrameReports<S> = Rune.FrameReports<S>
    }

    enum present_time {
        typealias Presented = PresentTimeEntry
        typealias Source = PresentTimeSource
        typealias Presents = Rune.Presents
        typealias Spread = PresentSpread
        typealias Summary = PresentSummary

        static let BUNCHED_MS = PRESENT_BUNCHED_MS
        static let SETTLE = PRESENT_SETTLE

        static func msSince(_ start: RuneInstant, _ at: RuneInstant) -> Double {
            presentMsSince(start, at)
        }

        #if os(macOS)
        typealias metal = presentMetal
        #endif
    }

    #if !os(WASI)
    enum present_worker {
        typealias PresentWorker = Rune.PresentWorker
    }
    #endif

    enum profile {
        typealias Phase = FramePhase
        typealias Scope = FrameProfileScope
        typealias Row = FrameProfileRow
        typealias Log = FrameProfileLog

        static let PHASES = Rune.PHASES

        static func cpuMs() -> Double? {
            frameCpuMs()
        }

        static func take() -> [Double] {
            takeFramePhases()
        }
    }

    enum surface_stats {
        typealias Missed = SurfaceMissed
        typealias SurfaceCounts = Rune.SurfaceCounts
        typealias Pacing = Rune.Pacing
        typealias SurfaceStats = Rune.SurfaceStats
        typealias SurfaceMeter = Rune.SurfaceMeter

        static func slept(start: RuneInstant, requestedResume: RuneInstant) -> Bool {
            surfaceSlept(start: start, requestedResume: requestedResume)
        }

        static func read(_ shared: SharedSurfaceStats) -> SurfaceStats {
            readSurfaceStats(shared)
        }
    }
}
