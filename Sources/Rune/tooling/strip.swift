// Ported from: crates/rune/src/tooling/strip.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `--strip`: frames, or their `--crop` rects, tiled into one image.

/// Tiles `--strip`'s frames, `cols` to a row, into one PNG.
func toolingWriteStrip(
    _ path: String,
    _ strip: [[UInt8]],
    _ frameSize: (UInt32, UInt32),
    _ cropsPx: [[UInt32]],
    _ gap: UInt32,
    _ cols: Int
) {
    guard !strip.isEmpty else { return }
    let (cw, ch) = toolingTileSize(frameSize.0, frameSize.1, cropsPx, gap)
    let gridCols = UInt32(max(1, min(strip.count, cols)))
    let countU32 = UInt32(strip.count)
    let rows = (countU32 + gridCols - 1) / gridCols
    let sw = gridCols * cw + (gridCols - 1) * gap
    let sh = rows * ch + (rows - 1) * gap

    let totalPixels = Int(sw) * Int(sh)
    var img = [UInt8](repeating: 128, count: totalPixels * 4)
    for p in 0..<totalPixels {
        img[p * 4 + 3] = 255
    }

    for (i, frame) in strip.enumerated() {
        let iU = UInt32(i)
        let cx = (iU % gridCols) * (cw + gap)
        let cy = (iU / gridCols) * (ch + gap)
        let rowBytes = Int(cw) * 4
        for y in 0..<ch {
            let dst = Int((cy + y) * sw + cx) * 4
            let src = Int(y * cw) * 4
            if src + rowBytes <= frame.count && dst + rowBytes <= img.count {
                img.replaceSubrange(dst..<(dst + rowBytes), with: frame[src..<(src + rowBytes)])
            }
        }
    }
    do {
        try toolingWritePng(path, sw, sh, img)
    } catch {
        toolingDie("\(path): \(error)")
    }
}

func toolingTileSize(_ w: UInt32, _ h: UInt32, _ crops: [[UInt32]], _ gap: UInt32) -> (UInt32, UInt32) {
    if crops.isEmpty {
        return (w, h)
    }
    let cw = crops.map { $0[2] }.max() ?? w
    let sumH = crops.reduce(UInt32(0)) { $0 + $1[3] }
    let ch = sumH + gap * UInt32(crops.count - 1)
    return (cw, ch)
}

/// The crops of one frame stacked vertically (the whole frame when there are none).
func toolingTile(_ px: [UInt8], _ w: UInt32, _ h: UInt32, _ crops: [[UInt32]], _ gap: UInt32) -> [UInt8] {
    if crops.isEmpty {
        return px
    }
    let (tw, th) = toolingTileSize(w, h, crops, gap)
    let totalPixels = Int(tw) * Int(th)
    var out = [UInt8](repeating: 128, count: totalPixels * 4)
    for p in 0..<totalPixels {
        out[p * 4 + 3] = 255
    }
    var oy: UInt32 = 0
    for c in crops {
        let x = c[0], y = c[1], cw = c[2], ch = c[3]
        precondition(x + cw <= w && y + ch <= h, "--crop outside the frame")
        let rowBytes = Int(cw) * 4
        for row in 0..<ch {
            let s = Int((y + row) * w + x) * 4
            let d = Int((oy + row) * tw) * 4
            out.replaceSubrange(d..<(d + rowBytes), with: px[s..<(s + rowBytes)])
        }
        oy += ch + gap
    }
    return out
}
