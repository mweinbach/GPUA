// Swift-only: Unified Shadcn-style UI ornaments across GPUI and Rune (ADR-0015).

import GPUI
import Rune
import RuneKit
import RuneLight

// MARK: - OrnamentAnchor & OrnamentHost

/// Viewport / container edge or corner anchor for floating ornaments (visionOS / macOS / Shadcn style).
public enum OrnamentAnchor: String, Sendable, Equatable, Hashable, CaseIterable {
    case topLeading
    case top
    case topTrailing
    case leading
    case center
    case trailing
    case bottomLeading
    case bottom
    case bottomTrailing
}

/// Pairs a floating ornament with its ``OrnamentAnchor`` and edge inset/offset.
public struct AnchoredOrnament: Sendable {
    public var anchor: OrnamentAnchor
    public var insetPx: Float
    public var ornament: AnyOrnament

    public init<O: GPUAOrnament>(
        anchor: OrnamentAnchor,
        insetPx: Float = 16.0,
        _ ornament: O
    ) {
        self.anchor = anchor
        self.insetPx = insetPx
        self.ornament = AnyOrnament(ornament)
    }
}

/// Composes a base view with floating anchored ornaments (toolbars, frosted bars, popovers, toasts)
/// on both ``GPUI`` and ``Rune``.
public struct OrnamentHost: GPUAOrnament {
    public var content: AnyOrnament
    public var ornaments: [AnchoredOrnament]

    public init<C: GPUAOrnament>(
        content: C,
        ornaments: [AnchoredOrnament] = []
    ) {
        self.content = AnyOrnament(content)
        self.ornaments = ornaments
    }

    public func ornament<O: GPUAOrnament>(
        at anchor: OrnamentAnchor,
        insetPx: Float = 16.0,
        _ child: O
    ) -> OrnamentHost {
        var copy = self
        copy.ornaments.append(AnchoredOrnament(anchor: anchor, insetPx: insetPx, child))
        return copy
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        var root = GPUI.div()
            .relative()
            .flex()
            .flexCol()
            .sizeFull()
            .bg(theme.background.toGPUIHsla())
            .textColor(theme.foreground.toGPUIHsla())
            .child(content.renderGPUI(theme: theme))

        for entry in ornaments {
            let pad = GPUI.Length.definite(.pixels(GPUI.px(entry.insetPx)))
            var holder = GPUI.div().absolute().flex().flexRow()
            switch entry.anchor {
            case .topLeading:
                holder = holder.top(pad).left(pad)
            case .top:
                holder = holder.top(pad).left0().right0().justifyCenter()
            case .topTrailing:
                holder = holder.top(pad).right(pad)
            case .leading:
                holder = holder.left(pad).top0().bottom0().itemsCenter()
            case .center:
                holder = holder.inset0().itemsCenter().justifyCenter()
            case .trailing:
                holder = holder.right(pad).top0().bottom0().itemsCenter()
            case .bottomLeading:
                holder = holder.bottom(pad).left(pad)
            case .bottom:
                holder = holder.bottom(pad).left0().right0().justifyCenter()
            case .bottomTrailing:
                holder = holder.bottom(pad).right(pad)
            }
            root = root.child(holder.child(entry.ornament.renderGPUI(theme: theme)))
        }
        return root.intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer: inout [Rune.El]) -> Rune.El {
        let base = Rune.col()
            .wFull()
            .hFull()
            .fill(theme.background.toRuneColor())
            .child(content.renderRune(theme: theme, layer: &layer))

        for entry in ornaments {
            let p = entry.insetPx
            let rendered = entry.ornament.renderRune(theme: theme, layer: &layer)
            let pinned: Rune.El
            switch entry.anchor {
            case .topLeading:
                pinned = Rune.row().pin(p, p, nil, nil).child(rendered)
            case .top:
                pinned = Rune.row().pin(0.0, p, 0.0, nil).justifyCenter().child(rendered)
            case .topTrailing:
                pinned = Rune.row().pin(nil, p, p, nil).child(rendered)
            case .leading:
                pinned = Rune.col().pin(p, 0.0, nil, 0.0).justifyCenter().child(rendered)
            case .center:
                pinned = Rune.row().pin(0.0, 0.0, 0.0, 0.0).center().child(rendered)
            case .trailing:
                pinned = Rune.col().pin(nil, 0.0, p, 0.0).justifyCenter().child(rendered)
            case .bottomLeading:
                pinned = Rune.row().pin(p, nil, nil, p).child(rendered)
            case .bottom:
                pinned = Rune.row().pin(0.0, nil, 0.0, p).justifyCenter().child(rendered)
            case .bottomTrailing:
                pinned = Rune.row().pin(nil, nil, p, p).child(rendered)
            }
            layer.append(pinned)
        }
        return base
    }
}

// MARK: - UIFloatingToolbar (Pill Ornament Bar)

/// Elevated pill toolbar ornament (Figma / Linear / visionOS style) with icon actions, labeled buttons,
/// dividers, status badges, and keyboard hints.
public struct UIFloatingToolbar: GPUAOrnament {
    public enum Slot: Sendable {
        case icon(OrnamentIcon, label: String, active: Bool = false)
        case action(String, icon: OrnamentIcon? = nil, active: Bool = false, shortcut: UIKbd? = nil)
        case separator
        case badge(UIBadge)
    }

    public var slots: [Slot]
    public var frosted: Bool

    public init(_ slots: [Slot], frosted: Bool = true) {
        self.slots = slots
        self.frosted = frosted
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        let dark = theme.appearance.isDark
        let surfaceBg = frosted
            ? theme.popover.withAlpha(dark ? 0.84 : 0.90)
            : theme.popover
        let rimBorder = theme.foreground.withAlpha(dark ? 0.14 : 0.12)

        var bar = GPUI.div()
            .flex()
            .flexRow()
            .itemsCenter()
            .gap(.pixels(GPUI.px(4.0)))
            .p(GPUI.px(5.0))
            .roundedFull()
            .bg(surfaceBg.toGPUIHsla())
            .border1()
            .borderColor(rimBorder.toGPUIHsla())
            .shadow(theme.gpuiPopoverShadows())

        for slot in slots {
            switch slot {
            case let .icon(ic, label: _, active: active):
                let fg = active ? theme.primaryForeground : theme.foreground
                let bg = active ? theme.primary : .transparent
                bar = bar.child(
                    GPUI.div()
                        .flex()
                        .itemsCenter()
                        .justifyCenter()
                        .size(GPUI.px(30.0))
                        .roundedFull()
                        .bg(bg.toGPUIHsla())
                        .cursorPointer()
                        .child(ic.renderGPUI(sizePx: 14.5, color: fg))
                )
            case let .action(title, icon: ic, active: active, shortcut: kbd):
                let fg = active ? theme.primaryForeground : theme.foreground
                let bg = active ? theme.primary : theme.secondary.withAlpha(0.65)
                var pill = GPUI.div()
                    .flex()
                    .flexRow()
                    .itemsCenter()
                    .gap(.pixels(GPUI.px(6.0)))
                    .h(GPUI.px(30.0))
                    .px(.pixels(GPUI.px(11.0)))
                    .roundedFull()
                    .bg(bg.toGPUIHsla())
                    .textSize(.pixels(GPUI.px(12.5)))
                    .fontWeight(.medium)
                    .textColor(fg.toGPUIHsla())
                    .cursorPointer()
                if let ic {
                    pill = pill.child(ic.renderGPUI(sizePx: 13.5, color: fg))
                }
                pill = pill.child(title)
                if let kbd {
                    pill = pill.child(kbd.renderGPUI(theme: theme))
                }
                bar = bar.child(pill)
            case .separator:
                bar = bar.child(
                    GPUI.div()
                        .w(GPUI.px(1.0))
                        .h(GPUI.px(18.0))
                        .mx(.definite(.pixels(GPUI.px(3.0))))
                        .bg(theme.border.toGPUIHsla())
                )
            case .badge(let b):
                bar = bar.child(b.renderGPUI(theme: theme))
            }
        }
        return bar.intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer: inout [Rune.El]) -> Rune.El {
        let dark = theme.appearance.isDark
        let surfaceBg = frosted
            ? theme.popover.withAlpha(dark ? 0.84 : 0.90)
            : theme.popover
        let rim = theme.foreground.withAlpha(dark ? 0.20 : 0.45).toRuneColor()
        let border = theme.border.toRuneColor()

        var bar = Rune.row()
            .role("toolbar")
            .padding(5.0)
            .gap(4.0)
            .centerY()
            .radius(theme.radii.full)
            .fill(surfaceBg.toRuneColor())
            .borderGradient(1.0, rim, border)
            .boxShadow(
                Rune.Shadow(
                    x: 0.0,
                    y: 8.0,
                    blur: 22.0,
                    spread: -3.0,
                    color: Rune.Color.BLACK.alpha(dark ? 0.50 : 0.14)
                )
            )
        if frosted {
            bar = bar.backdropBlur(theme.glass.blurRadius)
        }

        for slot in slots {
            switch slot {
            case let .icon(ic, label: lbl, active: active):
                let fg = active ? theme.primaryForeground : theme.foreground
                let bg = active ? theme.primary : .transparent
                bar = bar.child(
                    Rune.row()
                        .role("button")
                        .label(lbl)
                        .size(30.0, 30.0)
                        .center()
                        .radius(15.0)
                        .fill(bg.toRuneColor())
                        .child(ic.renderRune(sizePx: 14.5, color: fg))
                )
            case let .action(title, icon: ic, active: active, shortcut: kbd):
                let fg = active ? theme.primaryForeground : theme.foreground
                let bg = active ? theme.primary : theme.secondary.withAlpha(0.65)
                var pill = Rune.row()
                    .role("button")
                    .label(title)
                    .h(30.0)
                    .pl(11.0)
                    .pr(11.0)
                    .gap(6.0)
                    .centerY()
                    .radius(theme.radii.full)
                    .fill(bg.toRuneColor())
                if let ic {
                    pill = pill.child(ic.renderRune(sizePx: 13.5, color: fg))
                }
                pill = pill.child(
                    Rune.text(title)
                        .font(Rune.TextStyle.new(12.5, 500.0).lh(16.0))
                        .color(fg.toRuneColor())
                )
                if let kbd {
                    pill = pill.child(kbd.renderRune(theme: theme, layer: &layer))
                }
                bar = bar.child(pill)
            case .separator:
                bar = bar.child(Rune.el().size(1.0, 18.0).ml(3.0).mr(3.0).fill(border))
            case .badge(let b):
                bar = bar.child(b.renderRune(theme: theme, layer: &layer))
            }
        }
        return bar
    }
}

// MARK: - UIGlassCard & UIFrostedBar (Backed by RuneLight.Glass)

/// Translucent Liquid-Glass / frosted card backed by ``OrnamentGlassTokens`` and ``RuneLight/Glass``.
public struct UIGlassCard: GPUAOrnament {
    public var title: String?
    public var subtitle: String?
    public var icon: OrnamentIcon?
    public var badge: UIBadge?
    public var children: [AnyOrnament]
    public var widthPx: Float?
    public var glassOverride: OrnamentGlassTokens?

    public init(
        title: String? = nil,
        subtitle: String? = nil,
        icon: OrnamentIcon? = nil,
        badge: UIBadge? = nil,
        children: [AnyOrnament] = [],
        widthPx: Float? = nil,
        glassOverride: OrnamentGlassTokens? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.badge = badge
        self.children = children
        self.widthPx = widthPx
        self.glassOverride = glassOverride
    }

    public func child<O: GPUAOrnament>(_ ornament: O) -> UIGlassCard {
        var copy = self
        copy.children.append(AnyOrnament(ornament))
        return copy
    }

    /// Produces the physical ``RuneLight/Glass`` pane matching this card's bounds and optical tokens.
    public func runeLightGlass(
        x: Float,
        y: Float,
        width: Float,
        height: Float,
        theme: OrnamentTheme
    ) -> RuneLight.Glass {
        let g = glassOverride ?? theme.glass
        return g.toRuneLightGlass(
            x: x,
            y: y,
            width: width,
            height: height,
            radius: theme.radii.xl,
            surfaceTint: theme.card
        )
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        let g = glassOverride ?? theme.glass
        let dark = theme.appearance.isDark
        let topStop = (dark ? OrnamentColor.white.withAlpha(0.14) : OrnamentColor.white.withAlpha(0.82))
            .mixed(with: theme.card.withAlpha(g.tintOpacity), 0.55)
        let botStop = theme.card.withAlpha(g.tintOpacity)
        let grad = GPUI.linearGradient(
            angle: 165.0,
            from: GPUI.LinearColorStop(color: topStop.toGPUIHsla(), percentage: 0.0),
            to: GPUI.LinearColorStop(color: botStop.toGPUIHsla(), percentage: 1.0)
        )
        let rim = OrnamentColor.white.withAlpha(g.rimOpacity)

        var card = GPUI.div()
            .flex()
            .flexCol()
            .gap(.pixels(GPUI.px(12.0)))
            .p(GPUI.px(18.0))
            .rounded(.pixels(GPUI.px(theme.radii.xl)))
            .bg(GPUI.Fill.color(grad))
            .border1()
            .borderColor(rim.toGPUIHsla())
            .shadow(theme.gpuiPopoverShadows())

        if let w = widthPx {
            card = card.w(GPUI.px(w))
        }

        if title != nil || subtitle != nil || badge != nil {
            var topRow = GPUI.div().flex().flexRow().itemsCenter().justifyBetween().gap(.pixels(GPUI.px(10.0)))
            var left = GPUI.div().flex().flexRow().itemsCenter().gap(.pixels(GPUI.px(9.0)))
            if let icon {
                left = left.child(
                    GPUI.div()
                        .flex()
                        .itemsCenter()
                        .justifyCenter()
                        .size(GPUI.px(32.0))
                        .rounded(.pixels(GPUI.px(theme.radii.md)))
                        .bg(theme.primary.withAlpha(0.20).toGPUIHsla())
                        .border1()
                        .borderColor(theme.primary.withAlpha(0.35).toGPUIHsla())
                        .child(icon.renderGPUI(sizePx: 15.5, color: theme.primary))
                )
            }
            var titles = GPUI.div().flex().flexCol().gap(.pixels(GPUI.px(2.0)))
            if let title {
                titles = titles.child(
                    GPUI.div()
                        .textSize(.pixels(GPUI.px(14.5)))
                        .fontWeight(.semibold)
                        .textColor(theme.foreground.toGPUIHsla())
                        .child(title)
                )
            }
            if let subtitle {
                titles = titles.child(
                    GPUI.div()
                        .textSize(.pixels(GPUI.px(12.0)))
                        .textColor(theme.mutedForeground.toGPUIHsla())
                        .child(subtitle)
                )
            }
            left = left.child(titles)
            topRow = topRow.child(left)
            if let badge {
                topRow = topRow.child(badge.renderGPUI(theme: theme))
            }
            card = card.child(topRow)
        }

        for ch in children {
            card = card.child(ch.renderGPUI(theme: theme))
        }
        return card.intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer: inout [Rune.El]) -> Rune.El {
        let g = glassOverride ?? theme.glass
        let dark = theme.appearance.isDark
        let topFill = (dark ? OrnamentColor.white.withAlpha(0.14) : OrnamentColor.white.withAlpha(0.84))
            .mixed(with: theme.card.withAlpha(g.tintOpacity), 0.55)
        let botFill = theme.card.withAlpha(g.tintOpacity)
        let rim = OrnamentColor.white.withAlpha(g.rimOpacity).toRuneColor()

        var card = Rune.col()
            .padding(18.0)
            .gap(12.0)
            .radius(theme.radii.xl)
            .backdropBlur(g.blurRadius)
            .gradient(topFill.toRuneColor(), botFill.toRuneColor())
            .borderGradient(1.0, rim, theme.border.withAlpha(0.55).toRuneColor())
            .boxShadow(
                Rune.Shadow(
                    x: 0.0,
                    y: 12.0,
                    blur: 28.0,
                    spread: -4.0,
                    color: Rune.Color.BLACK.alpha(dark ? 0.52 : 0.14)
                )
            )
        if let w = widthPx {
            card = card.w(w)
        }

        if title != nil || subtitle != nil || badge != nil {
            var left = Rune.row().gap(9.0).centerY()
            if let icon {
                left = left.child(
                    Rune.row()
                        .size(32.0, 32.0)
                        .center()
                        .radius(theme.radii.md)
                        .fill(theme.primary.withAlpha(0.20).toRuneColor())
                        .border(1.0, theme.primary.withAlpha(0.35).toRuneColor())
                        .child(icon.renderRune(sizePx: 15.5, color: theme.primary))
                )
            }
            var titles = Rune.col().gap(2.0)
            if let title {
                titles = titles.child(
                    Rune.text(title)
                        .font(Rune.TextStyle.new(14.5, 600.0).lh(19.0))
                        .color(theme.foreground.toRuneColor())
                )
            }
            if let subtitle {
                titles = titles.child(
                    Rune.text(subtitle)
                        .font(Rune.TextStyle.new(12.0, 400.0).lh(16.0))
                        .color(theme.mutedForeground.toRuneColor())
                )
            }
            left = left.child(titles)
            var topRow = Rune.row().wFull().justifyBetween().centerY().gap(10.0).child(left)
            if let badge {
                topRow = topRow.child(badge.renderRune(theme: theme, layer: &layer))
            }
            card = card.child(topRow)
        }

        for ch in children {
            card = card.child(ch.renderRune(theme: theme, layer: &layer))
        }
        return card
    }
}

/// Horizontal frosted status / navigation bar ornament backed by ``OrnamentGlassTokens``.
public struct UIFrostedBar: GPUAOrnament {
    public var leading: [AnyOrnament]
    public var center: [AnyOrnament]
    public var trailing: [AnyOrnament]

    public init(
        leading: [AnyOrnament] = [],
        center: [AnyOrnament] = [],
        trailing: [AnyOrnament] = []
    ) {
        self.leading = leading
        self.center = center
        self.trailing = trailing
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        let dark = theme.appearance.isDark
        let bg = theme.popover.withAlpha(dark ? 0.76 : 0.85)
        let rim = OrnamentColor.white.withAlpha(theme.glass.rimOpacity)

        var leadRow = GPUI.div().flex().flexRow().itemsCenter().gap(.pixels(GPUI.px(8.0)))
        for item in leading { leadRow = leadRow.child(item.renderGPUI(theme: theme)) }

        var midRow = GPUI.div().flex().flexRow().itemsCenter().gap(.pixels(GPUI.px(8.0)))
        for item in center { midRow = midRow.child(item.renderGPUI(theme: theme)) }

        var trailRow = GPUI.div().flex().flexRow().itemsCenter().gap(.pixels(GPUI.px(8.0)))
        for item in trailing { trailRow = trailRow.child(item.renderGPUI(theme: theme)) }

        return GPUI.div()
            .flex()
            .flexRow()
            .itemsCenter()
            .justifyBetween()
            .wFull()
            .h(GPUI.px(46.0))
            .px(.pixels(GPUI.px(14.0)))
            .rounded(.pixels(GPUI.px(theme.radii.lg)))
            .bg(bg.toGPUIHsla())
            .border1()
            .borderColor(rim.toGPUIHsla())
            .shadow(theme.gpuiPopoverShadows())
            .child(leadRow)
            .child(midRow)
            .child(trailRow)
            .intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer: inout [Rune.El]) -> Rune.El {
        let dark = theme.appearance.isDark
        let bg = theme.popover.withAlpha(dark ? 0.76 : 0.85).toRuneColor()
        let rim = OrnamentColor.white.withAlpha(theme.glass.rimOpacity).toRuneColor()

        var leadRow = Rune.row().gap(8.0).centerY()
        for item in leading { leadRow = leadRow.child(item.renderRune(theme: theme, layer: &layer)) }

        var midRow = Rune.row().gap(8.0).centerY()
        for item in center { midRow = midRow.child(item.renderRune(theme: theme, layer: &layer)) }

        var trailRow = Rune.row().gap(8.0).centerY()
        for item in trailing { trailRow = trailRow.child(item.renderRune(theme: theme, layer: &layer)) }

        return Rune.row()
            .wFull()
            .h(46.0)
            .pl(14.0)
            .pr(14.0)
            .justifyBetween()
            .centerY()
            .radius(theme.radii.lg)
            .backdropBlur(theme.glass.blurRadius)
            .fill(bg)
            .borderGradient(1.0, rim, theme.border.toRuneColor())
            .child(leadRow)
            .child(midRow)
            .child(trailRow)
    }
}

// MARK: - UIPopover, UITooltip & UIHoverCard

/// Shadcn `Popover` ornament pairing a trigger with an anchored floating surface.
public struct UIPopover: GPUAOrnament {
    public var trigger: AnyOrnament
    public var title: String?
    public var description: String?
    public var content: [AnyOrnament]
    public var isOpen: Bool
    public var widthPx: Float

    public init<T: GPUAOrnament>(
        trigger: T,
        title: String? = nil,
        description: String? = nil,
        content: [AnyOrnament] = [],
        isOpen: Bool = true,
        widthPx: Float = 260.0
    ) {
        self.trigger = AnyOrnament(trigger)
        self.title = title
        self.description = description
        self.content = content
        self.isOpen = isOpen
        self.widthPx = widthPx
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        var stack = GPUI.div().flex().flexCol().itemsStart().gap(.pixels(GPUI.px(6.0)))
        stack = stack.child(trigger.renderGPUI(theme: theme))
        guard isOpen else {
            return stack.intoAnyElement()
        }
        var pop = GPUI.div()
            .flex()
            .flexCol()
            .gap(.pixels(GPUI.px(10.0)))
            .w(GPUI.px(widthPx))
            .p(GPUI.px(14.0))
            .rounded(.pixels(GPUI.px(theme.radii.lg)))
            .bg(theme.popover.toGPUIHsla())
            .border1()
            .borderColor(theme.border.toGPUIHsla())
            .shadow(theme.gpuiPopoverShadows())
        if title != nil || description != nil {
            var hdr = GPUI.div().flex().flexCol().gap(.pixels(GPUI.px(3.0)))
            if let title {
                hdr = hdr.child(
                    GPUI.div()
                        .textSize(.pixels(GPUI.px(13.5)))
                        .fontWeight(.semibold)
                        .textColor(theme.popoverForeground.toGPUIHsla())
                        .child(title)
                )
            }
            if let description {
                hdr = hdr.child(
                    GPUI.div()
                        .textSize(.pixels(GPUI.px(12.0)))
                        .textColor(theme.mutedForeground.toGPUIHsla())
                        .child(description)
                )
            }
            pop = pop.child(hdr)
        }
        for item in content {
            pop = pop.child(item.renderGPUI(theme: theme))
        }
        return stack.child(pop).intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer: inout [Rune.El]) -> Rune.El {
        let trigEl = trigger.renderRune(theme: theme, layer: &layer)
        guard isOpen else {
            return trigEl
        }
        var pop = Rune.col()
            .role("dialog")
            .w(widthPx)
            .padding(14.0)
            .gap(10.0)
            .radius(theme.radii.lg)
            .fill(theme.popover.toRuneColor())
            .border(1.0, theme.border.toRuneColor())
            .boxShadow(
                Rune.Shadow(
                    x: 0.0,
                    y: 10.0,
                    blur: 24.0,
                    spread: -4.0,
                    color: Rune.Color.BLACK.alpha(theme.appearance.isDark ? 0.50 : 0.12)
                )
            )
        if title != nil || description != nil {
            var hdr = Rune.col().gap(3.0)
            if let title {
                hdr = hdr.child(
                    Rune.text(title)
                        .font(Rune.TextStyle.new(13.5, 600.0).lh(18.0))
                        .color(theme.popoverForeground.toRuneColor())
                )
            }
            if let description {
                hdr = hdr.child(
                    Rune.text(description)
                        .font(Rune.TextStyle.new(12.0, 400.0).lh(16.0))
                        .color(theme.mutedForeground.toRuneColor())
                )
            }
            pop = pop.child(hdr)
        }
        for item in content {
            pop = pop.child(item.renderRune(theme: theme, layer: &layer))
        }
        return Rune.col().gap(6.0).child(trigEl).child(pop)
    }
}

/// Compact high-contrast Shadcn `Tooltip` with optional shortcut badge.
public struct UITooltip: GPUAOrnament {
    public var trigger: AnyOrnament
    public var text: String
    public var shortcut: UIKbd?
    public var isVisible: Bool

    public init<T: GPUAOrnament>(
        trigger: T,
        text: String,
        shortcut: UIKbd? = nil,
        isVisible: Bool = true
    ) {
        self.trigger = AnyOrnament(trigger)
        self.text = text
        self.shortcut = shortcut
        self.isVisible = isVisible
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        var col = GPUI.div().flex().flexCol().itemsCenter().gap(.pixels(GPUI.px(5.0)))
        if isVisible {
            var tip = GPUI.div()
                .flex()
                .flexRow()
                .itemsCenter()
                .gap(.pixels(GPUI.px(6.0)))
                .h(GPUI.px(26.0))
                .px(.pixels(GPUI.px(10.0)))
                .rounded(.pixels(GPUI.px(theme.radii.sm)))
                .bg(theme.foreground.toGPUIHsla())
                .textSize(.pixels(GPUI.px(11.5)))
                .fontWeight(.medium)
                .textColor(theme.background.toGPUIHsla())
                .shadow(theme.gpuiCardShadows())
                .child(text)
            if let shortcut {
                var kbdCopy = shortcut
                kbdCopy.compact = true
                tip = tip.child(kbdCopy.renderGPUI(theme: theme))
            }
            col = col.child(tip)
        }
        return col.child(trigger.renderGPUI(theme: theme)).intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer: inout [Rune.El]) -> Rune.El {
        let trigEl = trigger.renderRune(theme: theme, layer: &layer)
        guard isVisible else { return trigEl }
        var tip = Rune.row()
            .role("tooltip")
            .h(26.0)
            .pl(10.0)
            .pr(10.0)
            .gap(6.0)
            .centerY()
            .radius(theme.radii.sm)
            .fill(theme.foreground.toRuneColor())
            .child(
                Rune.text(text)
                    .font(Rune.TextStyle.new(11.5, 500.0).lh(15.0))
                    .color(theme.background.toRuneColor())
            )
        if let shortcut {
            var kbdCopy = shortcut
            kbdCopy.compact = true
            tip = tip.child(kbdCopy.renderRune(theme: theme, layer: &layer))
        }
        return Rune.col().gap(5.0).itemsCenter().child(tip).child(trigEl)
    }
}

/// Rich preview `HoverCard` modeled after shadcn/ui (`@gpua/ui`, repo/profile hover cards).
public struct UIHoverCard: GPUAOrnament {
    public var trigger: AnyOrnament
    public var icon: OrnamentIcon
    public var title: String
    public var subtitle: String
    public var bio: String
    public var meta: String?
    public var isOpen: Bool

    public init<T: GPUAOrnament>(
        trigger: T,
        icon: OrnamentIcon = .sparkles,
        title: String,
        subtitle: String,
        bio: String,
        meta: String? = nil,
        isOpen: Bool = true
    ) {
        self.trigger = AnyOrnament(trigger)
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.bio = bio
        self.meta = meta
        self.isOpen = isOpen
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        let wrap = GPUI.div().flex().flexCol().itemsStart().gap(.pixels(GPUI.px(6.0)))
            .child(trigger.renderGPUI(theme: theme))
        guard isOpen else { return wrap.intoAnyElement() }

        let avatar = GPUI.div()
            .flex()
            .itemsCenter()
            .justifyCenter()
            .size(GPUI.px(36.0))
            .roundedFull()
            .bg(theme.primary.withAlpha(0.16).toGPUIHsla())
            .border1()
            .borderColor(theme.primary.withAlpha(0.32).toGPUIHsla())
            .flexShrink0()
            .child(icon.renderGPUI(sizePx: 16.0, color: theme.primary))

        var details = GPUI.div()
            .flex()
            .flexCol()
            .gap(.pixels(GPUI.px(4.0)))
            .flex1()
            .minW(.definite(.pixels(GPUI.px(0.0))))
            .child(
                GPUI.div().flex().flexRow().itemsCenter().gap(.pixels(GPUI.px(6.0)))
                    .child(
                        GPUI.div()
                            .textSize(.pixels(GPUI.px(13.5)))
                            .fontWeight(.semibold)
                            .textColor(theme.popoverForeground.toGPUIHsla())
                            .child(title)
                    )
                    .child(
                        GPUI.div()
                            .textSize(.pixels(GPUI.px(12.0)))
                            .textColor(theme.mutedForeground.toGPUIHsla())
                            .child(subtitle)
                    )
            )
            .child(
                GPUI.div()
                    .textSize(.pixels(GPUI.px(12.5)))
                    .lineHeight(.pixels(GPUI.px(17.5)))
                    .textColor(theme.popoverForeground.withAlpha(0.9).toGPUIHsla())
                    .child(bio)
            )
        if let meta {
            details = details.child(
                GPUI.div()
                    .pt(.pixels(GPUI.px(3.0)))
                    .textSize(.pixels(GPUI.px(11.5)))
                    .textColor(theme.mutedForeground.toGPUIHsla())
                    .child(meta)
            )
        }

        let card = GPUI.div()
            .flex()
            .flexRow()
            .itemsStart()
            .gap(.pixels(GPUI.px(12.0)))
            .w(GPUI.px(336.0))
            .p(GPUI.px(14.0))
            .rounded(.pixels(GPUI.px(theme.radii.lg)))
            .bg(theme.popover.toGPUIHsla())
            .border1()
            .borderColor(theme.border.toGPUIHsla())
            .shadow(theme.gpuiPopoverShadows())
            .child(avatar)
            .child(details)

        return wrap.child(card).intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer: inout [Rune.El]) -> Rune.El {
        let trigEl = trigger.renderRune(theme: theme, layer: &layer)
        guard isOpen else { return trigEl }

        let avatar = Rune.row()
            .size(36.0, 36.0)
            .center()
            .radius(18.0)
            .fill(theme.primary.withAlpha(0.16).toRuneColor())
            .border(1.0, theme.primary.withAlpha(0.32).toRuneColor())
            .child(icon.renderRune(sizePx: 16.0, color: theme.primary))

        var details = Rune.col().gap(4.0).grow(1.0)
            .child(
                Rune.row().gap(6.0).centerY()
                    .child(Rune.text(title).font(Rune.TextStyle.new(13.5, 600.0).lh(18.0)).color(theme.popoverForeground.toRuneColor()))
                    .child(Rune.text(subtitle).font(Rune.TextStyle.new(12.0, 400.0).lh(16.0)).color(theme.mutedForeground.toRuneColor()))
            )
            .child(
                Rune.text(bio)
                    .font(Rune.TextStyle.new(12.5, 400.0).lh(17.5))
                    .color(theme.popoverForeground.withAlpha(0.9).toRuneColor())
            )
        if let meta {
            details = details.child(
                Rune.text(meta)
                    .font(Rune.TextStyle.new(11.5, 400.0).lh(15.0))
                    .color(theme.mutedForeground.toRuneColor())
            )
        }

        let card = Rune.row()
            .w(290.0)
            .padding(14.0)
            .gap(12.0)
            .radius(theme.radii.lg)
            .fill(theme.popover.toRuneColor())
            .border(1.0, theme.border.toRuneColor())
            .child(avatar)
            .child(details)

        return Rune.col().gap(6.0).child(trigEl).child(card)
    }
}

// MARK: - UIToast & UIToastViewport

/// Sonner / shadcn-style `Toast` notification banner.
public struct UIToast: GPUAOrnament {
    public enum Status: String, Sendable, Equatable, Hashable, CaseIterable {
        case `default`
        case success
        case warning
        case destructive
        case info
    }

    public var title: String
    public var description: String?
    public var status: Status
    public var actionLabel: String?
    public var widthPx: Float

    public init(
        title: String,
        description: String? = nil,
        status: Status = .default,
        actionLabel: String? = nil,
        widthPx: Float = 320.0
    ) {
        self.title = title
        self.description = description
        self.status = status
        self.actionLabel = actionLabel
        self.widthPx = widthPx
    }

    private func accentSpec(_ theme: OrnamentTheme) -> (icon: OrnamentIcon, color: OrnamentColor) {
        switch status {
        case .default: return (.bell, theme.foreground)
        case .success: return (.check, theme.success)
        case .warning: return (.warning, theme.warning)
        case .destructive: return (.warning, theme.destructive)
        case .info: return (.info, theme.info)
        }
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        let spec = accentSpec(theme)
        let borderColor = status == .destructive ? theme.destructive.withAlpha(0.45) : theme.border

        var copyCol = GPUI.div()
            .flex()
            .flexCol()
            .gap(.pixels(GPUI.px(2.0)))
            .flex1()
            .minW(.definite(.pixels(GPUI.px(0.0))))
            .child(
                GPUI.div()
                    .textSize(.pixels(GPUI.px(13.0)))
                    .fontWeight(.semibold)
                    .textColor(theme.popoverForeground.toGPUIHsla())
                    .child(title)
            )
        if let description {
            copyCol = copyCol.child(
                GPUI.div()
                    .textSize(.pixels(GPUI.px(12.0)))
                    .lineHeight(.pixels(GPUI.px(16.5)))
                    .textColor(theme.mutedForeground.toGPUIHsla())
                    .child(description)
            )
        }

        var row = GPUI.div()
            .flex()
            .flexRow()
            .itemsCenter()
            .gap(.pixels(GPUI.px(11.0)))
            .w(GPUI.px(widthPx))
            .px(.pixels(GPUI.px(14.0)))
            .py(.pixels(GPUI.px(12.0)))
            .rounded(.pixels(GPUI.px(theme.radii.lg)))
            .bg(theme.popover.toGPUIHsla())
            .border1()
            .borderColor(borderColor.toGPUIHsla())
            .shadow(theme.gpuiPopoverShadows())
            .child(
                GPUI.div()
                    .flex()
                    .itemsCenter()
                    .justifyCenter()
                    .size(GPUI.px(24.0))
                    .roundedFull()
                    .bg(spec.color.withAlpha(0.15).toGPUIHsla())
                    .flexShrink0()
                    .child(spec.icon.renderGPUI(sizePx: 13.5, color: spec.color))
            )
            .child(copyCol)

        if let actionLabel {
            row = row.child(UIButton(actionLabel, variant: .outline, size: .xs).renderGPUI(theme: theme))
        }
        return row.intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer: inout [Rune.El]) -> Rune.El {
        let spec = accentSpec(theme)
        let borderColor = status == .destructive ? theme.destructive.withAlpha(0.45) : theme.border

        var copyCol = Rune.col().gap(2.0).grow(1.0)
            .child(
                Rune.text(title)
                    .font(Rune.TextStyle.new(13.0, 600.0).lh(17.0))
                    .color(theme.popoverForeground.toRuneColor())
            )
        if let description {
            copyCol = copyCol.child(
                Rune.text(description)
                    .font(Rune.TextStyle.new(12.0, 400.0).lh(16.5))
                    .color(theme.mutedForeground.toRuneColor())
            )
        }

        var row = Rune.row()
            .role("status")
            .w(widthPx)
            .pl(14.0)
            .pr(14.0)
            .pt(12.0)
            .pb(12.0)
            .gap(11.0)
            .centerY()
            .radius(theme.radii.lg)
            .fill(theme.popover.toRuneColor())
            .border(1.0, borderColor.toRuneColor())
            .boxShadow(
                Rune.Shadow(
                    x: 0.0,
                    y: 8.0,
                    blur: 22.0,
                    spread: -3.0,
                    color: Rune.Color.BLACK.alpha(theme.appearance.isDark ? 0.48 : 0.12)
                )
            )
            .child(
                Rune.row()
                    .size(24.0, 24.0)
                    .center()
                    .radius(12.0)
                    .fill(spec.color.withAlpha(0.15).toRuneColor())
                    .child(spec.icon.renderRune(sizePx: 13.5, color: spec.color))
            )
            .child(copyCol)

        if let actionLabel {
            row = row.child(UIButton(actionLabel, variant: .outline, size: .xs).renderRune(theme: theme, layer: &layer))
        }
        return row
    }
}

/// Stacked toast region ornament (`UIToastViewport`).
public struct UIToastViewport: GPUAOrnament {
    public var toasts: [UIToast]

    public init(_ toasts: [UIToast]) {
        self.toasts = toasts
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        var stack = GPUI.div().flex().flexCol().itemsEnd().gap(.pixels(GPUI.px(8.0)))
        for t in toasts {
            stack = stack.child(t.renderGPUI(theme: theme))
        }
        return stack.intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer: inout [Rune.El]) -> Rune.El {
        var stack = Rune.col().gap(8.0).itemsEnd()
        for t in toasts {
            stack = stack.child(t.renderRune(theme: theme, layer: &layer))
        }
        return stack
    }
}
