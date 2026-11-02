// Ported from: crates/rune-motion/src/store/tracks.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

extension AnimationStore {
    /// Tracks sampled (or `set`) in the last tick: what changed on screen.
    public func touched() -> [(NodeId, PropId)] {
        var out: [(NodeId, PropId)] = []
        out.reserveCapacity(touchedList.count)
        for id in touchedList where contains(id) {
            let m = tMeta[Int(id.index)]
            out.append((m.node, m.prop))
        }
        return out
    }

    /// Tracks animating now, ticked yet or not: what's set to move.
    public func active() -> [(NodeId, PropId)] {
        var out: [(NodeId, PropId)] = []
        out.reserveCapacity(activeIndices.count)
        for t in activeIndices {
            let m = tMeta[Int(t)]
            out.append((m.node, m.prop))
        }
        return out
    }

    /// When everything running only waits for a delayed start, holding still until then: the
    /// store time the first of them starts. `nil` while anything moves, or nothing waits. A
    /// host can sleep until then rather than draw frames that show nothing new. Tracks on a
    /// stopped clock don't count, as in ``running()``.
    public func waitingUntil() -> Double? {
        var first = Double.infinity
        for tRaw in activeIndices {
            let t = Int(tRaw)
            if frozen(t) {
                continue
            }
            let now = timeOf(t)
            let due = tNextDue[t]
            if tSettleAt[t] > now || !due.isFinite {
                return nil
            }
            let k = Double(clockScale(tClock[t]))
            first = min(first, _now + max(due - now, 0.0) / k)
        }
        return first.isFinite ? first : nil
    }

    /// Like ``touched()``, with track ids.
    public func touchedTracks() -> [(TrackId, NodeId, PropId)] {
        var out: [(TrackId, NodeId, PropId)] = []
        out.reserveCapacity(touchedList.count)
        for id in touchedList where contains(id) {
            let m = tMeta[Int(id.index)]
            out.append((id, m.node, m.prop))
        }
        return out
    }

    /// Zero-allocation iteration over touched tracks for `Scene.tick()`.
    @inline(__always)
    func forEachTouchedTrack(_ body: (TrackId, NodeId, PropId) -> Void) {
        for id in touchedList where contains(id) {
            let m = tMeta[Int(id.index)]
            body(id, m.node, m.prop)
        }
    }

    /// Moves track `t`'s lanes by `d` (value, target and anything scheduled) and leaves the motion
    /// on them as it is: the same motion in coordinates shifted under it.
    func translate(_ t: Int, _ d: UnsafeBufferPointer<Float>) {
        let l0 = Int(tLane0[t])
        let n = min(Int(tN[t]), d.count)
        for i in 0..<n {
            let delta = d[i]
            if delta == 0.0 {
                continue
            }
            let l = l0 + i
            lTarget[l] += delta
            lValue[l] += delta
            var p = lPending[l]
            while p != noneIndex {
                let pi = Int(p)
                pending[pi].target += delta
                p = pending[pi].next
            }
        }
        setTouchedList.append(TrackId(index: UInt32(t), generation: tMeta[t].generation))
    }
}
