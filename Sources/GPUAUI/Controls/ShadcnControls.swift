// Swift-only: Unified Shadcn-style UI ornaments across GPUI and Rune (ADR-0015).

import GPUI
import Rune
import RuneKit

// MARK: - UIKbd (Keyboard Shortcut Keycaps)

/// Shadcn-style `<kbd>` shortcut badge (`UIKbd(["⌘", "K"])` or `UIKbd("⌘⇧P")`).
public struct UIKbd: GPUAOrnament {
    public var keys: [String]
    public var compact: Bool

    public init(_ keys: [String], compact: Bool = false) {
        self.keys = keys
        self.compact = compact
    }

    public init(_ combo: String, compact: Bool = false) {
        if combo.contains("+") {
            self.keys = combo.split(separator: "+").map(String.init)
        } else {
            self.keys = [combo]
        }
        self.compact = compact
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        let h: Float = compact ? 18.0 : 21.0
        let fontPx: Float = compact ? 10.5 : 11.5
        let bg = theme.muted.toGPUIHsla()
        let fg = theme.mutedForeground.toGPUIHsla()
        let border = theme.border.toGPUIHsla()

        var row = GPUI.div().flex().flexRow().itemsCenter().gap(.pixels(GPUI.px(3.0))).flexShrink0()
        for k in keys {
            row = row.child(
                GPUI.div()
                    .flex()
                    .itemsCenter()
                    .justifyCenter()
                    .h(GPUI.px(h))
                    .minW(.definite(.pixels(GPUI.px(h))))
                    .px(.pixels(GPUI.px(compact ? 4.5 : 6.0)))
                    .rounded(.pixels(GPUI.px(theme.radii.xs)))
                    .bg(bg)
                    .border1()
                    .borderColor(border)
                    .fontFamily(GPUI.SharedString(theme.fontMono))
                    .textSize(.pixels(GPUI.px(fontPx)))
                    .fontWeight(.medium)
                    .textColor(fg)
                    .child(k)
            )
        }
        return row.intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer _: inout [Rune.El]) -> Rune.El {
        let h: Float = compact ? 18.0 : 21.0
        let fontPx: Float = compact ? 10.5 : 11.5
        let bg = theme.muted.toRuneColor()
        let fg = theme.mutedForeground.toRuneColor()
        let border = theme.border.toRuneColor()
        let ts = Rune.TextStyle.new(fontPx, 500.0).lh(fontPx + 2.0).mono()

        var out = Rune.row().gap(3.0).centerY()
        for k in keys {
            out = out.child(
                Rune.row()
                    .h(h)
                    .minW(h)
                    .pl(compact ? 4.5 : 6.0)
                    .pr(compact ? 4.5 : 6.0)
                    .center()
                    .radius(theme.radii.xs)
                    .fill(bg)
                    .border(1.0, border)
                    .child(Rune.text(k).font(ts).color(fg))
            )
        }
        return out
    }
}

// MARK: - UIBadge

/// Semantic status or category pill modeled after shadcn/ui `Badge`.
public struct UIBadge: GPUAOrnament {
    public enum Status: String, Sendable, Equatable, Hashable, CaseIterable {
        case `default`
        case secondary
        case outline
        case destructive
        case success
        case warning
        case info
    }

    public var label: String
    public var status: Status
    public var icon: OrnamentIcon?
    public var dot: Bool

    public init(
        _ label: String,
        status: Status = .default,
        icon: OrnamentIcon? = nil,
        dot: Bool = false
    ) {
        self.label = label
        self.status = status
        self.icon = icon
        self.dot = dot
    }

    private func resolveColors(_ theme: OrnamentTheme) -> (bg: OrnamentColor, fg: OrnamentColor, border: OrnamentColor?, dotColor: OrnamentColor) {
        let dark = theme.appearance.isDark
        switch status {
        case .default:
            return (theme.primary, theme.primaryForeground, nil, theme.primaryForeground)
        case .secondary:
            return (theme.secondary, theme.secondaryForeground, theme.border, theme.primary)
        case .outline:
            return (.transparent, theme.foreground, theme.border, theme.mutedForeground)
        case .destructive:
            return (
                theme.destructive.withAlpha(dark ? 0.18 : 0.12),
                dark ? OrnamentColor(hex: 0xFCA5A5) : OrnamentColor(hex: 0xB91C1C),
                theme.destructive.withAlpha(0.35),
                theme.destructive
            )
        case .success:
            return (
                theme.success.withAlpha(dark ? 0.18 : 0.12),
                dark ? OrnamentColor(hex: 0x86EFAC) : OrnamentColor(hex: 0x15803D),
                theme.success.withAlpha(0.35),
                theme.success
            )
        case .warning:
            return (
                theme.warning.withAlpha(dark ? 0.18 : 0.12),
                dark ? OrnamentColor(hex: 0xFCD34D) : OrnamentColor(hex: 0xB45309),
                theme.warning.withAlpha(0.35),
                theme.warning
            )
        case .info:
            return (
                theme.info.withAlpha(dark ? 0.18 : 0.12),
                dark ? OrnamentColor(hex: 0x7DD3FC) : OrnamentColor(hex: 0x0369A1),
                theme.info.withAlpha(0.35),
                theme.info
            )
        }
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        let c = resolveColors(theme)
        var pill = GPUI.div()
            .flex()
            .flexRow()
            .itemsCenter()
            .gap(.pixels(GPUI.px(5.0)))
            .h(GPUI.px(22.0))
            .px(.pixels(GPUI.px(9.0)))
            .roundedFull()
            .bg(c.bg.toGPUIHsla())
            .textSize(.pixels(GPUI.px(11.5)))
            .fontWeight(.semibold)
            .textColor(c.fg.toGPUIHsla())
            .flexShrink0()
        if let b = c.border {
            pill = pill.border1().borderColor(b.toGPUIHsla())
        }
        if dot {
            pill = pill.child(
                GPUI.div()
                    .size(GPUI.px(6.0))
                    .roundedFull()
                    .bg(c.dotColor.toGPUIHsla())
            )
        }
        if let icon {
            pill = pill.child(icon.renderGPUI(sizePx: 11.5, color: c.fg))
        }
        return pill.child(label).intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer _: inout [Rune.El]) -> Rune.El {
        let c = resolveColors(theme)
        let ts = Rune.TextStyle.new(11.5, 600.0).lh(14.0)
        var pill = Rune.row()
            .role("status")
            .label(label)
            .h(22.0)
            .pl(9.0)
            .pr(9.0)
            .gap(5.0)
            .centerY()
            .radius(theme.radii.full)
            .fill(c.bg.toRuneColor())
        if let b = c.border {
            pill = pill.border(1.0, b.toRuneColor())
        }
        if dot {
            pill = pill.child(Rune.el().size(6.0, 6.0).radius(3.0).fill(c.dotColor.toRuneColor()))
        }
        if let icon {
            pill = pill.child(icon.renderRune(sizePx: 11.5, color: c.fg))
        }
        return pill.child(Rune.text(label).font(ts).color(c.fg.toRuneColor()))
    }
}

// MARK: - UIButton & UIIconButton

/// Shadcn-style composable `Button` supporting 7 semantic variants, 5 density sizes, leading/trailing
/// vector icons, and optional trailing shortcut keycaps.
public struct UIButton: GPUAOrnament {
    public var label: String
    public var variant: OrnamentVariant
    public var size: OrnamentSize
    public var icon: OrnamentIcon?
    public var trailingIcon: OrnamentIcon?
    public var shortcut: UIKbd?
    public var disabled: Bool
    public var fullWidth: Bool

    public init(
        _ label: String,
        variant: OrnamentVariant = .primary,
        size: OrnamentSize = .md,
        icon: OrnamentIcon? = nil,
        trailingIcon: OrnamentIcon? = nil,
        shortcut: UIKbd? = nil,
        disabled: Bool = false,
        fullWidth: Bool = false
    ) {
        self.label = label
        self.variant = variant
        self.size = size
        self.icon = icon
        self.trailingIcon = trailingIcon
        self.shortcut = shortcut
        self.disabled = disabled
        self.fullWidth = fullWidth
    }

    fileprivate static func buttonColors(_ variant: OrnamentVariant, _ theme: OrnamentTheme) -> (bg: OrnamentColor, fg: OrnamentColor, border: OrnamentColor?, elevated: Bool, underline: Bool) {
        switch variant {
        case .default, .primary:
            return (theme.primary, theme.primaryForeground, nil, true, false)
        case .secondary:
            return (theme.secondary, theme.secondaryForeground, theme.border.withAlpha(0.5), false, false)
        case .outline:
            return (theme.card, theme.foreground, theme.border, true, false)
        case .ghost:
            return (.transparent, theme.foreground, nil, false, false)
        case .destructive:
            return (theme.destructive, theme.destructiveForeground, nil, true, false)
        case .link:
            return (.transparent, theme.primary, nil, false, true)
        }
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        let skin = Self.buttonColors(variant, theme)
        var btn = GPUI.div()
            .flex()
            .flexRow()
            .itemsCenter()
            .justifyCenter()
            .gap(.pixels(GPUI.px(7.0)))
            .h(GPUI.px(size.heightPx))
            .px(.pixels(GPUI.px(size.horizontalPadPx)))
            .rounded(.pixels(GPUI.px(theme.radii.md)))
            .bg(skin.bg.toGPUIHsla())
            .textSize(.pixels(GPUI.px(size.fontSizePx)))
            .fontWeight(.medium)
            .textColor(skin.fg.toGPUIHsla())
            .flexShrink0()

        if fullWidth {
            btn = btn.wFull()
        }
        if let b = skin.border {
            btn = btn.border1().borderColor(b.toGPUIHsla())
        }
        if skin.elevated {
            btn = btn.shadow(theme.gpuiCardShadows())
        }
        if skin.underline {
            btn = btn.underline()
        }
        if disabled {
            btn = btn.opacity(0.5).cursorNotAllowed()
        } else {
            btn = btn.cursorPointer()
        }
        if let icon {
            btn = btn.child(icon.renderGPUI(sizePx: size.iconSizePx, color: skin.fg))
        }
        btn = btn.child(label)
        if let trailingIcon {
            btn = btn.child(trailingIcon.renderGPUI(sizePx: size.iconSizePx, color: skin.fg.withAlpha(0.85)))
        }
        if let shortcut {
            btn = btn.child(shortcut.renderGPUI(theme: theme))
        }
        return btn.intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer: inout [Rune.El]) -> Rune.El {
        let skin = Self.buttonColors(variant, theme)
        let ts = Rune.TextStyle.new(size.fontSizePx, 500.0).lh(size.fontSizePx + 4.0)
        var btn = Rune.row()
            .role("button")
            .label(label)
            .h(size.heightPx)
            .pl(size.horizontalPadPx)
            .pr(size.horizontalPadPx)
            .gap(7.0)
            .center()
            .radius(theme.radii.md)
            .fill(skin.bg.toRuneColor())
        if fullWidth {
            btn = btn.wFull()
        }
        if let b = skin.border {
            btn = btn.border(1.0, b.toRuneColor())
        }
        if skin.elevated {
            btn = btn.boxShadow(
                Rune.Shadow(
                    x: 0.0,
                    y: 1.5,
                    blur: 4.0,
                    spread: 0.0,
                    color: Rune.Color.BLACK.alpha(theme.appearance.isDark ? 0.35 : 0.08)
                )
            )
        }
        if disabled {
            btn = btn.opacity(0.5)
        }
        if let icon {
            btn = btn.child(icon.renderRune(sizePx: size.iconSizePx, color: skin.fg))
        }
        btn = btn.child(Rune.text(label).font(ts).color(skin.fg.toRuneColor()))
        if let trailingIcon {
            btn = btn.child(trailingIcon.renderRune(sizePx: size.iconSizePx, color: skin.fg.withAlpha(0.85)))
        }
        if let shortcut {
            btn = btn.child(shortcut.renderRune(theme: theme, layer: &layer))
        }
        return btn
    }
}

/// Square Shadcn-style icon button (`UIIconButton(.sparkles, label: "AI Assist")`).
public struct UIIconButton: GPUAOrnament {
    public var icon: OrnamentIcon
    public var label: String
    public var variant: OrnamentVariant
    public var size: OrnamentSize
    public var active: Bool
    public var disabled: Bool

    public init(
        _ icon: OrnamentIcon,
        label: String,
        variant: OrnamentVariant = .ghost,
        size: OrnamentSize = .icon,
        active: Bool = false,
        disabled: Bool = false
    ) {
        self.icon = icon
        self.label = label
        self.variant = variant
        self.size = size
        self.active = active
        self.disabled = disabled
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        let effectiveVariant: OrnamentVariant = active && variant == .ghost ? .secondary : variant
        let skin = UIButton.buttonColors(effectiveVariant, theme)
        let side = size.heightPx
        var box = GPUI.div()
            .flex()
            .itemsCenter()
            .justifyCenter()
            .size(GPUI.px(side))
            .rounded(.pixels(GPUI.px(theme.radii.md)))
            .bg(skin.bg.toGPUIHsla())
            .flexShrink0()
        if let b = skin.border {
            box = box.border1().borderColor(b.toGPUIHsla())
        }
        if disabled {
            box = box.opacity(0.45)
        } else {
            box = box.cursorPointer()
        }
        return box.child(icon.renderGPUI(sizePx: size.iconSizePx, color: skin.fg)).intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer _: inout [Rune.El]) -> Rune.El {
        let effectiveVariant: OrnamentVariant = active && variant == .ghost ? .secondary : variant
        let skin = UIButton.buttonColors(effectiveVariant, theme)
        let side = size.heightPx
        var box = Rune.row()
            .role("button")
            .label(label)
            .size(side, side)
            .center()
            .radius(theme.radii.md)
            .fill(skin.bg.toRuneColor())
        if let b = skin.border {
            box = box.border(1.0, b.toRuneColor())
        }
        if disabled {
            box = box.opacity(0.45)
        }
        return box.child(icon.renderRune(sizePx: size.iconSizePx, color: skin.fg))
    }
}

// MARK: - UICard

/// Shadcn-style `Card` container with header (`badge`, `icon`, `title`, `description`, `headerTrailing`),
/// structured `content` ornaments, and optional `footer` action bar.
public struct UICard: GPUAOrnament {
    public var title: String?
    public var description: String?
    public var icon: OrnamentIcon?
    public var badge: UIBadge?
    public var headerTrailing: AnyOrnament?
    public var children: [AnyOrnament]
    public var footer: [AnyOrnament]
    public var widthPx: Float?

    public init(
        title: String? = nil,
        description: String? = nil,
        icon: OrnamentIcon? = nil,
        badge: UIBadge? = nil,
        headerTrailing: AnyOrnament? = nil,
        children: [AnyOrnament] = [],
        footer: [AnyOrnament] = [],
        widthPx: Float? = nil
    ) {
        self.title = title
        self.description = description
        self.icon = icon
        self.badge = badge
        self.headerTrailing = headerTrailing
        self.children = children
        self.footer = footer
        self.widthPx = widthPx
    }

    public func child<O: GPUAOrnament>(_ item: O) -> UICard {
        var copy = self
        copy.children.append(AnyOrnament(item))
        return copy
    }

    public func footerItem<O: GPUAOrnament>(_ item: O) -> UICard {
        var copy = self
        copy.footer.append(AnyOrnament(item))
        return copy
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        var card = GPUI.div()
            .flex()
            .flexCol()
            .rounded(.pixels(GPUI.px(theme.radii.lg)))
            .bg(theme.card.toGPUIHsla())
            .border1()
            .borderColor(theme.border.toGPUIHsla())
            .shadow(theme.gpuiCardShadows())
            .textColor(theme.cardForeground.toGPUIHsla())
            .overflowHidden()

        if let w = widthPx {
            card = card.w(GPUI.px(w))
        } else {
            card = card.wFull()
        }

        if title != nil || description != nil || badge != nil || headerTrailing != nil {
            var headerCol = GPUI.div().flex().flexCol().gap(.pixels(GPUI.px(4.0))).flex1()
            if let badge {
                headerCol = headerCol.child(
                    GPUI.div().flex().flexRow().mb(.definite(.pixels(GPUI.px(2.0)))).child(badge.renderGPUI(theme: theme))
                )
            }
            if let title {
                var titleRow = GPUI.div().flex().flexRow().itemsCenter().gap(.pixels(GPUI.px(8.0)))
                if let icon {
                    titleRow = titleRow.child(icon.renderGPUI(sizePx: 16.0, color: theme.primary))
                }
                titleRow = titleRow.child(
                    GPUI.div()
                        .textSize(.pixels(GPUI.px(15.5)))
                        .lineHeight(.pixels(GPUI.px(21.0)))
                        .fontWeight(.semibold)
                        .textColor(theme.cardForeground.toGPUIHsla())
                        .child(title)
                )
                headerCol = headerCol.child(titleRow)
            }
            if let description {
                headerCol = headerCol.child(
                    GPUI.div()
                        .textSize(.pixels(GPUI.px(12.5)))
                        .lineHeight(.pixels(GPUI.px(18.0)))
                        .textColor(theme.mutedForeground.toGPUIHsla())
                        .child(description)
                )
            }

            var headerBar = GPUI.div()
                .flex()
                .flexRow()
                .itemsStart()
                .justifyBetween()
                .gap(.pixels(GPUI.px(12.0)))
                .px(.pixels(GPUI.px(18.0)))
                .pt(.pixels(GPUI.px(18.0)))
                .pb(.pixels(GPUI.px(children.isEmpty && footer.isEmpty ? 18.0 : 12.0)))
                .child(headerCol)
            if let trailing = headerTrailing {
                headerBar = headerBar.child(trailing.renderGPUI(theme: theme))
            }
            card = card.child(headerBar)
        }

        if !children.isEmpty {
            var body = GPUI.div()
                .flex()
                .flexCol()
                .gap(.pixels(GPUI.px(12.0)))
                .px(.pixels(GPUI.px(18.0)))
                .pt(.pixels(GPUI.px(title == nil && description == nil ? 18.0 : 4.0)))
                .pb(.pixels(GPUI.px(18.0)))
            for ch in children {
                body = body.child(ch.renderGPUI(theme: theme))
            }
            card = card.child(body)
        }

        if !footer.isEmpty {
            var footerRow = GPUI.div()
                .flex()
                .flexRow()
                .itemsCenter()
                .justifyEnd()
                .gap(.pixels(GPUI.px(8.0)))
                .px(.pixels(GPUI.px(18.0)))
                .py(.pixels(GPUI.px(12.0)))
                .bg(theme.muted.withAlpha(0.45).toGPUIHsla())
                .borderT(.pixels(GPUI.px(1.0)))
                .borderColor(theme.border.toGPUIHsla())
            for f in footer {
                footerRow = footerRow.child(f.renderGPUI(theme: theme))
            }
            card = card.child(footerRow)
        }

        return card.intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer: inout [Rune.El]) -> Rune.El {
        var card = Rune.col()
            .radius(theme.radii.lg)
            .fill(theme.card.toRuneColor())
            .border(1.0, theme.border.toRuneColor())
            .boxShadow(
                Rune.Shadow(
                    x: 0.0,
                    y: 2.0,
                    blur: 8.0,
                    spread: 0.0,
                    color: Rune.Color.BLACK.alpha(theme.appearance.isDark ? 0.38 : 0.07)
                )
            )
            .clip()
        if let w = widthPx {
            card = card.w(w)
        } else {
            card = card.wFull()
        }

        if title != nil || description != nil || badge != nil || headerTrailing != nil {
            var headerCol = Rune.col().gap(4.0).grow(1.0)
            if let badge {
                headerCol = headerCol.child(Rune.row().centerY().child(badge.renderRune(theme: theme, layer: &layer)))
            }
            if let title {
                var titleRow = Rune.row().gap(8.0).centerY()
                if let icon {
                    titleRow = titleRow.child(icon.renderRune(sizePx: 16.0, color: theme.primary))
                }
                titleRow = titleRow.child(
                    Rune.text(title)
                        .font(Rune.TextStyle.new(15.5, 600.0).lh(21.0))
                        .color(theme.cardForeground.toRuneColor())
                )
                headerCol = headerCol.child(titleRow)
            }
            if let description {
                headerCol = headerCol.child(
                    Rune.text(description)
                        .font(Rune.TextStyle.new(12.5, 400.0).lh(18.0))
                        .color(theme.mutedForeground.toRuneColor())
                )
            }
            var headerBar = Rune.row()
                .pl(18.0)
                .pr(18.0)
                .pt(18.0)
                .pb(children.isEmpty && footer.isEmpty ? 18.0 : 12.0)
                .gap(12.0)
                .justifyBetween()
                .child(headerCol)
            if let trailing = headerTrailing {
                headerBar = headerBar.child(trailing.renderRune(theme: theme, layer: &layer))
            }
            card = card.child(headerBar)
        }

        if !children.isEmpty {
            var body = Rune.col()
                .pl(18.0)
                .pr(18.0)
                .pt(title == nil && description == nil ? 18.0 : 4.0)
                .pb(18.0)
                .gap(12.0)
            for ch in children {
                body = body.child(ch.renderRune(theme: theme, layer: &layer))
            }
            card = card.child(body)
        }

        if !footer.isEmpty {
            card = card.child(Rune.el().wFull().h(1.0).fill(theme.border.toRuneColor()))
            var footerRow = Rune.row()
                .wFull()
                .pl(18.0)
                .pr(18.0)
                .pt(12.0)
                .pb(12.0)
                .gap(8.0)
                .justifyEnd()
                .centerY()
                .fill(theme.muted.withAlpha(0.45).toRuneColor())
            for f in footer {
                footerRow = footerRow.child(f.renderRune(theme: theme, layer: &layer))
            }
            card = card.child(footerRow)
        }
        return card
    }
}

// MARK: - UITabs & UISegmented

/// Single tab item inside ``UITabs`` / ``UISegmented``.
public struct UITabItem: Sendable, Equatable, Hashable {
    public var id: String
    public var label: String
    public var icon: OrnamentIcon?
    public var badgeCount: Int?

    public init(id: String, label: String, icon: OrnamentIcon? = nil, badgeCount: Int? = nil) {
        self.id = id
        self.label = label
        self.icon = icon
        self.badgeCount = badgeCount
    }
}

/// Shadcn `Tabs` / segmented control supporting `.segmented` pill tray and `.underline` bar styles.
public struct UITabs: GPUAOrnament {
    public enum Style: String, Sendable, Equatable, Hashable {
        case segmented
        case underline
    }

    public var items: [UITabItem]
    public var activeId: String
    public var style: Style

    public init(items: [UITabItem], activeId: String, style: Style = .segmented) {
        self.items = items
        self.activeId = activeId
        self.style = style
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        switch style {
        case .segmented:
            var tray = GPUI.div()
                .flex()
                .flexRow()
                .itemsCenter()
                .gap(.pixels(GPUI.px(3.0)))
                .p(GPUI.px(4.0))
                .rounded(.pixels(GPUI.px(theme.radii.md)))
                .bg(theme.muted.toGPUIHsla())
                .border1()
                .borderColor(theme.border.withAlpha(0.6).toGPUIHsla())

            for item in items {
                let selected = item.id == activeId
                let fg = selected ? theme.foreground : theme.mutedForeground
                var cell = GPUI.div()
                    .flex()
                    .flexRow()
                    .itemsCenter()
                    .justifyCenter()
                    .gap(.pixels(GPUI.px(6.0)))
                    .h(GPUI.px(28.0))
                    .px(.pixels(GPUI.px(12.0)))
                    .rounded(.pixels(GPUI.px(theme.radii.sm)))
                    .textSize(.pixels(GPUI.px(12.5)))
                    .fontWeight(selected ? .semibold : .medium)
                    .textColor(fg.toGPUIHsla())
                    .cursorPointer()
                if selected {
                    cell = cell
                        .bg(theme.card.toGPUIHsla())
                        .border1()
                        .borderColor(theme.border.toGPUIHsla())
                        .shadow(theme.gpuiCardShadows())
                }
                if let icon = item.icon {
                    cell = cell.child(icon.renderGPUI(sizePx: 13.5, color: fg))
                }
                cell = cell.child(item.label)
                if let count = item.badgeCount {
                    cell = cell.child(
                        GPUI.div()
                            .px(.pixels(GPUI.px(5.5)))
                            .h(GPUI.px(17.0))
                            .flex()
                            .itemsCenter()
                            .roundedFull()
                            .bg(theme.secondary.toGPUIHsla())
                            .textSize(.pixels(GPUI.px(10.5)))
                            .textColor(theme.mutedForeground.toGPUIHsla())
                            .child("\(count)")
                    )
                }
                tray = tray.child(cell)
            }
            return tray.intoAnyElement()

        case .underline:
            var bar = GPUI.div()
                .flex()
                .flexRow()
                .itemsCenter()
                .gap(.pixels(GPUI.px(16.0)))
                .borderB(.pixels(GPUI.px(1.0)))
                .borderColor(theme.border.toGPUIHsla())
            for item in items {
                let selected = item.id == activeId
                let fg = selected ? theme.foreground : theme.mutedForeground
                var cell = GPUI.div()
                    .flex()
                    .flexRow()
                    .itemsCenter()
                    .gap(.pixels(GPUI.px(6.0)))
                    .pb(.pixels(GPUI.px(9.0)))
                    .pt(.pixels(GPUI.px(4.0)))
                    .textSize(.pixels(GPUI.px(13.0)))
                    .fontWeight(selected ? .semibold : .medium)
                    .textColor(fg.toGPUIHsla())
                if selected {
                    cell = cell.borderB(.pixels(GPUI.px(2.0))).borderColor(theme.primary.toGPUIHsla())
                }
                if let icon = item.icon {
                    cell = cell.child(icon.renderGPUI(sizePx: 14.0, color: fg))
                }
                cell = cell.child(item.label)
                bar = bar.child(cell)
            }
            return bar.intoAnyElement()
        }
    }

    public func renderRune(theme: OrnamentTheme, layer _: inout [Rune.El]) -> Rune.El {
        let ts = Rune.TextStyle.new(12.5, 500.0).lh(16.0)
        let tsActive = Rune.TextStyle.new(12.5, 600.0).lh(16.0)
        switch style {
        case .segmented:
            var tray = Rune.row()
                .role("tablist")
                .padding(4.0)
                .gap(3.0)
                .centerY()
                .radius(theme.radii.md)
                .fill(theme.muted.toRuneColor())
                .border(1.0, theme.border.withAlpha(0.6).toRuneColor())
            for item in items {
                let selected = item.id == activeId
                let fg = selected ? theme.foreground : theme.mutedForeground
                var cell = Rune.row()
                    .role("tab")
                    .label(item.label)
                    .h(28.0)
                    .pl(12.0)
                    .pr(12.0)
                    .gap(6.0)
                    .center()
                    .radius(theme.radii.sm)
                if selected {
                    cell = cell
                        .fill(theme.card.toRuneColor())
                        .border(1.0, theme.border.toRuneColor())
                }
                if let icon = item.icon {
                    cell = cell.child(icon.renderRune(sizePx: 13.5, color: fg))
                }
                cell = cell.child(Rune.text(item.label).font(selected ? tsActive : ts).color(fg.toRuneColor()))
                if let count = item.badgeCount {
                    cell = cell.child(
                        Rune.row()
                            .h(17.0)
                            .pl(5.5)
                            .pr(5.5)
                            .center()
                            .radius(theme.radii.full)
                            .fill(theme.secondary.toRuneColor())
                            .child(Rune.text("\(count)").font(Rune.TextStyle.new(10.5, 500.0).lh(13.0)).color(theme.mutedForeground.toRuneColor()))
                    )
                }
                tray = tray.child(cell)
            }
            return tray

        case .underline:
            var bar = Rune.row().role("tablist").gap(16.0).centerY()
            for item in items {
                let selected = item.id == activeId
                let fg = selected ? theme.foreground : theme.mutedForeground
                var colEl = Rune.col().gap(7.0)
                var top = Rune.row().gap(6.0).centerY()
                if let icon = item.icon {
                    top = top.child(icon.renderRune(sizePx: 14.0, color: fg))
                }
                top = top.child(Rune.text(item.label).font(selected ? tsActive : ts).color(fg.toRuneColor()))
                colEl = colEl.child(top)
                colEl = colEl.child(
                    Rune.el()
                        .wFull()
                        .h(2.0)
                        .fill(selected ? theme.primary.toRuneColor() : Rune.Color.TRANSPARENT)
                )
                bar = bar.child(colEl)
            }
            return bar
        }
    }
}

/// Alias matching `RuneKit.Segmented` naming alongside `UITabs`.
public typealias UISegmented = UITabs

// MARK: - UISwitch & UICheckbox

/// Shadcn-style toggle `Switch` with optional label and description.
public struct UISwitch: GPUAOrnament {
    public var checked: Bool
    public var label: String?
    public var description: String?
    public var disabled: Bool

    public init(
        checked: Bool,
        label: String? = nil,
        description: String? = nil,
        disabled: Bool = false
    ) {
        self.checked = checked
        self.label = label
        self.description = description
        self.disabled = disabled
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        let trackBg = checked ? theme.primary : theme.input
        let thumbColor = checked ? theme.primaryForeground : theme.foreground
        let track = GPUI.div()
            .flex()
            .flexRow()
            .itemsCenter()
            .justifyStart()
            .w(GPUI.px(38.0))
            .h(GPUI.px(21.0))
            .p(GPUI.px(2.0))
            .pl(.pixels(GPUI.px(checked ? 19.0 : 2.0)))
            .roundedFull()
            .bg(trackBg.toGPUIHsla())
            .flexShrink0()
            .child(
                GPUI.div()
                    .size(GPUI.px(17.0))
                    .roundedFull()
                    .bg(thumbColor.toGPUIHsla())
                    .shadow(theme.gpuiCardShadows())
            )

        guard label != nil || description != nil else {
            return (disabled ? track.opacity(0.5) : track).intoAnyElement()
        }

        var copyCol = GPUI.div().flex().flexCol().gap(.pixels(GPUI.px(2.0)))
        if let label {
            copyCol = copyCol.child(
                GPUI.div()
                    .textSize(.pixels(GPUI.px(13.0)))
                    .fontWeight(.medium)
                    .textColor(theme.foreground.toGPUIHsla())
                    .child(label)
            )
        }
        if let description {
            copyCol = copyCol.child(
                GPUI.div()
                    .textSize(.pixels(GPUI.px(12.0)))
                    .textColor(theme.mutedForeground.toGPUIHsla())
                    .child(description)
            )
        }

        var row = GPUI.div()
            .flex()
            .flexRow()
            .itemsCenter()
            .justifyBetween()
            .gap(.pixels(GPUI.px(12.0)))
            .child(copyCol)
            .child(track)
        if disabled {
            row = row.opacity(0.5)
        }
        return row.intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer _: inout [Rune.El]) -> Rune.El {
        let trackBg = checked ? theme.primary : theme.input
        let thumbColor = checked ? theme.primaryForeground : theme.foreground
        var track = Rune.row()
            .role("switch")
            .w(38.0)
            .h(21.0)
            .pt(2.0)
            .pb(2.0)
            .pl(checked ? 19.0 : 2.0)
            .pr(2.0)
            .centerY()
            .radius(theme.radii.full)
            .fill(trackBg.toRuneColor())
            .child(
                Rune.el()
                    .size(17.0, 17.0)
                    .radius(theme.radii.full)
                    .fill(thumbColor.toRuneColor())
            )
        if let label {
            track = track.label(label)
        }

        guard label != nil || description != nil else {
            return disabled ? track.opacity(0.5) : track
        }

        var copyCol = Rune.col().gap(2.0).grow(1.0)
        if let label {
            copyCol = copyCol.child(
                Rune.text(label)
                    .font(Rune.TextStyle.new(13.0, 500.0).lh(18.0))
                    .color(theme.foreground.toRuneColor())
            )
        }
        if let description {
            copyCol = copyCol.child(
                Rune.text(description)
                    .font(Rune.TextStyle.new(12.0, 400.0).lh(16.0))
                    .color(theme.mutedForeground.toRuneColor())
            )
        }

        var row = Rune.row()
            .wFull()
            .justifyBetween()
            .centerY()
            .gap(12.0)
            .child(copyCol)
            .child(track)
        if disabled {
            row = row.opacity(0.5)
        }
        return row
    }
}

/// Shadcn-style `Checkbox` supporting `.unchecked`, `.checked`, and `.indeterminate` states.
public struct UICheckbox: GPUAOrnament {
    public var checked: Bool
    public var indeterminate: Bool
    public var label: String?
    public var description: String?
    public var disabled: Bool

    public init(
        checked: Bool,
        indeterminate: Bool = false,
        label: String? = nil,
        description: String? = nil,
        disabled: Bool = false
    ) {
        self.checked = checked
        self.indeterminate = indeterminate
        self.label = label
        self.description = description
        self.disabled = disabled
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        let active = checked || indeterminate
        var box = GPUI.div()
            .flex()
            .itemsCenter()
            .justifyCenter()
            .size(GPUI.px(17.0))
            .rounded(.pixels(GPUI.px(theme.radii.xs)))
            .bg((active ? theme.primary : .transparent).toGPUIHsla())
            .border1()
            .borderColor((active ? theme.primary : theme.input).toGPUIHsla())
            .flexShrink0()
        if indeterminate {
            box = box.child(
                GPUI.div()
                    .w(GPUI.px(9.0))
                    .h(GPUI.px(2.0))
                    .roundedFull()
                    .bg(theme.primaryForeground.toGPUIHsla())
            )
        } else if checked {
            box = box.child(OrnamentIcon.check.renderGPUI(sizePx: 12.0, color: theme.primaryForeground))
        }

        guard label != nil || description != nil else {
            return (disabled ? box.opacity(0.5) : box).intoAnyElement()
        }

        var copyCol = GPUI.div().flex().flexCol().gap(.pixels(GPUI.px(2.0)))
        if let label {
            copyCol = copyCol.child(
                GPUI.div()
                    .textSize(.pixels(GPUI.px(13.0)))
                    .fontWeight(.medium)
                    .textColor(theme.foreground.toGPUIHsla())
                    .child(label)
            )
        }
        if let description {
            copyCol = copyCol.child(
                GPUI.div()
                    .textSize(.pixels(GPUI.px(12.0)))
                    .textColor(theme.mutedForeground.toGPUIHsla())
                    .child(description)
            )
        }

        var row = GPUI.div()
            .flex()
            .flexRow()
            .itemsStart()
            .gap(.pixels(GPUI.px(10.0)))
            .child(box)
            .child(copyCol)
        if disabled {
            row = row.opacity(0.5)
        }
        return row.intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer _: inout [Rune.El]) -> Rune.El {
        let active = checked || indeterminate
        var box = Rune.row()
            .role("checkbox")
            .size(17.0, 17.0)
            .center()
            .radius(theme.radii.xs)
            .fill((active ? theme.primary : .transparent).toRuneColor())
            .border(1.0, (active ? theme.primary : theme.input).toRuneColor())
        if indeterminate {
            box = box.child(Rune.el().size(9.0, 2.0).radius(1.0).fill(theme.primaryForeground.toRuneColor()))
        } else if checked {
            box = box.child(OrnamentIcon.check.renderRune(sizePx: 12.0, color: theme.primaryForeground))
        }
        guard label != nil || description != nil else {
            return disabled ? box.opacity(0.5) : box
        }
        var copyCol = Rune.col().gap(2.0)
        if let label {
            copyCol = copyCol.child(
                Rune.text(label)
                    .font(Rune.TextStyle.new(13.0, 500.0).lh(17.0))
                    .color(theme.foreground.toRuneColor())
            )
        }
        if let description {
            copyCol = copyCol.child(
                Rune.text(description)
                    .font(Rune.TextStyle.new(12.0, 400.0).lh(16.0))
                    .color(theme.mutedForeground.toRuneColor())
            )
        }
        let row = Rune.row().gap(10.0).child(box).child(copyCol)
        return disabled ? row.opacity(0.5) : row
    }
}

// MARK: - UIInput

/// Shadcn-style text `Input` field with optional label, leading/trailing icons, shortcut hint,
/// focus ring, and validation state.
public struct UIInput: GPUAOrnament {
    public var value: String
    public var placeholder: String
    public var label: String?
    public var helperText: String?
    public var leadingIcon: OrnamentIcon?
    public var trailingShortcut: UIKbd?
    public var focused: Bool
    public var invalid: Bool
    public var disabled: Bool

    public init(
        value: String = "",
        placeholder: String = "",
        label: String? = nil,
        helperText: String? = nil,
        leadingIcon: OrnamentIcon? = nil,
        trailingShortcut: UIKbd? = nil,
        focused: Bool = false,
        invalid: Bool = false,
        disabled: Bool = false
    ) {
        self.value = value
        self.placeholder = placeholder
        self.label = label
        self.helperText = helperText
        self.leadingIcon = leadingIcon
        self.trailingShortcut = trailingShortcut
        self.focused = focused
        self.invalid = invalid
        self.disabled = disabled
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        let isEmpty = value.isEmpty
        let displayStr = isEmpty ? placeholder : value
        let textColor = isEmpty ? theme.mutedForeground : theme.foreground
        let borderColor: OrnamentColor = invalid
            ? theme.destructive
            : (focused ? theme.ring : theme.input)

        var field = GPUI.div()
            .flex()
            .flexRow()
            .itemsCenter()
            .gap(.pixels(GPUI.px(8.0)))
            .h(GPUI.px(36.0))
            .wFull()
            .px(.pixels(GPUI.px(11.0)))
            .rounded(.pixels(GPUI.px(theme.radii.md)))
            .bg(theme.background.mixed(with: theme.card, 0.5).toGPUIHsla())
            .border(.pixels(GPUI.px(focused ? 1.5 : 1.0)))
            .borderColor(borderColor.toGPUIHsla())

        if let leadingIcon {
            field = field.child(leadingIcon.renderGPUI(sizePx: 14.5, color: theme.mutedForeground))
        }
        field = field.child(
            GPUI.div()
                .flex1()
                .textSize(.pixels(GPUI.px(13.0)))
                .textColor(textColor.toGPUIHsla())
                .truncate()
                .child(displayStr)
        )
        if let trailingShortcut {
            field = field.child(trailingShortcut.renderGPUI(theme: theme))
        }
        if disabled {
            field = field.opacity(0.5)
        }

        guard label != nil || helperText != nil else {
            return field.intoAnyElement()
        }

        var stack = GPUI.div().flex().flexCol().gap(.pixels(GPUI.px(6.0))).wFull()
        if let label {
            stack = stack.child(
                GPUI.div()
                    .textSize(.pixels(GPUI.px(12.5)))
                    .fontWeight(.medium)
                    .textColor(theme.foreground.toGPUIHsla())
                    .child(label)
            )
        }
        stack = stack.child(field)
        if let helperText {
            let helperColor = invalid ? theme.destructive : theme.mutedForeground
            stack = stack.child(
                GPUI.div()
                    .textSize(.pixels(GPUI.px(11.5)))
                    .textColor(helperColor.toGPUIHsla())
                    .child(helperText)
            )
        }
        return stack.intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer: inout [Rune.El]) -> Rune.El {
        let isEmpty = value.isEmpty
        let displayStr = isEmpty ? placeholder : value
        let textColor = isEmpty ? theme.mutedForeground : theme.foreground
        let borderColor: OrnamentColor = invalid
            ? theme.destructive
            : (focused ? theme.ring : theme.input)

        var field = Rune.row()
            .role("textbox")
            .h(36.0)
            .wFull()
            .pl(11.0)
            .pr(11.0)
            .gap(8.0)
            .centerY()
            .radius(theme.radii.md)
            .fill(theme.background.mixed(with: theme.card, 0.5).toRuneColor())
            .border(focused ? 1.5 : 1.0, borderColor.toRuneColor())

        if let leadingIcon {
            field = field.child(leadingIcon.renderRune(sizePx: 14.5, color: theme.mutedForeground))
        }
        field = field.child(
            Rune.el()
                .grow(1.0)
                .shrink()
                .child(
                    Rune.text(displayStr)
                        .font(Rune.TextStyle.new(13.0, 400.0).lh(18.0))
                        .color(textColor.toRuneColor())
                )
        )
        if let trailingShortcut {
            field = field.child(trailingShortcut.renderRune(theme: theme, layer: &layer))
        }
        if disabled {
            field = field.opacity(0.5)
        }

        guard label != nil || helperText != nil else {
            return field
        }

        var stack = Rune.col().wFull().gap(6.0)
        if let label {
            stack = stack.child(
                Rune.text(label)
                    .font(Rune.TextStyle.new(12.5, 500.0).lh(16.0))
                    .color(theme.foreground.toRuneColor())
            )
        }
        stack = stack.child(field)
        if let helperText {
            let helperColor = invalid ? theme.destructive : theme.mutedForeground
            stack = stack.child(
                Rune.text(helperText)
                    .font(Rune.TextStyle.new(11.5, 400.0).lh(15.0))
                    .color(helperColor.toRuneColor())
            )
        }
        return stack
    }
}
