// Tests ported from: crates/rune-kit/src/diff/model.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneKit

private struct LineNumbers: Equatable {
    let kind: LineKind
    let old: UInt32?
    let new: UInt32?

    init(_ kind: LineKind, _ old: UInt32?, _ new: UInt32?) {
        self.kind = kind
        self.old = old
        self.new = new
    }
}

private struct LineSummary: Equatable {
    let kind: LineKind
    let text: String
    let noNewline: Bool

    init(_ kind: LineKind, _ text: String, _ noNewline: Bool) {
        self.kind = kind
        self.text = text
        self.noNewline = noNewline
    }
}

private func replaceAll(_ s: String, _ target: String, _ replacement: String) -> String {
    guard !target.isEmpty else { return s }
    var out = ""
    var rest = s[...]
    while let range = rest.range(of: target) {
        out.append(contentsOf: rest[..<range.lowerBound])
        out.append(replacement)
        rest = rest[range.upperBound...]
    }
    out.append(contentsOf: rest)
    return out
}

private func utf8Slice(_ s: String, _ r: Range<Int>) -> String {
    let bytes = Array(s.utf8)
    return String(decoding: bytes[r], as: UTF8.self)
}

@Suite("DiffModelTests")
struct DiffModelTests {
    @Test func textsMakeHunksWithThreeLinesOfContext() {
        let old = (1...20).map { "line \($0)\n" }.joined()
        var new = replaceAll(old, "line 5\n", "line five\n")
        new = replaceAll(new, "line 17\n", "")
        new = replaceAll(new, "line 20\n", "line 20\nline 21\n")

        let f = FileDiff.fromTexts("a.txt", old, new)
        let headers = f.hunks.map { $0.header() }
        #expect(headers == ["@@ -2,7 +2,7 @@ line 1", "@@ -14,7 +14,7 @@ line 13"])

        let second = f.hunks[1].lines.map { LineNumbers($0.kind, $0.old, $0.new) }
        #expect(second[3] == LineNumbers(.removed, 17, nil))
        #expect(second.last == LineNumbers(.added, nil, 20))
        #expect(f.additions() == 2)
        #expect(f.deletions() == 2)

        let added = f.hunks[0].lines.first { $0.kind == .added }!
        #expect(utf8Slice(added.text, added.changes[0]) == "five")
    }

    @Test func aMissingFinalNewlineIsAChange() {
        let f = FileDiff.fromTexts("a", "one\ntwo", "one\ntwo\n")
        let l = f.hunks[0].lines.map { LineSummary($0.kind, $0.text, $0.noNewline) }
        #expect(
            l == [
                LineSummary(.context, "one", false),
                LineSummary(.removed, "two", true),
                LineSummary(.added, "two", false),
            ]
        )

        let bothMissing = FileDiff.fromTexts("a", "one\ntwo", "one\nthree")
        let l2 = bothMissing.hunks[0].lines.map { LineSummary($0.kind, $0.text, $0.noNewline) }
        #expect(
            l2 == [
                LineSummary(.context, "one", false),
                LineSummary(.removed, "two", true),
                LineSummary(.added, "three", true),
            ]
        )

        #expect(FileDiff.fromTexts("a", "same\n", "same\n").hunks.isEmpty)
        #expect(FileDiff.fromTexts("a", "same", "same").hunks.isEmpty)

        // CRLF normalizes line endings while preserving changes.
        #expect(FileDiff.fromTexts("a", "one\r\ntwo\r\n", "one\ntwo\n").hunks.isEmpty)
        let crlf = FileDiff.fromTexts("a", "one\r\ntwo\r\n", "one\r\nthree\r\n")
        #expect(crlf.hunks[0].lines[1].text == "two")
        #expect(crlf.hunks[0].lines[2].text == "three")

        // NUL bytes mark a binary file.
        let bin = FileDiff.fromTexts("img.bin", "a\0b", "c\0d")
        #expect(bin.binary && bin.hunks.isEmpty)
    }

    @Test func hostileAndFuzzedPatchesNeverPanicOrBlowUp() {
        let cases = [
            "",
            "diff --git\n--- \n+++ \n@@ -4294967295,4294967295 +4294967295,4294967295 @@\n-a\n+b\n\\ No newline",
            "diff --git \"a/unclosed b/unclosed\n--- \"a/\\777\\x\n+++ b/\n@@ -0,0 +0,0 @@\n",
            "diff --git 🚀 a/x 🚀 b/y\n@@ -1,999999 +1,999999 @@\n+truncated",
            "--- a/f\n+++ b/f\n@@ -10,2 +10,2 @@\n ctx\n-old\n+new\n@@ -2,1 +2,1 @@\n-out_of_order\n+ok\n",
        ]
        for patch in cases {
            let files = diff.parse(patch)
            _ = DiffState.new(files)
        }

        // Fuzz-style random line soup of headers, hunks, escapes and markers.
        var seed: UInt64 = 0x9e37_79b9_7f4a_7c15
        func next(_ n: Int) -> Int {
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            return Int(seed % UInt64(n))
        }
        let fragments = [
            "diff --git a/f.rs b/f.rs\n",
            "diff --git \"a/sp ace\\303\\251\" \"b/sp ace\\n\"\n",
            "--- a/f.rs\n",
            "+++ b/f.rs\n",
            "--- /dev/null\n",
            "+++ /dev/null\n",
            "@@ -1,3 +1,3 @@ fn f()\n",
            "@@ -0,0 +1,5 @@\n",
            "@@ -4294967295,10 +0,4294967295 @@\n",
            "@@ malformed @@\n",
            " context line\n",
            "-removed line\n",
            "+added line\n",
            "\\ No newline at end of file\n",
            "rename from \"a/\\123\"\n",
            "similarity index 999%\n",
            "Binary files a/x and b/x differ\n",
            "\r\n",
        ]
        for _ in 0..<300 {
            let len = 1 + next(24)
            let patch = (0..<len).map { _ in fragments[next(fragments.count)] }.joined()
            let files = diff.parse(patch)
            var state = DiffState.new(files)
            state.setMode(.split)
            for f in 0..<state.files().count {
                _ = state.sideLine(f, .old, 1)
                _ = state.sideLine(f, .new, 1)
            }
        }
    }

    @Test func anAddedFileAndAnInsertionCountFromZero() {
        let f = FileDiff.between(nil, "new.rs", "", "fn main() {}\n")
        #expect(f.status == .added)
        #expect(f.hunks[0].header() == "@@ -0,0 +1 @@")

        let reparsed = diff.parse("--- /dev/null\n+++ b/new.rs\n@@ -0,0 +1 @@\n+fn main() {}\n")
        #expect(reparsed[0].hunks[0].lines == f.hunks[0].lines)
        #expect(reparsed[0].status == .added)
    }

    @Test func languagesComeFromTheExtension() {
        func lang(_ p: String) -> String? {
            FileDiff.fromTexts(p, "", "x").language()
        }
        #expect(lang("src/lib.rs") == "rs")
        #expect(lang("web/App.tsx") == "tsx")
        #expect(lang(".gitignore") == nil)
        #expect(lang("Makefile") == "Makefile")
    }
}
