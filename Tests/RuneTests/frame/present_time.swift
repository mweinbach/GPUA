// Tests ported from: crates/rune/src/frame/present_time.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Testing
@testable import Rune

private final class FakePresentSource: PresentTimeSource, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [PresentTimeEntry] = []

    func push(_ entry: PresentTimeEntry) {
        lock.lock()
        entries.append(entry)
        lock.unlock()
    }

    func take(_ out: inout [PresentTimeEntry]) {
        lock.lock()
        out.append(contentsOf: entries)
        entries.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}

@Suite("Rune Frame Present Time Tests")
struct RuneFramePresentTimeTests {
    private static let header = #"{"type":"header","launch":"rune","width":480,"height":120,"hz":120.0,"scale":2,"clock":"wall"}"#

    private func written(_ out: [UInt8]) throws -> [[String: Any]] {
        let text = String(decoding: out, as: UTF8.self)
        return try text
            .split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
            .map { line in
                let obj = try JSONSerialization.jsonObject(with: Data(line.utf8))
                return try #require(obj as? [String: Any])
            }
    }

    #if os(macOS)
    @Test("host time maps onto instants")
    func hostTimeMapsOntoInstants() {
        let now = RuneInstant.now()
        #expect(presentMetal.instantAt(now, 100.0, 100.008) == now.adding(.milliseconds(8)))
        #expect(presentMetal.instantAt(now, 100.0, 99.992) == RuneInstant(now.raw.advanced(by: .milliseconds(-8))))
    }
    #endif

    @Test("lines wait for their present time and keep their order")
    func linesWaitForTheirPresentTimeAndKeepTheirOrder() throws {
        let start = RuneInstant.now()
        let us: (Int64) -> RuneInstant = { start.adding(.microseconds($0)) }
        let fake = FakePresentSource()
        var presents = Presents.new(fake, start)
        var out: [UInt8] = []

        presents.push(#"{"t":1"#, 1, false, &out)
        presents.push(#"{"t":2"#, 2, true, &out)
        #expect(out.isEmpty)

        // Frame 2's present arrives first; frame 1 still holds it back.
        fake.push((2, us(33_333)))
        presents.push(#"{"t":3"#, nil, true, &out)
        #expect(out.isEmpty && presents.waiting())

        fake.push((1, us(25_000)))
        presents.push(#"{"t":4"#, 3, true, &out)
        var lines = try written(out)
        #expect(lines.count == 3)
        #expect((lines[0]["present_ms"] as? NSNumber)?.doubleValue == 25.0)
        #expect(lines[0]["present_dt_ms"] == nil)
        #expect((lines[1]["present_ms"] as? NSNumber)?.doubleValue == 33.333)
        #expect((lines[1]["present_dt_ms"] as? NSNumber)?.doubleValue == 8.333)
        #expect(lines[2]["present_ms"] == nil)

        fake.push((3, nil))
        presents.flush(&out)
        lines = try written(out)
        #expect((lines[3]["t"] as? NSNumber)?.intValue == 4)
        #expect(lines[3]["present_ms"] is NSNull)
    }

    @Test("idle gaps and lost presents do not count as intervals")
    func idleGapsAndLostPresentsDoNotCountAsIntervals() throws {
        let start = RuneInstant.now()
        let fake = FakePresentSource()
        var presents = Presents.new(fake, start)
        var out: [UInt8] = []

        presents.push(#"{"t":0"#, 1, false, &out)
        fake.push((1, start))
        // After idle: presented 500 ms later, no interval.
        presents.push(#"{"t":500"#, 2, false, &out)
        fake.push((2, start.adding(.milliseconds(500))))
        // Never reported: written without a present after PRESENT_WAIT_FRAMES later frames.
        presents.push(#"{"t":508"#, 3, true, &out)
        for k in 0..<PRESENT_WAIT_FRAMES {
            presents.push("{\"t\":\(600 + k)", nil, true, &out)
        }
        let lines = try written(out)
        #expect(lines.count == 3 + Int(PRESENT_WAIT_FRAMES))
        #expect(lines[1]["present_dt_ms"] == nil)
        #expect(lines[2]["present_ms"] == nil)
    }

    private func afterGap(_ frames: [(UInt64?, Bool, UInt64??)]) throws -> [String: Any] {
        let start = RuneInstant.now()
        let fake = FakePresentSource()
        var presents = Presents.new(fake, start)
        var out: [UInt8] = []

        presents.push(#"{"t":0"#, 100, true, &out)
        fake.push((100, start))
        for (k, (seq, continuous, present)) in frames.enumerated() {
            presents.push("{\"t\":\(k + 1)", seq, continuous, &out)
            if let seq, let at = present {
                fake.push((seq, at.map { start.adding(.milliseconds(Int64($0))) }))
            }
        }
        presents.push(#"{"t":"last""#, 200, true, &out)
        fake.push((200, start.adding(.milliseconds(508))))
        presents.flush(&out)
        let lines = try written(out)
        let last = try #require(lines.last)
        #expect(last["t"] as? String == "last")
        #expect((last["present_ms"] as? NSNumber)?.doubleValue == 508.0)
        return last
    }

    @Test("a skipped first frame after idle starts no interval")
    func skippedFirstFrameAfterIdleStartsNoInterval() throws {
        let last = try afterGap([(1, false, .some(nil))])
        #expect(last["present_dt_ms"] == nil)
    }

    @Test("a frame without a drawable breaks the interval")
    func frameWithoutADrawableBreaksTheInterval() throws {
        let last = try afterGap([(nil, true, nil)])
        #expect(last["present_dt_ms"] == nil)
    }

    @Test("a present that never came breaks the interval")
    func presentThatNeverCameBreaksTheInterval() throws {
        let last = try afterGap([(1, true, nil)])
        #expect(last["present_dt_ms"] == nil)
        // The interval still spans two presented frames drawn back to back.
        let ok = try afterGap([(1, true, .some(500))])
        #expect((ok["present_dt_ms"] as? NSNumber)?.doubleValue == 8.0)
    }

    @Test("summary counts bunched and missed intervals and lag")
    func summaryCountsBunchedAndMissedIntervalsAndLag() throws {
        var trace = [Self.header]
        let frames: [(Double, Double?, Double?)] = [
            (8.0, 25.0, nil),
            (16.4, 33.3, 8.3),
            (24.7, 33.8, 0.5),   // bunched
            (33.0, 34.6, 0.8),   // bunched
            (41.4, 58.3, 23.7),  // missed (> 12.5 ms)
            (49.7, nil, nil),    // skipped
            (58.0, 66.7, 8.4),
        ]
        for (k, (target, present, dt)) in frames.enumerated() {
            let pField = present.map { String($0) } ?? "null"
            let dtField = dt.map { ",\"present_dt_ms\":\($0)" } ?? ""
            trace.append("{\"t\":\(k),\"n\":1,\"target_ms\":\(target),\"present_ms\":\(pField)\(dtField)}")
        }
        let s = try #require(PresentSummary.ofTrace(trace.joined(separator: "\n")))
        #expect((s.frames, s.presented, s.skipped, s.bunched, s.missed) == (7, 6, 1, 2, 1))
        let i = try #require(s.interval)
        #expect((i.p50, i.p95, i.max) == (8.3, 23.7, 23.7))
        let lag = try #require(s.lag)
        #expect(abs(lag.p50 - 9.1) < 1e-9 && abs(lag.max - 17.0) < 1e-9)
        #expect(s.description.contains("2 bunched (<2 ms), 1 missed (>12.50 ms)"))
    }

    @Test("traces without present times have no summary")
    func tracesWithoutPresentTimesHaveNoSummary() {
        let old = [
            Self.header,
            #"{"t":0,"n":1,"quality":{"cpu_ms":0.2}}"#,
            #"{"t":8.33,"n":1,"e":[[1,0,0,10,10,1,0,0]]}"#,
        ].joined(separator: "\n")
        #expect(PresentSummary.ofTrace(old) == nil)
        let targets = [Self.header, #"{"t":0,"n":1,"target_ms":8.0}"#].joined(separator: "\n")
        #expect(PresentSummary.ofTrace(targets) == nil)
        #expect(PresentSummary.ofTrace("") == nil)
    }

    @Test("spread uses nearest rank")
    func spreadUsesNearestRank() throws {
        let s = try #require(PresentSpread.of((1...20).map { Double($0) }))
        #expect((s.p50, s.p95, s.max) == (10.0, 19.0, 20.0))
        #expect(PresentSpread.of([4.0]) == PresentSpread(p50: 4.0, p95: 4.0, max: 4.0))
        #expect(PresentSpread.of([]) == nil)
    }
}
