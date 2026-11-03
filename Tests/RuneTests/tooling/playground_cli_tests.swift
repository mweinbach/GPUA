// Tests ported from: crates/rune/src/tooling/playground_cli_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if !os(WASI)
import Foundation
#endif
import Testing
@testable import Rune

#if !os(WASI)
private struct CliPadState {
    var x: Float = 0.0
    var size: Float = 0.0
    var green: Bool = false
}

private func cliPadView(_ p: CliPadState, _: Cx<CliPadState>) -> El {
    let fill = p.green ? oklch(0.7, 0.2, 145.0) : oklch(0.6, 0.2, 30.0)
    return el()
        .wFull()
        .hFull()
        .child(el().key("puck").pgAbsolute(p.x, 10.0).size(p.size, p.size).bg(fill))
}

private func cliPadScenes() -> [(String, (inout CliPadState) -> Void)] {
    [("Motion/Slide", { p in p.size = 20.0 })]
}

private func cliPadApp() -> App<CliPadState> {
    let playground = Playground<CliPadState>.new()
        .enabled(true)
        .trigger("Slide", "r", "Slide") { _, play in
            play.after(0.3) { p, _ in p.x = 60.0 }
        }
        .trigger("Slide", "g", "Green") { p, _ in p.green = true }
        .variant("Slide", "Small") { p in p.size = 20.0 }
        .variant("Slide", "Big") { p in p.size = 40.0 }
    var spec = AppSpec<CliPadState>("pad", (960.0, 240.0), { CliPadState() }, cliPadView)
    spec.scenes = cliPadScenes()
    return App.new(spec).playground(playground)
}

private func cliRun(_ dir: URL, _ name: String, _ extraArgs: [String]) throws -> URL {
    let out = dir.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let snap = out.appendingPathComponent("snap.png")
    var argv = ["--playground", "Motion/Slide", "--scale", "2", "--fps", "30", "--snap", snap.path]
    argv.append(contentsOf: extraArgs.map { $0.replacingOccurrences(of: "{out}", with: out.path) })
    headless(cliPadApp(), Args.parseFrom(argv))
    return out
}

private func cliBytes(_ dir: URL) throws -> [(String, [UInt8])] {
    let items = (try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]))
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    var result: [(String, [UInt8])] = []
    for item in items {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
            result.append(contentsOf: try cliBytes(item))
        } else {
            result.append((item.lastPathComponent, [UInt8](try Data(contentsOf: item))))
        }
    }
    return result
}

private func cliPngSize(_ path: URL) throws -> (UInt32, UInt32) {
    let b = [UInt8](try Data(contentsOf: path))
    func be(_ i: Int) -> UInt32 {
        (UInt32(b[i]) << 24) | (UInt32(b[i + 1]) << 16) | (UInt32(b[i + 2]) << 8) | UInt32(b[i + 3])
    }
    return (be(16), be(20))
}

private func cliHasFfprobe() -> Bool {
    #if os(Android)
    return false
    #else
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = ["ffprobe", "-version"]
    p.standardOutput = Pipe()
    p.standardError = Pipe()
    do {
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0
    } catch {
        return false
    }
    #endif
}

@Suite("ToolingPlaygroundCliTests", .serialized)
struct ToolingPlaygroundCliTests {
    @Test func aPlaygroundSceneRendersItsScriptTheSameEveryRun() throws {
        headlessTestMutex.lock()
        defer { headlessTestMutex.unlock() }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rune-playground-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let script = dir.appendingPathComponent("script.json")
        try #"[{"t": 0.5, "type": "type", "text": "g"}, {"t": 1.2, "type": "mark", "name": "end"}]"#
            .write(to: script, atomically: true, encoding: .utf8)

        let video = cliHasFfprobe()
        var args = ["--script", script.path, "--at", "1.0", "--out", "{out}/frames", "--every", "6"]
        if video {
            args.append(contentsOf: ["--video", "{out}/clip.mp4"])
        }
        let first = try cliBytes(cliRun(dir, "first", args))
        let second = try cliBytes(cliRun(dir, "second", args))
        #expect(first.contains(where: { $0.0 == "snap.png" }) && first.contains(where: { $0.0.hasPrefix("frame_") }))
        #expect(first.contains(where: { $0.0 == "clip.mp4" }) == video)
        #expect(first.count == second.count)
        for ((name, a), (_, b)) in zip(first, second) {
            #expect(a == b, "File \(name) differed between runs")
        }

        let still = try cliBytes(cliRun(dir, "still", ["--at", "1.0"]))
        let start = try cliBytes(cliRun(dir, "start", ["--at", "0"]))
        let snapFirst = first.first(where: { $0.0 == "snap.png" })!.1
        let snapStill = still.first(where: { $0.0 == "snap.png" })!.1
        let snapStart = start.first(where: { $0.0 == "snap.png" })!.1
        #expect(snapFirst != snapStill)
        #expect(snapStill != snapStart)
    }

    @Test func variantAndCropPickAStorysVariantAndCropTheSnapToAnElement() throws {
        headlessTestMutex.lock()
        defer { headlessTestMutex.unlock() }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rune-playground-crop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let parsed = Args.parseFrom(["--playground", "--snap", "s.png", "--crop", "1,2,3,4", "--crop", "puck", "--variant", "Big"])
        #expect(parsed.crops == [[1.0, 2.0, 3.0, 4.0]])
        #expect(parsed.cropKey == "puck")
        #expect(parsed.variant == "Big")

        let small = try cliRun(dir, "small", ["--variant", "1", "--crop", "puck"])
        let big = try cliRun(dir, "big", ["--variant", "Big", "--crop", "puck"])
        let again = try cliRun(dir, "again", ["--variant", "big", "--crop", "puck"])
        let smallSz = try cliPngSize(small.appendingPathComponent("snap.png"))
        let bigSz = try cliPngSize(big.appendingPathComponent("snap.png"))
        #expect(smallSz == (40, 40))
        #expect(bigSz == (80, 80))
        #expect((try cliBytes(big)).map(\.1) == (try cliBytes(again)).map(\.1))
    }

    @Test func wholeWindowSnapsTheListAndSideColumnAndCropsToTheirKeys() throws {
        headlessTestMutex.lock()
        defer { headlessTestMutex.unlock() }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rune-playground-whole-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let stage = try cliRun(dir, "stage", ["--at", "0"])
        let whole = try cliRun(dir, "whole", ["--at", "0", "--whole-window"])
        let again = try cliRun(dir, "again", ["--at", "0", "--whole-window"])
        let group = try cliRun(dir, "group", ["--at", "0", "--whole-window", "--crop", "playground-group-0"])
        let side = try cliRun(dir, "side", ["--at", "0", "--whole-window", "--crop", "playground-side"])

        let stagePng = decodePng([UInt8](try Data(contentsOf: stage.appendingPathComponent("snap.png"))))!
        let wholePng = decodePng([UInt8](try Data(contentsOf: whole.appendingPathComponent("snap.png"))))!
        #expect(stagePng.width == 988 && stagePng.height == 480)
        #expect(wholePng.width == 1920 && wholePng.height == 480)

        let croppedStageFromWhole = toolingCropRgba(wholePng.rgba, 1920, [402, 0, 988, 480])
        #expect(croppedStageFromWhole == stagePng.rgba)

        func varied(_ x: UInt32, _ w: UInt32) -> Bool {
            let region = toolingCropRgba(wholePng.rgba, 1920, [x, 0, w, 480])
            guard region.count >= 4 else { return false }
            let p0 = Array(region[0..<4])
            var idx = 4
            while idx + 4 <= region.count {
                if Array(region[idx..<(idx + 4)]) != p0 {
                    return true
                }
                idx += 4
            }
            return false
        }
        #expect(varied(0, 400) && varied(1392, 528))
        #expect((try cliBytes(whole)).map(\.1) == (try cliBytes(again)).map(\.1))
        let groupSz = try cliPngSize(group.appendingPathComponent("snap.png"))
        let sideSz = try cliPngSize(side.appendingPathComponent("snap.png"))
        #expect(groupSz == (368, 48))
        #expect(sideSz == (528, 480))
    }
}
#endif
