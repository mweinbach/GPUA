// Ported from: crates/rune/src/input/drop_pointer.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS) && canImport(AppKit)
import AppKit
#endif

/// Samples the system pointer position over a window during external file drags when the
/// windowing layer does not report drag-over coordinates directly.
internal struct DropPointer: Sendable {
    internal init() {}

    internal static func new() -> DropPointer {
        DropPointer()
    }

    #if os(macOS) && canImport(AppKit)
    /// Samples the pointer over `view` in points from its top-left on the main thread.
    @MainActor
    internal func sample(in view: NSView) -> (Float, Float)? {
        guard let nsWindow = view.window else { return nil }
        let p = view.convert(nsWindow.mouseLocationOutsideOfEventStream, from: nil)
        let y = view.isFlipped ? p.y : (view.bounds.size.height - p.y)
        return (Float(p.x), Float(y))
    }
    #endif

    /// Converts a physical screen point `(x, y)` into window content points given `origin` and `scale`.
    internal static func screenToWindow(
        screen: (Int32, Int32),
        windowOrigin: (Int32, Int32),
        scale: Float
    ) -> (Float, Float)? {
        guard scale.isFinite && scale > 0 else { return nil }
        return (
            Float(screen.0 - windowOrigin.0) / scale,
            Float(screen.1 - windowOrigin.1) / scale
        )
    }
}
