// Ported from: crates/rune-kit/src/badge.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Badge / tag (`@opencode/ui` data-display/badge) and Divider (`layout/divider`).

import Rune

public enum BadgeVariant: Sendable, Equatable, Hashable {
    case neutral
    case accent
    case subtle

    public init() {
        self = .neutral
    }

    public static let `default`: BadgeVariant = .neutral
}

public struct Badge: Sendable {
    private var labelVal: String
    private var variantVal: BadgeVariant
    private var standardVal: Bool
    private var highContrastVal: Bool

    public init(_ label: String) {
        self.labelVal = label
        self.variantVal = .neutral
        self.standardVal = false
        self.highContrastVal = false
    }

    public static func new(_ label: String) -> Badge {
        Badge(label)
    }

    public func variant(_ v: BadgeVariant) -> Badge {
        var copy = self
        copy.variantVal = v
        return copy
    }

    /// The older, larger tag (`appearance="standard"`).
    public func standard() -> Badge {
        var copy = self
        copy.standardVal = true
        return copy
    }

    /// A stronger border (`data-high-contrast`).
    public func highContrast() -> Badge {
        var copy = self
        copy.highContrastVal = true
        return copy
    }

    public func build(_ k: Kit) -> El {
        let c = k.c
        let fill: Color
        let ink: Color
        let border: Color?
        switch variantVal {
        case .neutral where standardVal:
            fill = c.surfaceRaisedBase
            ink = c.stdText
            border = c.borderWeak
        case .neutral:
            fill = c.layer02
            ink = c.textMuted
            border = highContrastVal ? c.borderStrong : c.borderBase
        case .accent:
            fill = c.bgAccent
            ink = c.textContrast
            border = nil
        case .subtle:
            fill = c.layer03
            ink = c.textMuted
            border = nil
        }

        let h: Float
        let px: Float
        let radius: Float
        let font: TextStyle
        if standardVal {
            h = 18.0
            px = 6.0
            radius = k.radius.xs
            font = k.ty.textSmallMedium
        } else {
            h = 16.0
            px = 4.0
            radius = 2.0
            font = k.ty.smallMedium.lh(11.0)
        }

        var e = row()
            .role("status")
            .label(labelVal)
            .center()
            .gap(4.0)
            .h(h)
            .px(px)
            .radius(radius)
            .fill(fill)
            .child(text(labelVal).font(font).color(ink))
        if let b = border {
            e = e.border(0.5, b)
        }
        return e
    }
}

/// A 1 point rule (`Divider`), horizontal unless `vertical`.
public struct Divider: Sendable {
    private var isVertical: Bool

    public init(vertical: Bool = false) {
        self.isVertical = vertical
    }

    public static func horizontal() -> Divider {
        Divider(vertical: false)
    }

    public static func vertical() -> Divider {
        Divider(vertical: true)
    }

    public func build(_ k: Kit) -> El {
        let e = el().role("separator").fill(k.c.borderBase)
        return isVertical ? e.w(1.0).hFull() : e.h(1.0).wFull()
    }
}

/// Namespace mirroring `rune_kit::badge` module exports.
public enum badge {
    public typealias BadgeVariant = RuneKit.BadgeVariant
    public typealias Badge = RuneKit.Badge
    public typealias Divider = RuneKit.Divider
}
