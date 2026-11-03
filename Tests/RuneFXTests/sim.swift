// Tests ported from: crates/rune-fx/src/sim.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneFX

/// `Sims.plan`'s bookkeeping without the GPU.
private func claim(_ grids: inout [Claim], _ key: SimKey, _ origin: [Float], _ frame: UInt64) -> Int {
    if let i = pick(grids, key, origin, frame) {
        grids[i] = Claim(key: key, origin: origin, used: frame)
        return i
    }
    grids.append(Claim(key: key, origin: origin, used: frame))
    return grids.count - 1
}

@Suite("RuneFX Sim Bookkeeping")
struct SimUnitTests {
    @Test("identical_fires_get_their_own_grids_and_free_them")
    func identicalFiresGetTheirOwnGridsAndFreeThem() {
        let key = SimKey(1, 0, 40, 30)
        var grids: [Claim] = []
        let a = claim(&grids, key, [0.0, 0.0], 1)
        let b = claim(&grids, key, [300.0, 0.0], 1)
        #expect(a != b, "same seed and size, two grids")

        // Next frame, listed the other way round and moved a little: each keeps its grid.
        #expect(claim(&grids, key, [302.0, 1.0], 2) == b)
        #expect(claim(&grids, key, [1.0, 0.0], 2) == a)
        #expect(grids.count == 2)

        // The second fire goes away: its grid is dropped at the next frame, the first's stays.
        _ = claim(&grids, key, [1.0, 0.0], 3)
        grids.removeAll { !$0.alive(4) }
        #expect(grids.count == 1)
        #expect(grids[0].origin == [1.0, 0.0])
    }

    @Test("hitches_skip_time_and_only_new_or_rewound_grids_warm_up")
    func hitchesSkipTimeAndOnlyNewOrRewoundGridsWarmUp() {
        let warm = Int((simWarmup / simDt).rounded())
        let (n0, _, reset0) = schedule(nil, 3.0, false)
        #expect(reset0 && n0 == warm)

        let (n1, t01, reset1) = schedule(1.0, 1.0 + 2.5 * simDt, false)
        #expect(!reset1 && n1 == 2 && abs(t01 - (1.0 + 0.5 * simDt)) < 1e-5)

        let (n2, t02, reset2) = schedule(1.0, 3.0, false)
        #expect(!reset2 && n2 == simMaxSteps && abs(t02 + Float(simMaxSteps) * simDt - 3.0) < 1e-5, "a 2 s hitch: \(n2) steps")

        #expect(schedule(2.0, 1.0, false).2, "back in time starts over")
        #expect(schedule(1.0, 3.0, true).0 == 0, "frozen")
    }
}
