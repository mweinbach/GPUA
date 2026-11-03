// Ported from: crates/rune/src/runtime/motion/loop_clock.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Looping animations (`LoopSpec` — spin, pulse, shimmer, breathe), phase evaluation, and offscreen/zero-opacity sleep.

import RuneMotion

extension Runtime {
    func syncNodeLoop(nodeIdx: Int) {
        let node = nodes[nodeIdx]
        let id = node.nodeId
        guard let spec = node.loopingSpec else {
            loops.removeValue(forKey: id)
            return
        }
        if var existing = loops[id] {
            existing.spec = spec
            loops[id] = existing
        } else {
            loops[id] = LoopEntry(spec: spec, startTime: t, phase: 0.0, sleeping: false)
        }
    }

    /// Evaluate active loop entries at time `t`. Loops whose element is completely invisible/clipped or reducedMotion sleep!
    func stepLoops() -> Bool {
        guard !loops.isEmpty else { return false }
        if !windowVisible {
            for id in Array(loops.keys) {
                loops[id]?.sleeping = true
            }
            return false
        }
        if reducedMotion {
            for i in nodes.indices {
                let id = nodes[i].nodeId
                guard var entry = loops[id] else { continue }
                entry.sleeping = true
                loops[id] = entry
                applyLoopSample(nodeIdx: i, spec: entry.spec)
            }
            return false
        }

        var anyAwake = false
        for i in nodes.indices {
            let id = nodes[i].nodeId
            guard var entry = loops[id] else { continue }

            // Sleep loops that are frozen, sub-8-bit-step opacity, zero-sized, or outside their clip rect!
            let effectiveOpacity = nodes[i].vis.opacity * nodes[i].groupOpacityAccum
            let isFrozen = nodes[i].cumulativeTimeScale <= 0.0
            let isOutOfSight: Bool = {
                switch entry.spec.kind {
                case .slide(let from, let to), .slideEased(let from, let to, _):
                    let lr = nodes[i].presentedRect
                    let w = lr[2]
                    let h = lr[3]
                    guard w > 0.01 && h > 0.01 else { return true }
                    // Base rect without current loop offset
                    let curOff = scene.get(id, RuneMotion.prop.offset) ?? Vec2(0.0, 0.0)
                    let parentScale = nodes[i].parent.map { nodes[$0].cumulativeScale } ?? 1.0
                    let baseX = lr[0] - curOff.x * parentScale
                    let baseY = lr[1] - curOff.y * parentScale
                    let minFx = min(from[0], to[0])
                    let maxFx = max(from[0], to[0])
                    let minFy = min(from[1], to[1])
                    let maxFy = max(from[1], to[1])
                    let sweepX0 = baseX + minFx * w
                    let sweepX1 = baseX + (maxFx + 1.0) * w
                    let sweepY0 = baseY + minFy * h
                    let sweepY1 = baseY + (maxFy + 1.0) * h
                    let cb = nodes[i].clipBounds
                    return sweepX1 <= cb[0] + 0.01 || sweepX0 >= cb[2] - 0.01
                        || sweepY1 <= cb[1] + 0.01 || sweepY0 >= cb[3] - 0.01
                default:
                    let vis = nodes[i].visibleRect
                    return vis[2] <= 0.01 || vis[3] <= 0.01
                }
            }()
            let isCulled = isFrozen || effectiveOpacity < (1.0 / 255.0) || isOutOfSight
            if isCulled {
                entry.sleeping = true
                loops[id] = entry
                continue
            }

            let period = max(Double(entry.spec.period), 1e-3)
            let delay = max(0.0, entry.spec.delay)
            let rawElapsed = (t - entry.startTime - delay) * Double(nodes[i].cumulativeTimeScale)
            if rawElapsed < -1e-9 {
                entry.phase = 0.0
                entry.sleeping = true
                loops[id] = entry
                applyLoopSample(nodeIdx: i, spec: entry.spec)
                continue
            }
            let elapsed = max(0.0, rawElapsed)
            if case .sequence = entry.spec.kind {
                let seqPhase = min(max(elapsed / period, 0.0), 1.0)
                let finished = seqPhase >= 1.0 - 1e-9
                entry.phase = finished ? 1.0 : seqPhase
                entry.sleeping = finished
                loops[id] = entry
                if !finished {
                    anyAwake = true
                }
                applyLoopSample(nodeIdx: i, spec: entry.spec)
            } else {
                entry.sleeping = false
                let rawPhase = (elapsed / period).truncatingRemainder(dividingBy: 1.0)
                entry.phase = rawPhase < 0.0 ? rawPhase + 1.0 : rawPhase
                loops[id] = entry
                anyAwake = true
                applyLoopSample(nodeIdx: i, spec: entry.spec)
            }
        }
        return anyAwake
    }

    func nextLoopWakeDeadline() -> Double? {
        guard !loops.isEmpty, windowVisible, !reducedMotion, timeScale > 0.0 else { return nil }
        var earliest: Double? = nil
        for i in nodes.indices {
            let id = nodes[i].nodeId
            guard let entry = loops[id], nodes[i].cumulativeTimeScale > 0.0 else { continue }
            let delay = max(0.0, entry.spec.delay)
            let remainingAnim = (entry.startTime + delay) - t
            if remainingAnim > 1e-9 {
                let wallDelay = remainingAnim / Double(max(timeScale, 1e-6))
                let due = clock + wallDelay
                if let cur = earliest {
                    earliest = min(cur, due)
                } else {
                    earliest = due
                }
            }
        }
        return earliest
    }

    private func applyLoopSample(nodeIdx: Int, spec: LoopSpec) {
        let nodeId = nodes[nodeIdx].nodeId
        let track = LoopTrack(spec, loops[nodeIdxKey(nodeId)]?.startTime ?? 0.0)
        let sampled = track.sampleAt(t, clock, reducedMotion)
        switch spec.kind {
        case .rotation:
            scene.set(nodeId, RuneMotion.prop.rotation, sampled)
        case .opacity, .opacityCycle:
            scene.set(nodeId, RuneMotion.prop.opacity, sampled)
        case .sequence:
            if let beat = track.pose(t, reducedMotion) {
                scene.set(nodeId, RuneMotion.prop.opacity, beat.opacity)
                scene.set(nodeId, RuneMotion.prop.scale, beat.scale)
            }
        case .slide, .slideEased:
            if let frac = track.offset(t, reducedMotion) {
                let w = nodes[nodeIdx].layoutRect[2]
                let h = nodes[nodeIdx].layoutRect[3]
                scene.set(nodeId, RuneMotion.prop.offset, Vec2(frac[0] * w, frac[1] * h))
            }
        }
    }

    private func nodeIdxKey(_ id: RuneMotion.NodeId) -> RuneMotion.NodeId {
        id
    }
}
