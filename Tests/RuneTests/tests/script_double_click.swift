// Tests ported from: crates/rune/tests/script_double_click.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Testing
@testable import Rune

private struct ScriptDoubleClickState {
    var presses: UInt32 = 0
}

private func scriptDoubleClickView(_ s: ScriptDoubleClickState, _: Cx<ScriptDoubleClickState>) -> El {
    col()
        .wFull()
        .hFull()
        .child(
            el()
                .key("row")
                .size(100.0, 40.0)
                .onPress { (st: inout ScriptDoubleClickState, _: inout Tx) in
                    st.presses += 1
                }
        )
        .child(text("presses \(s.presses)").key("out"))
}

@Suite("ScriptDoubleClickIntegrationTests", .serialized)
struct ScriptDoubleClickIntegrationTests {
    @Test func doubleClickScriptEventDispatchesBothPressesOnVirtualClock() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rune-script-double-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let scriptPath = dir.appendingPathComponent("script.json")
        let treePath = dir.appendingPathComponent("tree.json")
        let scriptJson = """
        [
            {"t": 0.1, "type": "double-click", "key": "row"},
            {"t": 1.0, "type": "click", "key": "row"},
            {"t": 2.0, "type": "click", "key": "row"}
        ]
        """
        try scriptJson.write(to: scriptPath, atomically: true, encoding: .utf8)

        headlessTestMutex.withLock {
            App.new(AppSpec.new("double", (200.0, 200.0), { ScriptDoubleClickState() }, scriptDoubleClickView))
                .args(["--script", scriptPath.path, "--tree", treePath.path])
                .run()
        }

        let data = try Data(contentsOf: treePath)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let elements = try #require(json["elements"] as? [[String: Any]])
        let out = try #require(elements.first { ($0["key"] as? String) == "out" })
        #expect(out["text"] as? String == "presses 4")
    }

    @Test(.disabled("Requires Wave 2 El.onDoublePress in Spine El"))
    func aDoubleClickEventRunsOnDoublePress() {}
}
