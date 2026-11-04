// Ported from: crates/rune-knobs/src/side.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

/// ⌘⇧K as a side panel down the window's right edge: it slides in on ``Knobs/slide()`` and pushes the
/// page over, its left edge drags to resize it, and its groups are listed in one scroll. The group last
/// used is the panel's: its name heads the panel, over its presets, and Random and Reset act
/// on it. Under the list, a line says what the hovered or keyboard's knob does.

import Rune

/// The panel's inset from its edges.
let INSET: Float = 12.0
private let ABOUT: TextStyle = TextStyle.new(12.0, 450.0).lh(16.0)
private let ABOUT_TITLE: TextStyle = TextStyle.new(12.0, 600.0).lh(16.0)

func sectionKey(_ i: Int) -> String {
    "knobs-sec-\(i)"
}

/// Where the keyboard's row is, to scroll it into view.
func nodeKey(_ n: Node, _ groups: [Group]) -> String {
    switch n {
    case .page(let p):
        let idx = groups.firstIndex(where: { $0.page() == p }) ?? 0
        return "knobs-page-\(idx)"
    case .group(let g):
        return "\(sectionKey(g))/head"
    case .knob(let g, let i):
        return "\(sectionKey(g))/body/knobs-card/knobs-knob-\(i)"
    }
}

/// `page` with the knobs beside it: put it where the page would go, filling the window. Read
/// ``Knobs/sideRoom()`` for the width the page loses while it's open.
public func side<S>(
    _ page: El,
    _ k: Knobs,
    _ groups: [Group],
    _ st: Style,
    _ lens: KnobsAccess<S>
) -> El {
    let w = k.sideW()
    let host = col()
        .key("knobs-page")
        .grow(1.0)
        .shrink()
        .minW(0.0)
        .hFull()
        .minH(0.0)
        .child(page)
        .child(overlay(k, groups, st, lens, "knobs-over"))
    // The panel keeps its width and is anchored to the box's left edge, so as the box opens the
    // panel slides in from the right with it; closed, it waits off the window's edge.
    // Shut, the panel isn't built: it was a few hundred elements every commit of every app.
    // Its removal holds it through the slide out.
    let slide = k.slide()
    var bx = el()
        .key("knobs-side")
        .w(k.open ? w : 0.0)
        .hFull()
        .clipSoft(0.0)
        .motion(slide)

    if k.open {
        let out = Transition.identity()
            .holdLayout()
            .springs(SpringPair.new(slide, Spring.new(slide.duration * 1.4, 0.0)))
        bx = bx.child(panel(k, groups, st, lens, w).transition(out))

        let edge = el()
            .key("knobs-edge")
            .absolute(0.0, 0.0)
            .w(6.0)
            .hFull()
            .cursor(.resizeColumn)
            .help("Drag to resize; double-click for the default width")
            .onDrag { (s: inout S, g: inout Drag, tx: inout Tx) in
                tx.instant()
                lens.withMutable(&s) { k in
                    switch g.phase {
                    case .down:
                        g.data = k.sideW()
                    case .move:
                        k.width = min(max(g.data - g.dx, SIDE_MIN), SIDE_MAX).rounded()
                    case .up:
                        if g.cancelled() {
                            k.width = g.data
                        }
                    }
                }
            }
            .onDoublePress { (s: inout S) in
                lens.withMutable(&s) { $0.width = 0.0 }
            }
        bx = bx.child(edge)
    }

    return row().key("knobs-frame").wFull().hFull().minH(0.0).child(host).child(bx)
}

public func side<S>(
    _ page: El,
    _ k: Knobs,
    _ groups: [Group],
    _ st: Style,
    _ keyPath: WritableKeyPath<S, Knobs>
) -> El {
    side(page, k, groups, st, KnobsAccess(keyPath))
}

public func side<S>(
    _ page: El,
    _ k: Knobs,
    _ groups: [Group],
    _ st: Style,
    _ lens: @escaping (inout S, (inout Knobs) -> Void) -> Void
) -> El {
    side(page, k, groups, st, KnobsAccess(lens))
}

/// The groups whose part of the window shows now: their region is laid out and overlaps the
/// page beside the panel.
private func seen(_ k: Knobs, _ groups: [Group]) -> Set<Int> {
    if !k.open {
        return []
    }
    guard let page = memoNamespace.windowLayout("knobs-page"), page.count >= 4 else {
        return []
    }
    var out: Set<Int> = []
    for g in 0..<groups.count {
        let reg = groups[g].region
        if reg.isEmpty { continue }
        guard let r = memoNamespace.windowLayout(reg), r.count >= 4 else { continue }
        if r[2] > 0.0 && r[3] > 0.0
            && r[0] < page[0] + page[2]
            && r[0] + r[2] > page[0]
            && r[1] < page[1] + page[3]
            && r[1] + r[3] > page[1]
        {
            out.insert(g)
        }
    }
    return out
}

private func panel<S>(
    _ k: Knobs,
    _ groups: [Group],
    _ st: Style,
    _ lens: KnobsAccess<S>,
    _ w: Float
) -> El {
    let g = k.current(groups)
    let title = g?.name ?? "Pick a part"
    let cx = Ctx(k: k, st: st, lens: lens, w: w - 2.0 * INSET)
    let curPlan = plan(k, groups, seen(k, groups))

    var top = col()
        .key("knobs-top")
        .wFull()
        .px(INSET)
        .pt(INSET)
        .pb(8.0)
        .gap(PAD)
        .child(head(k, groups, st, lens, g, title, true).pl(PAD))
    if let g {
        top = top.child(presets(cx, g))
    } else {
        top = top.child(
            text("Click a part of the window to tune it.")
                .key("knobs-hint")
                .font(LABEL)
                .color(st.fg3)
                .px(PAD)
                .h(28.0)
        )
    }
    top = top.child(filter(k, groups, st, lens, curPlan))
    if !curPlan.tabs.isEmpty && k.query.isEmpty {
        top = top.child(tabs(st, lens, curPlan))
    }

    let scroll = col()
        .key("knobs-scroll")
        .wFull()
        .grow(1.0)
        .minH(0.0)
        .scroll(ScrollSpec(stickBottom: false))
        .scrollEdgeFade(24.0)
        .child(list(cx, groups, curPlan))

    let keys = curPlan
    return col()
        .key("knobs-panel")
        .absolute(0.0, 0.0)
        .w(w)
        .hFull()
        .minH(0.0)
        .fill(st.bg)
        .focusable(true)
        .noFocusRing()
        .onKey { (s: inout S, ev: KeyEvent, tx: inout Tx) in
            lens.withMutable(&s) { k in
                guard k.open else { return false }
                let wasFiltering = k.filtering
                if k.filtering {
                    k.editModel.focused = false
                }
                let did = k.treeKey(groups, keys, ev)
                if !wasFiltering && k.filtering {
                    tx.focus("knobs-filter-input")
                }
                return took(&k, did, groups, &tx)
            }
        }
        // The pointer moving takes the highlight from the keyboard's row, so only one row is lit.
        .onPointerMoveLocal { (s: inout S, _, tx: inout Tx) in
            lens.withMutable(&s) { k in
                if k.kbd && k.drag == nil {
                    k.kbd = false
                    tx.instant()
                } else {
                    tx.liveOnly()
                }
            }
        }
        .child(el().key("knobs-rim").absolute(0.0, 0.0).w(0.5).hFull().fill(st.border))
        .child(top)
        .child(scroll)
        .child(about(k, groups, st))
}

/// What a panel key did, shown: the motion it asks for and the keyboard's row in view. True if
/// the key was taken.
private func took(_ k: inout Knobs, _ did: Did, _ groups: [Group], _ tx: inout Tx) -> Bool {
    switch did {
    case .not:
        return false
    case .now:
        if k.open {
            tx.instant()
        } else {
            tx.motion(k.slide())
        }
    case .fold:
        tx.motion(k.foldSpring())
    }
    if let n = k.at() {
        tx.scrollIntoView(nodeKey(n, groups))
    }
    return true
}

/// How to start typing, or the field: a single-line text field while it edits, with the
/// keys the panel keeps (↑ ↓ Tab, Return, Esc) handled before it, and the matches counted on
/// the right.
private func filter<S>(
    _ k: Knobs,
    _ groups: [Group],
    _ st: Style,
    _ lens: KnobsAccess<S>,
    _ plan: Plan
) -> El {
    let typed = !k.query.isEmpty
    var r = row()
        .key("knobs-filter")
        .wFull()
        .h(28.0)
        .px(PAD)
        .gap(8.0)
        .centerY()
        .radius(7.0)
        .fill(st.inset)

    if k.filtering {
        let keys = plan
        var edit = k.edit()
        if edit.text != k.query {
            edit.replaceText(k.query)
        }
        let field = textInput(edit, LABEL)
            .key("knobs-filter-input")
            .singleLine()
            .color(st.fg)
            .caret(st.fg2, st.fg.alpha(0.22))
            .grow(1.0)
            .minW(0.0)
            .onEdit(editAccess { (s: inout S, body: (inout TextEdit) -> Void) in
                lens.withMutable(&s) { k in
                    body(&k.editModel)
                }
            })
            .onInputKey { (s: inout S, ev: KeyEvent, tx: inout Tx) in
                lens.withMutable(&s) { k in
                    k.syncEdit()
                    let did = k.filterKey(groups, keys, ev)
                    if did != .not && !k.filtering {
                        tx.focus("knobs-panel")
                    }
                    return took(&k, did, groups, &tx)
                }
            }
            .onInputChange { (s: inout S, tx: inout Tx) in
                tx.instant()
                lens.withMutable(&s) { k in
                    k.edited()
                    k.kbd = true
                    k.refilter(groups, keys)
                }
            }
            // PORT NOTE: Also route focused filter keys through `El.onKey` so headless `Runtime`
            // (`input_keys.swift`) intercepts panel navigation keys before editing `k.editModel`.
            .onKey { (s: inout S, ev: KeyEvent, tx: inout Tx) in
                lens.withMutable(&s) { k in
                    k.syncEdit()
                    let did = k.filterKey(groups, keys, ev)
                    if did != .not {
                        if !k.filtering {
                            tx.focus("knobs-panel")
                        }
                        return took(&k, did, groups, &tx)
                    }
                    let prev = k.editModel.text
                    if ev.isCommand("a") {
                        k.editModel.anchor = 0
                        k.editModel.focus = k.editModel.text.utf8.count
                        tx.instant()
                        return true
                    }
                    if ev.isCommand("c") {
                        let sel = k.editModel.selectedText()
                        if !sel.isEmpty {
                            tx.copy(sel)
                        }
                        tx.instant()
                        return true
                    }
                    if ev.isCommand("x") {
                        let sel = k.editModel.selectedText()
                        if !sel.isEmpty {
                            tx.copy(sel)
                            k.editModel.insert("")
                        }
                        tx.instant()
                        if k.editModel.text != prev {
                            k.edited()
                            k.kbd = true
                            k.refilter(groups, keys)
                        }
                        return true
                    }
                    if ev.isCommand("v") {
                        tx.paste()
                        tx.instant()
                        return true
                    }
                    let singleEv: KeyEvent
                    if case .text(let raw) = ev.key {
                        let clean = raw
                            .replacingOccurrences(of: "\r\n", with: " ")
                            .replacingOccurrences(of: "\n", with: " ")
                            .replacingOccurrences(of: "\r", with: " ")
                        singleEv = KeyEvent(key: .text(clean), mods: ev.mods)
                    } else {
                        singleEv = ev
                    }
                    let out = k.editModel.key(singleEv)
                    if let copied = out.copy {
                        tx.copy(copied)
                    }
                    if out.blur {
                        tx.blur()
                    }
                    tx.instant()
                    if k.editModel.text != prev {
                        k.edited()
                        k.kbd = true
                        k.refilter(groups, keys)
                    }
                    return true
                }
            }
        // Taking the field out gives focus back to the panel.
        r = r.child(
            el()
                .key("knobs-filter-field")
                .grow(1.0)
                .minW(0.0)
                .hFull()
                .centerY()
                .focusReturn("knobs-panel")
                .child(field)
        )
    } else {
        r = r
            .onPressTx { (s: inout S, tx: inout Tx) in
                tx.instant()
                tx.focus("knobs-filter-input")
                lens.withMutable(&s) { k in
                    k.kbd = true
                    k.startFilter()
                }
            }
            .child(
                text(typed ? k.query : "Press / to filter")
                    .font(LABEL)
                    .color(typed ? st.fg : st.fg3)
                    .truncateFade()
                    .shrink()
            )
    }

    if typed {
        let n = plan.sections.flatMap(\.subs).reduce(0) { $0 + $1.knobs.count }
        if !k.filtering {
            r = r.child(spacer())
        }
        r = r.child(text(n == 1 ? "1 knob" : "\(n) knobs").font(VALUE).color(st.fg3))
    }
    return r
}

/// The knob the pointer is over, or else the keyboard's.
private func described(_ k: Knobs, _ groups: [Group]) -> Knob? {
    if let h = k.hot {
        return groups.flatMap(\.knobs).first(where: { $0.name == h })
    }
    if case .knob(let g, let i)? = k.at(), k.kbd {
        guard g >= 0, g < groups.count, i >= 0, i < groups[g].knobs.count else { return nil }
        return groups[g].knobs[i]
    }
    return nil
}

/// The line under the list: what the knob in hand does, and the option under the pointer
/// (or the one picked), or the keys.
private func about(_ k: Knobs, _ groups: [Group], _ st: Style) -> El {
    let c = col().key("knobs-about").wFull().h(64.0).px(INSET + PAD).pt(8.0).gap(2.0)
    guard let d = described(k, groups) else {
        return c.child(
            text("↑↓ move   ←→ fold, open or change   1–9 pick   / filter")
                .font(ABOUT)
                .color(st.fg3)
                .wrap()
        )
    }
    var out = c.child(text(d.title()).font(ABOUT_TITLE).color(st.fg2).truncateFade())
    let desc = d.describe()
    if !desc.isEmpty {
        out = out.child(text(desc).key("knobs-about-line").font(ABOUT).color(st.fg3).wrap())
    }
    let opt: Int?
    if let hotOpt = k.hotOpt, hotOpt.0 == d.name {
        opt = hotOpt.1
    } else if !d.labels.isEmpty {
        opt = Int(k.get(d).rounded())
    } else {
        opt = nil
    }
    if let j = opt, j >= 0, j < d.labels.count {
        let optLabel = d.labels[j]
        let optHint = d.hint(j)
        if !optHint.isEmpty {
            out = out.child(
                text("\(optLabel): \(optHint)")
                    .key("knobs-about-option")
                    .font(ABOUT)
                    .color(st.fg2)
                    .truncateFade()
            )
        }
    }
    return out
}

// PORT NOTE: Helper binding `knobs-filter-input` on a headless `Runtime<S>` so `Runtime.paste(_:)`
// and pointer caret/focus mutations sync directly into `Knobs.editModel` and `Knobs.query`.
extension Runtime {
    public func bindKnobsFilter(_ groups: [Group], _ lens: KnobsAccess<S>) {
        bindEdit("knobs-filter-input", EditAccess { s, mutate in
            lens.withMutable(&s) { k in
                k.syncEdit()
                let prev = k.editModel.text
                mutate(&k.editModel)
                if k.editModel.text != prev {
                    k.edited()
                    k.kbd = true
                    let p = plan(k, groups, [])
                    k.refilter(groups, p)
                }
            }
        })
    }

    public func bindKnobsFilter(_ groups: [Group], _ keyPath: WritableKeyPath<S, Knobs>) {
        bindKnobsFilter(groups, KnobsAccess(keyPath))
    }

    public func bindKnobsFilter(
        _ groups: [Group],
        _ lens: @escaping (inout S, (inout Knobs) -> Void) -> Void
    ) {
        bindKnobsFilter(groups, KnobsAccess(lens))
    }
}
