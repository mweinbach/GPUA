// Ported from: crates/gpui_ios/src/display_link.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(iOS) || os(visionOS)
import Foundation
import QuartzCore

// MARK: - CADisplayLink Vsync Driver

// PORT NOTE: Replaces upstream ObjC runtime `ClassDecl("GPUIDisplayLinkTarget")` and manual
// `Box::into_raw` ivar storage with a native Swift `NSObject` target class and RAII invalidation
// in `DisplayLink.deinit` (ADR-0011).

/// Objective-C selector target invoked by `CADisplayLink` on every display refresh tick.
@MainActor
final class GPUIDisplayLinkTarget: NSObject {
    private let callback: () -> Void

    init(callback: @escaping () -> Void) {
        self.callback = callback
        super.init()
    }

    @objc func step(_ displayLink: CADisplayLink) {
        _ = displayLink
        autoreleasepool {
            callback()
        }
    }
}

/// Manages a `CADisplayLink` attached to `RunLoop.main` in `.common` mode so vsync frames
/// continue firing smoothly during scroll/pan tracking as well as normal idle run-loop ticks.
@MainActor
final class DisplayLink {
    private let target: GPUIDisplayLinkTarget
    // PORT NOTE: Mutated on MainActor and invalidated on the main thread in `deinit`.
    private nonisolated(unsafe) let displayLink: CADisplayLink

    /// Creates a new paused `DisplayLink` registered on `RunLoop.main` in `.common` mode.
    init(callback: @escaping () -> Void) {
        let target = GPUIDisplayLinkTarget(callback: callback)
        let link = CADisplayLink(target: target, selector: #selector(GPUIDisplayLinkTarget.step(_:)))
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        self.target = target
        self.displayLink = link
    }

    deinit {
        if Thread.isMainThread {
            displayLink.invalidate()
        } else {
            let rawBits = Int(bitPattern: Unmanaged.passRetained(displayLink).toOpaque())
            DispatchQueue.main.async {
                if let ptr = UnsafeMutableRawPointer(bitPattern: rawBits) {
                    let link = Unmanaged<CADisplayLink>.fromOpaque(ptr).takeRetainedValue()
                    link.invalidate()
                }
            }
        }
    }

    /// Resumes vsync callbacks (`isPaused = false`).
    func start() {
        displayLink.isPaused = false
    }

    /// Pauses vsync callbacks (`isPaused = true`). Must be called when the scene enters
    /// the background so no Metal command buffers are submitted while backgrounded.
    func stop() {
        displayLink.isPaused = true
    }

    /// Whether the display link is currently paused.
    var isPaused: Bool {
        displayLink.isPaused
    }
}
#endif
