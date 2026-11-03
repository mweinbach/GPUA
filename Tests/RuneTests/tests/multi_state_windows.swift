// Tests ported from: crates/rune/tests/multi_state_windows.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Testing
@testable import Rune

private struct MultiStateReview {
    var count: UInt32
}

private struct MultiStateSettings {
    var name: String
}

private func multiStateReviewView(_ s: MultiStateReview, _: Cx<MultiStateReview>) -> El {
    text("review \(s.count)").key("out")
}

private func multiStateSettingsView(_ s: MultiStateSettings, _: Cx<MultiStateSettings>) -> El {
    text("settings \(s.name)").key("out")
}

private func makeMultiStateReview() -> App<MultiStateReview> {
    App.new(AppSpec.new("Review", (400.0, 300.0), { MultiStateReview(count: 0) }, multiStateReviewView))
}

private func makeMultiStateSettings() -> WindowSpec<MultiStateSettings> {
    WindowSpec.new("settings", AppSpec.new("Settings", (320.0, 200.0), { MultiStateSettings(name: "default") }, multiStateSettingsView))
}

private func multiStateRendered(_ name: String, _ run: ([String]) -> Void) throws -> (String, [Double]) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("rune-multi-state-\(name)-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let treePath = dir.appendingPathComponent("tree.json")
    headlessTestMutex.withLock {
        run(["--tree", treePath.path])
    }

    let data = try Data(contentsOf: treePath)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let elements = try #require(json["elements"] as? [[String: Any]])
    let out = try #require(elements.first { ($0["key"] as? String) == "out" })
    let txt = try #require(out["text"] as? String)
    let vpNums = try #require(json["viewport"] as? [NSNumber])
    return (txt, vpNums.map(\.doubleValue))
}

@Suite("MultiStateWindowsIntegrationTests", .serialized)
struct MultiStateWindowsIntegrationTests {
    @Test func aFactoryMixesStateTypesAndToolsRenderTheSelectedOne() throws {
        let cases: [(String, String, [Double])] = [
            ("review", "review 7", [400.0, 300.0]),
            ("settings", "settings Kit", [320.0, 200.0]),
        ]
        for (key, expectedText, expectedViewport) in cases {
            let (out, size) = try multiStateRendered("factory-\(key)") { baseArgs in
                var args = baseArgs
                args.append(contentsOf: ["--window", key])
                runWindowsWithArgs(RunOptions(), args) { _ in
                    let review = makeMultiStateReview()
                    review.handle().update { s, _ in s.count = 7 }
                    let settingsHandle = AppHandle<MultiStateSettings>()
                    settingsHandle.update { s, _ in s.name = "Kit" }
                    let settings = makeMultiStateSettings().handle(settingsHandle)
                    return [WindowSpec.fromApp("review", review).boxed(), settings.intoAny()]
                }
            }
            #expect(out == expectedText)
            #expect(size == expectedViewport)
        }
    }

    @Test func appWindowIsSelectableWithItsOwnStateAndHiddenUntilOpened() throws {
        let cases: [(String, String, [Double])] = [
            ("main", "review 7", [400.0, 300.0]),
            ("settings", "settings Kit", [320.0, 200.0]),
        ]
        for (key, expectedText, expectedViewport) in cases {
            let (out, size) = try multiStateRendered("app-\(key)") { baseArgs in
                var args = baseArgs
                args.append(contentsOf: ["--window", key])
                let app = makeMultiStateReview()
                let hidden = WindowOptions(visible: false)
                let (settings, window) = app.window(makeMultiStateSettings().options(hidden))
                #expect(window.key() == "settings")
                #expect(!settings.isVisible() && !window.isReady())
                window.open()
                settings.update { s, _ in s.name = "Kit" }
                app.handle().update { s, _ in s.count = 7 }
                app.args(args).run()
            }
            #expect(out == expectedText)
            #expect(size == expectedViewport)
        }
    }

    @Test func factoryWindowsCanAddTheirOwnSecondaryWindows() throws {
        let (out, _) = try multiStateRendered("nested") { baseArgs in
            var args = baseArgs
            args.append(contentsOf: ["--window", "settings"])
            runWindowsWithArgs(RunOptions(), args) { _ in
                let review = makeMultiStateReview()
                let (settings, _) = review.window(makeMultiStateSettings())
                settings.update { s, _ in s.name = "nested" }
                return [WindowSpec.fromApp("review", review).boxed()]
            }
        }
        #expect(out == "settings nested")
    }
}
