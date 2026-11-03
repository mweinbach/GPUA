// Ported from: crates/rune/src/native_surface/place.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Where a frame sits inside its element: which edge a spare or cropped side is shared from, and
//! whether the frame is scaled at all.

/// `El.surfaceAnchor` and `El.surfaceUnscaled`. The default centres and scales by `SurfaceFit`.
public struct SurfacePlace: Sendable, Equatable, Hashable {
    public var anchor: [Align]
    public var unscaled: Bool

    public static let CENTRED = SurfacePlace(anchor: [.center, .center], unscaled: false)

    public init(anchor: [Align] = [.center, .center], unscaled: Bool = false) {
        self.anchor = anchor
        self.unscaled = unscaled
    }

    public static func `default`() -> SurfacePlace {
        .CENTRED
    }

    /// How much of the spare (or cropped) space along each axis lies before the image.
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

/// The image's rect in device pixels inside `node` (`[x, y, w, h]`); it may overflow the node, which
/// then crops it. `unscaled` draws one texel per device pixel and ignores `fit`.
func surfaceImageRect(
    _ node: [Float],
    _ source: [UInt32],
    _ fit: SurfaceFit,
    _ place: SurfacePlace
) -> [Float] {
    let sw = Float(source[0])
    let sh = Float(source[1])
    let scale: Float
    if place.unscaled {
        scale = 1.0
    } else {
        let a = node[2] / sw
        let b = node[3] / sh
        switch fit {
        case .fit: scale = min(a, b)
        case .fill: scale = max(a, b)
        }
    }
    let shVec = place.share()
    let kx = shVec[0]
    let ky = shVec[1]
    let w = sw * scale
    let h = sh * scale
    let x = node[0] + (node[2] - w) * kx
    let y = node[1] + (node[3] - h) * ky
    // At unit scale favour sharp shared text over a subpixel translation of its image.
    if abs(scale - 1.0) < 1e-6 {
        return [x.rounded(), y.rounded(), w, h]
    }
    return [x, y, w, h]
}
