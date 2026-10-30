// Tests ported from: crates/gpui_platform/src/gpui_platform.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

import Testing
import Foundation
import GPUI
@testable import GPUIPlatform

// PORT NOTE: TestBox provides thread-safe cell storage for testing async completion.
private final class TestBox: @unchecked Sendable {
    var ran: Bool = false
}

@Suite("GPUIPlatform Tests")
struct GPUIPlatformTests {
    @Test
    func testCurrentPlatform() throws {
        let platform = currentPlatform(headless: true)
        let ts = platform.textSystem()
        #if os(macOS) || os(Linux) || os(Windows)
        #expect(!ts.allFontNames().isEmpty)
        #endif
        let defaultFontId = try ts.fontId(descriptor: Font())
        let metrics = ts.fontMetrics(fontId: defaultFontId)
        #expect(metrics.unitsPerEm > 0)
    }

    @Test
    @MainActor
    func testHeadlessApplication() {
        let app = headless()
        #expect(app.app.windows().isEmpty)
    }

    @Test
    func testBackgroundExecutor() async throws {
        let exec = try #require(backgroundExecutor())
        let box = TestBox()
        let task = exec.spawn {
            box.ran = true
            return 42
        }
        let value = await task.value
        #expect(box.ran)
        #expect(value == 42)
    }

    @Test
    @MainActor
    func testForegroundTasksRunWithRunUntilParked() {
        let platform = currentPlatform(headless: true)
        let cx = VisualTestAppContext(platform: platform)
        let box = TestBox()

        cx.update { cx in
            cx.spawn { _ in
                box.ran = true
            }.detach()
        }

        #expect(!box.ran)
        cx.runUntilParked()
        #expect(box.ran)
    }

    // Upstream: #[test] #[ignore] // Requires macOS main thread
    @Test(.disabled("Upstream #[ignore]: Requires macOS main thread"))
    @MainActor
    func testAdvanceClockTriggersDelayedTasks() async {
        let platform = currentPlatform(headless: true)
        let cx = VisualTestAppContext(platform: platform)
        let box = TestBox()

        let executor = cx.backgroundExecutor
        cx.update { cx in
            cx.spawn { _ in
                _ = await executor.timer(.milliseconds(500)).value
                box.ran = true
            }.detach()
        }

        cx.runUntilParked()
        #expect(!box.ran)

        cx.advanceClock(.milliseconds(600))
        #expect(box.ran)
    }

    // Upstream: #[test] #[ignore] // Requires macOS main thread - window creation fails on test threads
    @Test(.disabled("Upstream #[ignore]: Requires macOS main thread - window creation fails on test threads"))
    @MainActor
    func testWindowSpawnUsesTestDispatcher() {
        let platform = currentPlatform(headless: true)
        let cx = VisualTestAppContext(platform: platform)
        let box = TestBox()

        cx.runUntilParked()
        #expect(!box.ran)
    }
}
