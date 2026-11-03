// Tests ported from: crates/rune/src/text/macos/smoothing_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if !os(WASI)
import Foundation
#endif
import Testing
@testable import Rune

@Suite("CoreGraphics macOS 15.3 smoothing pipeline parity")
struct MacosSmoothingTests {
    private static let tileSize = (96, 112)

    #if !os(WASI)
    private func smoothingDataDir() -> String? {
        guard let crateDir = upstreamRuneCrateDir() else { return nil }
        let dir = "\(crateDir)/src/text/macos/smoothing_data"
        return FileManager.default.fileExists(atPath: dir) ? dir : nil
    }

    private func interSfnt() -> SfntFont? {
        guard let crateDir = upstreamRuneCrateDir() else { return nil }
        let path = "\(crateDir)/assets/Inter-Regular.ttf"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return SfntFont(data: [UInt8](data), index: 0)
    }

    private func parsePath(_ raw: Any) -> MacosPath {
        guard let arr = raw as? [[Any]] else { return [] }
        return arr.map { r in
            func num(_ i: Int) -> Double {
                (r[i] as? NSNumber)?.doubleValue ?? 0.0
            }
            func pt(_ i: Int) -> MacosPoint {
                MacosPoint(num(i), num(i + 1))
            }
            let kind = (r[0] as? NSNumber)?.intValue ?? 4
            switch kind {
            case 0: return .move(pt(1))
            case 1: return .line(pt(1))
            case 2: return .quad(pt(1), pt(3))
            case 3: return .cubic(pt(1), pt(3), pt(5))
            default: return .close
            }
        }
    }

    private func points(_ cmd: MacosCmd) -> [MacosPoint] {
        switch cmd {
        case .move(let p), .line(let p): return [p]
        case .quad(let a, let b): return [a, b]
        case .cubic(let a, let b, let c): return [a, b, c]
        case .close: return []
        }
    }

    private func sameKind(_ a: MacosCmd, _ b: MacosCmd) -> Bool {
        switch (a, b) {
        case (.move, .move), (.line, .line), (.quad, .quad), (.cubic, .cubic), (.close, .close):
            return true
        default:
            return false
        }
    }

    private func pathError(_ model: MacosPath, _ oracle: MacosPath) -> Double? {
        guard model.count == oracle.count,
              zip(model, oracle).allSatisfy({ sameKind($0, $1) })
        else { return nil }
        var worst = 0.0
        for (a, b) in zip(model, oracle) {
            for (pa, pb) in zip(points(a), points(b)) {
                worst = max(worst, max(abs(pa.x - pb.x), abs(pa.y - pb.y)))
            }
        }
        return worst
    }

    private func rgbLinear(_ raw: Any) -> [Double] {
        let arr = (raw as? [NSNumber]) ?? []
        let r = arr.count > 0 ? srgbToLinear(arr[0].doubleValue) : 0.0
        let g = arr.count > 1 ? srgbToLinear(arr[1].doubleValue) : 0.0
        let b = arr.count > 2 ? srgbToLinear(arr[2].doubleValue) : 0.0
        return [r, g, b]
    }

    private func tile(_ path: MacosPath) -> [UInt8] {
        let (w, h) = Self.tileSize
        var out = [UInt8](repeating: 0, count: w * h)
        if path.isEmpty { return out }
        let (data, at) = macosMask(path)
        for row in 0..<Int(at.h) {
            for col in 0..<Int(at.w) {
                let x = 8 + Int(at.left) + col
                let y = h - 24 - Int(at.top) + row
                if x >= 0 && y >= 0 && x < w && y < h {
                    out[y * w + x] = data[row * Int(at.w) + col]
                }
            }
        }
        return out
    }

    private func referenceTile(_ blob: [UInt8], _ crop: [NSNumber]) -> [UInt8] {
        let x0 = crop[0].intValue
        let y0 = crop[1].intValue
        let cw = crop[2].intValue
        let ch = crop[3].intValue
        let at = crop[4].intValue
        let (w, h) = Self.tileSize
        var out = [UInt8](repeating: 0, count: w * h)
        for y in 0..<ch {
            let dst = (y0 + y) * w + x0
            let src = at + y * cw
            for x in 0..<cw {
                out[dst + x] = blob[src + x]
            }
        }
        return out
    }

    @Test("radius_matches_the_native_luminance_sweep")
    func radiusMatchesNativeLuminanceSweep() throws {
        guard let dir = smoothingDataDir() else { return }
        let data = try Data(contentsOf: URL(fileURLWithPath: "\(dir)/sweep.json"))
        let sweep = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let steps = (sweep["steps"] as! NSNumber).intValue
        let ppem = (sweep["ppem"] as! NSNumber).doubleValue
        let transitions = (sweep["transitions"] as! [[NSNumber]]).map { ($0[0].intValue, $0[1].doubleValue) }
        for i in 0...steps {
            let v = Double(i) / Double(steps)
            let want = transitions.reversed().first(where: { $0.0 <= i })!.1
            let lin = srgbToLinear(v)
            #expect(radiusForBucket(ppem, luminanceBucket([lin, lin, lin])) == want, "grey \(v)")
        }
        for c in (sweep["chromatic"] as! [[Any]]) {
            let want = (c[1] as! NSNumber).doubleValue
            #expect(radiusForBucket(ppem, luminanceBucket(rgbLinear(c[0]))) == want)
        }
    }

    @Test("dilation_matches_coregraphics_paths")
    func dilationMatchesCoreGraphicsPaths() throws {
        guard let dir = smoothingDataDir() else { return }
        let data = try Data(contentsOf: URL(fileURLWithPath: "\(dir)/dilation.json"))
        let cases = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        var worst = 0.0
        for c in cases {
            let ppem = (c["ppem"] as! NSNumber).doubleValue
            let d = radiusForBucket(ppem, luminanceBucket(rgbLinear(c["color"]!)))
            let model = macosDilate(parsePath(c["path"]!), dx: d, dy: d)
            guard let err = pathError(model, parsePath(c["oracle"]!)) else {
                Issue.record("Structure differs in path \(String(describing: c["id"]))")
                return
            }
            worst = max(worst, err)
        }
        #expect(worst < 1e-11, "max coordinate error \(worst)")
    }

    @Test("autohint_matches_native_transforms")
    func autohintMatchesNativeTransforms() throws {
        guard let dir = smoothingDataDir() else { return }
        let text = try String(contentsOfFile: "\(dir)/hints.jsonl", encoding: .utf8)
        let rows: [[String: Any]] = try text.split(whereSeparator: \.isNewline).map { line in
            try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
        }
        var metrics: [String: HintMetrics] = [:]
        for r in rows where (r["valid"] as? NSNumber)?.intValue == 1 {
            let name = r["font"] as! String
            metrics[name] = HintMetrics(
                upem: (r["upem"] as! NSNumber).doubleValue,
                xHeight: (r["otop"] as! NSNumber).doubleValue,
                capHeight: (r["Xtop"] as! NSNumber).doubleValue,
                maxY: (r["fonttop"] as! NSNumber).doubleValue,
                stemHeight: (r["stem"] as! NSNumber).doubleValue
            )
        }
        var count = 0
        var worst = 0.0
        var mismatches = 0
        for r in rows {
            let m = metrics[r["font"] as! String]!
            let ppem = (r["ppem"] as! NSNumber).doubleValue
            let d = (r["d"] as! NSNumber).doubleValue
            let valid = ((r["valid"] as! NSNumber).intValue == 1)
            let t = macosAutohint(m, ppem, d)
            if (t != nil) != valid {
                mismatches += 1
            }
            if let t, let expected = r["transform"] as? [NSNumber] {
                count += 1
                for (i, v) in t.values.enumerated() {
                    worst = max(worst, abs(v - expected[i].doubleValue))
                }
            }
        }
        #expect(count == 180 && mismatches == 0)
        #expect(worst < 1e-12, "max parameter error \(worst)")
    }

    @Test("swash_metrics_match_the_native_hint_inputs")
    func sfntMetricsMatchNativeHintInputs() {
        guard let font = interSfnt() else { return }
        let m = truetypeMetrics(font)
        #expect(m == HintMetrics(upem: 2048.0, xHeight: 1132.0, capHeight: 1490.0, maxY: 2269.0, stemHeight: 0.0))
    }

    @Test("masks_match_coregraphics_within_three_levels")
    func masksMatchCoreGraphicsWithinThreeLevels() throws {
        guard let dir = smoothingDataDir(), let font = interSfnt() else { return }
        let idxData = try Data(contentsOf: URL(fileURLWithPath: "\(dir)/masks.json"))
        let index = try JSONSerialization.jsonObject(with: idxData) as! [[String: Any]]
        let blob = [UInt8](try Data(contentsOf: URL(fileURLWithPath: "\(dir)/masks.bin")))
        let metrics = truetypeMetrics(font)
        let (w, h) = Self.tileSize

        for (pipeline, tag) in [(ApplePipeline.SMOOTHED, "on"), (ApplePipeline.UNSMOOTHED, "off")] {
            var pixels: UInt64 = 0
            var sum: UInt64 = 0
            var maxDiff: UInt8 = 0
            for c in index {
                let ppem = (c["ppem"] as! NSNumber).doubleValue
                let ph = c["phase"] as! [NSNumber]
                let phase = MacosPoint(ph[0].doubleValue, ph[1].doubleValue)
                let gid = UInt16((c["glyph"] as! NSNumber).intValue)
                let outline = designOutline(font, glyph: gid, ppem: ppem)!
                let d = radiusForBucket(ppem, luminanceBucket(rgbLinear(c["color"]!)))
                let ours = tile(prepareOutline(outline, pipeline: pipeline, ppem: ppem, radius: d, phase: phase, metrics: metrics))
                let ref = referenceTile(blob, c[tag] as! [NSNumber])

                var x0 = w, y0 = h, x1 = 0, y1 = 0
                for y in 0..<h {
                    for x in 0..<w {
                        if ours[y * w + x] != 0 || ref[y * w + x] != 0 {
                            x0 = min(x0, x); y0 = min(y0, y)
                            x1 = max(x1, x + 1); y1 = max(y1, y + 1)
                        }
                    }
                }
                for y in max(0, y0 - 1)..<min(h, y1 + 1) {
                    for x in max(0, x0 - 1)..<min(w, x1 + 1) {
                        let a = Int(ours[y * w + x])
                        let b = Int(ref[y * w + x])
                        let diff = UInt8(abs(a - b))
                        pixels += 1
                        sum += UInt64(diff)
                        maxDiff = max(maxDiff, diff)
                    }
                }
            }
            let mae = Double(sum) / Double(max(pixels, 1))
            #expect(maxDiff <= 3 && mae < 0.2, "smoothing \(tag): maxDiff=\(maxDiff) mae=\(mae)")
        }
    }
    #endif

    @Test("radius_grows_with_ppem_to_the_f32_cap")
    func radiusGrowsWithPpemToF32Cap() {
        let dark = hex("#1d1e22")!
        let cases: [(Double, Double)] = [
            (8.0, 0.0464),
            (32.0, 0.1856),
            (51.0, 0.29579999999999995),
            (52.0, 0.30000001192092896),
            (200.0, 0.30000001192092896)
        ]
        for (ppem, want) in cases {
            #expect(radiusForBucket(ppem, colorBucket(dark)) == want)
        }
        #expect(colorBucket(hex("#e6e6e6")!) == 3)
        #expect(colorBucket(hex("#f1f1f1")!) == 4)
        #expect(colorBucket(hex("#ff0000")!) == 1)
    }

    @Test("flattening_emits_lines_within_coregraphics_tolerance")
    func flatteningEmitsLinesWithinCoreGraphicsTolerance() {
        let path: MacosPath = [
            .move(MacosPoint(0.0, 0.0)),
            .cubic(MacosPoint(0.0, 10.0), MacosPoint(10.0, 10.0), MacosPoint(10.0, 0.0)),
            .quad(MacosPoint(5.0, -6.0), MacosPoint(0.0, 0.0)),
            .close
        ]
        let flat = macosFlatten(path)
        let onlyLinear = flat.allSatisfy { cmd in
            switch cmd {
            case .move, .line, .close: return true
            default: return false
            }
        }
        #expect(onlyLinear)
        #expect(flat.contains(.line(MacosPoint(10.0, 0.0))))
        #expect(flat[flat.count - 2] == .line(MacosPoint(0.0, 0.0)))
        let lineCount = flat.filter { if case .line = $0 { return true }; return false }.count
        #expect(lineCount > 8 && lineCount < 64)
    }

    @Test("text_system_keys_glyphs_by_ink")
    func textSystemKeysGlyphsByInk() {
        let ts = TextSystem()
        ts.setApplePipeline(ApplePipeline.SMOOTHED)
        let style = TextStyle.new(16.0, 400.0)
        var dark: [GlyphQuad] = []
        var light: [GlyphQuad] = []
        ts.setGlyphInks(hex("#1d1e22")!, [])
        ts.glyphs("Hamburg", style, 1.0, [0.0, 0.0], &dark)
        let before = ts.atlas.rasterized()
        ts.setGlyphInks(Color.WHITE, [])
        ts.glyphs("Hamburg", style, 1.0, [0.0, 0.0], &light)
        #expect(dark.count == light.count)
        #expect(ts.atlas.rasterized() > before)
        let area = { (q: [GlyphQuad]) in q.reduce(Float(0)) { $0 + $1.rect[2] * $1.rect[3] } }
        #expect(area(light) >= area(dark))
        #expect(zip(dark, light).contains { $0.uv != $1.uv })
    }

    @Test("pipelines_never_share_masks")
    func pipelinesNeverShareMasks() {
        let ts = TextSystem()
        let style = TextStyle.new(16.0, 400.0)
        var noFlatten = ApplePipeline.UNSMOOTHED
        noFlatten.flatten = false
        for pipeline in [ApplePipeline.SMOOTHED, ApplePipeline.UNSMOOTHED, noFlatten] {
            ts.setApplePipeline(pipeline)
            let before = ts.atlas.rasterized()
            var q: [GlyphQuad] = []
            ts.glyphs("Hamburg", style, 1.0, [0.0, 0.0], &q)
            #expect(ts.atlas.rasterized() > before, "\(pipeline) reused another pipeline's masks")
        }
        ts.setApplePipeline(ApplePipeline.UNSMOOTHED)
        ts.setGlyphInks(Color.WHITE, [])
        let before = ts.atlas.rasterized()
        var scratch: [GlyphQuad] = []
        ts.glyphs("Hamburg", style, 1.0, [0.0, 0.0], &scratch)
        #expect(ts.atlas.rasterized() == before)
    }
}
