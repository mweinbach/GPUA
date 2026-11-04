// Ported from: crates/rune-knobs/src/rows.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

/// The rows every panel shares (the side panel, the floating one, a storybook's column): a
/// group's preset tray and its card of knobs. Rows lay out for the card width they're given.

import Rune

let PAD: Float = 10.0
let ROW: Float = 32.0

let LABEL: TextStyle = TextStyle.new(12.0, 450.0).lh(16.0)
let VALUE: TextStyle = TextStyle.new(11.5, 450.0).lh(16.0).features("'tnum' 1")
let TITLE: TextStyle = TextStyle.new(13.0, 600.0).lh(18.0).tracking(-0.13)
let CHIP: TextStyle = TextStyle.new(12.0, 500.0).lh(16.0)
private let CHIP_ON: TextStyle = TextStyle.new(12.0, 600.0).lh(16.0)
/// The number key over each option of the keyboard's choice.
private let DIGIT: TextStyle = TextStyle.new(8.5, 600.0).lh(10.0).features("'tnum' 1")

/// More options than this get a stepper, with the whole list a click away.
private let LONG: Int = 10
/// Option cells: their padding, the gap between them and the well's inset.
private let OPT_PAD: Float = 7.0
private let OPT_GAP: Float = 2.0
private let WELL: Float = 2.0

/// How wide `s` sets in `style`.
private func textW(_ s: String, _ style: TextStyle) -> Float {
    Rune.measure(s, [], style, nil).0
}

/// What the rows need: the knobs, the look, the way back to the app's `Knobs`, and the card's
/// width.
struct Ctx<S> {
    var k: Knobs
    var st: Style
    var lens: KnobsAccess<S>
    var w: Float
}

/// Which knob a row is: its group's name and index among the groups, and its own index.
private struct Id: Sendable {
    var group: String
    var g: Int
    var i: Int
}

/// Using a knob makes it the panel's group and the keyboard's knob.
private func touch(_ k: inout Knobs, _ id: Id) {
    if k.group != id.group {
        k.group = id.group
    }
    k.cursor = id.i
    k.atNode = .knob(id.g, id.i)
    k.kbd = true
}

/// Hovering a knob shows what it does under the side panel; right-clicking it puts it back to
/// its default.
private func hovers<S>(_ e: El, _ lens: KnobsAccess<S>, _ id: Id, _ d: Knob) -> El {
    let name = d.name
    return e
        .onSecondaryPress { (s: inout S, _, tx: inout Tx) in
            tx.instant()
            lens.withMutable(&s) { k in
                touch(&k, id)
                k.resetKnob(d)
            }
        }
        .onHoverChange { (s: inout S, inside: Bool, tx: inout Tx) in
            tx.instant()
            lens.withMutable(&s) { k in
                if inside {
                    k.hot = name
                    if k.drag == nil {
                        k.kbd = false
                    }
                } else if k.hot == name {
                    k.hot = nil
                }
            }
        }
}

/// Knobs `show` of `g` (group `gi` of the panel's) on one card; `mark` is the keyboard's knob.
func card<S>(_ cxIn: Ctx<S>, _ g: Group, _ gi: Int, _ show: [Int], _ mark: Int?) -> El {
    var cx = cxIn
    // The rows that choose a layout by width (a choice: beside its label, or a grid) read the
    // card's laid-out width; `cx.w` is where the first frame starts. The read is rounded, so
    // only a real resize rebuilds.
    if let w = memoNamespace.layoutWith("knobs-card", { r in r.count >= 3 ? r[2].rounded() : 0.0 }), w > 0.0 {
        cx.w = w
    }
    var cardEl = col().key("knobs-card").wFull().radius(8.0).fill(cx.st.fill).clipRounded(8.0)
    for (n, i) in show.enumerated() {
        let d = g.knobs[i]
        let id = Id(group: g.name, g: gi, i: i)
        var r = d.labels.isEmpty ? slider(cx, id, d) : choice(cx, id, d)
        if mark == i {
            r = r.fill(cx.st.fillHover)
        }
        if n > 0 {
            r = r.child(el().key("rule").absolute(0.0, 0.0).wFull().h(0.5).fill(cx.st.rule))
        }
        cardEl = cardEl.child(r)
    }
    return cardEl
}

func presets<S>(_ cx: Ctx<S>, _ g: Group) -> El {
    let k = cx.k
    let st = cx.st
    let lens = cx.lens
    let active = k.active(g)
    var names: [(String, Bool)] = [(DEFAULT, false)]
    for p in g.presets {
        names.append((p.name, false))
    }
    if let savedList = k.saved[g.name] {
        for (n, _) in savedList {
            names.append((n, true))
        }
    }
    var tray = row().key("knobs-presets").wFull().flexWrap().gap(2.0).padding(2.0).radius(8.0).fill(st.inset)
    for (i, (name, isSaved)) in names.enumerated() {
        let on = (name == active)
        let drifted = on && k.drifted(g, name)
        let shown = (name == DEFAULT) ? g.defaultLabel : name
        let presetName = name
        var chip = row()
            .key("knobs-preset-\(i)")
            .role("button")
            .label(shown)
            .grow(1.0)
            .minW(52.0)
            .h(24.0)
            .px(8.0)
            .gap(5.0)
            .center()
            .radius(6.0)
            .fill(on ? st.raised : Color.TRANSPARENT)
            .hover(st.fillHover)
            .onPressTx { (s: inout S, tx: inout Tx) in
                tx.instant()
                lens.withMutable(&s) { $0.apply(g, presetName) }
            }
            .child(text(shown).font(on ? CHIP_ON : CHIP).color(on ? st.fg : st.fg2))
        if drifted {
            chip = chip.child(el().key("drift").w(4.0).h(4.0).radius(2.0).fill(st.fg3))
        }
        if isSaved {
            chip = chip.help("Right-click to delete").onSecondaryPress { (s: inout S, _, tx: inout Tx) in
                tx.instant()
                lens.withMutable(&s) { $0.delete(g, presetName) }
            }
        }
        tray = tray.child(chip)
    }
    return tray.child(
        row()
            .key("knobs-save")
            .role("button")
            .label("Save preset")
            .help("Save preset")
            .w(28.0)
            .h(24.0)
            .center()
            .radius(6.0)
            .hover(st.fillHover)
            .onPressTx { (s: inout S, tx: inout Tx) in
                tx.instant()
                lens.withMutable(&s) { _ = $0.save(g) }
            }
            .child(text("+").font(TITLE).color(st.fg3))
    )
}

/// Formats `v` for `d`'s readout according to its step and range span.
public func readout(_ d: Knob, _ v: Float) -> String {
    let span = d.max - d.min
    if d.step >= 1.0 || span > 20.0 {
        return formatFixed(v, 0)
    } else if span > 2.0 {
        return formatFixed(v, 1)
    } else {
        return formatFixed(v, 2)
    }
}

private func slider<S>(_ cx: Ctx<S>, _ id: Id, _ d: Knob) -> El {
    let i = id.i
    let k = cx.k
    let st = cx.st
    let lens = cx.lens
    let v = k.get(d)
    let frac: Float = d.max > d.min ? (v - d.min) / (d.max - d.min) : 0.0
    let hot = (k.hot == d.name)
    let held = (k.drag == d.name)
    let changed = abs(v - d.`default`) > 1e-4
    let tint: Color = held ? st.sliderActive : (hot ? st.sliderHover : st.slider)

    let base = el()
        .key("knobs-knob-\(i)")
        .role("slider")
        .label(d.title())
        .wFull()
        .h(ROW)
        .fill((hot || held) ? st.fillHover : Color.TRANSPARENT)

    return hovers(base, lens, id, d)
        .onDrag { (s: inout S, g: inout Drag, tx: inout Tx) in
            tx.instant()
            lens.withMutable(&s) { k in
                let span = d.max - d.min
                switch g.phase {
                case .down:
                    k.checkpoint()
                    touch(&k, id)
                    g.data = k.get(d)
                    k.drag = d.name
                case .move:
                    k.set(d, g.data + g.dx / max(g.w, 1.0) * span)
                case .up:
                    if g.cancelled() {
                        k.set(d, g.data)
                    } else if abs(g.dx) < 2.0 && abs(g.dy) < 2.0 {
                        let ratio = min(max(g.x / max(g.w, 1.0), 0.0), 1.0)
                        k.set(d, d.min + ratio * span)
                    }
                    if k.undoStack.last == k.values {
                        _ = k.undoStack.popLast()
                    }
                    k.drag = nil
                }
            }
        }
        .child(
            row()
                .key("fill")
                .absolute(0.0, 0.0)
                .wFrac(frac)
                .h(ROW)
                .fill(tint)
                .child(spacer())
                .child(
                    el()
                        .key("handle")
                        .w(3.0)
                        .minW(3.0)
                        .h(ROW - 12.0)
                        .mt(6.0)
                        .radius(1.5)
                        .fill(st.handle)
                        .opacity(held ? 0.95 : (hot ? 0.65 : 0.0))
                )
        )
        .child(
            row()
                .key("text")
                .absolute(0.0, 0.0)
                .wFull()
                .h(ROW)
                .px(PAD)
                .gap(8.0)
                .centerY()
                .child(text(d.title()).font(LABEL).color(st.fg2).truncateFade().shrink())
                .child(spacer())
                .child(text(readout(d, v)).font(VALUE).color((hot || held || changed) ? st.fg : st.fg2))
        )
}

/// How a choice lays out at a card width.
// PORT NOTE: Named `ChoiceShape` internally to avoid shadowing `Rune.Shape`.
enum ChoiceShape: Sendable, Equatable {
    /// The options beside the label.
    case inline
    /// The label over a grid of equal cells, `cols` across.
    case grid(cols: Int)
    /// The label and a stepper over the current option; the grid shows when expanded.
    case long(cols: Int)
}

/// The narrowest cell that fits every option, the settled dot included.
private func cellW(_ d: Knob, _ dot: Bool) -> Float {
    let widest = d.labels.reduce(Float(0.0)) { acc, l in max(acc, textW(l, CHIP_ON)) }
    return widest + 2.0 * OPT_PAD + (dot ? 9.0 : 0.0)
}

/// Columns for `n` cells of at least `cell` in `room`, balanced so the rows come out even
/// (six options in rows of three, not four and two).
private func columns(_ n: Int, _ cell: Float, _ room: Float) -> Int {
    guard n > 0 else { return 1 }
    let raw = ((room - 2.0 * WELL + OPT_GAP) / max(cell + OPT_GAP, 1e-6)).rounded(.down)
    let fitInt = raw.isFinite ? Int(max(raw, 0.0)) : 1
    let fit = min(max(fitInt, 1), max(n, 1))
    let rowCount = (n + fit - 1) / fit
    return (n + rowCount - 1) / rowCount
}

func shape(_ d: Knob, _ w: Float, _ dot: Bool) -> ChoiceShape {
    let n = d.labels.count
    let labelsSum = d.labels.reduce(Float(0.0)) { acc, l in acc + textW(l, CHIP_ON) + 2.0 * OPT_PAD }
    let inlineNeed = labelsSum + OPT_GAP * Float(max(n - 1, 0)) + 2.0 * WELL + (dot ? 9.0 : 0.0)
    if inlineNeed + textW(d.title(), LABEL) + 2.0 * PAD + 16.0 <= w {
        return .inline
    }
    let cols = columns(n, cellW(d, dot), w - 2.0 * (PAD - 6.0))
    return n > LONG ? .long(cols: cols) : .grid(cols: cols)
}

private func choice<S>(_ cx: Ctx<S>, _ id: Id, _ d: Knob) -> El {
    let lens = cx.lens
    // A click anywhere on the row, not only on an option, puts the keyboard on it for ←→.
    return hovers(choiceRow(cx, id, d), lens, id, d).onPressTx { (s: inout S, tx: inout Tx) in
        tx.instant()
        lens.withMutable(&s) { k in
            touch(&k, id)
        }
    }
}

private func choiceRow<S>(_ cx: Ctx<S>, _ id: Id, _ d: Knob) -> El {
    let i = id.i
    let k = cx.k
    let st = cx.st
    let lens = cx.lens
    let w = cx.w
    let at = Int(k.get(d).rounded())
    let settled: Int? = k.settled?[d.name].map { Int(d.clamp($0).rounded()) }
    let rowShape = shape(d, w, settled != nil)
    // The keyboard's choice numbers its options for 1–9, in the chip's left padding so nothing moves.
    let keyed = (k.at() == .knob(id.g, id.i))

    let option: (Int, String, Float?) -> El = { j, optLabel, cell in
        let on = (j == at)
        var o = row()
            .key("opt-\(j)")
            .role("button")
            .label(optLabel)
            .h(22.0)
            .px(OPT_PAD)
            .gap(5.0)
            .center()
            .radius(5.0)
            .fill(on ? st.raised : Color.TRANSPARENT)
            .hover(st.fillHover)
            .onHoverChange { (s: inout S, inside: Bool, tx: inout Tx) in
                tx.instant()
                lens.withMutable(&s) { k in
                    if inside {
                        k.hot = d.name
                        k.hotOpt = (d.name, j)
                    } else if let cur = k.hotOpt, cur.0 == d.name, cur.1 == j {
                        k.hotOpt = nil
                    }
                }
            }
            .onPressTx { (s: inout S, tx: inout Tx) in
                tx.instant()
                lens.withMutable(&s) { k in
                    k.checkpoint()
                    touch(&k, id)
                    k.set(d, Float(j))
                }
            }
            .child(text(optLabel).font(CHIP).color(on ? st.fg : st.fg2).truncateFade().shrink())
        if settled == j {
            o = o.child(el().key("current").w(4.0).h(4.0).radius(2.0).fill(st.fg3))
        }
        if keyed && j < 9 {
            o = o.child(text("\(j + 1)").key("digit").font(DIGIT).color(st.fg3).absolute(1.5, 1.5))
        }
        if let cw = cell {
            o = o.w(cw)
        }
        return o
    }

    let buildGrid: (Int) -> El = { cols in
        let safeCols = max(cols, 1)
        let room = w - 2.0 * (PAD - 6.0) - 2.0 * WELL
        let cw = (room - OPT_GAP * Float(safeCols - 1)) / Float(safeCols)
        var g = col().key("seg").wFull().padding(WELL).gap(OPT_GAP).radius(7.0).fill(st.inset)
        var r = 0
        var start = 0
        while start < d.labels.count {
            let end = min(start + safeCols, d.labels.count)
            var line = row().key("line-\(r)").gap(OPT_GAP)
            for idx in start..<end {
                let c = idx - start
                line = line.child(option(r * safeCols + c, d.labels[idx], cw))
            }
            g = g.child(line)
            start = end
            r += 1
        }
        return g
    }

    let titleEl = text(d.title()).font(LABEL).color(st.fg2).truncateFade().shrink()

    switch rowShape {
    case .inline:
        var seg = row().key("seg").h(26.0).padding(WELL).gap(OPT_GAP).radius(7.0).fill(st.inset)
        for (j, optLabel) in d.labels.enumerated() {
            seg = seg.child(option(j, optLabel, nil))
        }
        return row()
            .key("knobs-knob-\(i)")
            .wFull()
            .h(ROW + 4.0)
            .pl(PAD)
            .pr(PAD - 4.0)
            .gap(8.0)
            .centerY()
            .child(titleEl)
            .child(spacer())
            .child(seg)

    case .grid(let cols):
        return col()
            .key("knobs-knob-\(i)")
            .wFull()
            .px(PAD - 6.0)
            .pb(6.0)
            .child(row().key("head").wFull().h(ROW - 4.0).px(6.0).centerY().child(titleEl))
            .child(buildGrid(cols))

    case .long(let cols):
        let isOpen = (k.expanded == d.name)
        let n = max(d.labels.count, 1)
        let stepHandler: (Int) -> (inout S, inout Tx) -> Void = { by in
            return { s, tx in
                tx.instant()
                lens.withMutable(&s) { k in
                    let cur = Int(k.get(d).rounded())
                    k.checkpoint()
                    touch(&k, id)
                    k.set(d, Float(euclidMod(cur + by, n)))
                }
            }
        }
        let arrow: (String, String, Int) -> El = { arrowKey, glyph, by in
            row()
                .key(arrowKey)
                .role("button")
                .label(by < 0 ? "Previous" : "Next")
                .w(22.0)
                .h(22.0)
                .center()
                .radius(5.0)
                .hover(st.fillHover)
                .onPressTx(stepHandler(by))
                .child(text(glyph).font(CHIP).color(st.fg2))
        }
        let name = d.name
        let curLabel = (at >= 0 && at < d.labels.count) ? d.labels[at] : ""
        let current = row()
            .key("current")
            .role("button")
            .label("Show all options")
            .help("Show all options")
            .h(22.0)
            .px(8.0)
            .gap(6.0)
            .center()
            .radius(5.0)
            .fill(isOpen ? st.raised : Color.TRANSPARENT)
            .hover(st.fillHover)
            .onPressTx { (s: inout S, tx: inout Tx) in
                tx.instant()
                lens.withMutable(&s) { k in
                    k.expanded = (k.expanded == name) ? nil : name
                }
            }
            .child(text(curLabel).font(CHIP).color(st.fg))
            .child(text("\(at + 1)/\(d.labels.count)").font(VALUE).color(st.fg3))
        let stepper = row()
            .key("stepper")
            .h(26.0)
            .padding(WELL)
            .gap(OPT_GAP)
            .centerY()
            .radius(7.0)
            .fill(st.inset)
            .child(arrow("prev", "‹", -1))
            .child(current)
            .child(arrow("next", "›", 1))
        let headEl = row()
            .key("head")
            .wFull()
            .h(ROW + 4.0)
            .pl(6.0)
            .gap(8.0)
            .centerY()
            .child(titleEl)
            .child(spacer())
            .child(stepper)
        let c = col().key("knobs-knob-\(i)").wFull().px(PAD - 6.0).child(headEl)
        return isOpen ? c.pb(6.0).child(buildGrid(cols)) : c
    }
}
