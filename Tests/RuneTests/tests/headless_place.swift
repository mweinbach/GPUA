// Tests ported from: crates/rune/tests/headless_place.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Testing
@testable import Rune

private func headlessPlaceView(_: Void, _: Cx<Void>) -> El {
    el()
}

private func headlessPlaced(_ app: App<Void>, _ name: String) throws -> ToolingJson? {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("rune-headless-place-\(name)-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let script = dir.appendingPathComponent("desktop.json")
    let tree = dir.appendingPathComponent("tree.json")
    try """
    {
        "displays": [{"id": 1, "frame": [0, 0, 1512, 982], "scale": 2, "primary": true},
                     {"id": 2, "frame": [1512, 0, 1920, 1080], "scale": 1}],
        "pointer": [2000, 400]
    }
    """.write(to: script, atomically: true, encoding: .utf8)

    headlessTestMutex.lock()
    defer { headlessTestMutex.unlock() }
    app.args(["--script", script.path, "--tree", tree.path]).run()
    let raw = try String(contentsOf: tree, encoding: .utf8)
    let parsed = try ToolingJson.parse(raw)
    return parsed.get("placed")
}

@Suite("HeadlessPlaceIntegrationTests", .serialized)
struct HeadlessPlaceIntegrationTests {
    @Test func headlessPlaceResolvesAgainstScriptedDisplays() throws {
        let app = App.new(AppSpec.new("place", (600.0, 80.0), { () }, headlessPlaceView))
        app.handle().place(
            .underPointer,
            .edge(edge: .top, margin: 160.0, align: .center, inset: 0.0)
        )
        let first = try headlessPlaced(app, "handle")
        #expect(first?.get("t")?.doubleValue == 0.0)
        #expect(first?.get("display")?.intValue == 2)
        let f1 = first?.get("frame")?.arrayValue?.compactMap(\.doubleValue)
        #expect(f1 == [2172.0, 160.0, 600.0, 80.0])

        var pollHandle: AppHandle<Void>? = nil
        var spec = AppSpec.new("poll", (600.0, 80.0), { () }, headlessPlaceView)
        spec.poll = { _, _, _ in
            pollHandle?.place(.primary, .fullScreen)
            return false
        }
        let pollApp = App.new(spec)
        pollHandle = pollApp.handle()
        let second = try headlessPlaced(pollApp, "poll")
        #expect(second?.get("t")?.doubleValue == 0.0)
        #expect(second?.get("display")?.intValue == 1)
        let f2 = second?.get("frame")?.arrayValue?.compactMap(\.doubleValue)
        #expect(f2 == [0.0, 0.0, 1512.0, 982.0])
    }
}
