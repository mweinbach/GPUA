// Ported from: crates/rune/src/playground/view.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The playground's window: the bar, the sidebar of stories, the stage and the side column.

extension PlaygroundLive {
    /// The window's root: the app's view above the bar, or the playground around its stage.
    func view(
        _ app: S,
        _ viewFn: (S, Cx<S>) -> El,
        _ cx: Cx<S>,
        _ viewport: (Float, Float)
    ) -> El {
        let isDark = appDark.map { $0(app) } ?? cx.systemDark()
        let t = tok.theme(isDark)
        if !open {
            if !bar {
                return playgroundCall(viewFn, app, cx)
            }
            let rootEl = playgroundCall(viewFn, app, cx)
            return col()
                .key("playground-closed")
                .w(viewport.0)
                .h(viewport.1)
                .child(rootEl.w(viewport.0).h(max(viewport.1 - PLAYGROUND_BAR, 0.0)))
                .child(barView(t))
        }
        let (sidebarW, sideW) = widths(viewport.0)
        let stageW = max(viewport.0 - sidebarW - sideW - 2.0, 0.0)
        var stageEl = stage(app, viewFn, cx, (stageW, viewport.1), t, isDark)
        if currentRegion == .stage {
            stageEl = stageEl.child(
                el()
                    .key("playground-stage-ring")
                    .pgPin(0.0, 0.0, 0.0, 0.0)
                    .border(2.0, cx.focusColor())
            )
        }
        let sideEl = side(app, cx, t, isDark, sideW, viewport.1)
        return row()
            .key("playground")
            .w(viewport.0)
            .h(viewport.1)
            .pgFill(t.bg)
            .child(sidebar(t, isDark, cx.accent(), cx.titlebarInset(), sidebarW, viewport.1))
            .child(el().w(1.0).h(viewport.1).pgFill(t.separator))
            .child(stageEl)
            .child(el().w(1.0).h(viewport.1).pgFill(t.separator))
            .child(sideEl)
            .child(sidebarEdge(sidebarW, viewport))
            .child(sideEdge(sideW, viewport))
    }

    private func barView(_ t: tok.Theme) -> El {
        let stories: String
        switch order.count {
        case 0: stories = ""
        case 1: stories = "1 story"
        default: stories = "\(order.count) stories"
        }
        let hint = shortcut.map(playgroundKeycaps)
        let parts = [stories.isEmpty ? nil : stories, hint].compactMap { $0 }
        let summary = parts.joined(separator: " · ")

        let openBtn = row()
            .key("playground-open")
            .h(20.0)
            .pgMl(4.0)
            .pgPx(6.0)
            .gap(6.0)
            .pgCenterY()
            .pgRadius(tok.radius.SM - 1.0)
            .hover(t.hover)
            .press(t.press)
            .child(icon(PLAYGROUND_GRID, 12.0).color(t.textSecondary))
            .child(text("Playground").font(tok.type_.LABEL).color(t.textSecondary))
            .role("button")
            .label("Open the playground")
            .pgOnPressTx { (_: inout PlaygroundControls, tx: inout Tx) in
                tx.openPlayground()
            }

        return col()
            .wFull()
            .h(PLAYGROUND_BAR)
            .pgFill(t.bg)
            .child(el().wFull().h(1.0).pgFill(t.separator))
            .child(
                row()
                    .wFull()
                    .h(PLAYGROUND_BAR - 1.0)
                    .pgCenterY()
                    .justifyBetween()
                    .child(openBtn)
                    .child(text(summary).font(tok.type_.LABEL).color(t.textSecondary).pgPr(10.0))
            )
    }

    /// Along the sidebar's foot: the stage's size, motion and appearance.
    func stageControls(_ t: tok.Theme, _ windowDark: Bool, _ sidebarW: Float) -> El {
        let isDark = dark ?? windowDark
        let (glyph, appearance) = isDark
            ? (PLAYGROUND_MOON, "Dark appearance")
            : (PLAYGROUND_SUN, "Light appearance")
        let themeBtn = playgroundIconButton(
            t,
            "playground-theme",
            glyph,
            appearance,
            false,
            windowDark,
            .dark(!isDark)
        )
        let reduceBtn = playgroundIconButton(
            t,
            "playground-reduce-motion",
            PLAYGROUND_MOTION,
            "Reduce Motion",
            reduceMotion,
            windowDark,
            .reduceMotion(!reduceMotion)
        )
        let sizeItems: [El] = sizes.isEmpty ? [] : [sizeMenu(t)]
        return row()
            .key("playground-stage-controls")
            .w(sidebarW)
            .h(PLAYGROUND_HEADER)
            .pgPx(8.0)
            .gap(2.0)
            .pgCenterY()
            .children(sizeItems)
            .child(spacer())
            .child(reduceBtn)
            .child(themeBtn)
    }

    /// The stage's size: the window's room or a preset, from a pop-up menu (a press steps
    /// through them where there's no native one).
    private func sizeMenu(_ t: tok.Theme) -> El {
        let presetIdx = size - 1
        let current: String
        if presetIdx >= 0 && presetIdx < sizes.count {
            current = sizes[presetIdx].0
        } else {
            current = "Window"
        }
        var options: [(String, String)] = [("0", "Window")]
        for (idx, (label, (w, h))) in sizes.enumerated() {
            options.append(("\(idx + 1)", "\(label)  \(pgFormatDimension(w))×\(pgFormatDimension(h))"))
        }
        let currentSize = size
        let totalChoices = sizes.count + 1

        return row()
            .key("playground-size")
            .h(PLAYGROUND_CONTROL)
            .pgPl(8.0)
            .pgPr(4.0)
            .gap(2.0)
            .pgCenterY()
            .pgRadius(tok.radius.SM)
            .hover(t.hover)
            .press(t.press)
            .child(text(current).font(tok.type_.LABEL).color(t.text))
            .child(icon(PLAYGROUND_CHEVRON_DOWN, 16.0).color(t.textSecondary))
            .role("button")
            .label("Stage size")
            .pgOnPressTx { (_: inout PlaygroundControls, tx: inout Tx) in
                if !popupMenuSupported() {
                    tx.pgPush(.size((currentSize + 1) % totalChoices))
                    return
                }
                let menu = PopupMenu.picker(options, "\(currentSize)")
                tx.popupMenu(menu, "playground-size") { (_: inout PlaygroundControls, picked: String?, tx: inout Tx) in
                    if let picked, let idx = Int(picked) {
                        tx.pgPush(.size(idx))
                    }
                }
            }
    }

    /// The column right of the stage: the story's group and name, the app's controls for it,
    /// its triggers, and a key hint.
    private func side(
        _ app: S,
        _ cx: Cx<S>,
        _ t: tok.Theme,
        _ dark: Bool,
        _ sideW: Float,
        _ height: Float
    ) -> El {
        let i = selected
        let titleItems: [El]
        if i < count() {
            titleItems = [
                col()
                    .key("playground-title")
                    .pgPx(4.0)
                    .gap(2.0)
                    .child(
                        text(group(i).replacingOccurrences(of: "/", with: " › "))
                            .font(tok.type_.SECTION)
                            .color(t.textSecondary)
                            .truncate()
                    )
                    .child(text(name(i)).font(tok.type_.TITLE).color(t.text).truncate())
            ]
        } else {
            titleItems = []
        }

        let slotEl: El? = sideSlot(app, cx).map { inner in
            let wrapped = el().key("playground-slot-\(i)").wFull().child(inner)
            return sideKeys() ? wrapped.focusable(true).noFocusRing() : wrapped
        }

        let variantNames = variants()
        let at = variantAt()
        let onFill = playgroundFocusedFill(cx.accent())

        let pickerItems: [El]
        if !variantNames.isEmpty {
            let rows = variantNames.prefix(9).enumerated().map { n, vName -> El in
                let on = n == at
                return row()
                    .key("playground-variant-\(n)")
                    .wFull()
                    .h(PLAYGROUND_ROW)
                    .pgPx(4.0)
                    .gap(8.0)
                    .pgCenterY()
                    .pgRadius(tok.radius.MD)
                    .pgFill(on ? playgroundSelectedFill(t, dark) : .TRANSPARENT)
                    .focusable(true)
                    .pgFocusHighlight(onFill)
                    .press(t.press)
                    .child(playgroundKeycap(t, "\(n + 1)"))
                    .child(
                        text(vName)
                            .font(tok.type_.BODY)
                            .color(on ? t.text : t.textSecondary)
                            .truncate()
                    )
                    .role("button")
                    .label(vName)
                    .pgOnPressTx { (_: inout PlaygroundControls, tx: inout Tx) in
                        tx.pgPush(.variant(n))
                    }
            }
            pickerItems = [
                col()
                    .key("playground-variants")
                    .wFull()
                    .pgPadding(4.0)
                    .gap(2.0)
                    .pgRadius(tok.radius.LG)
                    .pgFill(t.card)
                    .pgOutline(1.0, 0.0, t.cardBorder)
                    .children(rows)
            ]
        } else {
            pickerItems = []
        }

        let triggerPairs = triggers()
        let cardItems: [El]
        if !triggerPairs.isEmpty {
            let rows = triggerPairs.map { key, label -> El in
                let req: PlaygroundRequest = (key == "r") ? .replay : .trigger(key)
                return row()
                    .key("playground-trigger-\(key)")
                    .wFull()
                    .h(PLAYGROUND_ROW)
                    .pgPx(4.0)
                    .gap(8.0)
                    .pgCenterY()
                    .pgRadius(tok.radius.MD)
                    .focusable(true)
                    .pgFocusHighlight(onFill)
                    .press(t.press)
                    .child(playgroundKeycap(t, playgroundCap(key)))
                    .child(text(label).font(tok.type_.BODY).color(t.text).truncate())
                    .role("button")
                    .label(label)
                    .pgOnPressTx { (_: inout PlaygroundControls, tx: inout Tx) in
                        tx.pgPush(req)
                    }
            }
            cardItems = [
                col()
                    .key("playground-triggers")
                    .wFull()
                    .pgPadding(4.0)
                    .gap(2.0)
                    .pgRadius(tok.radius.LG)
                    .pgFill(t.card)
                    .pgOutline(1.0, 0.0, t.cardBorder)
                    .children(rows)
            ]
        } else {
            cardItems = []
        }

        let hasControls = slotEl != nil || !variantNames.isEmpty || !triggerPairs.isEmpty
        let hintText = hint(variantNames.count, hasControls)

        return col()
            .key("playground-side")
            .w(sideW)
            .h(height)
            .pgPx(12.0)
            .pgPt(12.0)
            .pgPb(12.0)
            .gap(12.0)
            .children(titleItems)
            .children(slotEl.map { [$0] } ?? [])
            .children(pickerItems)
            .children(cardItems)
            .child(spacer())
            .child(
                text(hintText)
                    .key("playground-hint")
                    .font(tok.type_.SECTION)
                    .color(t.textSecondary)
                    .pgPx(4.0)
                    .wrap()
            )
    }

    /// The keys of the column that has the keyboard, under the side column.
    private func hint(_ variantCount: Int, _ hasControls: Bool) -> String {
        let vText: String?
        switch min(variantCount, 9) {
        case 0: vText = nil
        case 1: vText = "1\u{a0}variant"
        case let n: vText = "1–\(n)\u{a0}variants"
        }
        let parts: [String?]
        switch currentRegion {
        case .list:
            parts = [
                "↑↓\u{a0}stories",
                "←→\u{a0}groups",
                "/\u{a0}filter",
                hasControls ? "Tab\u{a0}controls" : nil,
                "Esc\u{a0}back",
            ]
        case .side:
            parts = [
                "↑↓\u{a0}controls",
                vText,
                "Esc\u{a0}stories",
            ]
        case .stage:
            parts = [
                "Keys go to the story",
                "Esc\u{a0}stories",
            ]
        }
        return parts.compactMap { $0 }.joined(separator: "\u{a0}· ")
    }

    /// The app's controls for the open story, from ``Playground/side(_:_:)`` or ``Story/side(_:)``
    /// (or their `sideKeys`), acting on its stage state.
    private func sideSlot(_ app: S, _ cx: Cx<S>) -> El? {
        if let scene {
            guard let (_, sideKind) = sides.first(where: { $0.0 == selected }) else { return nil }
            let stageCx: Cx<S> = cx.retype()
            let rootEl: El
            switch sideKind {
            case .stage(let v):
                rootEl = v(scene.state, stageCx)
            case .real(let v):
                rootEl = v(scene.state, app, stageCx)
            case .keys(let v, _):
                rootEl = v(scene.state, sideActive, stageCx)
            }
            cx.absorb(stageCx)
            return rootEl
        }
        guard let (ownStory, stageBox) = own() else { return nil }
        let unitCx: Cx<Void> = cx.retype()
        let rootEl = ownStory.side(stageBox, sideActive, unitCx)
        cx.absorb(unitCx)
        return rootEl
    }

    private func stage(
        _ app: S,
        _ viewFn: (S, Cx<S>) -> El,
        _ cx: Cx<S>,
        _ area: (Float, Float),
        _ t: tok.Theme,
        _ windowDark: Bool
    ) -> El {
        var env = cx.env()
        env.systemDark = dark ?? windowDark
        let pageInfo = currentPage()
        let frameSize = own().flatMap { $0.0.frame() }
        let presetIdx = size - 1
        let preset: (Float, Float)? = (presetIdx >= 0 && presetIdx < sizes.count) ? sizes[presetIdx].1 : nil
        let stageLayout = layout()
        let (w, h): (Float, Float) = (stageLayout == .fill) ? area : (frameSize ?? preset ?? area)

        let contentOpt: El?
        if let scene {
            contentOpt = nested(cx, env) { c in
                playgroundCall(viewFn, scene.state, c)
            }
        } else if let (_, page) = pageInfo, case .live(let liveFn) = page.kind {
            contentOpt = nested(cx, env) { c in
                liveFn(app, c)
            }
        } else if pageInfo != nil {
            contentOpt = own().map { ownStory, stageBox in
                let unitCx: Cx<Void> = cx.retype()
                unitCx.envValue = env
                unitCx.titlebarInsetValue = 0.0
                if reduceMotion {
                    unitCx.reducedMotion(true)
                }
                let rootEl = ownStory.view(stageBox, unitCx)
                cx.absorb(unitCx)
                return rootEl
            }
        } else {
            contentOpt = nil
        }

        let inner = tok.theme(env.systemDark)
        let content = contentOpt ?? col().pgCenter().child(
            text("Add scenes to AppSpec::scenes, or stories to the playground")
                .font(tok.type_.BODY)
                .color(inner.textSecondary)
        )

        let stageKey = "playground-stage-\(generation)"
        var stageEl: El
        switch stageLayout {
        case .scroll:
            stageEl = col()
                .key(stageKey)
                .w(w)
                .h(h)
                .scroll(ScrollSpec(stickBottom: false))
                .child(
                    col()
                        .key("playground-margin")
                        .w(w)
                        .pgPadding(PLAYGROUND_SCROLL_MARGIN)
                        .child(content.w(max(w - 2.0 * PLAYGROUND_SCROLL_MARGIN, 0.0)))
                )
        case .center, .fill:
            stageEl = el()
                .key(stageKey)
                .w(w)
                .h(h)
                .child(content.w(w).h(h))
        }

        if stageLayout != .fill {
            if frameSize != nil {
                stageEl = stageEl.border(1.0, t.textSecondary.alpha(0.35)).pgBorderDash(4.0, 3.0)
            } else if preset != nil {
                stageEl = stageEl.pgOutline(1.0, 0.0, inner.separator)
            }
        }

        return col()
            .w(area.0)
            .h(area.1)
            .pgCenter()
            .pgFill(inner.bg)
            .pgClipRounded(0.0)
            .child(stageEl)
    }

    /// Runs a stage view of the app's own type with the stage's appearance and motion.
    private func nested(_ cx: Cx<S>, _ env: Env, _ f: (Cx<S>) -> El) -> El {
        let stageCx: Cx<S> = cx.retype()
        stageCx.envValue = env
        stageCx.titlebarInsetValue = 0.0
        if reduceMotion {
            stageCx.reducedMotion(true)
        }
        let rootEl = f(stageCx)
        cx.absorb(stageCx)
        return rootEl
    }
}

/// A selected row's fill, a step stronger in dark mode where the track is faint.
func playgroundSelectedFill(_ t: tok.Theme, _ dark: Bool) -> Color {
    dark ? t.controlOff : t.controlTrack
}

/// Text a step quieter than secondary: the list's counts and motion marks.
func playgroundTertiary(_ t: tok.Theme) -> Color {
    t.textSecondary.mix(t.bg, 0.45)
}

private func playgroundKeycap(_ t: tok.Theme, _ key: String) -> El {
    row()
        .key("cap")
        .h(20.0)
        .minW(22.0)
        .pgPx(6.0)
        .pgCenter()
        .pgRadius(tok.radius.SM - 2.0)
        .pgFill(t.controlTrack)
        .child(text(key).font(tok.type_.LABEL).color(t.text))
}

private func playgroundCap(_ key: Character) -> String {
    key == " " ? "Space" : String(key).uppercased()
}

private func playgroundKeycaps(_ shortcut: Shortcut) -> String {
    #if os(macOS)
    return shortcut.menuKeycaps().joined(separator: "")
    #else
    return shortcut.menuKeycaps().joined(separator: "+")
    #endif
}

private func playgroundIconButton(
    _ t: tok.Theme,
    _ key: String,
    _ glyph: Icon,
    _ label: String,
    _ on: Bool,
    _ dark: Bool,
    _ request: PlaygroundRequest
) -> El {
    let sel = playgroundSelectedFill(t, dark)
    return row()
        .key(key)
        .size(PLAYGROUND_CONTROL, PLAYGROUND_CONTROL)
        .pgCenter()
        .pgRadius(tok.radius.SM)
        .pgFill(on ? sel : .TRANSPARENT)
        .hover(on ? sel : t.hover)
        .press(t.press)
        .child(icon(glyph, 16.0).color(on ? t.text : t.textSecondary))
        .role("button")
        .label(label)
        .help(label)
        .pgOnPressTx { (_: inout PlaygroundControls, tx: inout Tx) in
            tx.pgPush(request)
        }
}

private func pgFormatDimension(_ v: Float) -> String {
    if v.isFinite && v.truncatingRemainder(dividingBy: 1.0) == 0.0 {
        return "\(Int(v))"
    }
    return "\(v)"
}

let PLAYGROUND_CHEVRON_LEFT = Icon(
    name: "playground-chevron-left",
    view: 16.0,
    body: #"<path d="M9.5 4L5.5 8L9.5 12" stroke="currentColor" stroke-width="1.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/>"#
)

let PLAYGROUND_GRID = Icon(
    name: "playground-grid",
    view: 12.0,
    body: #"<rect x="1" y="1" width="4" height="4" rx="1" fill="currentColor"/><rect x="7" y="1" width="4" height="4" rx="1" fill="currentColor"/><rect x="1" y="7" width="4" height="4" rx="1" fill="currentColor"/><rect x="7" y="7" width="4" height="4" rx="1" fill="currentColor"/>"#
)

let PLAYGROUND_CHEVRON_RIGHT = Icon(
    name: "playground-chevron-right",
    view: 16.0,
    body: #"<path d="M6.75 5L9.75 8L6.75 11" stroke="currentColor" stroke-width="1.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/>"#
)

let PLAYGROUND_CHEVRON_DOWN = Icon(
    name: "playground-chevron-down",
    view: 16.0,
    body: #"<path d="M5 6.75L8 9.75L11 6.75" stroke="currentColor" stroke-width="1.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/>"#
)

let PLAYGROUND_SUN = Icon(
    name: "playground-sun",
    view: 16.0,
    body: #"<circle cx="8" cy="8" r="2.75" stroke="currentColor" stroke-width="1.5" fill="none"/><path d="M8 1.75V3M8 13V14.25M1.75 8H3M13 8H14.25M3.6 3.6L4.45 4.45M11.55 11.55L12.4 12.4M3.6 12.4L4.45 11.55M11.55 4.45L12.4 3.6" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>"#
)

let PLAYGROUND_MOON = Icon(
    name: "playground-moon",
    view: 16.0,
    body: #"<path d="M13.25 9.5A5.5 5.5 0 0 1 6.5 2.75A5.5 5.5 0 1 0 13.25 9.5Z" stroke="currentColor" stroke-width="1.5" fill="none" stroke-linejoin="round"/>"#
)

let PLAYGROUND_MOTION = Icon(
    name: "playground-motion",
    view: 16.0,
    body: #"<circle cx="10" cy="8" r="3.25" stroke="currentColor" stroke-width="1.5" fill="none"/><path d="M1.75 5.5H4.5M1.25 8H4M1.75 10.5H4.5" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>"#
)
