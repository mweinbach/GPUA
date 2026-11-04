// Ported from: crates/rune-kit/src/keybind.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Keybind (`@opencode/ui` data-display/keybind): small keycaps. A single character is
//! upper-cased ("k" draws K); names such as `Shortcut.keycaps`'s "Space" draw as given.

import Rune

public enum KeybindVariant: Sendable, Equatable, Hashable {
    case neutral
    case ghost

    public init() {
        self = .neutral
    }

    public static let `default`: KeybindVariant = .neutral
}

public struct Keybind: Sendable {
    private var keysVal: [String]
    private var variantVal: KeybindVariant

    public init<S: Swift.Sequence>(_ keys: S) where S.Element == String {
        self.keysVal = Array(keys)
        self.variantVal = .neutral
    }

    public init(_ keys: [Substring]) {
        self.keysVal = keys.map(String.init)
        self.variantVal = .neutral
    }

    public static func new<S: Swift.Sequence>(_ keys: S) -> Keybind where S.Element == String {
        Keybind(keys)
    }

    public static func new(_ keys: [Substring]) -> Keybind {
        Keybind(keys)
    }

    public func variant(_ v: KeybindVariant) -> Keybind {
        var copy = self
        copy.variantVal = v
        return copy
    }

    public func build(_ k: Kit) -> El {
        let c = k.c
        let fill: Color
        let ink: Color
        switch variantVal {
        case .neutral:
            fill = c.layer03
            ink = c.textMuted
        case .ghost:
            fill = Color.TRANSPARENT
            ink = c.textFaint
        }
        let font = k.ty.smallMedium.lh(11.0)
        let label = keysVal.joined(separator: " ")
        return row()
            .role("group")
            .label(label)
            .gap(2.0)
            .centerY()
            .children(
                keysVal.enumerated().map { (i, key) in
                    row()
                        .key("key\(i)")
                        .minW(14.0)
                        .h(14.0)
                        .px(4.0)
                        .center()
                        .radius(2.0)
                        .fill(fill)
                        .child(text(keycap(key)).font(font).color(ink))
                }
            )
    }
}

private func keycap(_ key: String) -> String {
    let upper = key.uppercased()
    // Only when it maps back: Turkish "ı" would draw as "I", another key.
    if key.unicodeScalars.count == 1 && upper.lowercased() == key {
        return upper
    }
    return key
}

/// Namespace mirroring `rune_kit::keybind` module exports.
public enum keybind {
    public typealias KeybindVariant = RuneKit.KeybindVariant
    public typealias Keybind = RuneKit.Keybind
}
