// Tests ported from: crates/rune-kit/src/diff/myers.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneKit

private func applyOps<T: Equatable>(_ a: [T], _ b: [T], _ ops: [MyersOp]) -> ([T], Int) {
    var out: [T] = []
    var same = 0
    for op in ops {
        switch op {
        case .equal(let old, let new, let len):
            #expect(Array(a[old..<(old + len)]) == Array(b[new..<(new + len)]))
            out.append(contentsOf: a[old..<(old + len)])
            same += len
        case .delete:
            break
        case .insert(let new, let len):
            out.append(contentsOf: b[new..<(new + len)])
        }
    }
    return (out, same)
}

private func lcsLen<T: Equatable>(_ a: [T], _ b: [T]) -> Int {
    var dp = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
    for i in stride(from: a.count - 1, through: 0, by: -1) {
        for j in stride(from: b.count - 1, through: 0, by: -1) {
            if a[i] == b[j] {
                dp[i][j] = dp[i + 1][j + 1] + 1
            } else {
                dp[i][j] = max(dp[i + 1][j], dp[i][j + 1])
            }
        }
    }
    return dp[0][0]
}

private func utf8Slice(_ s: String, _ r: Range<Int>) -> String {
    let bytes = Array(s.utf8)
    return String(decoding: bytes[r], as: UTF8.self)
}

@Suite("DiffMyersTests")
struct DiffMyersTests {
    @Test func scriptsAreMinimalAndRebuildTheNewSide() {
        var seed: UInt64 = 0x2545_f491
        func next(_ n: UInt64) -> UInt64 {
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            return seed % n
        }
        for round in 0..<1200 {
            let (len, alphabet): (UInt64, UInt64) = (round % 3 == 0) ? (40, 3) : (14, 4)
            let la = Int(next(len))
            let lb = Int(next(len))
            let a: [UInt8] = (0..<la).map { _ in UInt8(next(alphabet)) }
            let b: [UInt8] = (0..<lb).map { _ in UInt8(next(alphabet)) }
            let ops = myers.diff(a, b)
            let (rebuilt, same) = applyOps(a, b, ops)
            #expect(rebuilt == b)
            #expect(same == lcsLen(a, b))
        }
    }

    @Test func manyScatteredEditsStillDiffLineByLine() {
        // Far past MAX_D edits: every seventh line changed across 30,000.
        let a: [UInt32] = Array(0..<30_000)
        let b: [UInt32] = (0..<30_000).map { i in (i % 7 == 3) ? (i + 1_000_000) : i }
        let ops = myers.diff(a, b)
        let (rebuilt, same) = applyOps(a, b, ops)
        #expect(rebuilt == b)
        #expect(same == 30_000 - 4_286)
    }

    @Test func adversarialInputsStayWithinBoundsAndRebuildTheNewSide() {
        // All equal.
        let eq: [UInt32] = Array(0..<2_500)
        #expect(myers.diff(eq, eq) == [.equal(old: 0, new: 0, len: 2_500)])

        // All different, both below and past MAX_D.
        for n in [50, 2_000] {
            let a: [UInt32] = (0..<n).map(UInt32.init)
            let b: [UInt32] = (n..<(2 * n)).map(UInt32.init)
            let ops = myers.diff(a, b)
            let (rebuilt, same) = applyOps(a, b, ops)
            #expect(rebuilt == b)
            #expect(same == 0)
        }

        // Short side matching inside a much longer side (both within and past MAX_D).
        let short: [UInt32] = Array(1...5)
        for len: UInt32 in [20, 2_500] {
            let long: [UInt32] = Array(0..<len)
            let ops = myers.diff(short, long)
            let (rebuilt, same) = applyOps(short, long, ops)
            #expect(rebuilt == long)
            #expect(same == 5)

            let opsRev = myers.diff(long, short)
            let (rebuiltRev, sameRev) = applyOps(long, short, opsRev)
            #expect(rebuiltRev == short)
            #expect(sameRev == 5)
        }

        // Repeated identical blocks (classic Myers pathology).
        var a: [UInt32] = []
        a.reserveCapacity(1_600)
        for _ in 0..<400 {
            a.append(contentsOf: [1, 2, 3, 4])
        }
        var b = a
        a.replaceSubrange(800..<804, with: [9, 9])
        b.replaceSubrange(400..<400, with: [1, 2, 3, 4, 8, 8])
        let ops = myers.diff(a, b)
        let (rebuilt, same) = applyOps(a, b, ops)
        #expect(rebuilt == b)
        #expect(same >= 1_596)
    }

    @Test func runsCoalesceWithDeletionsFirst() {
        let a = ["a", "b", "c", "d"]
        let b = ["a", "x", "y", "d", "e"]
        #expect(
            myers.diff(a, b) == [
                .equal(old: 0, new: 0, len: 1),
                .delete(old: 1, len: 2),
                .insert(new: 1, len: 2),
                .equal(old: 3, new: 3, len: 1),
                .insert(new: 4, len: 1),
            ]
        )
        let empty: [UInt8] = []
        #expect(myers.diff(empty, empty).isEmpty)
    }

    @Test func wordChangesCoverChangedWordsAndJoinAcrossSpaces() {
        let (a, b) = myers.words("let total = price * count;", "let total = price * amount + tax;")
        #expect(a == [20..<25])
        #expect(utf8Slice("let total = price * amount + tax;", b[0]) == "amount + tax")

        // Nothing in common: no word emphasis, the line colour says it all.
        let disjoint = myers.words("fn main() {}", "SELECT * FROM users")
        #expect(disjoint.0.isEmpty && disjoint.1.isEmpty)

        let identical = myers.words("same", "same")
        #expect(identical.0.isEmpty && identical.1.isEmpty)
    }
}
