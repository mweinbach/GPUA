// Ported from: crates/rune/src/overlay/any_host.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Type-erased `AnyOverlayHost` protocol & conformance for `Overlay<T>` (`crates/rune/src/overlay/any_host.rs`).

protocol AnyOverlayHost: AnyObject {
    var overlayWindowId: UInt64? { get }
    var overlayIsVisible: Bool { get }
    func stepOverlay(now: RuneInstant, displays: [Display])
    func overlayWakeDeadline(now: RuneInstant) -> RuneInstant?
    func shutdownOverlay()
}

extension Overlay: AnyOverlayHost {
    var overlayWindowId: UInt64? {
        window?.id
    }

    var overlayIsVisible: Bool {
        visible
    }

    func stepOverlay(now: RuneInstant, displays: [Display]) {
        stepOverlayFrame(now: now, displays: displays)
    }

    func overlayWakeDeadline(now: RuneInstant) -> RuneInstant? {
        computeOverlayWakeDeadline(now: now)
    }

    func shutdownOverlay() {
        closeOverlay()
    }
}
