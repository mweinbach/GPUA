// Ported from: crates/rune/src/tooling/crop.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `--crop KEY` and `--playground`'s stage: a `--snap` cropped to one element's rect.

/// The pixel rect `[x, y, w, h]` `--snap` keeps, or `nil` for the whole frame: `--crop KEY`'s
/// element, else the playground's stage when `--playground` opened it without `--whole-window`.
func toolingTrySnapRect<S>(
    rt: Runtime<S>,
    args: Args,
    scale: Float,
    frameSize: (UInt32, UInt32)
) throws -> [UInt32]? {
    let (w, h) = frameSize
    let all = rt.hostElements()
    let stage: Int?
    if args.playground != nil && !args.wholeWindow {
        stage = all.firstIndex { !$0.exiting && ($0.key.map(playgroundIsStage) ?? false) }
    } else {
        stage = nil
    }

    func pixels(_ i: Int) -> [UInt32]? {
        let r = all[i].rect
        guard r.count >= 4 else { return nil }
        func pxFloor(_ v: Float, _ maxV: UInt32) -> UInt32 {
            min(UInt32(max((v * scale).rounded(.down), 0.0)), maxV)
        }
        func pxCeil(_ v: Float, _ maxV: UInt32) -> UInt32 {
            min(UInt32(max((v * scale).rounded(.up), 0.0)), maxV)
        }
        let x0 = pxFloor(r[0], w)
        let y0 = pxFloor(r[1], h)
        let x1 = pxCeil(r[0] + r[2], w)
        let y1 = pxCeil(r[1] + r[3], h)
        return (x1 > x0 && y1 > y0) ? [x0, y0, x1 - x0, y1 - y0] : nil
    }

    guard let key = args.cropKey else {
        return stage.flatMap(pixels)
    }

    let found: Int
    if stage != nil {
        guard let sIdx = playgroundStageElement(all, key) else {
            throw ToolingCliError("--crop \(key): no element on the playground's stage has that key or path; --whole-window searches the whole window")
        }
        found = sIdx
    } else {
        guard let idx = all.firstIndex(where: { !$0.exiting && ($0.key == key || $0.path == key) }) else {
            throw ToolingCliError("--crop \(key): no element has that key or path")
        }
        found = idx
    }

    guard let rect = pixels(found) else {
        throw ToolingCliError("--crop \(key): the element is empty or outside the frame")
    }
    return rect
}

func toolingSnapRect<S>(
    rt: Runtime<S>,
    args: Args,
    scale: Float,
    frameSize: (UInt32, UInt32)
) -> [UInt32]? {
    do {
        return try toolingTrySnapRect(rt: rt, args: args, scale: scale, frameSize: frameSize)
    } catch let err as ToolingCliError {
        toolingDie(err.message)
    } catch {
        toolingDie("\(error)")
    }
}

/// Extracts `rect = [x, y, cw, ch]` of an RGBA frame `w` pixels wide.
func toolingCropRgba(_ px: [UInt8], _ w: UInt32, _ rect: [UInt32]) -> [UInt8] {
    let x = Int(rect[0])
    let y = Int(rect[1])
    let cw = Int(rect[2])
    let ch = Int(rect[3])
    let width = Int(w)
    var out: [UInt8] = []
    out.reserveCapacity(cw * ch * 4)
    for r in 0..<ch {
        let start = ((y + r) * width + x) * 4
        let end = start + cw * 4
        if end <= px.count {
            out.append(contentsOf: px[start..<end])
        }
    }
    return out
}
