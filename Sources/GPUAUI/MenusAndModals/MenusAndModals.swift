// Swift-only: Unified Shadcn-style UI ornaments across GPUI and Rune (ADR-0015).

import GPUI
import Rune
import RuneKit

@inline(__always)
private func containsSubsequenceCaseInsensitive(_ haystack: String, _ needle: String) -> Bool {
    if needle.isEmpty { return true }
    let h = Array(haystack.lowercased().utf8)
    let n = Array(needle.lowercased().utf8)
    guard n.count <= h.count else { return false }
    let limit = h.count - n.count
    for start in 0...limit {
        var matched = true
        for j in 0..<n.count where h[start + j] != n[j] {
            matched = false
            break
        }
        if matched { return true }
    }
    return false
}

// MARK: - UIDropdownMenu & UIContextMenu

/// Entry inside ``UIDropdownMenu`` or ``UIContextMenu``.
public enum UIMenuEntry: Sendable, Equatable, Hashable {
    case label(String)
    case item(
        title: String,
        icon: OrnamentIcon? = nil,
        shortcut: String? = nil,
        checked: Bool = false,
        highlighted: Bool = false,
        destructive: Bool = false,
        disabled: Bool = false
    )
    case separator
}

/// Shared menu panel renderer used by both ``UIDropdownMenu`` and ``UIContextMenu``.
private enum MenuSurfaceRenderer {
    static func renderGPUI(entries: [UIMenuEntry], widthPx: Float, theme: OrnamentTheme) -> GPUI.AnyElement {
        var menu = GPUI.div()
            .flex()
            .flexCol()
            .gap(.pixels(GPUI.px(2.0)))
            .w(GPUI.px(widthPx))
            .p(GPUI.px(5.0))
            .rounded(.pixels(GPUI.px(theme.radii.md)))
            .bg(theme.popover.toGPUIHsla())
            .border1()
            .borderColor(theme.border.toGPUIHsla())
            .shadow(theme.gpuiPopoverShadows())

        for entry in entries {
            switch entry {
            case .label(let heading):
                menu = menu.child(
                    GPUI.div()
                        .px(.pixels(GPUI.px(9.0)))
                        .py(.pixels(GPUI.px(5.0)))
                        .textSize(.pixels(GPUI.px(11.5)))
                        .fontWeight(.semibold)
                        .textColor(theme.mutedForeground.toGPUIHsla())
                        .child(heading)
                )
            case .separator:
                menu = menu.child(
                    GPUI.div()
                        .wFull()
                        .h(GPUI.px(1.0))
                        .my(.definite(.pixels(GPUI.px(3.0))))
                        .bg(theme.border.toGPUIHsla())
                )
            case let .item(title, icon, shortcut, checked, highlighted, destructive, disabled):
                let fg: OrnamentColor = destructive ? theme.destructive : (highlighted ? theme.accentForeground : theme.popoverForeground)
                let rowBg: OrnamentColor = highlighted
                    ? (destructive ? theme.destructive.withAlpha(0.14) : theme.accent)
                    : .transparent

                var left = GPUI.div().flex().flexRow().itemsCenter().gap(.pixels(GPUI.px(8.0))).flex1()
                if checked {
                    left = left.child(OrnamentIcon.check.renderGPUI(sizePx: 13.5, color: fg))
                } else if let icon {
                    left = left.child(icon.renderGPUI(sizePx: 14.0, color: destructive ? fg : theme.mutedForeground))
                }
                left = left.child(
                    GPUI.div()
                        .textSize(.pixels(GPUI.px(12.5)))
                        .fontWeight(highlighted ? .medium : .normal)
                        .textColor(fg.toGPUIHsla())
                        .child(title)
                )

                var row = GPUI.div()
                    .flex()
                    .flexRow()
                    .itemsCenter()
                    .justifyBetween()
                    .gap(.pixels(GPUI.px(12.0)))
                    .h(GPUI.px(30.0))
                    .px(.pixels(GPUI.px(9.0)))
                    .rounded(.pixels(GPUI.px(theme.radii.sm)))
                    .bg(rowBg.toGPUIHsla())
                    .child(left)

                if let shortcut {
                    row = row.child(
                        GPUI.div()
                            .fontFamily(GPUI.SharedString(theme.fontMono))
                            .textSize(.pixels(GPUI.px(11.0)))
                            .textColor(theme.mutedForeground.toGPUIHsla())
                            .child(shortcut)
                    )
                }
                if disabled {
                    row = row.opacity(0.45)
                } else {
                    row = row.cursorPointer()
                }
                menu = menu.child(row)
            }
        }
        return menu.intoAnyElement()
    }

    static func renderRune(entries: [UIMenuEntry], widthPx: Float, theme: OrnamentTheme) -> Rune.El {
        var menu = Rune.col()
            .role("menu")
            .w(widthPx)
            .padding(5.0)
            .gap(2.0)
            .radius(theme.radii.md)
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

        for entry in entries {
            switch entry {
            case .label(let heading):
                menu = menu.child(
                    Rune.row()
                        .pl(9.0)
                        .pr(9.0)
                        .pt(5.0)
                        .pb(5.0)
                        .child(
                            Rune.text(heading)
                                .font(Rune.TextStyle.new(11.5, 600.0).lh(15.0))
                                .color(theme.mutedForeground.toRuneColor())
                        )
                )
            case .separator:
                menu = menu.child(
                    Rune.el().wFull().h(1.0).mt(3.0).mb(3.0).fill(theme.border.toRuneColor())
                )
            case let .item(title, icon, shortcut, checked, highlighted, destructive, disabled):
                let fg: OrnamentColor = destructive ? theme.destructive : (highlighted ? theme.accentForeground : theme.popoverForeground)
                let rowBg: OrnamentColor = highlighted
                    ? (destructive ? theme.destructive.withAlpha(0.14) : theme.accent)
                    : .transparent

                var left = Rune.row().gap(8.0).centerY().grow(1.0)
                if checked {
                    left = left.child(OrnamentIcon.check.renderRune(sizePx: 13.5, color: fg))
                } else if let icon {
                    left = left.child(icon.renderRune(sizePx: 14.0, color: destructive ? fg : theme.mutedForeground))
                }
                left = left.child(
                    Rune.text(title)
                        .font(Rune.TextStyle.new(12.5, highlighted ? 500.0 : 400.0).lh(17.0))
                        .color(fg.toRuneColor())
                )

                var row = Rune.row()
                    .role("menuitem")
                    .label(title)
                    .wFull()
                    .h(30.0)
                    .pl(9.0)
                    .pr(9.0)
                    .gap(12.0)
                    .justifyBetween()
                    .centerY()
                    .radius(theme.radii.sm)
                    .fill(rowBg.toRuneColor())
                    .child(left)

                if let shortcut {
                    row = row.child(
                        Rune.text(shortcut)
                            .font(Rune.TextStyle.new(11.0, 400.0).lh(14.0).mono())
                            .color(theme.mutedForeground.toRuneColor())
                    )
                }
                if disabled {
                    row = row.opacity(0.45)
                }
                menu = menu.child(row)
            }
        }
        return menu
    }
}

/// Shadcn `DropdownMenu` anchored below a trigger control.
public struct UIDropdownMenu: GPUAOrnament {
    public var trigger: AnyOrnament
    public var entries: [UIMenuEntry]
    public var isOpen: Bool
    public var widthPx: Float

    public init<T: GPUAOrnament>(
        trigger: T,
        entries: [UIMenuEntry],
        isOpen: Bool = true,
        widthPx: Float = 224.0
    ) {
        self.trigger = AnyOrnament(trigger)
        self.entries = entries
        self.isOpen = isOpen
        self.widthPx = widthPx
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        var col = GPUI.div().flex().flexCol().itemsStart().gap(.pixels(GPUI.px(6.0)))
            .child(trigger.renderGPUI(theme: theme))
        if isOpen {
            col = col.child(MenuSurfaceRenderer.renderGPUI(entries: entries, widthPx: widthPx, theme: theme))
        }
        return col.intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer: inout [Rune.El]) -> Rune.El {
        let trig = trigger.renderRune(theme: theme, layer: &layer)
        guard isOpen else { return trig }
        return Rune.col()
            .gap(6.0)
            .child(trig)
            .child(MenuSurfaceRenderer.renderRune(entries: entries, widthPx: widthPx, theme: theme))
    }
}

/// Shadcn `ContextMenu` wrapping a target region with an opened right-click menu surface.
public struct UIContextMenu: GPUAOrnament {
    public var target: AnyOrnament
    public var entries: [UIMenuEntry]
    public var isOpen: Bool
    public var widthPx: Float

    public init<T: GPUAOrnament>(
        target: T,
        entries: [UIMenuEntry],
        isOpen: Bool = true,
        widthPx: Float = 224.0
    ) {
        self.target = AnyOrnament(target)
        self.entries = entries
        self.isOpen = isOpen
        self.widthPx = widthPx
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        var wrap = GPUI.div().relative().flex().flexCol().itemsStart().gap(.pixels(GPUI.px(8.0)))
            .child(target.renderGPUI(theme: theme))
        if isOpen {
            wrap = wrap.child(MenuSurfaceRenderer.renderGPUI(entries: entries, widthPx: widthPx, theme: theme))
        }
        return wrap.intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer: inout [Rune.El]) -> Rune.El {
        let tgt = target.renderRune(theme: theme, layer: &layer)
        guard isOpen else { return tgt }
        return Rune.col()
            .gap(8.0)
            .child(tgt)
            .child(MenuSurfaceRenderer.renderRune(entries: entries, widthPx: widthPx, theme: theme))
    }
}

// MARK: - UICommandPalette (⌘K Spotlight Modal)

/// Single command entry inside ``UICommandGroup``.
public struct UICommandItem: Sendable, Equatable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var icon: OrnamentIcon
    public var shortcut: [String]

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        icon: OrnamentIcon = .sparkles,
        shortcut: [String] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.shortcut = shortcut
    }
}

/// Named section inside ``UICommandPalette``.
public struct UICommandGroup: Sendable, Equatable, Hashable {
    public var heading: String
    public var items: [UICommandItem]

    public init(heading: String, items: [UICommandItem]) {
        self.heading = heading
        self.items = items
    }
}

/// Shadcn `CommandDialog` / `⌘K` spotlight palette with live query filtering, grouped items,
/// highlighted active row, shortcut keycaps, and footer navigation legend.
public struct UICommandPalette: GPUAOrnament {
    public var query: String
    public var placeholder: String
    public var groups: [UICommandGroup]
    public var selectedId: String?
    public var widthPx: Float

    public init(
        query: String = "",
        placeholder: String = "Type a command or search...",
        groups: [UICommandGroup],
        selectedId: String? = nil,
        widthPx: Float = 480.0
    ) {
        self.query = query
        self.placeholder = placeholder
        self.groups = groups
        self.selectedId = selectedId
        self.widthPx = widthPx
    }

    /// Groups filtered by `query` (matches `title`, `subtitle`, or `heading`).
    public func filteredGroups() -> [UICommandGroup] {
        guard !query.isEmpty else { return groups }
        var out: [UICommandGroup] = []
        for g in groups {
            let matching = g.items.filter { item in
                containsSubsequenceCaseInsensitive(item.title, query)
                    || (item.subtitle.map { containsSubsequenceCaseInsensitive($0, query) } ?? false)
                    || containsSubsequenceCaseInsensitive(g.heading, query)
            }
            if !matching.isEmpty {
                out.append(UICommandGroup(heading: g.heading, items: matching))
            }
        }
        return out
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        let visibleGroups = filteredGroups()
        let activeId = selectedId ?? visibleGroups.first?.items.first?.id

        let searchBar = GPUI.div()
            .flex()
            .flexRow()
            .itemsCenter()
            .justifyBetween()
            .gap(.pixels(GPUI.px(10.0)))
            .h(GPUI.px(44.0))
            .px(.pixels(GPUI.px(14.0)))
            .borderB(.pixels(GPUI.px(1.0)))
            .borderColor(theme.border.toGPUIHsla())
            .child(
                GPUI.div()
                    .flex()
                    .flexRow()
                    .itemsCenter()
                    .gap(.pixels(GPUI.px(10.0)))
                    .flex1()
                    .child(OrnamentIcon.search.renderGPUI(sizePx: 15.5, color: theme.mutedForeground))
                    .child(
                        GPUI.div()
                            .textSize(.pixels(GPUI.px(13.5)))
                            .textColor((query.isEmpty ? theme.mutedForeground : theme.popoverForeground).toGPUIHsla())
                            .child(query.isEmpty ? placeholder : query)
                    )
            )
            .child(UIKbd(["ESC"], compact: true).renderGPUI(theme: theme))

        var body = GPUI.div()
            .flex()
            .flexCol()
            .gap(.pixels(GPUI.px(6.0)))
            .p(GPUI.px(6.0))

        if visibleGroups.isEmpty {
            body = body.child(
                GPUI.div()
                    .flex()
                    .itemsCenter()
                    .justifyCenter()
                    .py(.pixels(GPUI.px(24.0)))
                    .textSize(.pixels(GPUI.px(13.0)))
                    .textColor(theme.mutedForeground.toGPUIHsla())
                    .child("No commands matching \"\(query)\".")
            )
        } else {
            for (gIdx, g) in visibleGroups.enumerated() {
                if gIdx > 0 {
                    body = body.child(
                        GPUI.div().wFull().h(GPUI.px(1.0)).my(.definite(.pixels(GPUI.px(2.0)))).bg(theme.border.toGPUIHsla())
                    )
                }
                var groupCol = GPUI.div().flex().flexCol().gap(.pixels(GPUI.px(2.0)))
                    .child(
                        GPUI.div()
                            .px(.pixels(GPUI.px(10.0)))
                            .py(.pixels(GPUI.px(4.0)))
                            .textSize(.pixels(GPUI.px(11.0)))
                            .fontWeight(.semibold)
                            .textColor(theme.mutedForeground.toGPUIHsla())
                            .child(g.heading)
                    )
                for item in g.items {
                    let isSelected = item.id == activeId
                    let fg = isSelected ? theme.accentForeground : theme.popoverForeground
                    let rowBg = isSelected ? theme.accent : .transparent

                    var left = GPUI.div().flex().flexRow().itemsCenter().gap(.pixels(GPUI.px(10.0))).flex1()
                        .child(item.icon.renderGPUI(sizePx: 15.0, color: isSelected ? theme.primary : theme.mutedForeground))
                        .child(
                            GPUI.div()
                                .textSize(.pixels(GPUI.px(13.0)))
                                .fontWeight(isSelected ? .medium : .normal)
                                .textColor(fg.toGPUIHsla())
                                .child(item.title)
                        )
                    if let sub = item.subtitle {
                        left = left.child(
                            GPUI.div()
                                .textSize(.pixels(GPUI.px(11.5)))
                                .textColor(theme.mutedForeground.toGPUIHsla())
                                .child(sub)
                        )
                    }

                    var row = GPUI.div()
                        .flex()
                        .flexRow()
                        .itemsCenter()
                        .justifyBetween()
                        .gap(.pixels(GPUI.px(10.0)))
                        .h(GPUI.px(34.0))
                        .px(.pixels(GPUI.px(10.0)))
                        .rounded(.pixels(GPUI.px(theme.radii.sm)))
                        .bg(rowBg.toGPUIHsla())
                        .cursorPointer()
                        .child(left)
                    if !item.shortcut.isEmpty {
                        row = row.child(UIKbd(item.shortcut, compact: true).renderGPUI(theme: theme))
                    }
                    groupCol = groupCol.child(row)
                }
                body = body.child(groupCol)
            }
        }

        let footer = GPUI.div()
            .flex()
            .flexRow()
            .itemsCenter()
            .justifyBetween()
            .px(.pixels(GPUI.px(14.0)))
            .py(.pixels(GPUI.px(8.0)))
            .bg(theme.muted.withAlpha(0.55).toGPUIHsla())
            .borderT(.pixels(GPUI.px(1.0)))
            .borderColor(theme.border.toGPUIHsla())
            .child(
                GPUI.div().flex().flexRow().itemsCenter().gap(.pixels(GPUI.px(10.0)))
                    .child(UIKbd(["↑", "↓"], compact: true).renderGPUI(theme: theme))
                    .child(
                        GPUI.div()
                            .textSize(.pixels(GPUI.px(11.5)))
                            .textColor(theme.mutedForeground.toGPUIHsla())
                            .child("Navigate")
                    )
                    .child(UIKbd(["↵"], compact: true).renderGPUI(theme: theme))
                    .child(
                        GPUI.div()
                            .textSize(.pixels(GPUI.px(11.5)))
                            .textColor(theme.mutedForeground.toGPUIHsla())
                            .child("Run")
                    )
            )
            .child(
                GPUI.div()
                    .textSize(.pixels(GPUI.px(11.0)))
                    .fontWeight(.medium)
                    .textColor(theme.mutedForeground.toGPUIHsla())
                    .child("GPUAUI Command")
            )

        return GPUI.div()
            .flex()
            .flexCol()
            .w(GPUI.px(widthPx))
            .rounded(.pixels(GPUI.px(theme.radii.lg)))
            .bg(theme.popover.toGPUIHsla())
            .border1()
            .borderColor(theme.border.toGPUIHsla())
            .shadow(theme.gpuiModalShadows())
            .overflowHidden()
            .child(searchBar)
            .child(body)
            .child(footer)
            .intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer: inout [Rune.El]) -> Rune.El {
        let visibleGroups = filteredGroups()
        let activeId = selectedId ?? visibleGroups.first?.items.first?.id

        let searchBar = Rune.row()
            .wFull()
            .h(44.0)
            .pl(14.0)
            .pr(14.0)
            .gap(10.0)
            .justifyBetween()
            .centerY()
            .child(
                Rune.row().gap(10.0).centerY().grow(1.0)
                    .child(OrnamentIcon.search.renderRune(sizePx: 15.5, color: theme.mutedForeground))
                    .child(
                        Rune.text(query.isEmpty ? placeholder : query)
                            .font(Rune.TextStyle.new(13.5, 400.0).lh(18.0))
                            .color((query.isEmpty ? theme.mutedForeground : theme.popoverForeground).toRuneColor())
                    )
            )
            .child(UIKbd(["ESC"], compact: true).renderRune(theme: theme, layer: &layer))

        var body = Rune.col().wFull().padding(6.0).gap(6.0)
        if visibleGroups.isEmpty {
            body = body.child(
                Rune.row()
                    .wFull()
                    .pt(24.0)
                    .pb(24.0)
                    .center()
                    .child(
                        Rune.text("No commands matching \"\(query)\".")
                            .font(Rune.TextStyle.new(13.0, 400.0).lh(18.0))
                            .color(theme.mutedForeground.toRuneColor())
                    )
            )
        } else {
            for (gIdx, g) in visibleGroups.enumerated() {
                if gIdx > 0 {
                    body = body.child(Rune.el().wFull().h(1.0).fill(theme.border.toRuneColor()))
                }
                var groupCol = Rune.col().wFull().gap(2.0)
                    .child(
                        Rune.row().pl(10.0).pr(10.0).pt(4.0).pb(4.0).child(
                            Rune.text(g.heading)
                                .font(Rune.TextStyle.new(11.0, 600.0).lh(14.0))
                                .color(theme.mutedForeground.toRuneColor())
                        )
                    )
                for item in g.items {
                    let isSelected = item.id == activeId
                    let fg = isSelected ? theme.accentForeground : theme.popoverForeground
                    let rowBg = isSelected ? theme.accent : .transparent

                    var left = Rune.row().gap(10.0).centerY().grow(1.0)
                        .child(item.icon.renderRune(sizePx: 15.0, color: isSelected ? theme.primary : theme.mutedForeground))
                        .child(
                            Rune.text(item.title)
                                .font(Rune.TextStyle.new(13.0, isSelected ? 500.0 : 400.0).lh(17.0))
                                .color(fg.toRuneColor())
                        )
                    if let sub = item.subtitle {
                        left = left.child(
                            Rune.text(sub)
                                .font(Rune.TextStyle.new(11.5, 400.0).lh(15.0))
                                .color(theme.mutedForeground.toRuneColor())
                        )
                    }

                    var row = Rune.row()
                        .role("option")
                        .label(item.title)
                        .wFull()
                        .h(34.0)
                        .pl(10.0)
                        .pr(10.0)
                        .gap(10.0)
                        .justifyBetween()
                        .centerY()
                        .radius(theme.radii.sm)
                        .fill(rowBg.toRuneColor())
                        .child(left)
                    if !item.shortcut.isEmpty {
                        row = row.child(UIKbd(item.shortcut, compact: true).renderRune(theme: theme, layer: &layer))
                    }
                    groupCol = groupCol.child(row)
                }
                body = body.child(groupCol)
            }
        }

        let footer = Rune.row()
            .wFull()
            .pl(14.0)
            .pr(14.0)
            .pt(8.0)
            .pb(8.0)
            .justifyBetween()
            .centerY()
            .fill(theme.muted.withAlpha(0.55).toRuneColor())
            .child(
                Rune.row().gap(8.0).centerY()
                    .child(UIKbd(["↑", "↓"], compact: true).renderRune(theme: theme, layer: &layer))
                    .child(Rune.text("Navigate").font(Rune.TextStyle.new(11.5, 400.0).lh(15.0)).color(theme.mutedForeground.toRuneColor()))
                    .child(UIKbd(["↵"], compact: true).renderRune(theme: theme, layer: &layer))
                    .child(Rune.text("Run").font(Rune.TextStyle.new(11.5, 400.0).lh(15.0)).color(theme.mutedForeground.toRuneColor()))
            )
            .child(Rune.text("GPUAUI Command").font(Rune.TextStyle.new(11.0, 500.0).lh(14.0)).color(theme.mutedForeground.toRuneColor()))

        return Rune.col()
            .role("dialog")
            .w(widthPx)
            .radius(theme.radii.lg)
            .fill(theme.popover.toRuneColor())
            .border(1.0, theme.border.toRuneColor())
            .boxShadow(
                Rune.Shadow(
                    x: 0.0,
                    y: 20.0,
                    blur: 44.0,
                    spread: -8.0,
                    color: Rune.Color.BLACK.alpha(theme.appearance.isDark ? 0.68 : 0.20)
                )
            )
            .clip()
            .child(searchBar)
            .child(Rune.el().wFull().h(1.0).fill(theme.border.toRuneColor()))
            .child(body)
            .child(Rune.el().wFull().h(1.0).fill(theme.border.toRuneColor()))
            .child(footer)
    }
}

// MARK: - UIDialog & UISheet

/// Shadcn `Dialog` modal card with optional backdrop scrim, header, body, and action footer.
public struct UIDialog: GPUAOrnament {
    public var title: String
    public var description: String?
    public var icon: OrnamentIcon?
    public var body: [AnyOrnament]
    public var cancelLabel: String?
    public var confirmLabel: String
    public var destructive: Bool
    public var showScrim: Bool
    public var widthPx: Float

    public init(
        title: String,
        description: String? = nil,
        icon: OrnamentIcon? = nil,
        body: [AnyOrnament] = [],
        cancelLabel: String? = "Cancel",
        confirmLabel: String = "Confirm",
        destructive: Bool = false,
        showScrim: Bool = false,
        widthPx: Float = 420.0
    ) {
        self.title = title
        self.description = description
        self.icon = icon
        self.body = body
        self.cancelLabel = cancelLabel
        self.confirmLabel = confirmLabel
        self.destructive = destructive
        self.showScrim = showScrim
        self.widthPx = widthPx
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        var headerTop = GPUI.div().flex().flexRow().itemsCenter().justifyBetween()
        var titleRow = GPUI.div().flex().flexRow().itemsCenter().gap(.pixels(GPUI.px(9.0)))
        if let icon {
            let tint = destructive ? theme.destructive : theme.primary
            titleRow = titleRow.child(
                GPUI.div()
                    .flex()
                    .itemsCenter()
                    .justifyCenter()
                    .size(GPUI.px(28.0))
                    .roundedFull()
                    .bg(tint.withAlpha(0.16).toGPUIHsla())
                    .child(icon.renderGPUI(sizePx: 14.5, color: tint))
            )
        }
        titleRow = titleRow.child(
            GPUI.div()
                .textSize(.pixels(GPUI.px(16.0)))
                .fontWeight(.semibold)
                .textColor(theme.popoverForeground.toGPUIHsla())
                .child(title)
        )
        headerTop = headerTop
            .child(titleRow)
            .child(UIIconButton(.x, label: "Close", variant: .ghost, size: .xs).renderGPUI(theme: theme))

        var modal = GPUI.div()
            .flex()
            .flexCol()
            .gap(.pixels(GPUI.px(14.0)))
            .w(GPUI.px(widthPx))
            .p(GPUI.px(20.0))
            .rounded(.pixels(GPUI.px(theme.radii.lg)))
            .bg(theme.popover.toGPUIHsla())
            .border1()
            .borderColor(theme.border.toGPUIHsla())
            .shadow(theme.gpuiModalShadows())
            .child(headerTop)

        if let description {
            modal = modal.child(
                GPUI.div()
                    .textSize(.pixels(GPUI.px(13.0)))
                    .lineHeight(.pixels(GPUI.px(18.5)))
                    .textColor(theme.mutedForeground.toGPUIHsla())
                    .child(description)
            )
        }
        for item in body {
            modal = modal.child(item.renderGPUI(theme: theme))
        }

        var actions = GPUI.div().flex().flexRow().itemsCenter().justifyEnd().gap(.pixels(GPUI.px(8.0))).pt(.pixels(GPUI.px(4.0)))
        if let cancelLabel {
            actions = actions.child(UIButton(cancelLabel, variant: .outline, size: .sm).renderGPUI(theme: theme))
        }
        actions = actions.child(
            UIButton(
                confirmLabel,
                variant: destructive ? .destructive : .primary,
                size: .sm
            ).renderGPUI(theme: theme)
        )
        modal = modal.child(actions)

        guard showScrim else { return modal.intoAnyElement() }
        return GPUI.div()
            .flex()
            .itemsCenter()
            .justifyCenter()
            .sizeFull()
            .p(GPUI.px(24.0))
            .bg(OrnamentColor.black.withAlpha(0.55).toGPUIHsla())
            .child(modal)
            .intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer: inout [Rune.El]) -> Rune.El {
        var titleRow = Rune.row().gap(9.0).centerY()
        if let icon {
            let tint = destructive ? theme.destructive : theme.primary
            titleRow = titleRow.child(
                Rune.row()
                    .size(28.0, 28.0)
                    .center()
                    .radius(14.0)
                    .fill(tint.withAlpha(0.16).toRuneColor())
                    .child(icon.renderRune(sizePx: 14.5, color: tint))
            )
        }
        titleRow = titleRow.child(
            Rune.text(title)
                .font(Rune.TextStyle.new(16.0, 600.0).lh(21.0))
                .color(theme.popoverForeground.toRuneColor())
        )
        let headerTop = Rune.row()
            .wFull()
            .justifyBetween()
            .centerY()
            .child(titleRow)
            .child(UIIconButton(.x, label: "Close", variant: .ghost, size: .xs).renderRune(theme: theme, layer: &layer))

        var modal = Rune.col()
            .role("dialog")
            .w(widthPx)
            .padding(20.0)
            .gap(14.0)
            .radius(theme.radii.lg)
            .fill(theme.popover.toRuneColor())
            .border(1.0, theme.border.toRuneColor())
            .boxShadow(
                Rune.Shadow(
                    x: 0.0,
                    y: 20.0,
                    blur: 44.0,
                    spread: -8.0,
                    color: Rune.Color.BLACK.alpha(theme.appearance.isDark ? 0.68 : 0.20)
                )
            )
            .child(headerTop)

        if let description {
            modal = modal.child(
                Rune.text(description)
                    .font(Rune.TextStyle.new(13.0, 400.0).lh(18.5))
                    .color(theme.mutedForeground.toRuneColor())
            )
        }
        for item in body {
            modal = modal.child(item.renderRune(theme: theme, layer: &layer))
        }

        var actions = Rune.row().wFull().justifyEnd().centerY().gap(8.0).pt(4.0)
        if let cancelLabel {
            actions = actions.child(UIButton(cancelLabel, variant: .outline, size: .sm).renderRune(theme: theme, layer: &layer))
        }
        actions = actions.child(
            UIButton(confirmLabel, variant: destructive ? .destructive : .primary, size: .sm)
                .renderRune(theme: theme, layer: &layer)
        )
        modal = modal.child(actions)

        guard showScrim else { return modal }
        let overlay = Rune.row()
            .pin(0.0, 0.0, 0.0, 0.0)
            .center()
            .fill(Rune.Color.BLACK.alpha(0.55))
            .child(modal)
        layer.append(overlay)
        return Rune.el()
    }
}

/// Shadcn `Sheet` edge-docked drawer panel (`.right`, `.left`, `.top`, `.bottom`).
public struct UISheet: GPUAOrnament {
    public enum Side: String, Sendable, Equatable, Hashable, CaseIterable {
        case right
        case left
        case top
        case bottom
    }

    public var side: Side
    public var title: String
    public var description: String?
    public var body: [AnyOrnament]
    public var footer: [AnyOrnament]
    public var widthPx: Float

    public init(
        side: Side = .right,
        title: String,
        description: String? = nil,
        body: [AnyOrnament] = [],
        footer: [AnyOrnament] = [],
        widthPx: Float = 340.0
    ) {
        self.side = side
        self.title = title
        self.description = description
        self.body = body
        self.footer = footer
        self.widthPx = widthPx
    }

    public func renderGPUI(theme: OrnamentTheme) -> GPUI.AnyElement {
        var header = GPUI.div().flex().flexCol().gap(.pixels(GPUI.px(4.0)))
            .pb(.pixels(GPUI.px(12.0)))
            .borderB(.pixels(GPUI.px(1.0)))
            .borderColor(theme.border.toGPUIHsla())
            .child(
                GPUI.div().flex().flexRow().itemsCenter().justifyBetween()
                    .child(
                        GPUI.div()
                            .textSize(.pixels(GPUI.px(15.5)))
                            .fontWeight(.semibold)
                            .textColor(theme.popoverForeground.toGPUIHsla())
                            .child(title)
                    )
                    .child(UIIconButton(.x, label: "Close sheet", variant: .ghost, size: .xs).renderGPUI(theme: theme))
            )
        if let description {
            header = header.child(
                GPUI.div()
                    .textSize(.pixels(GPUI.px(12.5)))
                    .lineHeight(.pixels(GPUI.px(17.5)))
                    .textColor(theme.mutedForeground.toGPUIHsla())
                    .child(description)
            )
        }

        var contentCol = GPUI.div().flex().flexCol().gap(.pixels(GPUI.px(12.0))).py(.pixels(GPUI.px(14.0))).flex1()
        for item in body {
            contentCol = contentCol.child(item.renderGPUI(theme: theme))
        }

        var drawer = GPUI.div()
            .flex()
            .flexCol()
            .justifyBetween()
            .w(GPUI.px(widthPx))
            .hFull()
            .p(GPUI.px(18.0))
            .bg(theme.popover.toGPUIHsla())
            .border1()
            .borderColor(theme.border.toGPUIHsla())
            .shadow(theme.gpuiModalShadows())
            .rounded(.pixels(GPUI.px(theme.radii.lg)))
            .child(header)
            .child(contentCol)

        if !footer.isEmpty {
            var fRow = GPUI.div()
                .flex()
                .flexRow()
                .itemsCenter()
                .justifyEnd()
                .gap(.pixels(GPUI.px(8.0)))
                .pt(.pixels(GPUI.px(12.0)))
                .borderT(.pixels(GPUI.px(1.0)))
                .borderColor(theme.border.toGPUIHsla())
            for f in footer {
                fRow = fRow.child(f.renderGPUI(theme: theme))
            }
            drawer = drawer.child(fRow)
        }
        return drawer.intoAnyElement()
    }

    public func renderRune(theme: OrnamentTheme, layer: inout [Rune.El]) -> Rune.El {
        var header = Rune.col().wFull().gap(4.0).pb(12.0)
            .child(
                Rune.row().wFull().justifyBetween().centerY()
                    .child(
                        Rune.text(title)
                            .font(Rune.TextStyle.new(15.5, 600.0).lh(20.0))
                            .color(theme.popoverForeground.toRuneColor())
                    )
                    .child(UIIconButton(.x, label: "Close sheet", variant: .ghost, size: .xs).renderRune(theme: theme, layer: &layer))
            )
        if let description {
            header = header.child(
                Rune.text(description)
                    .font(Rune.TextStyle.new(12.5, 400.0).lh(17.5))
                    .color(theme.mutedForeground.toRuneColor())
            )
        }

        var contentCol = Rune.col().wFull().gap(12.0).pt(14.0).pb(14.0).grow(1.0)
        for item in body {
            contentCol = contentCol.child(item.renderRune(theme: theme, layer: &layer))
        }

        var drawer = Rune.col()
            .role("dialog")
            .w(widthPx)
            .hFull()
            .padding(18.0)
            .radius(theme.radii.lg)
            .fill(theme.popover.toRuneColor())
            .border(1.0, theme.border.toRuneColor())
            .child(header)
            .child(Rune.el().wFull().h(1.0).fill(theme.border.toRuneColor()))
            .child(contentCol)

        if !footer.isEmpty {
            drawer = drawer.child(Rune.el().wFull().h(1.0).fill(theme.border.toRuneColor()))
            var fRow = Rune.row().wFull().pt(12.0).gap(8.0).justifyEnd().centerY()
            for f in footer {
                fRow = fRow.child(f.renderRune(theme: theme, layer: &layer))
            }
            drawer = drawer.child(fRow)
        }
        return drawer
    }
}
