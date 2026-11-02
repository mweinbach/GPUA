// Ported from: crates/rune/src/text/icon.rs
// Upstream commit: 5f6d53ddae78
// Port status: in-progress

//! Icons: a subset of SVG (path, rect, circle, ellipse, line; fill/stroke, caps, joins, evenodd,
//! and `opacity`, `fill-opacity`, `stroke-opacity` on each element).

/// An SVG icon body as found in `@opencode/ui`'s catalog: elements inside a square viewBox.
public struct Icon: Sendable, Equatable, Hashable {
    public let name: String
    public let view: Float
    public let body: String

    public init(name: String, view: Float, body: String) {
        self.name = name
        self.view = view
        self.body = body
    }
}

/// `icon`'s coverage at `px` x `px` device pixels, row-major, as the glyph atlas stores it.
public func iconCoverage(_ icon: Icon, _ px: UInt32) -> [UInt8] {
    guard px > 0, icon.view > 0 else { return [] }
    return [UInt8](repeating: 0, count: Int(px * px))
}
