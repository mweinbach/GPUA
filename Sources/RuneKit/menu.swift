// Ported from: crates/rune-kit/src/menu.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Menu, context menu and their items (`@opencode/ui` navigation/menu, components/context-menu).
//! Compact (default) and standard appearances.

import Rune

/// A menu at a secondary-press position. Store the point from `El.onSecondaryPress`
/// in app state; clear it in `onClose` and item callbacks. Uses Menu's flipping anchor.
public func contextMenu(_ key: String, _ trigger: El, _ point: PointerPress?) -> Menu {
    let menu = Menu.new(key).trigger(trigger).open(point != nil)
    if let p = point {
        return menu.at(p.x, p.y)
    }
    return menu
}

public indirect enum MenuEntry {
    case item(MenuItem)
    case separator
    case label(String)
}

public struct MenuItem {
    var labelText: String
    var iconVal: Icon?
    var leadEl: El?
    var shortcutText: String?
    var badgeText: String?
    /// Checkbox and radio items: whether the indicator shows.
    var checkedFlag: Bool?
    var subSpec: ([MenuEntry], Bool)?
    var stateVal: State
    var acts: Acts

    public init(_ label: String) {
        self.labelText = label
        self.iconVal = nil
        self.leadEl = nil
        self.shortcutText = nil
        self.badgeText = nil
        self.checkedFlag = nil
        self.subSpec = nil
        self.stateVal = .rest
        self.acts = Acts()
    }

    public static func new(_ label: String) -> MenuItem {
        MenuItem(label)
    }

    /// A 14 point icon before the label.
    public func icon(_ i: Icon) -> MenuItem {
        var copy = self
        copy.iconVal = i
        return copy
    }

    /// Anything before the label (an avatar, …).
    public func lead(_ e: El) -> MenuItem {
        var copy = self
        copy.leadEl = e
        return copy
    }

    public func shortcut(_ s: String) -> MenuItem {
        var copy = self
        copy.shortcutText = s
        return copy
    }

    public func badge(_ b: String) -> MenuItem {
        var copy = self
        copy.badgeText = b
        return copy
    }

    /// A checkbox or radio item, showing the check when `on`.
    public func checked(_ on: Bool) -> MenuItem {
        var copy = self
        copy.checkedFlag = on
        return copy
    }

    /// A submenu trigger; `open` shows its entries to the right.
    public func submenu(_ entries: [MenuEntry], _ open: Bool) -> MenuItem {
        var copy = self
        copy.subSpec = (entries, open)
        return copy
    }

    /// `.hover` paints the highlighted (keyboard-focused) row.
    public func state(_ s: State) -> MenuItem {
        var copy = self
        copy.stateVal = s
        return copy
    }

    public func disabled(_ d: Bool) -> MenuItem {
        var copy = self
        if d {
            copy.stateVal = .disabled
        }
        return copy
    }

    public func onSelect<S>(_ f: @escaping (inout S) -> Void) -> MenuItem {
        var copy = self
        copy.acts.press(f)
        return copy
    }

    public func onSelectTx<S>(_ f: @escaping (inout S, inout Tx) -> Void) -> MenuItem {
        var copy = self
        copy.acts.pressTx(f)
        return copy
    }

    func build(_ k: Kit, _ standard: Bool, _ key: String, _ layer: inout [El]) -> El {
        let c = k.c
        let disabled = stateVal == .disabled
        let highlighted = stateVal == .hover || (subSpec?.1 == true)
        let hover = standard ? c.surfaceRaisedHover : c.hover
        let (font, ink): (TextStyle, Color) = if standard {
            (k.ty.textSmallMedium, disabled ? c.textWeak : c.textStrong)
        } else {
            (k.ty.uiCompact, c.textBase)
        }
        var content = Rune.row().key("content").grow(1.0).shrink().gap(8.0).centerY()
        if let l = leadEl {
            content = content.child(l)
        }
        if let i = iconVal {
            content = content.child(
                Rune.icon(i, 14.0).key("icon").color(standard ? c.stdIcon : c.iconBase)
            )
        }
        content = content.child(
            Rune.text(labelText).key("label").font(font).color(ink).truncate()
        )
        var e = Rune.row()
            .key(key)
            .role("menuitem")
            .label(labelText)
            .radius(standard ? k.radius.sm : 4.0)
            .gap(8.0)
            .centerY()
        e = standard ? e.px(8.0).py(4.0) : e.h(28.0).pl(12.0).pr(6.0)
        if highlighted {
            e = e.fill(hover)
        } else if !disabled {
            // One highlight for pointer and keys, landing at once like NSMenu's.
            e = e.focusHighlight(hover)
        }
        e = e.child(content)
        if let s = shortcutText {
            let st = k.ty.smallMedium.lh(11.0)
            e = e.child(Rune.text(s).key("shortcut").font(st).color(c.textFaint))
        }
        if let b = badgeText {
            e = e.child(
                Rune.row()
                    .key("badge")
                    .h(16.0)
                    .px(4.0)
                    .center()
                    .radius(2.0)
                    .fill(c.layer02)
                    .border(0.5, c.borderBase)
                    .child(Rune.text(b).font(k.ty.smallMedium.lh(11.0)).color(c.textMuted))
            )
        }
        if let on = checkedFlag {
            let mark = Rune.icon(k.glyph.checkSmall, 14.0)
                .color(standard ? c.stdIcon : c.iconBase)
                .opacity(on ? 1.0 : 0.0)
            e = e.child(Rune.el().key("indicator").size(16.0, 16.0).center().child(mark))
        }
        if let (entries, open) = subSpec {
            e = e.child(
                Rune.icon(k.glyph.caretRight, 16.0)
                    .key("chevron")
                    .color(standard ? c.stdIcon : c.textFaint)
            )
            if open {
                var sub = Menu.new("")
                sub.key = "\(key)-sub"
                sub.entries = entries
                sub.standardFlag = standard
                sub.minWidthVal = 160.0
                var deeper: [El] = []
                let surface = sub.surface(k, &deeper)
                layer.append(overlayMenuAnchor(k, surface, key, .rightStart, 0.0))
                layer.append(contentsOf: deeper)
            }
        }
        if disabled && !standard {
            e = e.dim(0.5)
        }
        // A popup opens on its checked item (NSPopUpButton).
        return acts.apply(e.focusable(!disabled).focusSelected(checkedFlag == true), !disabled)
    }
}

/// Makes an open surface modal: it takes focus, Escape and outside presses dismiss it, and
/// focus returns to the trigger when it closes.
typealias MenuModal = (El) -> El

/// The outside-press scrim and the modal for a close request.
func menuDismissal<S>(_ key: String, _ close: @escaping (inout S) -> Void) -> (El, MenuModal) {
    (
        scrim(key, close),
        { e in e.modal(true, close) }
    )
}

/// Mounts a dismissal's scrim into `layer` and hands back its modal.
func menuMountDismiss(_ dismiss: (El, MenuModal)?, _ layer: inout [El]) -> MenuModal? {
    guard let (scrimEl, modal) = dismiss else {
        return nil
    }
    layer.append(scrimEl)
    return modal
}

/// A dropdown menu: `Menu.new("file").trigger(button).item(..).open(s.open).build(kit, &layer)`.
public struct Menu {
    var key: String
    var triggerEl: El?
    var entries: [MenuEntry]
    var openFlag: Bool
    var standardFlag: Bool
    var placementVal: Placement
    var gutterVal: Float
    var minWidthVal: Float
    var atPoint: (Float, Float)?
    var dismissSpec: (El, MenuModal)?

    public init(_ key: String) {
        self.key = key
        self.triggerEl = nil
        self.entries = []
        self.openFlag = false
        self.standardFlag = false
        self.placementVal = .bottomStart
        self.gutterVal = 6.0
        self.minWidthVal = 160.0
        self.atPoint = nil
        self.dismissSpec = nil
    }

    public static func new(_ key: String) -> Menu {
        Menu(key)
    }

    public func trigger(_ t: El) -> Menu {
        var copy = self
        copy.triggerEl = t
        return copy
    }

    public func item(_ i: MenuItem) -> Menu {
        var copy = self
        copy.entries.append(.item(i))
        return copy
    }

    public func separator() -> Menu {
        var copy = self
        copy.entries.append(.separator)
        return copy
    }

    public func groupLabel(_ l: String) -> Menu {
        var copy = self
        copy.entries.append(.label(l))
        return copy
    }

    public func open(_ o: Bool) -> Menu {
        var copy = self
        copy.openFlag = o
        return copy
    }

    /// The older bordered look (`appearance="standard"`).
    public func standard() -> Menu {
        var copy = self
        copy.standardFlag = true
        copy.minWidthVal = 128.0
        return copy
    }

    public func placement(_ p: Placement) -> Menu {
        var copy = self
        copy.placementVal = p
        return copy
    }

    public func gutter(_ g: Float) -> Menu {
        var copy = self
        copy.gutterVal = g
        return copy
    }

    public func minWidth(_ w: Float) -> Menu {
        var copy = self
        copy.minWidthVal = w
        return copy
    }

    /// A context menu: open at a window point (where the secondary press landed).
    public func at(_ x: Float, _ y: Float) -> Menu {
        var copy = self
        copy.atPoint = (x, y)
        return copy
    }

    /// Presses outside and Escape close the menu. While open it holds keyboard focus.
    public func onClose<S>(_ f: @escaping (inout S) -> Void) -> Menu {
        var copy = self
        copy.dismissSpec = menuDismissal("\(key)-scrim", f)
        return copy
    }

    fileprivate func surface(_ k: Kit, _ layer: inout [El]) -> El {
        let c = k.c
        let standard = standardFlag
        var frame = Rune.col()
            .key("\(key)-menu")
            .role("menu")
            .focusGroup()
            .minW(minWidthVal)
            .itemsStretch()
        if standard {
            frame = shadows(
                k,
                frame.radius(k.radius.md).fill(c.surfaceRaised).border(1.0, k.alpha(c.stdBorder, 0.5)),
                k.elevation.md
            )
        } else {
            frame = shadows(k, frame.radius(6.0).fill(c.layer01), k.elevation.floating)
        }
        var list = Rune.col().key("rows").itemsStretch().padding(standard ? 4.0 : 2.0)
        for (i, entry) in entries.enumerated() {
            let child: El = switch entry {
            case .item(let item):
                item.build(k, standard, "\(key)-item\(i)", &layer)
            case .separator:
                {
                    let (m, color): (Float, Color) = standard ? (4.0, c.borderWeak) : (2.0, c.borderMuted)
                    return Rune.el().key("sep\(i)").h(1.0).mt(m).mb(m).ml(-m).mr(-m).fill(color)
                }()
            case .label(let l):
                {
                    let e = Rune.row().key("label\(i)").centerY()
                    if standard {
                        return e.px(8.0).py(4.0).child(Rune.text(l).font(k.ty.textXsmallMedium).color(c.textWeak))
                    } else {
                        return e.h(28.0).px(12.0).child(Rune.text(l).font(k.ty.smallMedium).color(c.textFaint))
                    }
                }()
            }
            list = list.child(child)
        }
        return frame.child(overlayFitScroll(list))
    }

    public func build(_ k: Kit, _ layer: inout [El]) -> El {
        let anchorKey = "\(key)-trigger"
        var trigger = Rune.row().key(anchorKey)
        if let t = triggerEl {
            trigger = trigger.child(t)
        }
        if !openFlag {
            return trigger
        }
        let modal = menuMountDismiss(dismissSpec, &layer)
        let (placement, gutter, targetKey): (Placement, Float, String) = if let (x, y) = atPoint {
            {
                let point = "\(key)-point"
                layer.append(Rune.el().key(point).absolute(x, y).size(0.0, 0.0))
                return (.bottomStart, 0.0, point)
            }()
        } else {
            (placementVal, gutterVal, anchorKey)
        }
        // Submenus anchor to items inside this surface, so they mount after it.
        var subs: [El] = []
        var surfaceEl = surface(k, &subs).focusReturn(anchorKey)
        if let modal = modal {
            surfaceEl = modal(surfaceEl)
        }
        layer.append(overlayMenuAnchor(k, surfaceEl, targetKey, placement, gutter))
        layer.append(contentsOf: subs)
        return trigger
    }
}

/// Namespace mirroring `rune_kit::menu` module exports.
public enum menu {
    public typealias MenuEntry = RuneKit.MenuEntry
    public typealias MenuItem = RuneKit.MenuItem
    public typealias Menu = RuneKit.Menu

    public static func contextMenu(_ key: String, _ trigger: El, _ point: PointerPress?) -> Menu {
        RuneKit.contextMenu(key, trigger, point)
    }
}
