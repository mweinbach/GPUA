// Ported from: crates/rune/src/runtime/motion/flights.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Cross-commit `Tx.flyText(source, target)` and `Tx.launch(source, destination)` flight capture and playback.

import RuneMotion

struct PendingTextFlightCapture {
    var sourceKey: String
    var targetKey: String
    var sourceRect: RuneMotion.Rect
    var sourceClip: [Float]
    var glyphs: [Instance]
    var scale: Float
}

extension Runtime {
    func capturePreCommitTextFlights(from previousNodes: [Node]) {
        pendingCapturedFlights.removeAll(keepingCapacity: true)
        guard !queuedTextFlights.isEmpty else { return }

        let s = max(env.scale, 0.001)
        for (srcKey, dstKey) in queuedTextFlights {
            guard let srcNode = previousNodes.first(where: { selectsKeyPath(srcKey, $0.path, $0.key) }),
                  let layout = srcNode.textLayout
            else { continue }

            let originX = srcNode.presentedRect[0]
            let originY = srcNode.presentedRect[1]
            var glyphInstances: [Instance] = []
            for line in layout.lines {
                for g in line.glyphs where g.advance > 0.0 {
                    let q = GlyphQuad(
                        rect: [(originX + g.x) * s, (originY + g.y) * s, g.advance * s, g.height * s],
                        uv: [0.0, 0.0],
                        ink: 0,
                        byte: UInt32(g.byteOffset),
                        color: 0
                    )
                    let fill = premul(g.color, g.alpha, srgbBlend)
                    glyphInstances.append(glyphInst(q, fill, NO_CLIP, [0.0, 0.0, 0.0, 0.0]))
                }
            }
            guard !glyphInstances.isEmpty else { continue }
            let srcRect = RuneMotion.Rect(
                srcNode.presentedRect[0],
                srcNode.presentedRect[1],
                max(srcNode.presentedRect[2], 1.0),
                max(srcNode.presentedRect[3], 1.0)
            )
            pendingCapturedFlights.append(
                PendingTextFlightCapture(
                    sourceKey: srcKey,
                    targetKey: dstKey,
                    sourceRect: srcRect,
                    sourceClip: srcNode.clipBounds,
                    glyphs: glyphInstances,
                    scale: s
                )
            )
        }
        queuedTextFlights.removeAll(keepingCapacity: true)
    }

    func resolvePostCommitTextFlights() {
        guard !pendingCapturedFlights.isEmpty else { return }
        for cap in pendingCapturedFlights {
            guard let dstIdx = keyIndex.findMatching(cap.targetKey, in: nodes) else { continue }
            let dstNode = nodes[dstIdx]
            let toRect = RuneMotion.Rect(
                dstNode.layoutRect[0],
                dstNode.layoutRect[1],
                max(dstNode.layoutRect[2], 1.0),
                max(dstNode.layoutRect[3], 1.0)
            )
            var flight = TextFlight(
                sourceKey: cap.sourceKey,
                targetKey: cap.targetKey,
                source: cap.sourceRect,
                sourceClip: cap.sourceClip,
                glyphs: cap.glyphs,
                scale: cap.scale,
                now: t
            )
            flight.destination = toRect
            activeTextFlights.append(flight)
        }
        pendingCapturedFlights.removeAll(keepingCapacity: true)
    }

    func pruneSettledTextFlights() {
        guard !activeTextFlights.isEmpty else { return }
        activeTextFlights.removeAll { flight in
            if reducedMotion {
                return flight.progressAt(t, true) >= 1.0
            }
            return flight.progress.isSettled(t)
        }
    }
}
