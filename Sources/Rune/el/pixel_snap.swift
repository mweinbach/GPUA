// Ported from: crates/rune/src/el/pixel_snap.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `El.pixelSnap`: opting a subtree out of device-pixel alignment.

extension El {
    /// Whether this element and its subtree snap their rects, borders and clip edges to whole
    /// device pixels (`true`, the default). Turn it off for an element an app moves itself frame
    /// by frame at sub-pixel speeds (`El.offset` from a value it animates), so it glides instead
    /// of stepping a pixel at a time.
    public func pixelSnap(_ on: Bool) -> El {
        var copy = self
        copy.vis.noPixelSnap = !on
        return copy
    }
}
