// Ported from: crates/gpui_windows/src/vsync.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Windows)
import Foundation
#if canImport(CWinSys)
import CWinSys
#endif

private let vsyncIntervalThreshold: TimeInterval = 0.001
private let defaultVsyncInterval: TimeInterval = 1.0 / 60.0

// PORT NOTE: VSyncProvider encapsulates DWM timing queries and wait logic, which is thread-safe and immutable after init.
public final class VSyncProvider: @unchecked Sendable {
    public let interval: TimeInterval
    private let flushFn: @Sendable () -> Bool

    public init() {
        var refreshInterval: Double = 0.0
        let status = cwin_win32_dwm_get_refresh_interval(&refreshInterval)
        if status == 0 && refreshInterval >= 0.001 {
            self.interval = refreshInterval
        } else {
            self.interval = defaultVsyncInterval
        }
        self.flushFn = {
            cwin_win32_dwm_flush() == 0
        }
    }

    public init(interval: TimeInterval, flushFn: @escaping @Sendable () -> Bool) {
        self.interval = interval
        self.flushFn = flushFn
    }

    public func waitForVsync() {
        let startTime = Date()
        let waitSucceeded = flushFn()
        let elapsed = Date().timeIntervalSince(startTime)

        // DwmFlush returns early if monitor is asleep or occlusion occurs.
        // If elapsed is under threshold, fall back to sleeping for the frame interval.
        if !waitSucceeded || elapsed < vsyncIntervalThreshold {
            Thread.sleep(forTimeInterval: interval)
        }
    }
}

#endif
