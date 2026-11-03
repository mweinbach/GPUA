// Tests ported from: crates/rune/tests/script_t0.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Testing
@testable import Rune

private struct ScriptT0State {
    var taps: [String] = []
    var typed: String = ""
}

private func scriptT0View(_ s: ScriptT0State, _: Cx<ScriptT0State>) -> El {
    col()
        .wFull()
        .hFull()
        .child(
            el()
                .key("a")
                .size(100.0, 40.0)
                .onPress { (st: inout ScriptT0State, _: inout Tx) in
                    st.taps.append("a")
                }
        )
        .child(
            el()
                .key("b")
                .size(100.0, 40.0)
                .onPress { (st: inout ScriptT0State, _: inout Tx) in
                    st.taps.append("b")
                }
        )
        .child(text("taps \(s.taps.joined(separator: ",")) typed \(s.typed)").key("out"))
}

private func scriptT0OnKey(_ s: inout ScriptT0State, _ k: KeyEvent, _: inout Tx) -> Bool {
    if case .text(let t) = k.key {
        s.typed.append(t)
    }
    return true
}

@Suite("ScriptT0IntegrationTests", .serialized)
struct ScriptT0IntegrationTests {
    @Test func scriptEventsAtTZeroSeeTheFirstLayout() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rune-script-t0-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let scriptPath = dir.appendingPathComponent("script.json")
        let treePath = dir.appendingPathComponent("tree.json")
        let scriptJson = """
        [
            {"t": 0.0, "type": "click", "key": "a"},
            {"type": "type", "text": "x"},
            {"t": 0.2, "type": "tap", "x": 50, "y": 60}
        ]
        """
        try scriptJson.write(to: scriptPath, atomically: true, encoding: .utf8)

        var spec = AppSpec.new("t0", (200.0, 200.0), { ScriptT0State() }, scriptT0View)
        spec.onKey = scriptT0OnKey

        headlessTestMutex.withLock {
            App.new(spec)
                .args(["--script", scriptPath.path, "--tree", treePath.path])
                .run()
        }

        let data = try Data(contentsOf: treePath)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let elements = try #require(json["elements"] as? [[String: Any]])
        let out = try #require(elements.first { ($0["key"] as? String) == "out" })
        #expect(out["text"] as? String == "taps a,b typed x")
    }
}
