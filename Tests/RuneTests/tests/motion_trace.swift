// Tests ported from: crates/rune/tests/motion_trace.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import RuneMotion
import Testing
@testable import Rune

@Suite("MotionTraceIntegrationTests")
struct MotionTraceIntegrationTests {
    @Test func traceNamesChannelsAndEventsMatchMotionLint() throws {
        let header = TraceHeader(launch: "pill", width: 200.0, height: 80.0, hz: 120.0, scale: 2.0)
        let (trace, buffer) = MotionTrace.inMemory(header)
        let scene = Scene.new()

        scene.insert(NodeId(40), NodeSpec.new(Rect(0.0, 0.0, 100.0, 40.0)), .initial)
        scene.insert(NodeId(90), NodeSpec.new(Rect(10.0, 0.0, 20.0, 20.0)), .initial)
        _ = scene.frameAt(0.0)

        scene.setTrace(trace.class("gpui").host("pill"))
        scene.traceName(NodeId(40), "chip:\"Area\"")
        let tr1 = try #require(scene.traceMut())
        tr1.channel("shell.width", "position", 100.12345)
        tr1.channel("phase:recording", "phase", 1.0)
        tr1.event("lab:\"Start\\n\"")
        _ = scene.frameAt(0.01)
        _ = scene.frameAt(0.02)

        scene.traceName(NodeId(40), "chip:Region")
        scene.traceMut()?.channel("shell.width", "position", 120.0)
        scene.traceMut()?.removeChannel("phase:recording")
        _ = scene.frameAt(0.03)

        scene.traceName(NodeId(40), nil)
        scene.traceMut()?.channel("phase:recording", "phase", 1.0)
        scene.traceMut()?.channel("shell.width", "position", .nan)
        _ = scene.frameAt(0.04)

        let taken = try #require(scene.takeTrace())
        let flushing: any TraceWriter = buffer
        _ = flushing
        _ = taken

        let rawLines = buffer.contents()
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        #expect(rawLines.count >= 5)

        let parsed: [[String: Any]] = try rawLines.map { line in
            let obj = try JSONSerialization.jsonObject(with: Data(line.utf8))
            return try #require(obj as? [String: Any])
        }

        let m1 = try #require(parsed[1]["m"] as? [[String: Any]])
        let named = try #require(m1.first { ($0["nm"] as? String) == "chip:\"Area\"" })
        let nodeIdNum = try #require(named["id"] as? Int)
        #expect(named["host"] as? String == "pill")
        #expect(named["cls"] as? String == "gpui")
        #expect(m1.contains { ($0["nm"] as? String) == "90" })

        let cm1 = try #require(parsed[1]["cm"] as? [[String: Any]])
        #expect(cm1.count == 2)
        #expect(cm1[0]["name"] as? String == "shell.width")
        #expect(cm1[0]["kind"] as? String == "position")
        #expect(cm1[1]["name"] as? String == "phase:recording")
        #expect(cm1[1]["kind"] as? String == "phase")

        let ev1 = try #require(parsed[1]["ev"] as? [String])
        #expect(ev1 == ["lab:\"Start\\n\""])

        for field in ["m", "cm", "c", "ev"] {
            #expect(parsed[2][field] == nil)
        }

        let m3 = try #require(parsed[3]["m"] as? [[String: Any]])
        #expect(m3[0]["id"] as? Int == nodeIdNum)
        #expect(m3[0]["nm"] as? String == "chip:Region")
        let cg3 = try #require(parsed[3]["cg"] as? [Int])
        #expect(cg3 == [2])

        let m4 = try #require(parsed[4]["m"] as? [[String: Any]])
        #expect(m4[0]["nm"] as? String == "40")
    }
}
