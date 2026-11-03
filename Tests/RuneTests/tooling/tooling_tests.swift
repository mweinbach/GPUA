// Tests ported from: crates/rune/src/tooling/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if !os(WASI)
import Foundation
#endif
import RuneMotion
import Testing
@testable import Rune

#if !os(WASI)
private final class MockPresentsSource: ToolingPresentSource, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [(UInt64, RuneInstant?)] = []

    func push(_ drawable: UInt64, _ at: RuneInstant?) {
        lock.withLock { items.append((drawable, at)) }
    }

    func take(_ out: inout [(UInt64, RuneInstant?)]) {
        lock.withLock {
            out.append(contentsOf: items)
            items.removeAll()
        }
    }
}

let headlessTestMutex = NSLock()
private let keyedLogLock = NSLock()
nonisolated(unsafe) private var keyedLog: [String] = []
private let reopenedLogLock = NSLock()
nonisolated(unsafe) private var reopenedLog: [(String, Bool)] = []

private struct DesktopPairState {
    var name: String
    var color: Rune.Color
    var other: AppHandle<DesktopPairState>?
    var act: (AppHandle<DesktopPairState>, inout Tx) -> Void
}
#endif

@Suite("ToolingTests", .serialized)
struct ToolingTests {
    @Test func sizeAndScaleMustBePositive() throws {
        let s = try toolingParseSize("400x300.5").get()
        #expect(s.0 == 400.0 && s.1 == 300.5)
        #expect(try toolingParseScale("1.5").get() == 1.5)
        for bad in ["0x0", "400x0", "-1x10", "NaNx10", "infx10", "400", "ax3"] {
            if case .success = toolingParseSize(bad) {
                Issue.record("Expected bad size \(bad) to fail")
            }
        }
        for bad in ["0", "-2", "NaN", "inf", "x"] {
            if case .success = toolingParseScale(bad) {
                Issue.record("Expected bad scale \(bad) to fail")
            }
        }
    }

    @Test func marksAreInertEventsThatTimesCanName() throws {
        let script = toolingParseScript(try ToolingJson.parse(#"""
        [
            {"t": 0.5, "type": "tap", "x": 1, "y": 1},
            {"t": 3.2, "type": "mark", "name": "end"},
            {"t": 1.0, "type": "mark", "name": "end-card"}
        ]
        """#))
        let marks: [(String, Double)] = script.compactMap { e in
            if case .mark(let n) = e.kind { return (n, e.t) }
            return nil
        }
        #expect(marks.count == 2)
        #expect(marks[0].0 == "end-card" && marks[0].1 == 1.0)
        #expect(marks[1].0 == "end" && marks[1].1 == 3.2)
        #expect(script[4].publicEvent().event == .mark("end"))

        #expect(toolingMarkTime("mark:end") == "end")
        #expect(toolingMarkTime("mark:end+0.5") == "end+0.5")
        #expect(toolingMarkTime("1.5") == nil)

        func timeline(_ flags: [String]) -> Result<ToolingTimeline, ToolingCliError> {
            ToolingTimeline.of(Args.parseFrom(flags), script)
        }
        let snap = try timeline(["--snap", "a.png", "--at", "mark:end+0.5"]).get()
        #expect(snap.snapFrame == 222 && snap.frames == 0)
        let video = try timeline(["--video", "a.mp4", "--start", "mark:end-card"]).get()
        #expect(video.startFrame == 60 && video.frames == 133 && video.lastFrame == 192)
        let auto = try timeline(["--frames", "1", "--duration", "auto"]).get()
        #expect(auto.frames == 1)
        let seconds = try timeline(["--video", "a.mp4", "--duration", "2", "--fps", "30"]).get()
        #expect(seconds.frames == 60 && seconds.lastFrame == 59)
        if case .failure(let err) = timeline(["--snap", "a.png", "--at", "mark:intro"]) {
            #expect(err.message == #"no mark "intro" in the script (marks: end-card, end)"#)
        } else {
            Issue.record("Expected missing mark error")
        }
        let unmarked = try ToolingTimeline.of(
            Args.parseFrom(["--video", "a.mp4"]),
            toolingParseScript(try ToolingJson.parse(#"[{"t": 0.5, "type": "tap", "x": 1, "y": 1}]"#))
        ).get()
        #expect(unmarked.frames == 96)
    }

    @Test func markNamesWinOverOffsetsAndOffsetsMustBeComplete() throws {
        let script = toolingParseScript(try ToolingJson.parse(#"""
        [
            {"t": 2.0, "type": "mark", "name": "step-1"},
            {"t": 4.0, "type": "mark", "name": "end-card"},
            {"t": 6.0, "type": "mark", "name": "end+0.5"},
            {"t": 8.0, "type": "mark", "name": "step"},
            {"t": 10.0, "type": "mark", "name": "end"}
        ]
        """#))
        func resolve(_ flag: String, _ value: String) -> Result<ToolingTimeline, ToolingCliError> {
            let args = Args.parseFrom(["--snap", "a.png", "--fps", "1000", flag, value])
            return ToolingTimeline.of(args, script)
        }
        for (value, frame) in [
            ("mark:step-1", 2000),
            ("mark:step-1+0.25", 2250),
            ("mark:step-1-0.5", 1500),
            ("mark:end+0.5", 6000),
            ("mark:end-card-0.25", 3750),
            ("mark:end-1e-3", 9999),
            ("mark:end+1e-3", 10001),
        ] {
            #expect(try resolve("--at", value).get().snapFrame == frame)
            #expect(try resolve("--start", value).get().startFrame == frame)
        }
        for value in ["mark:end+0.5s", "mark:end-", "mark:end+NaN", "mark:end+inf", "mark:end+1e999"] {
            if case .failure(let err) = resolve("--at", value) {
                #expect(err.message.contains("invalid mark time") && err.message.contains("marks: step-1, end-card, end+0.5, step, end"))
            } else {
                Issue.record("Expected invalid mark error for \(value)")
            }
        }
        let args = Args.parseFrom(["--at", "mark:end", "--at", "1", "--start", "mark:step", "--start", "0"])
        let tl = try ToolingTimeline.of(args, script).get()
        #expect(tl.snapFrame == 60 && tl.startFrame == 0)
    }

    @Test func nativeTraceDoesNotSelectVirtualRendering() {
        #expect(Args.parseFrom(["--trace", "trace.jsonl", "--frames", "120"]).headless())
        #expect(!Args.parseFrom(["--native", "--trace", "trace.jsonl", "--frames", "120"]).headless())
        #expect(Args.parseFrom(["--native", "--snap", "snap.png"]).headless())
    }

    @Test func aScriptAloneReplaysHeadlessUnlessNative() {
        #expect(Args.parseFrom(["--script", "s.json"]).headless())
        #expect(!Args.parseFrom(["--native", "--script", "s.json"]).headless())
        #expect(!Args.parseFrom(["--theme", "light"]).headless())
    }

    @Test func theWindowTitleStartsFromTheSpecAndFollowsSetTitle() {
        let spec = AppSpec<UInt32>("Notes", (100.0, 100.0), { 0 }) { _, _ in
            el().size(100.0, 100.0).onPress { (n: inout UInt32, tx: inout Tx) in
                n += 1
                tx.setTitle("Notes \(n % 2)")
            }
        }
        let rt = toolingRuntimeFor(spec: spec, state: UInt32(0), size: (100.0, 100.0), env: Env.new(true, 1.0), waker: {})
        _ = rt.hostFrame(0.0)
        let title0 = toolingTreeJson(rt, 0.0)["title"].stringValue
        #expect(title0 == "Notes")
        let change0 = hostAttachment(for: rt).takeWindowTitleChange()
        #expect(change0 == nil)

        _ = rt.hostPointerDown(50.0, 50.0)
        _ = rt.hostPointerUp(50.0, 50.0)
        _ = rt.hostFrame(0.1)
        let title1 = toolingTreeJson(rt, 0.1)["title"].stringValue
        #expect(title1 == "Notes 1")
        let change1 = hostAttachment(for: rt).takeWindowTitleChange()
        #expect(change1 == "Notes 1")
        let change2 = hostAttachment(for: rt).takeWindowTitleChange()
        #expect(change2 == nil)

        rt.hostUpdate { _, tx in tx.setTitle("Notes 1") }
        let change3 = hostAttachment(for: rt).takeWindowTitleChange()
        #expect(change3 == nil)
        let updatedDraft = rt.hostUpdateIf { _, tx in
            tx.setTitle("Draft")
            return false
        }
        #expect(!updatedDraft)
        let change4 = hostAttachment(for: rt).takeWindowTitleChange()
        #expect(change4 == "Draft")
    }

    #if !os(WASI)
    @Test func traceAnnotationsFromHiddenPollSurviveIdleCatchUpOnce() throws {
        let rt = Runtime(false, { _, _ in el() }, (100.0, 100.0), Env())
        let (trace, buffer) = MotionTrace.inMemory(TraceHeader(launch: "hidden", width: 100.0, height: 100.0, hz: 60.0, scale: 1.0))
        rt.scene.setTrace(trace)
        toolingTraceState(for: rt).enabled = true
        rt.poll = { pending, _, tx in
            guard pending else { return false }
            pending = false
            tx.traceEvent("hidden:ready")
            tx.traceChannel("shell.width", "position", 40.0)
            return true
        }
        _ = rt.hostFrame(0.0)
        rt.state = true
        let commits0 = windowHostState(for: rt).commitsCount
        _ = rt.hostPollHidden()
        #expect(windowHostState(for: rt).commitsCount == commits0)
        _ = rt.hostFrame(0.02)
        let taken = rt.scene.takeTrace()
        try taken?.flush()
        let lines = try buffer.contents().split(separator: "\n").map { try ToolingJson.parse(String($0)) }
        let matched = lines.filter { $0["ev"] == .array([.string("hidden:ready")]) }
        #expect(matched.count == 1)
    }

    @Test func traceAnnotationsReachBothWritersOnce() throws {
        func view(_ changed: Bool, _ cx: Cx<Bool>) -> El {
            _ = cx
            let (cls, host) = changed ? ("other", "other-host") : ("gpui", "pill")
            return el().key("root").pgTraceNamespace(cls, host)
                .child(el().key("generation-7").pgTraceName("chip:Area").size(30.0, 20.0))
                .child(el().key("fixed").pgTraceName("fixed").pgTraceNamespace("gpui", "pill"))
        }
        let rt = Runtime(false, view, (100.0, 100.0), Env.new(true, 1.0))
        let (mTrace, buffer) = MotionTrace.inMemory(TraceHeader(launch: "pill", width: 100.0, height: 100.0, hz: 60.0, scale: 1.0))
        rt.scene.setTrace(mTrace)
        toolingTraceState(for: rt).enabled = true
        let pathURL = FileManager.default.temporaryDirectory.appendingPathComponent("rune-annotations-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: pathURL) }

        do {
            let trace = ToolingTrace.open(pathURL.path, rt.viewport, 60.0, 1.0)
            rt.hostUpdate { _, tx in
                tx.traceEvent("lab:Start")
                tx.traceChannel("shell.width", "position", 30.0)
            }
            rt.hostUpdate { _, tx in
                tx.traceEvent("lab:Ready")
                tx.traceChannel("shell.width", "position", 40.0)
            }
            _ = rt.hostFrame(0.0)
            trace.frame(rt, 0.0, 0.0)
            _ = rt.hostFrame(0.02)
            trace.frame(rt, 20.0, 0.0)
            rt.hostUpdate { s, _ in s = true }
            _ = rt.hostFrame(0.02)
            trace.frame(rt, 40.0, 0.0)
            trace.close()
        }
        try rt.scene.takeTrace()?.flush()
        let toolingText = try String(contentsOf: pathURL, encoding: .utf8)
        for text in [toolingText, buffer.contents()] {
            let lines = try text.split(separator: "\n").map { try ToolingJson.parse(String($0)) }
            let chip = (lines[1]["m"].arrayValue ?? []).first(where: { $0["nm"].stringValue == "chip:Area" })!
            #expect(chip["cls"].stringValue == "gpui")
            #expect(chip["host"].stringValue == "pill")
            #expect(lines[1]["ev"] == .array([.string("lab:Start"), .string("lab:Ready")]))
            let channel = (lines[1]["cm"].arrayValue ?? []).first(where: { $0["name"].stringValue == "shell.width" })!
            #expect(channel["kind"].stringValue == "position")
            let chVals = lines[1]["c"].arrayValue ?? []
            #expect(chVals.contains(where: { ($0.arrayValue?.first == channel["id"]) && ($0.arrayValue?.last?.doubleValue == 40.0) }))
            for field in ["cm", "c", "ev"] {
                #expect(lines[2][field].isNull)
            }
            let updated = lines[3]["m"].arrayValue ?? []
            let renamed = updated.first(where: { $0["nm"].stringValue == "chip:Area" })!
            #expect(renamed["id"] == chip["id"])
            #expect(renamed["cls"].stringValue == "other")
            #expect(renamed["host"].stringValue == "other-host")
            #expect(!updated.contains(where: { $0["nm"].stringValue == "fixed" }))
        }
    }

    @Test func nativeTracesAddTargetAndPresentTimesWithoutChangingOtherFields() throws {
        func runCase(_ name: String, timed: Bool) throws -> String {
            let rt = Runtime(false, { _, _ in el().key("box").size(20.0, 20.0) }, (100.0, 100.0), Env.new(true, 1.0))
            let pathURL = FileManager.default.temporaryDirectory.appendingPathComponent("rune-present-\(name)-\(UUID().uuidString).jsonl")
            defer { try? FileManager.default.removeItem(at: pathURL) }
            let start = RuneInstant.now()
            let source = MockPresentsSource()
            let trace = ToolingTrace.openClock(pathURL.path, rt.viewport, 120.0, 1.0, "wall")
            if timed {
                trace.recordPresents(source, start)
            }
            for k in 0..<UInt64(3) {
                _ = rt.hostFrame(1.0 / 120.0)
                let timing = ToolingFrameTiming(
                    targetMs: timed ? Double(k) * 8.333 : nil,
                    drawable: timed ? (k + 1) : nil,
                    continuous: k > 0
                )
                trace.frameTimed(rt, Double(k) * 8.0, 0.0, timing)
                let at = start.adding(Double(20_000 + k * 8_333) / 1_000_000.0)
                source.push(k + 1, at)
            }
            trace.close()
            return try String(contentsOf: pathURL, encoding: .utf8)
        }

        let plain = try runCase("plain", timed: false)
        let timed = try runCase("timed", timed: true)
        func strip(_ text: String) throws -> [ToolingJson] {
            try text.split(separator: "\n").map { raw in
                var v = try ToolingJson.parse(String(raw))
                for key in ["target_ms", "present_ms", "present_dt_ms"] {
                    v.removeKey(key)
                }
                if var q = v.get("quality") {
                    q["cpu_ms"] = .int(0)
                    v["quality"] = q
                }
                return v
            }
        }
        #expect(try strip(plain) == strip(timed))
        #expect(!plain.contains("present_ms") && !plain.contains("target_ms"))
        let frames = try timed.split(separator: "\n").dropFirst().map { try ToolingJson.parse(String($0)) }
        #expect(frames.count == 3)
        #expect(frames[1]["target_ms"].doubleValue == 8.333)
        #expect(frames[1]["present_ms"].doubleValue == 28.333)
        #expect(frames[1]["present_dt_ms"].doubleValue == 8.333)
        let summary = ToolingPresentSummary.ofTrace(timed)!
        #expect(summary.frames == 3 && summary.presented == 3 && summary.bunched == 0 && summary.missed == 0)
        #expect(ToolingPresentSummary.ofTrace(plain) == nil)
    }

    @Test func durationAndOutSelectHeadlessPngOutputUnlessNative() throws {
        headlessTestMutex.lock()
        defer { headlessTestMutex.unlock() }

        for flags in [["--out", "frames"], ["--duration", "auto"], ["--duration", "auto", "--out", "frames"]] {
            #expect(Args.parseFrom(flags).headless())
            #expect(!Args.parseFrom(flags + ["--native"]).headless())
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rune-duration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let scriptURL = dir.appendingPathComponent("script.json")
        try #"[{"t": 0.1, "type": "mark", "name": "end"}]"#.write(to: scriptURL, atomically: true, encoding: .utf8)

        for automatic in [false, true] {
            let outURL = dir.appendingPathComponent(automatic ? "explicit" : "default")
            var flags = ["--script", scriptURL.path, "--out", outURL.path, "--fps", "30", "--scale", "1"]
            if automatic {
                flags.append(contentsOf: ["--duration", "auto"])
            }
            let args = Args.parseFrom(flags)
            #expect(args.headless())
            let spec = AppSpec("duration", (8.0, 8.0), { () }, { _, _ in el() })
            headless(App.new(spec), args)
            let files = try FileManager.default.contentsOfDirectory(atPath: outURL.path).sorted()
            #expect(files == ["frame_0000.png", "frame_0001.png", "frame_0002.png", "frame_0003.png"])
        }
    }

    @Test func singleWindowSnapshotsHonorTransparencyAndPhysicalSize() throws {
        headlessTestMutex.lock()
        defer { headlessTestMutex.unlock() }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rune-window-options-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        func render(_ name: String, _ options: WindowOptions, _ size: (Float, Float)?, _ legacy: Bool) throws -> ([UInt8], (width: UInt32, height: UInt32, rgba: [UInt8])) {
            let spec = AppSpec("options", (20.0, 12.0), { () }) { _, _ in
                el().wFull().hFull().child(el().pgAbsolute(2.0, 2.0).size(8.0, 8.0).bg(oklcha(0.6, 0.2, 30.0, 0.5)))
            }
            let app = App.new(spec).windowOptions(options)
            let snapURL = dir.appendingPathComponent("\(name).png")
            var args = Args()
            args.snap = snapURL.path
            args.scale = 2.0
            args.size = size
            if legacy {
                headlessConfigured(app, args, transparent: false)
            } else {
                headless(app, args)
            }
            let rawBytes = [UInt8](try Data(contentsOf: snapURL))
            let decoded = decodePng(rawBytes)!
            return (rawBytes, decoded)
        }

        let plain = try render("plain", WindowOptions(), nil, false)
        let legacy = try render("legacy", WindowOptions(), nil, true)
        #expect(plain.0 == legacy.0)
        #expect(plain.1.width == 40 && plain.1.height == 24)
        #expect(stride(from: 3, to: plain.1.rgba.count, by: 4).allSatisfy { plain.1.rgba[$0] == 255 })

        var options = WindowOptions()
        options.transparent = true
        options.physicalSize = (80, 60)
        let transparent = try render("transparent", options, nil, false).1
        #expect(transparent.width == 80 && transparent.height == 60)
        #expect(transparent.rgba[3] == 0)
        let a88 = transparent.rgba[(8 * 80 + 8) * 4 + 3]
        #expect((127...128).contains(a88))

        let overridden = try render("override", options, (16.0, 10.0), false).1
        #expect(overridden.width == 32 && overridden.height == 20)
    }

    @Test func windowResizesMoveTheHeadlessViewportOnTheVirtualClock() throws {
        headlessTestMutex.lock()
        defer { headlessTestMutex.unlock() }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rune-window-resize-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let scriptURL = dir.appendingPathComponent("script.json")
        try #"[{"t": 0.1, "type": "tap", "key": "grow"}]"#.write(to: scriptURL, atomically: true, encoding: .utf8)

        func viewport(_ name: String, _ instant: Bool, _ at: String) throws -> (Double, Double) {
            let spec = AppSpec<Bool>("resize", (300.0, 400.0), { false }) { _, _ in
                el().key("root").wFull().hFull().child(
                    el().key("grow").size(50.0, 50.0).onPress { (isInstant: inout Bool, tx: inout Tx) in
                        if isInstant {
                            tx.hostResizeWindowInstant((300.0, 600.0))
                        } else {
                            tx.hostResizeWindow((300.0, 600.0))
                        }
                    }
                )
            }
            let treeURL = dir.appendingPathComponent("\(name).json")
            let args = Args.parseFrom(["--script", scriptURL.path, "--scale", "1", "--fps", "60", "--at", at, "--tree", treeURL.path])
            headless(App.new(spec).`init` { instant }, args)
            let tree = try ToolingJson.parse(String(contentsOf: treeURL, encoding: .utf8))
            let arr = tree["viewport"].arrayValue!
            return (arr[0].doubleValue!, arr[1].doubleValue!)
        }

        #expect(try viewport("before", false, "0.1") == (300.0, 400.0))
        #expect(try viewport("released", false, "0.1834") == (300.0, 400.0))
        let (_, firstH) = try viewport("first", false, "0.2")
        #expect(firstH > 400.0)
        let (w, h) = try viewport("moving", false, "0.3")
        #expect(w == 300.0 && h > 400.0 && h < 600.0)
        #expect(try viewport("moving-again", false, "0.3") == (w, h))
        #expect(try viewport("landed", false, "2") == (300.0, 600.0))
        #expect(try viewport("instant", true, "0.3") == (300.0, 600.0))
    }

    @Test func aScriptedResizeStepsTheViewportWithTheHand() throws {
        headlessTestMutex.lock()
        defer { headlessTestMutex.unlock() }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rune-script-resize-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let scriptURL = dir.appendingPathComponent("script.json")
        try #"[{"t": 0.1, "type": "resize", "dw": -100, "dh": -40, "dur": 0.5}]"#.write(to: scriptURL, atomically: true, encoding: .utf8)

        func viewport(_ at: String) throws -> (Double, Double) {
            let spec = AppSpec("resize", (300.0, 400.0), { () }, { _, _ in el().key("root").wFull().hFull() })
            let treeURL = dir.appendingPathComponent("\(at).json")
            let args = Args.parseFrom(["--script", scriptURL.path, "--scale", "1", "--fps", "60", "--at", at, "--tree", treeURL.path])
            headless(App.new(spec), args)
            let tree = try ToolingJson.parse(String(contentsOf: treeURL, encoding: .utf8))
            let arr = tree["viewport"].arrayValue!
            return (arr[0].doubleValue!, arr[1].doubleValue!)
        }

        #expect(try viewport("0.05") == (300.0, 400.0))
        let (w, h) = try viewport("0.35")
        #expect(w < 300.0 && w > 200.0 && h < 400.0 && h > 360.0)
        #expect(try viewport("1") == (200.0, 360.0))
    }

    @Test func fitContentHeightFollowsTheContent() throws {
        headlessTestMutex.lock()
        defer { headlessTestMutex.unlock() }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rune-fit-content-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let scriptURL = dir.appendingPathComponent("script.json")
        try #"[{"t": 0.1, "type": "tap", "key": "more"}]"#.write(to: scriptURL, atomically: true, encoding: .utf8)

        func viewport(_ name: String, _ at: String) throws -> (Double, Double) {
            let spec = AppSpec<Int>("fit", (300.0, 400.0), { 1 }) { rows, _ in
                var root = col().key("root").wFull().child(
                    el().key("more").size(50.0, 50.0).onPress { (r: inout Int, _: inout Tx) in r += 1 }
                )
                for i in 0..<rows {
                    root = root.child(el().key("row\(i)").size(100.0, 40.0))
                }
                return root
            }
            let treeURL = dir.appendingPathComponent("\(name).json")
            let args = Args.parseFrom(["--script", scriptURL.path, "--scale", "2", "--fps", "60", "--at", at, "--tree", treeURL.path])
            headless(App.new(spec).fitContentHeight(), args)
            let tree = try ToolingJson.parse(String(contentsOf: treeURL, encoding: .utf8))
            let arr = tree["viewport"].arrayValue!
            return (arr[0].doubleValue!, arr[1].doubleValue!)
        }

        #expect(try viewport("open", "0") == (300.0, 90.0))
        let (_, h) = try viewport("moving", "0.3")
        #expect(h > 90.0 && h < 130.0)
        #expect(try viewport("landed", "2") == (300.0, 130.0))
    }

    @Test func appsReadTheHeadlessRunFromInit() throws {
        headlessTestMutex.lock()
        defer { headlessTestMutex.unlock() }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rune-run-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let scriptURL = dir.appendingPathComponent("script.json")
        try #"[{"t": 0.5, "type": "tap", "x": 4, "y": 5}, {"t": 0.25, "type": "type", "text": "hi", "every": 0.1}]"#
            .write(to: scriptURL, atomically: true, encoding: .utf8)

        let spec = AppSpec<Int>("run", (37.0, 23.0), {
            let run = headlessRun()!
            #expect(run.size() == (37.0, 23.0) && run.scale() == 1.0 && run.fps() == 30.0)
            return run.events().count
        }, { _, _ in el() })
        let treeURL = dir.appendingPathComponent("tree.json")
        let args = Args.parseFrom(["--script", scriptURL.path, "--scale", "1", "--fps", "30", "--tree", treeURL.path])
        headless(App.new(spec), args)
        let run = headlessRun()!
        #expect(run.script() == scriptURL.path)
        #expect(run.events().count == 5)
        #expect(run.scriptEnd() == 0.58 && run.frames() == 0 && run.start() == 0.0)
        #expect(abs(run.end() - 47.0 / 30.0) < 1e-9)
    }

    @Test func keycapsDrawOverFramesButNeverEnterTheTree() throws {
        headlessTestMutex.lock()
        defer { headlessTestMutex.unlock() }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rune-keys-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let scriptURL = dir.appendingPathComponent("script.json")
        try #"[{"t": 0.1, "type": "type", "text": "hi"}, {"t": 0.3, "type": "tap", "x": 150, "y": 30}]"#
            .write(to: scriptURL, atomically: true, encoding: .utf8)

        func runCase(_ name: String, _ extra: [String]) throws -> ([UInt8], String) {
            let spec = AppSpec("keys", (200.0, 120.0), { () }) { _, _ in
                el().key("root").wFull().hFull().bg(oklch(0.9, 0.0, 0.0))
            }
            let snapURL = dir.appendingPathComponent("\(name).png")
            let treeURL = dir.appendingPathComponent("\(name).json")
            let flags = ["--script", scriptURL.path, "--scale", "1", "--at", "0.5", "--snap", snapURL.path, "--tree", treeURL.path] + extra
            headless(App.new(spec), Args.parseFrom(flags))
            return ([UInt8](try Data(contentsOf: snapURL)), try String(contentsOf: treeURL, encoding: .utf8))
        }

        let plain = try runCase("plain", [])
        let keys = try runCase("keys", ["--keys", "top-left", "--pointer"])
        let light = try runCase("light", ["--keys", "top-left", "--pointer", "--keys-theme", "light"])
        let dark = try runCase("dark", ["--keys", "top-left", "--pointer", "--keys-theme", "dark"])
        #expect(plain.1 == keys.1)
        #expect(plain.0 != keys.0)
        #expect(keys.0 == light.0)
        #expect(light.0 != dark.0)
        #expect(Args.parseFrom(["--keys", "--snap", "a.png"]).keys == .bottomLeft)
        #expect(Args.parseFrom(["--keys", "top"]).keys == .top)
        #expect(Args.parseFrom(["--snap", "a.png"]).keys == nil)
    }

    @Test func scriptChordsOnlyFireGlobalHandlersEvenWhenTheWindowIsKey() throws {
        let parsed = toolingParseScript(try ToolingJson.parse(#"[{"t": 0.1, "type": "shortcut", "chord": "cmd+space"}, {"t": 0.2, "shortcut": "cmd+k"}]"#))
        #expect(parsed[0].kind == .shortcut(try Shortcut.parse("cmd+space").get()))
        #expect(parsed[1].kind == .shortcut(try Shortcut.parse("cmd+k").get()))

        headlessTestMutex.lock()
        defer { headlessTestMutex.unlock() }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rune-chords-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let scriptURL = dir.appendingPathComponent("script.json")
        try #"""
        [
            {"focus": true},
            {"t": 0.1, "type": "shortcut", "chord": "cmd+k"},
            {"t": 0.2, "type": "shortcut", "chord": "cmd+space"},
            {"t": 0.3, "shortcut": "cmd+k"},
            {"t": 0.4, "focus": false},
            {"t": 0.5, "type": "shortcut", "chord": "cmd+space"},
            {"t": 0.6, "type": "key", "name": "Escape"}
        ]
        """#.write(to: scriptURL, atomically: true, encoding: .utf8)

        keyedLogLock.withLock { keyedLog.removeAll() }
        var spec = AppSpec("chords", (40.0, 30.0), { () }, { _, _ in el() })
        spec.onKey = { _, ev, _ in
            keyedLogLock.withLock { keyedLog.append("on_key \(ev.key)") }
            return true
        }
        let app = App.new(spec)
            .globalShortcut("cmd+k") { _, _ in keyedLogLock.withLock { keyedLog.append("global cmd+k") } }
            .globalShortcut("cmd+space") { _, _ in keyedLogLock.withLock { keyedLog.append("global cmd+space") } }
        let treeURL = dir.appendingPathComponent("tree.json")
        headless(app, Args.parseFrom(["--script", scriptURL.path, "--tree", treeURL.path]))
        let seen = keyedLogLock.withLock { keyedLog }
        #expect(seen == ["global cmd+k", "global cmd+space", "global cmd+k", "global cmd+space", "on_key escape"])
    }

    @Test func traceAllNamesUnkeyedElementsAndReportsWhatAnimated() throws {
        #expect(Args.parseFrom(["--trace-all"]).traceAll)
        func runLines(_ all: Bool) throws -> [ToolingJson] {
            let rt = Runtime(
                false,
                { wide, _ in el().key("root").size(100.0, 100.0).child(el().size(wide ? 80.0 : 20.0, 20.0).pgAnimateLayout(true)) },
                (100.0, 100.0),
                Env.new(true, 1.0)
            )
            _ = rt.hostFrame(0.0)
            let pathURL = FileManager.default.temporaryDirectory.appendingPathComponent("rune-trace-all-\(all)-\(UUID().uuidString).jsonl")
            defer { try? FileManager.default.removeItem(at: pathURL) }
            let trace = ToolingTrace.open(pathURL.path, rt.viewport, 60.0, 1.0)
            trace.all = all
            trace.frame(rt, 0.0, 0.0)
            rt.state = true
            rt.hostInvalidate()
            _ = rt.hostFrame(0.0)
            _ = rt.hostFrame(0.05)
            trace.frame(rt, 50.0, 0.0)
            trace.close()
            let text = try String(contentsOf: pathURL, encoding: .utf8)
            return try text.split(separator: "\n").map { try ToolingJson.parse(String($0)) }
        }
        let keyed = try runLines(false)
        #expect((keyed[1]["m"].arrayValue ?? []).count == 1)
        let all = try runLines(true)
        let metas = all[1]["m"].arrayValue ?? []
        let root = metas.first(where: { $0["nm"].stringValue == "root" })!
        let child = metas.first(where: { $0["nm"].stringValue != "root" })!
        #expect(child["pv"] == root["id"])
        #expect(all[2]["quality"]["why"] == .array([.string("tracks")]))
        let tk = all[2]["tk"].arrayValue ?? []
        #expect(tk.contains(where: {
            let row = $0.arrayValue ?? []
            return row.count >= 3 && row[0] == child["id"] && row[1].stringValue == "frame" && row[2].intValue == 1
        }))
    }

    @Test func desktopCompositesEachWindowAtItsFrameWithAShadow() throws {
        headlessTestMutex.lock()
        defer { headlessTestMutex.unlock() }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rune-desktop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let backdropURL = dir.appendingPathComponent("backdrop.png")
        let grey = [UInt8](repeating: 128, count: 240 * 160 * 4).enumerated().map { ($0.offset % 4 == 3) ? UInt8(255) : UInt8(128) }
        try Data(encodePng(240, 160, grey)!).write(to: backdropURL)
        let scriptURL = dir.appendingPathComponent("script.json")
        try #"[{"t": 0.1, "type": "tap", "x": 45, "y": 35}]"#.write(to: scriptURL, atomically: true, encoding: .utf8)

        let red = Rune.Color(1.0, 0.0, 0.0, 1.0)
        let blue = Rune.Color(0.0, 0.0, 1.0, 1.0)

        func render(_ name: String) throws -> [UInt8] {
            let snapURL = dir.appendingPathComponent(name)
            let args = ["--desktop", backdropURL.path, "--script", scriptURL.path, "--scale", "2", "--at", "0.5", "--snap", snapURL.path]
            runWindowsWithArgs(RunOptions(), args) { displays in
                #expect(displays[0].size == (240, 160))
                let fillSpec = { AppSpec<Rune.Color>("fill", (1.0, 1.0), { Rune.Color.TRANSPARENT }, { c, _ in el().wFull().hFull().bg(c) }) }
                var backOpts = WindowOptions()
                backOpts.position = (40, 40)
                backOpts.physicalSize = (100, 60)
                var panelOpts = WindowOptions()
                panelOpts.borderless = true
                panelOpts.position = (160, 100)
                panelOpts.physicalSize = (40, 40)
                return [
                    WindowSpec.new("back", fillSpec()).state(red).options(backOpts).boxed(),
                    WindowSpec.new("panel", fillSpec()).state(blue).configuredOptions(panelOpts.macos(MacWindowOptions().shadow(false))).boxed(),
                ]
            }
            return [UInt8](try Data(contentsOf: snapURL))
        }

        let bytes = try render("a.png")
        #expect(bytes == (try render("b.png")))
        let png = decodePng(bytes)!
        #expect(png.width == 240 && png.height == 160)
        func px(_ x: Int, _ y: Int) -> [UInt8] {
            let idx = (y * 240 + x) * 4
            return Array(png.rgba[idx..<(idx + 4)])
        }
        func isRed(_ p: [UInt8]) -> Bool { p[0] > 245 && p[1] < 10 && p[2] < 10 }
        func isBlue(_ p: [UInt8]) -> Bool { p[2] > 245 && p[0] < 10 && p[1] < 10 }
        #expect(isRed(px(90, 70)) && isRed(px(40, 70)) && isRed(px(139, 70)) && isRed(px(90, 40)) && isRed(px(90, 99)))
        #expect(!isRed(px(39, 70)) && !isRed(px(140, 70)) && !isRed(px(90, 100)))
        #expect(isBlue(px(160, 100)) && isBlue(px(199, 139)) && isBlue(px(180, 120)))
        #expect(!isRed(px(40, 40)))
        let below = px(90, 106)
        #expect(below[0] < 112 && below[0] == below[2])
        #expect(px(180, 146) == [128, 128, 128, 255])
        #expect(px(4, 156) == [128, 128, 128, 255])

        let run = headlessRun()!
        #expect(run.desktop() == backdropURL.path)
        let frames = run.windowsAt(0.5)
        let back = frames.first(where: { $0.key == "back" })!
        #expect(back.frame == [20.0, 20.0, 50.0, 30.0] && back.visible && back.focused)
        #expect(run.windowFrames().contains(where: { $0.key == "panel" && $0.focused && $0.t == 0.0 }))
    }

    @Test func snapshotsLeaveThePlaygroundOutUnlessAsked() throws {
        headlessTestMutex.lock()
        defer { headlessTestMutex.unlock() }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rune-playground-snap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        func snapView(_ n: UInt32, _: Cx<UInt32>) -> El {
            col().wFull().hFull().pad(8.0).child(text("count \(n)"))
        }

        func render(_ name: String, _ withPlayground: Bool, _ open: String??) throws -> [UInt8] {
            let spec = AppSpec<UInt32>("snap", (240.0, 160.0), { 3 }, snapView)
            var app = App.new(spec)
            if withPlayground {
                app = app.playground(Playground<UInt32>.new().enabled(true).bar(true))
            }
            let snapURL = dir.appendingPathComponent("\(name).png")
            var args = Args()
            args.snap = snapURL.path
            args.scale = 2.0
            args.playground = open
            headless(app, args)
            return [UInt8](try Data(contentsOf: snapURL))
        }

        let plain = try render("plain", false, nil)
        let withBar = try render("with", true, nil)
        let opened = try render("open", true, .some(nil))
        #expect(plain == withBar)
        #expect(plain != opened)
    }
    #endif
}
