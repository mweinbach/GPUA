// Tests ported from: crates/rune-kit/tests/table.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Table: column widths and resizing, sorting from the header, row selection and keys,
//! virtualisation, accessibility roles and truncation tooltips, in a headless runtime.

import Rune
import Testing
@testable import RuneKit

private struct TableFile {
    var id: String
    var name: String
    var size: UInt64
}

private struct TableSortEvent: Equatable {
    var col: String
    var dir: SortDir
}

private struct TableApp {
    var files: [TableFile]
    var table: TableState
    var sorts: [TableSortEvent]
    var opened: [String]

    static func new(_ n: Int, _ multi: Bool) -> TableApp {
        let files = (0..<n).map { i in
            TableFile(
                id: "f\(i)",
                name: "file \(i) with a name long enough to cut short.rs",
                size: (UInt64(i) * 7919) % 100_000
            )
        }
        return TableApp(
            files: files,
            table: TableState.new().multiSelect(multi),
            sorts: [],
            opened: []
        )
    }
}

private let tableW: Float = 500.0
private let tableH: Float = 300.0

private func tableView(_ s: TableApp, _: Cx<TableApp>) -> El {
    tableSizedView(s, tableW, tableH)
}

private func tableSizedView(_ s: TableApp, _ w: Float, _ h: Float) -> El {
    let k = Kit.neutral(true)
    return col().size(w, h).child(
        Table<TableApp>.new(\.table, { $0.files.count }, { $0.files[$1].id })
            .name("Files")
            .column(TableColumn.new("name", "Name").flex(1.0).min(120.0).sortable())
            .column(TableColumn.new("size", "Size").width(100.0).min(60.0).max(180.0).align(.end).sortable())
            .column(TableColumn.new("kind", "Kind").width(80.0).resizable(false))
            .cell { s, i, colId in
                switch colId {
                case "name":
                    return Cell.text(s.files[i].name)
                case "size":
                    return Cell.text(String(s.files[i].size)).mono()
                default:
                    return Cell.text("Rust").muted()
                }
            }
            .onSort { s, colId, dir, _ in
                s.sorts.append(TableSortEvent(col: colId, dir: dir))
                if colId == "size" {
                    s.files.sort { a, b in dir.ordered(a.size, b.size) }
                }
            }
            .onOpen { s, id, _ in
                s.opened.append(id)
            }
            .zebra(true)
            .build(s, k)
            .h(h)
    )
}

private func tableRuntime(_ app: TableApp) -> Runtime<TableApp> {
    let rt = Runtime.new(app, tableView, (tableW, tableH), Env.new(true, 1.0))
    _ = rt.frame(0.0)
    _ = rt.frame(1.0 / 60.0)
    return rt
}

private func tableFind(_ rt: Runtime<TableApp>, _ f: (ElementInfo) -> Bool) -> [ElementInfo] {
    rt.elements().filter { !$0.exiting && f($0) }
}

private func tableHeader(_ rt: Runtime<TableApp>, _ id: String) -> ElementInfo {
    tableFind(rt) { $0.role == "columnheader" && $0.key == id }[0]
}

private func tablePressWith(_ rt: Runtime<TableApp>, _ key: Key, _ mods: Mods) {
    _ = rt.keyDown(KeyEvent(key: key, mods: mods))
    _ = rt.frame(0.0)
}

private func tablePress(_ rt: Runtime<TableApp>, _ key: Key) {
    tablePressWith(rt, key, Mods())
}

private func tableClick(_ rt: Runtime<TableApp>, _ x: Float, _ y: Float) {
    _ = rt.pointerDown(x, y)
    rt.pointerUp(x, y)
    _ = rt.frame(0.0)
}

@Suite("TableIntegrationTests")
struct TableIntegrationTests {
    @Test func fixedColumnsKeepTheirWidthAndFlexTakesTheRestInHeaderAndRowsAlike() {
        let rt = tableRuntime(TableApp.new(20, false))
        let name = tableHeader(rt, "name")
        let size = tableHeader(rt, "size")
        let kind = tableHeader(rt, "kind")
        #expect(size.rect[2] == 100.0 && kind.rect[2] == 80.0)
        #expect(name.rect[2] == tableW - 180.0)
        let cells = tableFind(rt) { $0.role == "gridcell" && $0.key == "size" }
        #expect(!cells.isEmpty)
        for c in cells {
            #expect(c.rect[0] == size.rect[0] && c.rect[2] == size.rect[2], "a body cell lines up under its header")
        }
    }

    // PORT NOTE: Blocked on Sources/Rune El.onLayoutTx callback dispatch, virtualRowsSource & helpWhenTruncated.
    @Test(.disabled("Blocked on Sources/Rune El.onLayoutTx callback dispatch, virtualRowsSource & helpWhenTruncated")) func draggingAHeaderEdgeResizesWithinTheColumnBounds() {
        let rt = tableRuntime(TableApp.new(20, false))
        let size = tableHeader(rt, "size")
        let handle = tableFind(rt) { $0.label == "Resize Size" }[0].rect
        let (x, y) = (handle[0] + handle[2] * 0.5, handle[1] + handle[3] * 0.5)
        func drag(_ dx: Float) {
            _ = rt.pointerDown(x, y)
            _ = rt.frame(0.0)
            for k in 1...4 {
                rt.pointerMove(x + dx * Float(k) / 4.0, y)
                _ = rt.frame(0.0)
            }
            rt.pointerUp(x + dx, y)
            _ = rt.frame(0.0)
            _ = rt.frame(0.0)
        }
        drag(30.0)
        #expect(rt.state.table.columnWidth("size") == 130.0)
        #expect(tableHeader(rt, "size").rect[2] == 130.0, "the column draws at its new width")
        #expect(tableHeader(rt, "name").rect[2] == tableW - 210.0, "and the flex column gives way")

        let handle2 = tableFind(rt) { $0.label == "Resize Size" }[0].rect
        let (x2, y2) = (handle2[0] + handle2[2] * 0.5, handle2[1] + handle2[3] * 0.5)
        _ = rt.pointerDown(x2, y2)
        _ = rt.frame(0.0)
        rt.pointerMove(x2 + 400.0, y2)
        _ = rt.frame(0.0)
        rt.pointerUp(x2 + 400.0, y2)
        _ = rt.frame(0.0)
        #expect(rt.state.table.columnWidth("size") == 180.0, "clamped to the max")

        _ = rt.pointerDown(x2, y2)
        _ = rt.frame(0.0)
        rt.pointerMove(x2 - 400.0, y2)
        _ = rt.frame(0.0)
        rt.pointerUp(x2 - 400.0, y2)
        _ = rt.frame(0.0)
        #expect(rt.state.table.columnWidth("size") == 60.0, "clamped to the min")
        #expect(size.rect[2] == 100.0)
        #expect(tableFind(rt) { $0.label == "Resize Kind" }.isEmpty, "a fixed column has no handle")
    }

    @Test func aHeaderClickSortsAndShowsTheDirection() {
        let rt = tableRuntime(TableApp.new(50, false))
        let r = tableHeader(rt, "size").rect
        tableClick(rt, r[0] + 20.0, r[1] + r[3] * 0.5)
        #expect(rt.state.sorts == [TableSortEvent(col: "size", dir: .ascending)])
        #expect(rt.state.table.sort()?.0 == "size" && rt.state.table.sort()?.1 == .ascending)
        #expect(tableHeader(rt, "size").label == "Size, sorted ascending")
        for i in 0..<(rt.state.files.count - 1) {
            #expect(rt.state.files[i].size <= rt.state.files[i + 1].size)
        }
        tableClick(rt, r[0] + 20.0, r[1] + r[3] * 0.5)
        #expect(rt.state.table.sort()?.0 == "size" && rt.state.table.sort()?.1 == .descending)
        #expect(tableHeader(rt, "size").label == "Size, sorted descending")
        #expect(tableHeader(rt, "name").label == "Name")
        let rKind = tableHeader(rt, "kind").rect
        tableClick(rt, rKind[0] + 20.0, rKind[1] + rKind[3] * 0.5)
        #expect(rt.state.sorts.count == 2, "a column that doesn't sort ignores clicks")
    }

    @Test func cancellingAColumnResizeRestoresTheOriginalWidthPolicy() {
        for initial in [Float?.none, .some(110.0)] {
            let rt = tableRuntime(TableApp.new(20, false))
            if let w = initial {
                rt.update { s, _ in s.table.setColumnWidth("size", w) }
                _ = rt.frame(0.0)
            }
            let handle = tableFind(rt) { $0.label == "Resize Size" }[0].rect
            let (x, y) = (handle[0] + handle[2] / 2.0, handle[1] + handle[3] / 2.0)
            _ = rt.pointerDown(x, y)
            rt.pointerMove(x + 40.0, y)
            _ = rt.frame(0.0)
            #expect(rt.state.table.columnWidth("size") != initial)
            tablePress(rt, .escape)
            #expect(rt.state.table.columnWidth("size") == initial)
            rt.pointerUp(x + 40.0, y)
            _ = rt.frame(0.0)
            #expect(rt.state.table.columnWidth("size") == initial)
        }
    }

    // PORT NOTE: Blocked on Sources/Rune El.onLayoutTx callback dispatch, virtualRowsSource & helpWhenTruncated.
    @Test(.disabled("Blocked on Sources/Rune El.onLayoutTx callback dispatch, virtualRowsSource & helpWhenTruncated")) func keysMoveTheSelectionAndReturnOpens() {
        let rt = tableRuntime(TableApp.new(200, false))
        tablePress(rt, .tab)
        #expect(rt.elements().first(where: { $0.focused })?.key == "table")
        tablePress(rt, .down)
        #expect(rt.state.table.cursor() == "f0")
        tablePress(rt, .down)
        tablePress(rt, .down)
        #expect(rt.state.table.cursor() == "f2")
        tablePress(rt, .pageDown)
        let curStr = rt.state.table.cursor()!
        let page = Int(curStr.dropFirst())! - 2
        #expect((5..<12).contains(page), "Page Down moves about a screen of rows: \(page)")
        tablePress(rt, .end)
        #expect(rt.state.table.cursor() == "f199")
        for f in 1..<30 {
            _ = rt.frame(Double(f) / 60.0)
        }
        let row = tableFind(rt) { $0.role == "row" && $0.itemSelected }[0]
        #expect(row.visible[3] > 20.0, "End scrolls the last row into view")
        tablePress(rt, .enter)
        #expect(rt.state.opened == ["f199"])
        tablePress(rt, .home)
        #expect(Array(rt.state.table.selected()) == ["f0"])
    }

    @Test func shiftExtendsAndCmdASelectsAllInAMultiSelectTable() {
        let rt = tableRuntime(TableApp.new(30, true))
        tablePress(rt, .tab)
        tablePress(rt, .down)
        tablePressWith(rt, .down, Mods(shift: true))
        tablePressWith(rt, .down, Mods(shift: true))
        let sel = rt.state.table.selected().sorted()
        #expect(sel == ["f0", "f1", "f2"])
        tablePressWith(rt, .command("a"), Mods(cmd: true))
        #expect(rt.state.table.selectedLen() == 30)
    }

    @Test func aSelectionFollowsItsRowThroughASort() {
        let rt = tableRuntime(TableApp.new(50, false))
        rt.update { s, tx in s.table.reveal("f7", &tx) }
        _ = rt.frame(0.0)
        let r = tableHeader(rt, "size").rect
        tableClick(rt, r[0] + 20.0, r[1] + r[3] * 0.5)
        #expect(Array(rt.state.table.selected()) == ["f7"])
    }

    // PORT NOTE: Blocked on Sources/Rune El.onLayoutTx callback dispatch, virtualRowsSource & helpWhenTruncated.
    @Test(.disabled("Blocked on Sources/Rune El.onLayoutTx callback dispatch, virtualRowsSource & helpWhenTruncated")) func aHundredThousandRowsBuildOnlyWhatShows() {
        let rt = tableRuntime(TableApp.new(100_000, false))
        let built = tableFind(rt) { $0.role == "row" }.count
        #expect((5..<60).contains(built), "\(built) rows built for a \(tableH) pt table")
    }

    // PORT NOTE: Blocked on Sources/Rune El.onLayoutTx callback dispatch, virtualRowsSource & helpWhenTruncated.
    @Test(.disabled("Blocked on Sources/Rune El.onLayoutTx callback dispatch, virtualRowsSource & helpWhenTruncated")) func rolesAndCutShortTextOfferTheirWholeText() {
        var app = TableApp.new(5, false)
        app.files[1].name = "short.rs"
        let rt = tableRuntime(app)
        rt.update { s, _ in
            s.table.setColumnWidth("name", 120.0)
            s.table.select("f0")
        }
        _ = rt.frame(0.0)
        let all = rt.elements()
        let grid = all.first(where: { $0.role == "grid" })!
        #expect(grid.label == "Files")
        #expect(all.filter { $0.role == "columnheader" }.count == 3)
        #expect(all.filter { $0.role == "row" && $0.itemSelected }.count == 1)
        #expect(all.filter { $0.role == "gridcell" }.count >= 15)
        let help = all.compactMap(\.help)
        #expect(help.contains("file 0 with a name long enough to cut short.rs"))
        #expect(!help.contains("short.rs"), "text that fits offers no truncation tooltip")
    }

    @Test func shrinkingRowsUnderASelectionStaysConsistent() {
        let rt = tableRuntime(TableApp.new(20, true))
        tablePress(rt, .tab)
        tablePress(rt, .end)
        #expect(rt.state.table.cursor() == "f19")
        rt.update { s, _ in s.files.removeSubrange(5..<s.files.count) }
        _ = rt.frame(0.0)
        tablePress(rt, .down)
        #expect(rt.state.table.cursor() == "f0", "a removed cursor starts at the top on Down")
        tablePressWith(rt, .end, Mods(shift: true))
        #expect(rt.state.table.selectedLen() == 5)
    }

    @Test(.disabled("benchmark"))
    func tableTime() {
        func percentile(_ v: inout [Double], _ p: Double) -> Double {
            v.sort()
            let idx = Int((Double(v.count - 1) * p).rounded())
            return v[idx]
        }
        func ms(_ start: Rune.time.Instant) -> Double {
            let d = Rune.time.Instant.now().durationSince(start)
            return (Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18) * 1e3
        }
        func bigView(_ s: TableApp, _: Cx<TableApp>) -> El {
            tableSizedView(s, 900.0, 900.0)
        }
        for run in 0..<3 {
            let app = TableApp.new(100_000, true)
            let t0 = Rune.time.Instant.now()
            let rt = Runtime.new(app, bigView, (900.0, 900.0), Env.new(true, 2.0))
            _ = rt.frame(0.0)
            let first = ms(t0)
            var frames: [Double] = []
            var withCommit: [Double] = []
            let c0 = rt.stats.commits
            for f in 1...600 {
                rt.wheel(450.0, 450.0, -48.0)
                let c = rt.stats.commits
                let t = Rune.time.Instant.now()
                _ = rt.frame(Double(f) / 120.0)
                let elapsed = ms(t)
                frames.append(elapsed)
                if rt.stats.commits > c {
                    withCommit.append(elapsed)
                }
            }
            let built = tableFind(rt) { $0.role == "row" }.count
            var rebuild: [Double] = []
            for _ in 0..<30 {
                rt.invalidate()
                let t = Rune.time.Instant.now()
                _ = rt.frame(5.0)
                rebuild.append(ms(t))
            }
            let r = tableHeader(rt, "size").rect
            let tSort = Rune.time.Instant.now()
            tableClick(rt, r[0] + 20.0, r[1] + r[3] * 0.5)
            let sortMs = ms(tSort)
            let handle = tableFind(rt) { $0.label == "Resize Size" }[0].rect
            let (x, y) = (handle[0] + handle[2] * 0.5, handle[1] + handle[3] * 0.5)
            _ = rt.pointerDown(x, y)
            _ = rt.frame(0.0)
            var drag: [Double] = []
            for k in 1...60 {
                rt.pointerMove(x + Float(k), y)
                let t = Rune.time.Instant.now()
                _ = rt.frame(0.0)
                drag.append(ms(t))
            }
            rt.pointerUp(x + 60.0, y)
            let maxMs = frames.max() ?? 0.0
            print(
                "table 100k run \(run): commits \(rt.stats.commits - c0), first \(first) ms, scroll p50 \(percentile(&frames, 0.5)) p95 \(percentile(&frames, 0.95)) max \(maxMs) (\(built) rows), sort \(sortMs) ms, drag p50 \(percentile(&drag, 0.5)) p95 \(percentile(&drag, 0.95))"
            )
            _ = rebuild
            _ = withCommit
        }
    }
}
