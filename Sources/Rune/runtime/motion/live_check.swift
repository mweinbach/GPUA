// Ported from: crates/rune/src/runtime/motion/live_check.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Poll `Live<T>` and `LiveText` bindings without triggering a full view commit (`liveOnly`).

import RuneMotion

extension Runtime {
    func attachNodeLiveBindings(nodeIdx: Int) {
        let node = nodes[nodeIdx]
        let id = node.nodeId
        let pixels = node.vis.cold.getIfSome?.pixels

        if let prev = liveNodeBindings.removeValue(forKey: id) {
            for sub in prev.subscriptions {
                sub.active = false
            }
        }

        if node.liveBindings.isEmpty && node.textSpec?.live == nil && pixels == nil {
            return
        }

        var subs: [LiveSubscription] = []
        var bounds = node.liveBindings
        for idx in bounds.indices {
            bounds[idx].attach(liveClockToken, t)
            let bits = bounds[idx].source.load()
            bounds[idx].seen = bits
            subs.append(bounds[idx].source.subscribe(liveWake))
            applyLiveValueToScene(nodeId: id, bound: bounds[idx], bits: bits, initial: true)
        }
        if let liveText = node.textSpec?.live {
            subs.append(liveText.source.subscribe(liveWake))
        }
        let pxSeenSize: (UInt32, UInt32)?
        if let px = pixels {
            subs.append(px.source.subscribe(liveWake))
            pxSeenSize = px.size()
        } else {
            pxSeenSize = nil
        }
        nodes[nodeIdx].liveBindings = bounds
        liveNodeBindings[id] = LiveNodeEntry(
            nodeIdx: nodeIdx,
            path: node.path,
            subscriptions: subs,
            liveTextSeenGen: node.textSpec?.live?.source.currentGeneration(),
            pixelsSeenSize: pxSeenSize
        )
    }

    /// Events whose handler called `Tx.liveOnly()` and so did not re-run the view.
    public func liveOnlyEvents() -> UInt64 {
        liveOnlySkips
    }

    /// Enable or disable debug stale-view checking for `Tx.liveOnly()` handlers.
    public func checkLiveOnly(_ on: Bool) {
        liveOnlyCheck = on
    }

    /// Stale-view warnings emitted by debug `Tx.liveOnly()` checks.
    public func liveOnlyWarnings() -> [String] {
        liveOnlyWarningsList
    }

    /// Sample all attached `Live` and `LiveText` sources; returns `true` if any linear tween is still running.
    func pollLiveBindings() -> Bool {
        guard windowVisible else { return false }
        _ = liveWake.takePending()
        var anyTweenRunning = false

        var pixelsSizeChanged = false

        for i in nodes.indices {
            let id = nodes[i].nodeId
            if let px = nodes[i].vis.cold.getIfSome?.pixels {
                let curSize = px.size()
                if let prevSize = liveNodeBindings[id]?.pixelsSeenSize,
                   prevSize.0 != curSize.0 || prevSize.1 != curSize.1
                {
                    liveNodeBindings[id]?.pixelsSeenSize = curSize
                    pixelsSizeChanged = true
                }
            }
            // Latch `LiveText` changes directly into the node's text layout without re-running the view.
            if let liveText = nodes[i].textSpec?.live {
                var seenGen = liveNodeBindings[id]?.liveTextSeenGen
                if let nextStr = liveText.read(&seenGen) {
                    liveNodeBindings[id]?.liveTextSeenGen = seenGen
                    if var spec = nodes[i].textSpec, spec.content != nextStr {
                        let prevContent = spec.content
                        spec.content = nextStr
                        nodes[i].textSpec = spec
                        let innerW = max(0.0, nodes[i].layoutRect[2])
                        var tl = layoutTextSpec(
                            spec,
                            maxWidth: innerW > 0.0 ? innerW : nil,
                            textSys: text,
                            previouslyShapedText: prevContent
                        )
                        alignTextLayout(&tl, containerWidth: innerW, align: spec.align)
                        nodes[i].textLayout = tl
                    }
                }
            }

            guard !nodes[i].liveBindings.isEmpty else { continue }
            for bIdx in nodes[i].liveBindings.indices {
                var bound = nodes[i].liveBindings[bIdx]
                let rawBits = bound.source.load()
                let effectiveBits: PackedLiveBits
                if let lin = bound.source.linear {
                    let startT = lin.start(liveClockToken, t)
                    let (sampled, running) = lin.sample(rawBits, max(0.0, t - startT))
                    effectiveBits = sampled
                    if running {
                        anyTweenRunning = true
                    }
                } else {
                    effectiveBits = rawBits
                }

                if bound.seen != effectiveBits {
                    bound.seen = effectiveBits
                    nodes[i].liveBindings[bIdx] = bound
                    applyLiveValueToScene(nodeId: id, bound: bound, bits: effectiveBits, initial: false)
                }
            }
        }
        if pixelsSizeChanged {
            let prevInstant = pendingInstantCommit
            pendingInstantCommit = true
            pendingCommitWhy |= CommitWhy.RELAYOUT
            performCommit()
            pendingInstantCommit = prevInstant
        }
        return anyTweenRunning
    }

    private func applyLiveValueToScene(
        nodeId: RuneMotion.NodeId,
        bound: LiveBound,
        bits: PackedLiveBits,
        initial: Bool
    ) {
        let useSpring = !initial && !reducedMotion && bound.spring != nil
        switch bound.property {
        case .opacity:
            let val = min(max(Float.decodeLive(bits), 0.0), 1.0)
            if useSpring, let sp = bound.spring {
                scene.animate(nodeId, RuneMotion.prop.opacity, val, sp)
            } else {
                scene.set(nodeId, RuneMotion.prop.opacity, val)
            }
        case .blur:
            let val = max(Float.decodeLive(bits), 0.0)
            if useSpring, let sp = bound.spring {
                scene.animate(nodeId, RuneMotion.prop.blur, val, sp)
            } else {
                scene.set(nodeId, RuneMotion.prop.blur, val)
            }
        case .scale:
            let val = max(Float.decodeLive(bits), 0.0)
            if useSpring, let sp = bound.spring {
                scene.animate(nodeId, P_SCALE, val, sp)
            } else {
                scene.set(nodeId, P_SCALE, val)
            }
        case .offset:
            let arr = [Float].decodeLive(bits)
            let v = Vec2(arr.count > 0 ? arr[0] : 0.0, arr.count > 1 ? arr[1] : 0.0)
            if useSpring, let sp = bound.spring {
                scene.animate(nodeId, RuneMotion.prop.offset, v, sp)
            } else {
                scene.set(nodeId, RuneMotion.prop.offset, v)
            }
        case .fill:
            let col = Color.decodeLive(bits)
            let rmc = RuneMotion.Color(r: col.r, g: col.g, b: col.b, a: col.a)
            if useSpring, let sp = bound.spring {
                scene.animate(nodeId, RuneMotion.prop.fill, rmc, sp)
                scene.animate(nodeId, P_FILL, col, sp)
            } else {
                scene.set(nodeId, RuneMotion.prop.fill, rmc)
                scene.set(nodeId, P_FILL, col)
            }
        case .rect:
            let arr = [Float].decodeLive(bits)
            if arr.count >= 4 {
                let r = RuneMotion.Rect(arr[0], arr[1], arr[2], arr[3])
                if useSpring, let sp = bound.spring {
                    scene.setFrame(nodeId, r, sp)
                } else {
                    scene.setFrame(nodeId, r, LayoutAnim.instant)
                }
            }
        }
    }
}
