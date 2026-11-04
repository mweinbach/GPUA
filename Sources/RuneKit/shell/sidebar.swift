// Ported from: crates/rune-kit/src/shell/sidebar.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! A source-list sidebar: collapsible sections of selectable rows, with header and footer
//! slots, keyboard navigation and an optional virtualised body.

import Rune

private typealias Apply = (El) -> El
private typealias Themed = (Kit) -> El

/// A sidebar row's height (AppKit's medium source-list row).
public let ROW_HEIGHT: Float = 28.0
/// A two-line sidebar row's default height when ``SidebarRow/subtitle(_:)`` is set without
/// ``SidebarRow/height(_:)``.
public let TWO_LINE_ROW_HEIGHT: Float = 40.0
/// Each level of ``SidebarRow/depth(_:)`` indents this far.
public let INDENT: Float = 16.0
/// Rows sit this far in from the sidebar's sides.
private let INSET: Float = 8.0

private enum Body {
    case items([Themed])
    case virtual((El, Float) -> El)
}

/// A sidebar's content: header, a scrolling list of sections and rows, and footer.
/// `Sidebar.new().header(..).section(..).footer(..).build(kit)`. The list is one Tab stop
/// that lands on the selected row. Up and Down move the selection (it follows focus, as in a
/// source list), Home and End go to the ends, typing a row's first letters jumps to it, and
/// Return presses the focused row.
public struct Sidebar {
    private var labelVal: String
    private var headerVal: [El]
    private var bodyVal: Body
    private var footerVal: [El]
    private var insetVal: Float
    private var headerGapVal: Float
    private var headerPadVal: [Float]
    private var rowGapVal: Float
    private var rowHeightVal: Float

    public init() {
        self.labelVal = "Sidebar"
        self.headerVal = []
        self.bodyVal = .items([])
        self.footerVal = []
        self.insetVal = INSET
        self.headerGapVal = 2.0
        self.headerPadVal = [0.0, INSET]
        self.rowGapVal = 0.0
        self.rowHeightVal = ROW_HEIGHT
    }

    public static func new() -> Sidebar {
        Sidebar()
    }

    public static var `default`: Sidebar {
        Sidebar()
    }

    /// Points between the sidebar's sides and its rows, header and footer (default 8).
    public func inset(_ points: Float) -> Sidebar {
        var copy = self
        copy.insetVal = max(points, 0.0)
        return copy
    }

    /// Points between the header's items (default 2).
    public func headerGap(_ points: Float) -> Sidebar {
        var copy = self
        copy.headerGapVal = max(points, 0.0)
        return copy
    }

    /// Points above the header and between it and the list (default 0 and 8).
    public func headerPadding(_ top: Float, _ bottom: Float) -> Sidebar {
        var copy = self
        copy.headerPadVal = [max(top, 0.0), max(bottom, 0.0)]
        return copy
    }

    /// Points between the list's items (default 0). Virtualised rows don't take it: give them
    /// the space in their height.
    public func rowGap(_ points: Float) -> Sidebar {
        var copy = self
        copy.rowGapVal = max(points, 0.0)
        return copy
    }

    /// The height of ``virtualRows(_:_:_:)``' rows (default ``ROW_HEIGHT``). Give the rows the
    /// same height with ``SidebarRow/height(_:)``.
    public func rowHeight(_ points: Float) -> Sidebar {
        var copy = self
        copy.rowHeightVal = max(points, 1.0)
        return copy
    }

    /// The list's accessible name.
    public func label(_ l: String) -> Sidebar {
        var copy = self
        copy.labelVal = l
        return copy
    }

    /// Above the list, outside its scrolling: a "New" row or button, a search field.
    public func header(_ e: El) -> Sidebar {
        var copy = self
        copy.headerVal.append(e)
        return copy
    }

    /// Below the list: an account or settings row, a version line.
    public func footer(_ e: El) -> Sidebar {
        var copy = self
        copy.footerVal.append(e)
        return copy
    }

    public func section(_ s: SidebarSection) -> Sidebar {
        item { k in s.build(k) }
    }

    /// Any element in the list: a built ``SidebarRow`` or ``SidebarHeader``, a divider.
    public func child(_ e: El) -> Sidebar {
        item { _ in e }
    }

    /// A virtualised list of `count` rows for long histories: only the rows near the viewport
    /// are built. `key(s, i)` names row `i` and `build(s, i)` builds it, typically a
    /// ``SidebarRow``, or a ``SidebarHeader`` in a flattened list of sections. `El.virtualRows`
    /// has the rules. Replaces any sections or children.
    public func virtualRows<S>(
        _ count: Int,
        _ key: @escaping (S, Int) -> String,
        _ build: @escaping (S, Int) -> El
    ) -> Sidebar {
        var copy = self
        copy.bodyVal = .virtual { e, height in
            e.virtualRows(count, height, key, build)
        }
        return copy
    }

    private func item(_ e: @escaping Themed) -> Sidebar {
        var copy = self
        switch copy.bodyVal {
        case .items(var v):
            v.append(e)
            copy.bodyVal = .items(v)
        case .virtual:
            copy.bodyVal = .items([e])
        }
        return copy
    }

    public func build(_ k: Kit) -> El {
        let inset = insetVal
        let baseList = col()
            .key("sidebar-list")
            .role("list")
            .label(labelVal)
            .focusGroup()
            .focusFollows()
            .wFull()
            .px(inset)
        let list: El
        switch bodyVal {
        case .items(let items):
            list = baseList.pb(INSET).gap(rowGapVal).children(items.map { f in f(k) })
        case .virtual(let rows):
            list = rows(baseList.growth(GrowthSpec()), rowHeightVal)
        }
        var root = col().key("sidebar").wFull().hFull().minH(0.0)
        if !headerVal.isEmpty {
            let top = headerPadVal[0]
            let bottom = headerPadVal[1]
            root = root.child(
                col()
                    .key("sidebar-header")
                    .wFull()
                    .px(inset)
                    .pt(top)
                    .pb(bottom)
                    .gap(headerGapVal)
                    .children(headerVal)
            )
        }
        root = root.child(
            col()
                .key("sidebar-scroll")
                .wFull()
                .grow(1.0)
                .minH(0.0)
                .scroll(ScrollSpec(stickBottom: false))
                .scrollEdgeFade(16.0)
                .child(list)
        )
        if !footerVal.isEmpty {
            root = root.child(
                col()
                    .key("sidebar-footer")
                    .wFull()
                    .px(inset)
                    .py(INSET)
                    .gap(headerGapVal)
                    .children(footerVal)
            )
        }
        return root
    }
}

/// A section's header row: its title, an optional count, a disclosure triangle and a trailing
/// action (a small "+" button, say). Pressing it calls `onToggle`; whether the section is
/// collapsed is the app's state. ``SidebarSection`` pairs it with its rows; use it on its own
/// in a virtualised list.
public struct SidebarHeader {
    private var titleVal: String
    private var countVal: String?
    private var collapsedVal: Bool?
    private var actionVal: El?
    private var toggleVal: Apply?

    public init(_ title: String) {
        self.titleVal = title
        self.countVal = nil
        self.collapsedVal = nil
        self.actionVal = nil
        self.toggleVal = nil
    }

    public static func new(_ title: String) -> SidebarHeader {
        SidebarHeader(title)
    }

    /// Shows a disclosure triangle for this state. Without it, or `onToggle`, the header is
    /// a plain label.
    public func collapsed(_ c: Bool) -> SidebarHeader {
        var copy = self
        copy.collapsedVal = c
        return copy
    }

    public func count(_ n: Int) -> SidebarHeader {
        var copy = self
        copy.countVal = "\(n)"
        return copy
    }

    /// A trailing element, such as a small "+" icon button.
    public func action(_ e: El) -> SidebarHeader {
        var copy = self
        copy.actionVal = e
        return copy
    }

    public func onToggle<S>(_ f: @escaping (inout S, inout Tx) -> Void) -> SidebarHeader {
        var copy = self
        copy.toggleVal = { e in e.onPressTx(f) }
        if copy.collapsedVal == nil {
            copy.collapsedVal = false
        }
        return copy
    }

    public func build(_ k: Kit) -> El {
        let c = k.c
        var title = row()
            .key("section-title")
            .gap(4.0)
            .centerY()
            .shrink()
            .child(text(titleVal).font(k.ty.textXsmallMedium).color(c.textMuted).truncate().shrink())
        if let n = countVal {
            title = title.child(text(n).key("count").font(k.ty.textXsmallMedium).color(c.textFaint))
        }
        if let collapsed = collapsedVal {
            let glyph = collapsed ? k.glyph.triangleRight : k.glyph.triangleDown
            title = title.child(icon(glyph, 12.0).key("disclosure").color(c.iconFaint))
        }
        let label: String
        if collapsedVal == true {
            label = "\(titleVal), collapsed"
        } else if collapsedVal == false && toggleVal != nil {
            label = "\(titleVal), expanded"
        } else {
            label = titleVal
        }
        var header = row()
            .key("section-header")
            .label(label)
            .wFull()
            .h(ROW_HEIGHT)
            .pt(4.0)
            .px(INSET)
            .centerY()
            .radius(k.radius.md)
            .child(title)
            .child(el().key("spacer").grow(1.0))
        if let a = actionVal {
            header = header.child(a)
        }
        if let toggle = toggleVal {
            // Pointer only: in the list's focus group the arrows step through rows, and with
            // selection following focus they would toggle the section as they passed.
            return k.interactive(toggle(header))
                .role("button")
                .hoverMotion(Anim.instant, Anim.instant)
                .focusable(false)
        }
        return header.role("heading")
    }
}

/// A titled group of rows that collapses: `SidebarSection.new("Today").collapsed(..)
/// .onToggle(..).row(..)`. Rows below it move on the kit's disclosure spring as it opens.
public struct SidebarSection {
    private var keyVal: String
    private var headerVal: SidebarHeader
    private var collapsedVal: Bool
    private var rowsVal: [El]

    public init(_ title: String) {
        self.keyVal = title
        self.headerVal = SidebarHeader(title)
        self.collapsedVal = false
        self.rowsVal = []
    }

    public static func new(_ title: String) -> SidebarSection {
        SidebarSection(title)
    }

    /// Its key among the list's children (default: the title).
    public func key(_ k: String) -> SidebarSection {
        var copy = self
        copy.keyVal = k
        return copy
    }

    public func collapsed(_ c: Bool) -> SidebarSection {
        var copy = self
        copy.collapsedVal = c
        copy.headerVal = copy.headerVal.collapsed(c)
        return copy
    }

    public func count(_ n: Int) -> SidebarSection {
        var copy = self
        copy.headerVal = copy.headerVal.count(n)
        return copy
    }

    public func action(_ e: El) -> SidebarSection {
        var copy = self
        copy.headerVal = copy.headerVal.action(e)
        return copy
    }

    public func onToggle<S>(_ f: @escaping (inout S, inout Tx) -> Void) -> SidebarSection {
        var copy = self
        copy.headerVal = copy.headerVal.onToggle(f)
        return copy
    }

    /// A row: a built ``SidebarRow``, keyed by the app.
    public func row(_ e: El) -> SidebarSection {
        var copy = self
        copy.rowsVal.append(e)
        return copy
    }

    public func rows<Seq: Swift.Sequence>(_ rows: Seq) -> SidebarSection where Seq.Element == El {
        var copy = self
        copy.rowsVal.append(contentsOf: rows)
        return copy
    }

    public func build(_ k: Kit) -> El {
        var s = col()
            .key(keyVal)
            .role("group")
            .wFull()
            .gap(2.0)
            .motion(k.motion.disclosure)
            .child(headerVal.build(k))
        if !collapsedVal {
            s = s.children(rowsVal)
        }
        return s
    }
}

/// What a ``SidebarRow``'s status slot shows.
public enum RowStatus {
    /// Working: a small spinner.
    case busy
    /// Waiting on the user: a dot in the warning colour.
    case attention
    /// Something new: a 7 point dot in the accent colour.
    case unread
    /// Any element, centred in the slot.
    case other(El)
}

/// A row that drags to a new place in its list: the list's drag, the row's index, and the
/// handlers that update the drag and make the move on a drop.
private struct Reordering {
    var state: Reorder
    var index: Int
    var bind: Apply
}

// PORT NOTE: Packaged as a struct rather than a `(TextEdit, Apply)` tuple to avoid an assertion in
// Swift 6.3.3's `LoadableByAddress` SIL pass on Windows x64 when storing `Optional<(TextEdit, (El) -> El)>`.
private struct Renaming {
    var edit: TextEdit
    var bind: Apply
}

/// A selectable sidebar row: icon, label, then a trailing detail (a time), badge or element.
/// `SidebarRow.new("Inbox").icon(INBOX).badge("3").selected(sel).onSelect(..).build(kit)`.
/// Key the built row by its item's id.
///
/// A taller row takes a second, muted line, an avatar and a status slot that turns into a
/// close button under the pointer: `SidebarRow.new(title).height(45.0).avatar(..)
/// .subtitle(project).status(.busy).onClose(..)`.
public struct SidebarRow {
    private var labelVal: String
    private var iconVal: Icon?
    private var avatarVal: El?
    private var subtitleVal: String?
    private var detailVal: String?
    private var badgeVal: String?
    private var trailingVal: El?
    private var statusVal: RowStatus?
    private var closeVal: Apply?
    private var selectedVal: Bool
    private var depthVal: UInt8
    private var heightVal: Float?
    private var titleStyleVal: TextStyle?
    private var subtitleStyleVal: TextStyle?
    private var subtitleColorVal: Color?
    private var selectOnlyVal: Bool
    private var renameVal: Renaming?
    private var reorderVal: Reordering?
    private var actsVal: [Apply]

    public init(_ label: String) {
        self.labelVal = label
        self.iconVal = nil
        self.avatarVal = nil
        self.subtitleVal = nil
        self.detailVal = nil
        self.badgeVal = nil
        self.trailingVal = nil
        self.statusVal = nil
        self.closeVal = nil
        self.selectedVal = false
        self.depthVal = 0
        self.heightVal = nil
        self.titleStyleVal = nil
        self.subtitleStyleVal = nil
        self.subtitleColorVal = nil
        self.selectOnlyVal = false
        self.renameVal = nil
        self.reorderVal = nil
        self.actsVal = []
    }

    public static func new(_ label: String) -> SidebarRow {
        SidebarRow(label)
    }

    public func icon(_ i: Icon) -> SidebarRow {
        var copy = self
        copy.iconVal = i
        return copy
    }

    /// A 16 point leading element in place of the icon: a project's avatar, an initial.
    public func avatar(_ e: El) -> SidebarRow {
        var copy = self
        copy.avatarVal = e
        return copy
    }

    /// A second line under the label, smaller and fainter than it (11 point `caption` in
    /// `textFaint`, under a medium-weight 13 point label). The row's accessible name is then
    /// "Label, Subtitle". Give the row the height for it (default ``TWO_LINE_ROW_HEIGHT``).
    public func subtitle(_ s: String) -> SidebarRow {
        var copy = self
        copy.subtitleVal = s
        return copy
    }

    /// The label's type, in place of the default (13 point; medium weight with a subtitle).
    /// It also sets the inline rename field's type.
    public func titleStyle(_ style: TextStyle) -> SidebarRow {
        var copy = self
        copy.titleStyleVal = style
        return copy
    }

    /// The subtitle's type, in place of the default (the kit's `caption`).
    public func subtitleStyle(_ style: TextStyle) -> SidebarRow {
        var copy = self
        copy.subtitleStyleVal = style
        return copy
    }

    /// The subtitle's colour, in place of the default (`textFaint`).
    public func subtitleColor(_ color: Color) -> SidebarRow {
        var copy = self
        copy.subtitleColorVal = color
        return copy
    }

    /// A row that shows the selection but never takes focus: for a list driven from outside,
    /// such as one a search field filters and steers with its own keys. The row is out of the
    /// Tab order, Tab and Space don't act on it, and pressing it selects it (`onSelect`)
    /// while a focused field stays focused (`El.preserveFocusOnPress`). Keyboard navigation
    /// of a select-only list (Up/Down and Return from the field) is the app's job. The selected
    /// row is still exposed as selected to assistive tech (`ElementInfo.itemSelected`), and
    /// changing the selection never pulls focus to the row. Equivalent to
    /// `.focusable(false).focusSelected(..)` on the built row, plus the focus-preserving press.
    public func selectOnly() -> SidebarRow {
        var copy = self
        copy.selectOnlyVal = true
        return copy
    }

    /// The row's height (default ``ROW_HEIGHT``, or ``TWO_LINE_ROW_HEIGHT`` with a subtitle).
    public func height(_ points: Float) -> SidebarRow {
        var copy = self
        copy.heightVal = max(points, 1.0)
        return copy
    }

    /// Faint trailing text: a time ("2m"), a count, a shortcut.
    public func detail(_ d: String) -> SidebarRow {
        var copy = self
        copy.detailVal = d
        return copy
    }

    /// A trailing pill (an unread count).
    public func badge(_ b: String) -> SidebarRow {
        var copy = self
        copy.badgeVal = b
        return copy
    }

    /// Any trailing element (a status dot, a menu button), after the detail and badge.
    public func trailing(_ e: El) -> SidebarRow {
        var copy = self
        copy.trailingVal = e
        return copy
    }

    /// A 20 point slot at the row's end, after everything else.
    public func status(_ s: RowStatus) -> SidebarRow {
        var copy = self
        copy.statusVal = s
        return copy
    }

    /// A close button in the status slot, in place of the status while the pointer is on the
    /// row. It swaps at once, with no fade.
    public func onClose<S>(_ f: @escaping (inout S, inout Tx) -> Void) -> SidebarRow {
        var copy = self
        copy.closeVal = { e in e.onPressTx(f) }
        return copy
    }

    public func selected(_ s: Bool) -> SidebarRow {
        var copy = self
        copy.selectedVal = s
        return copy
    }

    /// Nesting level: each indents the row by ``INDENT``.
    public func depth(_ d: UInt8) -> SidebarRow {
        var copy = self
        copy.depthVal = d
        return copy
    }

    /// Called when the row is pressed, or reached with the arrow keys.
    public func onSelect<S>(_ f: @escaping (inout S, inout Tx) -> Void) -> SidebarRow {
        var copy = self
        copy.actsVal.append({ e in e.onPressTx(f) })
        return copy
    }

    /// Called on a double click (rename, open in a new window).
    public func onDoubleClick<S>(_ f: @escaping (inout S, inout Tx) -> Void) -> SidebarRow {
        var copy = self
        copy.actsVal.append({ e in e.onDoublePressTx(f) })
        return copy
    }

    // PORT NOTE: Supports both `WritableKeyPath<S, Reorder>` and scoped mutation closures in place
    // of Rust `fn(&mut S) -> &mut Reorder`.
    /// Drags the row to a new place among the list's `count` rows, of which it is row `index`.
    /// It lifts above its neighbours and follows the pointer, and they step aside on springs.
    /// A drop calls `drop(&s, from, to)` to move the item; Escape, or the window losing focus,
    /// puts it back. `keyPath` finds the ``Reorder`` in the app's state. A press that doesn't
    /// move is still a select.
    public func reorder<S>(
        _ state: Reorder,
        _ index: Int,
        _ count: Int,
        _ keyPath: WritableKeyPath<S, Reorder>,
        _ drop: @escaping (inout S, Int, Int) -> Void
    ) -> SidebarRow {
        reorder(state, index, count, { s, body in body(&s[keyPath: keyPath]) }, drop)
    }

    /// Drags the row to a new place among the list's `count` rows using a scoped mutation closure.
    public func reorder<S>(
        _ state: Reorder,
        _ index: Int,
        _ count: Int,
        _ access: @escaping (inout S, (inout Reorder) -> Void) -> Void,
        _ drop: @escaping (inout S, Int, Int) -> Void
    ) -> SidebarRow {
        var copy = self
        let bind: Apply = { e in
            e.onDrag { (s: inout S, d: inout Drag, tx: inout Tx) in
                var moved: (Int, Int)? = nil
                access(&s) { r in
                    switch d.phase {
                    case .down:
                        break
                    case .move:
                        // The rows it passes spring aside; it follows the pointer exactly.
                        tx.animated()
                        r.follow(index, count, d.dy, d.h)
                    case .up:
                        moved = r.end(d.cancelled())
                    }
                }
                if let (from, to) = moved {
                    drop(&s, from, to)
                }
            }
        }
        copy.reorderVal = Reordering(state: state, index: index, bind: bind)
        return copy
    }

    // PORT NOTE: Supports `WritableKeyPath<S, TextEdit>`, `EditAccess<S>`, and scoped mutation
    // closures in place of Rust `fn(&mut S) -> &mut TextEdit`.
    /// Edits the label in place, in the field bound to `edit` (`keyPath` finds it in the app's
    /// state). Set `edit.focused` and its text when renaming starts. Return calls `commit`,
    /// Escape calls `cancel`; both should end the rename.
    public func renaming<S>(
        _ edit: TextEdit,
        _ keyPath: WritableKeyPath<S, TextEdit>,
        _ commit: @escaping (inout S, inout Tx) -> Void,
        _ cancel: @escaping (inout S, inout Tx) -> Void
    ) -> SidebarRow {
        renaming(edit, EditAccess(keyPath), commit, cancel)
    }

    /// Edits the label in place using an `EditAccess<S>` descriptor.
    public func renaming<S>(
        _ edit: TextEdit,
        _ access: EditAccess<S>,
        _ commit: @escaping (inout S, inout Tx) -> Void,
        _ cancel: @escaping (inout S, inout Tx) -> Void
    ) -> SidebarRow {
        var copy = self
        let bind: Apply = { e in
            e.onEdit(access).onSubmit(commit).onInputKey { (s: inout S, ev: KeyEvent, tx: inout Tx) -> Bool in
                if ev.key == .escape {
                    cancel(&s, &tx)
                    return true
                }
                return false
            }
        }
        copy.renameVal = Renaming(edit: edit, bind: bind)
        return copy
    }

    /// Edits the label in place using a scoped mutation closure.
    public func renaming<S>(
        _ edit: TextEdit,
        _ access: @escaping (inout S, (inout TextEdit) -> Void) -> Void,
        _ commit: @escaping (inout S, inout Tx) -> Void,
        _ cancel: @escaping (inout S, inout Tx) -> Void
    ) -> SidebarRow {
        renaming(edit, EditAccess(access), commit, cancel)
    }

    public func build(_ k: Kit) -> El {
        let c = k.c
        let renaming = renameVal != nil
        let (ink, glyph) = selectedVal ? (c.textBase, c.iconBase) : (c.textMuted, c.iconMuted)
        let twoLines = subtitleVal != nil
        let height = heightVal ?? (twoLines ? TWO_LINE_ROW_HEIGHT : ROW_HEIGHT)
        let font: TextStyle
        if let ts = titleStyleVal {
            font = ts
        } else if twoLines {
            var compact = k.ty.uiCompact
            compact.weight = 500.0
            font = compact
        } else {
            font = k.ty.ui
        }
        let subFont = subtitleStyleVal ?? k.ty.caption()
        let name: String
        if let sub = subtitleVal, !sub.isEmpty {
            name = "\(labelVal), \(sub)"
        } else {
            name = labelVal
        }
        let focusable = !renaming && !selectOnlyVal
        var r = row()
            .label(name)
            .wFull()
            .h(height)
            .pl(INSET + Float(depthVal) * INDENT)
            .pr(INSET)
            .gap(6.0)
            .centerY()
            .radius(k.radius.md)
            .motion(k.motion.control)
            .hoverGroup()
            .hoverMotion(Anim.instant, Anim.instant)
            .focusable(focusable)
            .focusSelected(selectedVal && !renaming)
        if selectOnlyVal {
            r = r.preserveFocusOnPress(true)
        }
        r = k.interactive(r)
        if selectedVal {
            r = r.fill(c.pressed)
        }
        let lead: El?
        if let a = avatarVal {
            lead = row().key("avatar").size(16.0, 16.0).center().child(a)
        } else if let i = iconVal {
            lead = Rune.icon(i, 16.0).key("icon").color(glyph)
        } else {
            lead = nil
        }
        let hasLead = lead != nil
        let labelEl: El
        if let rename = renameVal {
            labelEl = rename.bind(
                textInput(rename.edit, font)
                    .singleLine()
                    .key("rename")
                    .focusSelected(true)
                    .focusReturn("sidebar-list")
                    .grow(1.0)
                    .shrink()
                    .color(c.textBase)
                    .caret(c.textBase, k.selection())
            )
        } else {
            labelEl = text(labelVal).key("label").font(font).color(ink).truncate().grow(1.0).shrink()
        }
        if let sub = subtitleVal {
            // Two lines: the lead and the label, then the subtitle under the label.
            var first = row().key("line1").wFull().gap(6.0).centerY()
            if let lead {
                first = first.child(lead)
            }
            first = first.child(labelEl)
            let secondText = text(sub)
                .key("subtitle")
                .font(subFont)
                .color(subtitleColorVal ?? c.textFaint)
                .truncate()
                .wFull()
            let second = row().key("line2").wFull().pl(hasLead ? 16.0 + 6.0 : 0.0).child(secondText)
            r = r.child(col().key("lines").grow(1.0).shrink().minW(0.0).child(first).child(second))
        } else {
            if let lead {
                r = r.child(lead)
            }
            r = r.child(labelEl)
        }
        if let d = detailVal {
            r = r.child(text(d).key("detail").font(k.ty.small).color(c.textFaint))
        }
        if let b = badgeVal {
            r = r.child(
                row()
                    .key("badge")
                    .h(16.0)
                    .px(5.0)
                    .center()
                    .radius(8.0)
                    .fill(c.layer03)
                    .child(text(b).font(k.ty.smallMedium).color(c.textMuted))
            )
        }
        if let t = trailingVal {
            r = r.child(t)
        }
        if statusVal != nil || closeVal != nil {
            func dot(_ color: Color) -> El {
                el().size(7.0, 7.0).radius(3.5).fill(color)
            }
            let statusEl: El? = statusVal.map { s in
                switch s {
                case .busy:
                    return Spinner.new().size(12.0).color(c.iconMuted).build(k)
                case .attention:
                    return dot(c.warning.icon)
                case .unread:
                    return dot(c.bgAccent)
                case .other(let e):
                    return e
                }
            }
            var slot = row().key("status").size(20.0, 20.0).center()
            if let st = statusEl {
                let mark = row().key("status-mark").size(20.0, 20.0).center().child(st)
                slot = slot.child(closeVal != nil ? mark.groupOpacity(1.0, 0.0) : mark)
            }
            if let bind = closeVal {
                let close = IconButton.new(k.glyph.close)
                    .controlSize(.small)
                    .variant(.ghostMuted)
                    .label("Close")
                    .build(k)
                // Pointer only, like the row's other hover controls: the list's arrows step rows.
                slot = slot.child(bind(close).key("close").absolute(0.0, 0.0).groupOpacity(0.0, 1.0).focusable(false))
            }
            r = r.child(slot)
        }
        for a in actsVal {
            r = a(r)
        }
        if let re = reorderVal {
            let lifted = re.state.dragging() == re.index
            r = r.offset(0.0, re.state.shift(re.index))
            if lifted {
                // Follows the pointer exactly; the rest of the list springs around it.
                // Opaque, on the window's deep background, so the rows it passes don't show through.
                r = k.elevate(
                    r.raise().offsetMotion(Anim.instant).fill(over(c.pressed, c.bgDeep)),
                    k.elevation.raised
                )
            }
            r = re.bind(r)
        }
        // After the handlers, which would make it a button.
        return r.role("listitem")
    }
}
