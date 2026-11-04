// Ported from: crates/rune-knobs/src/side_list.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

/// How the side panel draws its `Plan`: pages with their groups under them, captions, tabs.
/// A header press folds or opens its section on ``Knobs/foldSpring()``; a folded section keeps
/// its rows under a clip that closes to nothing, so they roll up rather than vanish.

import Rune

private let PAGE_H: Float = 34.0
private let GROUP_H: Float = 30.0
/// How far a page's groups sit in from its header.
private let NEST: Float = 12.0
private let PAGE: TextStyle = TextStyle.new(13.0, 600.0).lh(18.0)
private let GROUP: TextStyle = TextStyle.new(12.0, 550.0).lh(16.0)
private let CAPTION: TextStyle = TextStyle.new(11.0, 600.0).lh(14.0).tracking(0.3)

func list<S>(_ cx: Ctx<S>, _ groups: [Group], _ plan: Plan) -> El {
    var l = col().key("knobs-sections").wFull().px(INSET).pb(INSET)
    for s in plan.sections {
        l = l.child(section(cx, groups, s))
    }
    if plan.sections.allSatisfy({ $0.subs.isEmpty }) {
        l = l.child(
            text("Nothing matches")
                .key("knobs-none")
                .font(GROUP)
                .color(cx.st.fg3)
                .px(PAD)
                .h(GROUP_H)
        )
    }
    return l
}

/// Rows that fold: open, they take their own height; folded, none, on the fold spring.
private func body(_ open: Bool) -> El {
    let b = col().key("body").wFull().clipSoft(0.0)
    return open ? b : b.h(0.0)
}

private func section<S>(_ cx: Ctx<S>, _ groups: [Group], _ s: Section) -> El {
    let k = cx.k
    let st = cx.st
    let lens = cx.lens
    let buildSubs: (El, Float) -> El = { container, sticky in
        var c = container
        for sub in s.subs {
            c = c.child(group(cx, groups, sub, sticky))
        }
        return c
    }

    switch s.head {
    case .bare:
        return buildSubs(col().key("knobs-bare").wFull(), 0.0)

    case .caption(let c):
        let capRow = row()
            .key("cap")
            .wFull()
            .h(28.0)
            .px(PAD)
            .itemsEnd()
            .pb(6.0)
            .child(text(c.uppercased()).font(CAPTION).color(st.fg3))
        return buildSubs(col().key("knobs-cap-\(c)").wFull().child(capRow), 0.0)

    case .page(let p):
        let i = groups.firstIndex(where: { $0.page() == p }) ?? 0
        let on = k.kbd && k.at() == .page(p)
        let n = s.subs.reduce(0) { $0 + groups[$1.g].knobs.count }
        let open = s.open
        var header = row()
            .key("head")
            .role("button")
            .label(p)
            .wFull()
            .h(PAGE_H)
            .px(PAD)
            .gap(7.0)
            .centerY()
            .radius(7.0)
            .fill(on ? st.fillHover : st.bg)
            .stickyTop(0.0)
            .onPressTx { (state: inout S, tx: inout Tx) in
                lens.withMutable(&state) { k in
                    tx.motion(k.foldSpring())
                    k.setFolded(p, open)
                    k.atNode = .page(p)
                    k.kbd = true
                }
            }
            .child(text(p).font(PAGE).color(s.seen ? st.fg : st.fg2).truncateFade().shrink())
        if s.seen {
            header = header.child(dot(st))
        }
        header = header
            .child(spacer())
            .child(text("\(n)").font(VALUE).color(s.open ? st.fg3 : st.fg2))
        return col()
            .key("knobs-page-\(i)")
            .wFull()
            .child(header)
            .child(buildSubs(body(s.open), PAGE_H))
    }
}

/// The on-screen mark beside a name.
private func dot(_ st: Style) -> El {
    el().key("seen").w(5.0).h(5.0).radius(2.5).fill(st.fg3)
}

/// A group under its page's header: `sticky` is where its header sticks, below the page's.
private func group<S>(_ cx: Ctx<S>, _ groups: [Group], _ sub: Sub, _ sticky: Float) -> El {
    let nested = sticky > 0.0
    let k = cx.k
    let st = cx.st
    let lens = cx.lens
    let g = groups[sub.g]
    let name = g.name
    let gi = sub.g
    let current = (k.group == name)
    let lit = current || (k.hover == name)
    let on = k.kbd && k.at() == .group(gi)
    let title = (sub.full && !g.under.isEmpty) ? "\(g.under) · \(name)" : name
    let open = sub.open

    var header = row()
        .key("head")
        .role("button")
        .label(name)
        .wFull()
        .h(GROUP_H)
        .pl(nested ? (PAD + NEST) : PAD)
        .pr(PAD)
        .gap(7.0)
        .centerY()
        .radius(7.0)
        .fill(on ? st.fillHover : st.bg)
        .stickyTop(sticky)
        .onHoverChange { (s: inout S, inside: Bool, tx: inout Tx) in
            tx.instant()
            lens.withMutable(&s) { k in
                if inside {
                    k.hover = name
                    if k.drag == nil {
                        k.kbd = false
                    }
                } else if k.hover == name {
                    k.hover = nil
                }
            }
        }
        .onPressTx { (s: inout S, tx: inout Tx) in
            lens.withMutable(&s) { k in
                tx.motion(k.foldSpring())
                k.setFolded(name, open)
                k.atNode = .group(gi)
                k.kbd = true
                if !open {
                    k.group = name
                }
            }
        }
        .onSecondaryPress { (s: inout S, _, tx: inout Tx) in
            tx.instant()
            lens.withMutable(&s) { $0.reset(g) }
        }
        .child(text(title).font(GROUP).color(lit ? st.fg : st.fg2).truncateFade().shrink())

    if sub.seen && !sub.full {
        header = header.child(dot(st))
    }
    header = header.child(spacer())

    // Hovered, the header offers Random and Reset for its group in place of its count.
    if k.hover == name {
        header = header
            .gap(2.0)
            .pr(PAD - 6.0)
            .child(tool(st, "random", icons.RANDOM, "Random", true, lens) { k, _ in
                k.random(g)
            })
            .child(tool(st, "reset", icons.RESET, "Reset", k.canReset(g), lens) { k, _ in
                k.reset(g)
            })
    } else {
        header = header.child(text("\(sub.knobs.count)").font(VALUE).color(open ? st.fg3 : st.fg2))
    }

    let mark: Int?
    if case .knob(let kg, let ki)? = k.at(), k.kbd && kg == gi {
        mark = ki
    } else {
        mark = nil
    }

    return col()
        .key(sectionKey(gi))
        .wFull()
        .child(header)
        .child(body(open).child(card(cx, g, gi, sub.knobs, mark).mb(INSET)))
}

/// The Tabs layout's pages: the one showing underlined, pages with nothing on screen dimmer.
func tabs<S>(_ st: Style, _ lens: KnobsAccess<S>, _ plan: Plan) -> El {
    var r = row().key("knobs-tabs").wFull().flexWrap().gap(14.0).px(PAD)
    for (i, (p, isSeen)) in plan.tabs.enumerated() {
        let on = (plan.tab == p)
        let pageName = p
        r = r.child(
            col()
                .key("knobs-tab-\(i)")
                .role("tab")
                .label(pageName)
                .h(26.0)
                .onPressTx { (s: inout S, tx: inout Tx) in
                    tx.instant()
                    lens.withMutable(&s) { k in
                        k.tab = pageName
                        k.atNode = nil
                    }
                }
                .child(spacer())
                .child(text(pageName).font(CHIP).color(on ? st.fg : (isSeen ? st.fg2 : st.fg3)))
                .child(spacer())
                .child(el().key("bar").wFull().h(1.5).radius(1.0).fill(on ? st.handle : Color.TRANSPARENT))
        )
    }
    return r
}
