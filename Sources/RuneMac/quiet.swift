// Ported from: crates/rune-mac/src/quiet.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import AppKit
import Darwin
import Dispatch

private let quietEnvVar = "MAC_APP_QUIET"

/// Call first thing in `main`, before the event loop.
///
/// When `scripts/mac-app` relaunches with `MAC_APP_QUIET` set while the app wasn't in front,
/// `launch()` keeps the app from stealing focus while it starts, then restores regular activation
/// policy and unhides without activation once macOS hides it (or after 5 seconds).
public func launch() {
    guard getenv(quietEnvVar) != nil else {
        return
    }
    unsetenv(quietEnvVar)
    onMainThreadSync {
        // NSApplication.ActivationPolicy.prohibited: windowing activation at launch does nothing.
        _ = NSApplication.shared.setActivationPolicy(.prohibited)
        scheduleQuietCheck(tries: 0)
    }
}

/// Launched with `.prohibited`, macOS hides the app within a few hundred milliseconds. Once it
/// has (or after 5 s), the app turns `.regular` again and shows its window without activating,
/// so it lands behind whatever is in front.
// PORT NOTE: Uses `DispatchQueue.main.asyncAfter` instead of raw C `dispatch_after_f` / `_dispatch_main_q` symbols.
private func scheduleQuietCheck(tries: Int) {
    DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(250_000_000)) {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            if !app.isHidden && tries < 20 {
                scheduleQuietCheck(tries: tries + 1)
                return
            }
            _ = app.setActivationPolicy(.regular)
            app.unhideWithoutActivation()
        }
    }
}
#endif
