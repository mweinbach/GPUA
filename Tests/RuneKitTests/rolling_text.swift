// Tests ported from: crates/rune-kit/src/rolling_text.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneKit

private func stored() -> (Int, Int) {
    withRollingTextStore { m in
        (m.labels.count, m.bytes)
    }
}

private func kept(_ old: String, _ new: String) -> String {
    let o = old.map { String($0) }
    let n = new.map { String($0) }
    return zip(rollingTextDiff(o, n, false), n)
        .map { $0.0 != nil ? $0.1 : "_" }
        .joined()
}

private func keptEnd(_ old: String, _ new: String) -> String {
    let o = old.map { String($0) }
    let n = new.map { String($0) }
    return zip(rollingTextDiff(o, n, true), n)
        .map { $0.0 != nil ? $0.1 : "_" }
        .joined()
}

@Suite(.serialized)
struct RollingTextInlineTests {
    @Test
    func memoryIsBoundedAndALabelBuiltEveryFrameKeepsItsOwn() {
        for i in 0..<10_000 {
            _ = rollingTextKeys("busy", "\(i % 7)", nil, false)
            _ = rollingTextKeys("row-\(i)", "0:30", nil, false)
            let s = stored()
            #expect(s.0 <= ROLLING_TEXT_MAX_LABELS && s.1 <= ROLLING_TEXT_MAX_BYTES)
        }
        let (first, _) = rollingTextKeys("busy", "3", nil, false)
        let (again, _) = rollingTextKeys("busy", "3", nil, false)
        #expect(!again[0].entered && again[0].id == first[0].id, "the busy label kept its memory")
        #expect(first[0].id > 1, "ids continued rather than restarting")
        let bytes = withRollingTextStore { m in
            m.labels.reduce(0) { $0 + $1.value.bytes($1.key) }
        }
        #expect(bytes == stored().1)
    }

    @Test
    func longLabelsAreBoundedByBytes() {
        let long = String(repeating: "x", count: 5_000)
        for i in 0..<200 {
            _ = rollingTextKeys("long-\(i)", long, nil, false)
            #expect(stored().1 <= ROLLING_TEXT_MAX_BYTES)
        }
    }

    @Test
    func aTrailingLabelMatchesFromTheRightLikeAnOdometer() {
        #expect(keptEnd("10s", "100s") == "__0s")
        #expect(keptEnd("19s", "100s") == "___s")
        #expect(keptEnd("9s", "10s") == "__s")
        #expect(keptEnd("$1.98", "$1.99") == "$1.9_")
        #expect(keptEnd("$9.99", "$10.00") == "$__.__")
        #expect(keptEnd("59s", "1m 00s") == "_____s")
    }

    @Test
    func aCountdownRollsOnlyTheChangedDigits() {
        #expect(kept("0:30", "0:29") == "0:__")
        #expect(kept("0:21", "0:20") == "0:2_")
        #expect(kept("1:00", "0:59") == "_:__")
        #expect(kept("9", "10") == "__")
    }

    @Test
    func prefixesSuffixesAndRunsKeepIdentityButLoneFarMatchesRoll() {
        #expect(kept("Copy password", "Copied, clears in 0:30") == "Cop___________________")
        #expect(kept("Copied, clears in 0:30", "Copy password") == "Cop__________")
        #expect(kept("12 files", "3 files") == "_ files")
        #expect(kept("Save draft", "Saved draft") == "Save_ draft")
        // The middle "ab" run moves as a pair.
        #expect(kept("xxabyy", "xqqqabzyy") == "x___ab_yy")
    }

    @Test
    func graphemesAreOneGlyph() {
        #expect(kept("e\u{301}1", "e\u{301}2") == "e\u{301}_")
        #expect(kept("👍🏽 1", "👍🏽 2") == "👍🏽 _")
    }

    @Test
    func rebuildingTheSameTextKeepsEveryKey() {
        let a = rollingTextKeys("same", "0:30", nil, false).0.map(\.id)
        let b = rollingTextKeys("same", "0:30", nil, false).0.map(\.id)
        #expect(a == b)
        let c = rollingTextKeys("same", "0:29", nil, false).0
        #expect(c[0].id == a[0] && c[1].id == a[1])
        #expect(c[2].entered && c[3].entered && !c[0].entered)
        #expect(c[2].id > a[3] && c[3].id > a[3], "new glyphs never reuse an exiting key")
    }

    @Test
    func aValueRollsTheWayItMoves() {
        func falls(_ text: String, _ v: Double?) -> Bool {
            rollingTextKeys("dir", text, v, false).1
        }
        #expect(!falls("9s", 9.0), "the first build rolls nowhere, as counting up")
        #expect(!falls("10s", 10.0), "rising")
        #expect(falls("8s", 8.0), "falling")
        #expect(!falls("8 s", 8.0), "new text with the same value rolls by the text rule")
        #expect(!falls("8s", nil), "so does a build without a value")
        #expect(!falls("-", .nan) && !falls("∞", -.infinity), "no direction for NaN or infinity")
        #expect(falls("7s", 7.0), "and they don't replace the last value")
        #expect(!falls("12s", 12.0), "rising again")
    }
}
