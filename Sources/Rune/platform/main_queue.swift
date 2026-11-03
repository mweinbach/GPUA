// Ported from: crates/rune/src/platform/main_queue.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Work for the main thread from anywhere: the main dispatch queue, which the event loop drains.

#if os(macOS)
import Dispatch

/// Run `f` on the main queue, which the window event loop drains.
// PORT NOTE: Uses `DispatchQueue.main.async` directly rather than raw `dispatch_async_f` C FFI.
func runOnMainQueue(_ f: @escaping @Sendable () -> Void) {
    DispatchQueue.main.async(execute: f)
}
#endif
