// Tests ported from: crates/rune/src/frame/encoded_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private final class EncodedLogBox {
    var items: [FrameEncoded] = []
}

@Suite("Rune Frame Encoded Tests")
struct RuneFrameEncodedTests {
    private func logging() -> (EncodedLogBox, OnFrameEncoded) {
        let box = EncodedLogBox()
        return (box, { f in box.items.append(f) })
    }

    @Test("reports number each frame of their window")
    func reportsNumberEachFrameOfTheirWindow() {
        let (logBox, hook) = logging()
        var reports = FrameReports<Void>.new(hook, "main")
        let target = RuneInstant.now().adding(.milliseconds(8))
        let started = RuneInstant.now()
        let encoded = reports.stamp()
        #expect(encoded != nil)

        reports.drawn(encoded, target, started, 0.0)
        reports.unchanged(target)
        reports.skipped()

        let log = logBox.items
        #expect(log.count == 3)
        #expect(log[0].seq() == 0 && log[0].outcome() == .drawn && log[0].window() == "main" && log[0].presentsAt() == target)
        #expect(log[1].seq() == 1 && log[1].outcome() == .unchanged && log[1].window() == "main" && log[1].presentsAt() == target)
        #expect(log[2].seq() == 2 && log[2].outcome() == .skipped && log[2].window() == "main" && log[2].presentsAt() == nil)
        #expect(log[0].at() == encoded)
        #expect(log[1].at() >= log[0].at() && log[2].at() >= log[1].at())
    }

    @Test("a drawn frame splits its work into update and encode")
    func drawnFrameSplitsItsWorkIntoUpdateAndEncode() {
        let (logBox, hook) = logging()
        var reports = FrameReports<Void>.new(hook, "main")
        let started = RuneInstant.now()
        let encoded = started.adding(.milliseconds(5))
        reports.drawn(encoded, nil, started, 2.0)
        // A clock step can put the stamp before the update ended: encode time is never negative.
        reports.drawn(started, nil, started, 2.0)
        reports.unchanged(nil)
        reports.skipped()

        let log = logBox.items
        #expect(log[0].updateMs() == 2.0)
        #expect(abs((log[0].encodeMs() ?? -1.0) - 3.0) < 1e-9)
        #expect(log[1].encodeMs() == 0.0)
        for f in log.dropFirst(2) {
            #expect(f.updateMs() == nil && f.encodeMs() == nil)
        }
    }

    @Test("without a hook nothing is timed or counted")
    func withoutAHookNothingIsTimedOrCounted() {
        var reports = FrameReports<Void>.new(nil, "main")
        #expect(reports.stamp() == nil)
        reports.drawn(nil, nil, .now(), 1.0)
        reports.unchanged(nil)
        reports.skipped()
        #expect(!reports.hasReporter)
    }

    @Test(
        "a window spec keeps its app's hook until it sets its own",
        .disabled("Requires WindowSpec and App.onFrameEncoded in window.swift / app.swift")
    )
    func windowSpecKeepsItsAppsHookUntilItSetsItsOwn() {}

    @Test("a drawn frame's inspector reads the runtime it presented")
    func drawnFrameInspectorReadsTheRuntimeItPresented() {
        var seen: [(UInt32, Bool)] = []
        var reports = FrameReports<UInt32>.new(nil, "main").inspecting { rt in
            seen.append((rt.state, rt.elements().contains(where: { $0.key == "box" })))
        }
        let rt = Runtime<UInt32>(7, { _, _ in el().key("box").size(20.0, 20.0) }, (100.0, 100.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        reports.inspect(rt)
        #expect(seen.count == 1)
        #expect(seen[0].0 == 7 && seen[0].1 == true)
        #expect(!FrameReports<UInt32>.new(nil, nil).hasDrawnInspector)
    }
}
