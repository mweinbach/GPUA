// Ported from: crates/rune/src/el/element_info.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! A whole `ElementInfo` to build from, so a stub doesn't break when Rune adds a field.

extension ElementInfo {
    /// A plain, fully opaque element at rest with no key: `el()` with nothing set, before layout
    /// (zero rects). Stubs fill in what they test:
    /// ```swift
    /// var info = ElementInfo.stub("send")
    /// info.focused = true
    /// ```
    public init() {
        self.init(
            path: "",
            key: nil,
            role: "group",
            label: nil,
            text: nil,
            rect: [0.0, 0.0, 0.0, 0.0],
            target: [0.0, 0.0, 0.0, 0.0],
            opacity: 1.0,
            scale: 1.0,
            blur: 0.0,
            radius: 0.0,
            fill: .TRANSPARENT,
            textColor: nil,
            parent: nil
        )
    }

    /// The default element keyed `key` (its path is the key too), for a test that stands in for
    /// `Runtime.elements()`.
    public static func stub(_ key: String) -> ElementInfo {
        var info = ElementInfo()
        info.path = key
        info.key = key
        return info
    }
}
