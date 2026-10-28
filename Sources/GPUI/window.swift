// Ported from: crates/gpui/src/window.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: not-started

// PORT NOTE: Forward declaration of Window to support Taffy layout engine and context
public struct Window: Sendable {
    public var scaleFactor: Float

    public init(scaleFactor: Float = 1.0) {
        self.scaleFactor = scaleFactor
    }
}
