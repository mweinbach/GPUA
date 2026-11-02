// Ported from: crates/rune/src/native_surface/place.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

public struct SurfacePlace: Sendable, Equatable {
    public var anchor: [Align]
    public var unscaled: Bool

    public init(anchor: [Align] = [.center, .center], unscaled: Bool = false) {
        self.anchor = anchor
        self.unscaled = unscaled
    }

    public func share() -> [Float] {
        func axis(_ a: Align) -> Float {
            switch a {
            case .start: return 0.0
            case .center: return 0.5
            case .end: return 1.0
            }
        }
        return [axis(anchor[0]), axis(anchor[1])]
    }
}
