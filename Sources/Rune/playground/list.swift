// Ported from: crates/rune/src/playground/list.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The sidebar: Back, the filter field, the story list as an indented tree, and the stage's
//! controls along its foot.

/// The filter field's row: the field and the gap under it.
private let PLAYGROUND_FIELD: Float = 32.0

extension PlaygroundLive {
    func sidebar(
        _ t: tok.Theme,
        _ dark: Bool,
        _ accent: Color,
        _ inset: Float,
        _ sidebarW: Float,
        _ height: Float
    ) -> El {
        let back = row()
            .key("playground-back")
            .h(PLAYGROUND_CONTROL)
            .pgPl(4.0)
            .pgPr(8.0)
            .gap(2.0)
            .pgCenterY()
            .pgRadius(tok.radius.SM)
            .hover(t.hover)
            .press(t.press)
            .child(icon(PLAYGROUND_CHEVRON_LEFT, 16.0).color(t.textSecondary))
            .child(text("Back").font(tok.type_.LABEL).color(t.text))
            .role("button")
            .label("Back to the app")
            .pgOnPressTx { (_: inout PlaygroundControls, tx: inout Tx) in
                tx.closePlayground()
            }

        let band: Float = inset > 0.0 ? PLAYGROUND_BAND : 0.0
        let headerEl = row().w(sidebarW).h(PLAYGROUND_HEADER).pgPl(8.0).pgCenterY().child(back)
        let dragEl: [El] = band > 0.0 ? [el().w(sidebarW).h(band).pgWindowDrag()] : []

        let onFill = currentRegion == .list ? playgroundFocusedFill(accent) : playgroundSelectedFill(t, dark)
        var listCol = col().key("playground-rows").wFull()
        let rowList = rows()
        for (n, entry) in rowList.enumerated() {
            switch entry {
            case .header(let g, let first, let depth):
                listCol = listCol.child(headerRow(t, onFill, g, first, depth, n == 0))
            case .story(let i, let depth):
                listCol = listCol.child(storyRow(t, onFill, i, depth))
            }
        }
        if rowList.isEmpty {
            let empty = order.isEmpty ? "No stories" : "No matches"
            listCol = listCol.child(text(empty).font(tok.type_.BODY).color(t.textSecondary).pgPx(8.0).pgPt(4.0))
        }
        let scrollList = col()
            .key("playground-list")
            .w(sidebarW)
            .h(max(0.0, height - 2.0 * PLAYGROUND_HEADER - PLAYGROUND_FIELD - band))
            .pgPx(8.0)
            .pgPb(8.0)
            .scroll(ScrollSpec(stickBottom: false))
            .child(listCol)

        return col()
            .w(sidebarW)
            .h(height)
            .children(dragEl)
            .child(headerEl)
            .child(filterField(t, sidebarW))
            .child(scrollList)
            .child(stageControls(t, dark, sidebarW))
    }

    /// Narrows the list to the stories whose path has every word typed; `/` focuses it.
    private func filterField(_ t: tok.Theme, _ sidebarW: Float) -> El {
        let field = textInput(controls.filter, tok.type_.LABEL)
            .key(PLAYGROUND_FILTER)
            .singleLine()
            .color(t.text)
            .pgCaret(t.text, t.text.alpha(0.2))
            .placeholder("Filter", playgroundTertiary(t))
            .grow(1.0)
            .minW(0.0)
            .label("Filter stories")
            .pgOnEdit(EditAccess(\PlaygroundControls.filter))

        return row().w(sidebarW).h(PLAYGROUND_FIELD).pgPx(8.0).pgPb(8.0).child(
            row()
                .wFull()
                .h(PLAYGROUND_FIELD - 8.0)
                .pgPx(8.0)
                .pgCenterY()
                .pgRadius(tok.radius.MD)
                .pgFill(t.card)
                .pgOutline(1.0, 0.0, t.cardBorder)
                .child(field)
        )
    }

    /// A story's row, indented a step for each group it's in.
    private func storyRow(_ t: tok.Theme, _ onFill: Color, _ i: Int, _ depth: Int) -> El {
        let on = i == selected && header == nil
        let storyName = name(i)
        let mark: [El]
        if hasTriggers(i) {
            mark = [
                spacer(),
                icon(PLAYGROUND_MOTION, 12.0)
                    .key("playground-motion-\(i)")
                    .color(playgroundTertiary(t))
                    .pgMl(6.0),
            ]
        } else {
            mark = []
        }

        return row()
            .key("playground-item-\(i)")
            .wFull()
            .h(PLAYGROUND_ROW)
            .pgPl(playgroundIndent(depth))
            .pgPr(8.0)
            .pgCenterY()
            .pgRadius(tok.radius.MD)
            .pgFill(on ? onFill : .TRANSPARENT)
            .hover(on ? onFill : t.hover)
            .child(
                text(storyName)
                    .font(tok.type_.BODY)
                    .color((on || i == selected) ? t.text : t.textSecondary)
                    .truncate()
            )
            .children(mark)
            .role("button")
            .label(storyName)
            .pgOnPressTx { (_: inout PlaygroundControls, tx: inout Tx) in
                tx.pgPush(.select(i))
            }
    }

    /// A group's header, keyed by its first story and depth: a disclosure chevron, its name a
    /// step bolder than a story's, and how many stories it holds. A press selects it and folds
    /// or unfolds it.
    private func headerRow(
        _ t: tok.Theme,
        _ onFill: Color,
        _ groupName: String,
        _ first: Int,
        _ depth: Int,
        _ top: Bool
    ) -> El {
        let on = header == groupName
        let isGroupFolded = isFolded(groupName)
        let displayName: String
        if let up = Self.parent(groupName) {
            displayName = String(groupName.dropFirst(up.count + 1))
        } else {
            displayName = groupName
        }
        let ink = (on || depth == 0) ? t.text : t.textSecondary
        let hKey = PlaygroundRow.headerKey(first, depth)
        let countKey = hKey.replacingOccurrences(of: "group", with: "count")

        let headerRowEl = row()
            .key(hKey)
            .wFull()
            .h(24.0)
            .pgPl(playgroundIndent(depth))
            .pgPr(8.0)
            .pgCenterY()
            .pgRadius(tok.radius.MD)
            .pgFill(on ? onFill : .TRANSPARENT)
            .hover(on ? onFill : t.hover)
            .child(
                row()
                    .w(PLAYGROUND_INDENT)
                    .h(24.0)
                    .pgCenter()
                    .child(
                        icon(isGroupFolded ? PLAYGROUND_CHEVRON_RIGHT : PLAYGROUND_CHEVRON_DOWN, 12.0)
                            .color(playgroundTertiary(t))
                    )
            )
            .child(text(displayName).font(tok.type_.SECTION).color(ink).truncate())
            .child(spacer())
            .child(
                text("\(countIn(groupName))")
                    .key(countKey)
                    .font(tok.type_.LABEL)
                    .color(playgroundTertiary(t))
                    .pgMl(6.0)
            )
            .role("button")
            .label(isGroupFolded ? "Show \(displayName)" : "Hide \(displayName)")
            .pgOnPressTx { (_: inout PlaygroundControls, tx: inout Tx) in
                tx.pgPush(.header(groupName))
                tx.pgPush(.fold(groupName, nil))
            }

        let above: Float
        if top {
            above = 2.0
        } else if depth == 0 {
            above = 10.0
        } else {
            above = 4.0
        }
        return col().wFull().pgPt(above).pgPb(2.0).child(headerRowEl)
    }
}

/// A row's left inset at `depth`: its text lines up with its group's name.
private func playgroundIndent(_ depth: Int) -> Float {
    8.0 + PLAYGROUND_INDENT * Float(depth)
}

/// A selection's fill in the column that has the keyboard: the accent, softly.
func playgroundFocusedFill(_ accent: Color) -> Color {
    accent.alpha(0.2)
}
