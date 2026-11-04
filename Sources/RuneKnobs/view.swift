// Ported from: crates/rune-knobs/src/view.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

/// The layer ⌘⇧K opens: region picking over the window, and the panel, drawn to match the knobs
/// library's main look (flat accent-tinted slider fills with a hairline handle, label left and
/// readout right on one row, rows sharing one card, text tabs, a preset tray).

import Rune

private let W: Float = 300.0
private let CARD_W: Float = W - 2.0 * PAD
/// Where an inline panel's first frame starts, before its card's laid-out width is known: the
/// playground's side column.
private let INLINE_CARD_W: Float = 220.0

private let TAG: TextStyle = TextStyle.new(11.0, 550.0).lh(14.0)

/// The smallest region under the point.
func regionAt(_ rects: [(String, [Float])], _ x: Float, _ y: Float) -> String? {
    var bestName: String? = nil
    var bestArea: Float = .infinity
    for (name, r) in rects {
        guard r.count >= 4 else { continue }
        if x >= r[0] && x < r[0] + r[2] && y >= r[1] && y < r[1] + r[3] {
            let area = r[2] * r[3]
            if bestName == nil || area < bestArea {
                bestName = name
                bestArea = area
            }
        }
    }
    return bestName
}

/// The whole layer, to add over the app's root (it draws nothing while closed). `lens` finds
/// the app's `Knobs` in its state. Region rects are read in window points, so put it where
/// its top-left is the window's and nothing scales it.
public func layer<S>(_ k: Knobs, _ groups: [Group], _ st: Style, _ lens: KnobsAccess<S>) -> El {
    let l = overlay(k, groups, st, lens, "knobs-layer")
    if !k.open {
        return l
    }
    // PORT NOTE: Keep `knobs-dock` and its right-aligned anchor at `h(0.0)` so only the 300 pt
    // floating `knobs-panel` participates in `Runtime.hitTestNode` and clicks elsewhere pass through.
    return l.child(
        row()
            .key("knobs-dock")
            .absolute(0.0, 0.0)
            .wFull()
            .h(0.0)
            .pr(12.0)
            .child(spacer())
            .child(
                el()
                    .w(W)
                    .h(0.0)
                    .child(panel(k, groups, st, lens, nil).absolute(0.0, 12.0))
            )
    )
}

public func layer<S>(
    _ k: Knobs,
    _ groups: [Group],
    _ st: Style,
    _ keyPath: WritableKeyPath<S, Knobs>
) -> El {
    layer(k, groups, st, KnobsAccess(keyPath))
}

public func layer<S>(
    _ k: Knobs,
    _ groups: [Group],
    _ st: Style,
    _ lens: @escaping (inout S, (inout Knobs) -> Void) -> Void
) -> El {
    layer(k, groups, st, KnobsAccess(lens))
}

/// Region picking and the outline around a group's region, over the element keyed `key`
/// (which this is): it reads that element's place to put window rects inside it.
func overlay<S>(_ k: Knobs, _ groups: [Group], _ st: Style, _ lens: KnobsAccess<S>, _ key: String) -> El {
    // PORT NOTE: Size the overlay container to `h(0.0)` unless actively region-picking so
    // `Runtime.hitTestNode` does not intercept clicks over the underlying app page, and mark
    // `knobs-outline` `.inert()` so decorative region outlines never block region-pick clicks.
    var l = el()
        .key(key)
        .absolute(0.0, 0.0)
        .wFull()
    if k.open && k.picking {
        l = l.hFull()
    } else {
        l = l.h(0.0)
    }
    if !k.open {
        return l
    }
    let origin = memoNamespace.windowLayout(key)
    let ox: Float = (origin?.count ?? 0) >= 2 ? (origin?[0] ?? 0.0) : 0.0
    let oy: Float = (origin?.count ?? 0) >= 2 ? (origin?[1] ?? 0.0) : 0.0
    let rects: [(String, [Float])] = groups.compactMap { g in
        guard let r = memoNamespace.windowLayout(g.region), r.count >= 4 else { return nil }
        return (g.name, r)
    }
    let picking = k.picking
    if picking {
        let at = rects
        // PORT NOTE: Sort region hit targets largest-to-smallest so the smallest enclosing region
        // sits topmost in reverse paint-order hit-testing (`Runtime.pointerMove` / `onHoverChange`)
        // in addition to `onPointerMoveLocal`.
        let byLargest = rects.sorted { ($0.1[2] * $0.1[3]) > ($1.1[2] * $1.1[3]) }
        var pickEl = el()
            .key("knobs-pick")
            .absolute(0.0, 0.0)
            .wFull()
            .hFull()
            .onPointerMoveLocal { (s: inout S, e: PointerEvent, tx: inout Tx) in
                tx.instant()
                lens.withMutable(&s) { k in
                    let h = regionAt(at, e.windowX, e.windowY)
                    if k.hover != h {
                        k.hover = h
                    }
                }
            }
            .onHoverChange { (s: inout S, inside: Bool, tx: inout Tx) in
                if !inside {
                    tx.instant()
                    lens.withMutable(&s) { $0.hover = nil }
                }
            }
            .onPressTx { (s: inout S, tx: inout Tx) in
                tx.instant()
                lens.withMutable(&s) { k in
                    if let h = k.hover {
                        k.pick(h)
                        if let i = groups.firstIndex(where: { $0.name == h }) {
                            tx.scrollIntoView(sectionKey(i))
                        }
                    }
                }
            }
        for (rName, r) in byLargest {
            pickEl = pickEl.child(
                el()
                    .key("knobs-pick-\(rName)")
                    .absolute(r[0] - ox, r[1] - oy)
                    .w(r[2])
                    .h(r[3])
                    .hit()
                    .onHoverChange { (s: inout S, inside: Bool, tx: inout Tx) in
                        tx.instant()
                        lens.withMutable(&s) { k in
                            if inside {
                                k.hover = rName
                            } else if k.hover == rName {
                                k.hover = nil
                            }
                        }
                    }
            )
        }
        l = l.child(pickEl)
    }
    if let outlined = k.hover,
       let (name, r) = rects.first(where: { $0.0 == outlined })
    {
        var o = el()
            .key("knobs-outline")
            .inert()
            .absolute(r[0] - ox, r[1] - oy)
            .w(r[2])
            .h(r[3])
            .radius(6.0)
            .border(1.0, st.outline)
        if picking {
            o = o.child(
                row()
                    .key("knobs-tag")
                    .absolute(6.0, 6.0)
                    .h(20.0)
                    .px(7.0)
                    .centerY()
                    .radius(5.0)
                    .fill(st.bg)
                    .child(text(name).font(TAG).color(st.fg))
            )
        }
        l = l.child(o)
    }
    return l
}

/// The panel alone, for an app's own layout (a storybook's right-hand column): it doesn't
/// float, pick regions or take keys itself, and a single group shows no tabs. The app sends it
/// ↑ ↓ ← → with ``Knobs/panelKey(_:_:)``; `active` marks the knob those keys move. It fills its
/// parent's width, and its rows lay out from the width they get (a slider's track grows with
/// it), so a 240 pt column and a 300 pt one both read.
public func inline<S>(
    _ k: Knobs,
    _ groups: [Group],
    _ st: Style,
    _ lens: KnobsAccess<S>,
    _ active: Bool
) -> El {
    panel(k, groups, st, lens, active)
}

public func inline<S>(
    _ k: Knobs,
    _ groups: [Group],
    _ st: Style,
    _ keyPath: WritableKeyPath<S, Knobs>,
    _ active: Bool
) -> El {
    inline(k, groups, st, KnobsAccess(keyPath), active)
}

public func inline<S>(
    _ k: Knobs,
    _ groups: [Group],
    _ st: Style,
    _ lens: @escaping (inout S, (inout Knobs) -> Void) -> Void,
    _ active: Bool
) -> El {
    inline(k, groups, st, KnobsAccess(lens), active)
}

/// A card of buttons that each do one thing, with the key that does it on a cap: a story's
/// triggers ("R  Replay", "F  Finish a task"). The app binds the keys. It fills its parent's
/// width up to 300 pt.
public func actions<S>(_ st: Style, _ items: [Action<S>]) -> El {
    var cardEl = col()
        .key("knobs-actions")
        .wFull()
        .maxW(W)
        .padding(4.0)
        .gap(2.0)
        .radius(12.0)
        .fill(st.bg)
        .borderGradient(0.5, st.rim, st.border)
    for (i, a) in items.enumerated() {
        let run = a.run
        cardEl = cardEl.child(
            row()
                .key("knobs-action-\(i)")
                .role("button")
                .label(a.label)
                .wFull()
                .h(ROW)
                .px(6.0)
                .gap(10.0)
                .centerY()
                .radius(8.0)
                .hover(st.fillHover)
                .onPressTx { (s: inout S, tx: inout Tx) in
                    run(&s, &tx)
                }
                .child(
                    row()
                        .key("cap")
                        .h(20.0)
                        .minW(22.0)
                        .px(6.0)
                        .radius(5.0)
                        .fill(st.fillSelected)
                        .center()
                        .child(text(a.cap).font(VALUE).color(st.fg))
                )
                .child(text(a.label).font(LABEL).color(st.fg2))
        )
    }
    return cardEl
}

func tool<S>(
    _ st: Style,
    _ key: String,
    _ glyph: Icon,
    _ label: String,
    _ enabled: Bool,
    _ lens: KnobsAccess<S>,
    _ f: @escaping (inout Knobs, inout Tx) -> Void
) -> El {
    let b = row()
        .key(key)
        .role("button")
        .label(label)
        .help(label)
        .w(22.0)
        .h(22.0)
        .radius(6.0)
        .center()
        .child(icon(glyph, 14.0).color(st.fg2))
    if !enabled {
        return b.opacity(0.3)
    }
    return b.hover(st.fillHover).onPressTx { (s: inout S, tx: inout Tx) in
        tx.instant()
        lens.withMutable(&s) { k in
            f(&k, &tx)
        }
    }
}

/// The panel's title and its tools: pick a part (with `pick`), Random and Reset for `g`, Undo,
/// Copy values.
func head<S>(
    _ k: Knobs,
    _ groups: [Group],
    _ st: Style,
    _ lens: KnobsAccess<S>,
    _ g: Group?,
    _ title: String,
    _ pick: Bool
) -> El {
    var headEl = row()
        .key("knobs-head")
        .wFull()
        .h(22.0)
        .gap(2.0)
        .centerY()
        .child(text(title).font(TITLE).color(st.fg).truncateFade().shrink())
        .child(spacer())
    if pick {
        headEl = headEl.child(tool(st, "knobs-repick", icons.TARGET, "Pick a part", true, lens) { k, _ in
            k.pickRegion()
        })
    }
    if let g {
        headEl = headEl
            .child(tool(st, "knobs-random", icons.RANDOM, "Random", true, lens) { k, _ in
                k.random(g)
            })
            .child(tool(st, "knobs-reset", icons.RESET, "Reset", k.canReset(g), lens) { k, _ in
                k.reset(g)
            })
    }
    return headEl
        .child(tool(st, "knobs-undo", icons.UNDO, "Undo", k.canUndo(), lens) { k, _ in
            _ = k.undo()
        })
        .child(tool(st, "knobs-copy", icons.COPY, "Copy values", true, lens) { k, tx in
            let all: [Group]
            if let cur = k.current(groups) {
                all = [cur]
            } else {
                all = groups
            }
            tx.copy(all.map { k.code($0) }.joined(separator: "\n"))
        })
}

/// `inline` is `Some(active)` for ``inline(_:_:_:_:_:)``.
private func panel<S>(
    _ k: Knobs,
    _ groups: [Group],
    _ st: Style,
    _ lens: KnobsAccess<S>,
    _ inlineActive: Bool?
) -> El {
    let g = k.current(groups)
    let title: String
    if inlineActive != nil && groups.count == 1 {
        title = groups[0].name
    } else {
        title = "Knobs"
    }
    let headEl = head(k, groups, st, lens, g, title, inlineActive == nil)

    var tabsEl = row().key("knobs-tabs").wFull().gap(16.0).px(PAD)
    for (i, t) in groups.enumerated() {
        let on = (g?.name == t.name)
        let lit = on || (k.hover == t.name)
        let name = t.name
        tabsEl = tabsEl.child(
            col()
                .key("knobs-tab-\(i)")
                .role("tab")
                .label(name)
                .h(28.0)
                .onHoverChange { (s: inout S, inside: Bool, tx: inout Tx) in
                    tx.instant()
                    lens.withMutable(&s) { k in
                        if inside {
                            k.hover = name
                        } else if k.hover == name {
                            k.hover = nil
                        }
                    }
                }
                .onPressTx { (s: inout S, tx: inout Tx) in
                    tx.instant()
                    lens.withMutable(&s) { $0.pick(name) }
                }
                .child(spacer())
                .child(text(name).font(CHIP).color(lit ? st.fg : st.fg2))
                .child(spacer())
                .child(el().key("bar").wFull().h(1.5).radius(1.0).fill(on ? st.handle : Color.TRANSPARENT))
        )
    }

    var p = col().key("knobs-panel")
    p = (inlineActive != nil) ? p.wFull() : p.w(W)
    p = p.padding(PAD).radius(12.0).fill(st.bg).borderGradient(0.5, st.rim, st.border)

    if let active = inlineActive {
        var out = p.child(headEl.pl(PAD))
        if groups.count > 1 {
            out = out
                .child(tabsEl.mt(4.0))
                .child(el().key("knobs-rule").wFull().h(0.5).fill(st.border))
        }
        guard let g else { return out }
        return body(true, out, k, groups, g, st, lens, active)
    }

    let floating = p
        .shadow(8.0, 24.0, st.shadow)
        .shadow(1.0, 3.0, st.shadow)
        .onHoverChange { (s: inout S, inside: Bool, tx: inout Tx) in
            tx.instant()
            lens.withMutable(&s) { k in
                if inside && k.picking {
                    k.hover = nil
                }
            }
        }
        .focusable(true)
        .noFocusRing()
        .onKey { (s: inout S, ev: KeyEvent, tx: inout Tx) in
            tx.instant()
            return lens.withMutable(&s) { $0.panelKey(groups, ev) }
        }
        .onPressTx { (s: inout S, tx: inout Tx) in
            tx.instant()
            lens.withMutable(&s) { $0.kbd = true }
        }
        .child(headEl.pl(PAD))
        .child(tabsEl.mt(4.0))
        .child(el().key("knobs-rule").wFull().h(0.5).fill(st.border))

    guard let g else {
        return floating.child(
            text("Click a part of the window to tune it.")
                .key("knobs-hint")
                .font(LABEL)
                .color(st.fg3)
                .px(PAD)
                .mt(12.0)
                .mb(4.0)
        )
    }
    return body(false, floating, k, groups, g, st, lens, k.kbd)
}

/// The presets and the knobs' card, under the panel's head; `active` marks the keyboard's knob.
private func body<S>(
    _ isInline: Bool,
    _ p: El,
    _ k: Knobs,
    _ groups: [Group],
    _ g: Group,
    _ st: Style,
    _ lens: KnobsAccess<S>,
    _ active: Bool
) -> El {
    let cx = Ctx(k: k, st: st, lens: lens, w: isInline ? INLINE_CARD_W : CARD_W)
    let gi = groups.firstIndex(where: { $0.name == g.name }) ?? 0
    let all = Array(0..<g.knobs.count)
    let mark: Int? = (active && !all.isEmpty) ? min(k.cursor, all.count - 1) : nil
    return p
        .child(presets(cx, g).mt(PAD))
        .child(card(cx, g, gi, all, mark).mt(PAD))
}
