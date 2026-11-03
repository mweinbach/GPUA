// Tests ported from: crates/rune-fx/src/catalog.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneFX

/// Parse and evaluate the Rust subset emitted by `FillParams.toRust()`.
private func evalEmittedRust(_ code: String) -> FillParams {
    precondition(code.hasPrefix("Fx::fill(") && code.hasSuffix(")"), "Unexpected code: \(code)")
    var s = String(code.dropFirst("Fx::fill(".count).dropLast())
    var intensity: Float = 1.0
    if let range = s.range(of: ".intensity(", options: .backwards) {
        let arg = String(s[range.upperBound...])
        precondition(arg.hasSuffix(")"), "Missing ) in \(code)")
        intensity = Float(arg.dropLast())!
        s = String(s[..<range.lowerBound])
    }
    var border: Float = 0.0
    if let range = s.range(of: ".border(", options: .backwards) {
        let arg = String(s[range.upperBound...])
        precondition(arg.hasSuffix(")"), "Missing ) in \(code)")
        border = Float(arg.dropLast())!
        s = String(s[..<range.lowerBound])
    }

    var fill: FillParams
    if let braceRange = s.range(of: " { ") {
        let ty = String(s[..<braceRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        var body = String(s[braceRange.upperBound...])
        precondition(body.hasSuffix(" }"), "Missing closing brace in \(code)")
        body = String(body.dropLast(2))
        let spreadRange = body.range(of: ", ..", options: .backwards)!
        let fieldsStr = String(body[..<spreadRange.lowerBound])
        let presetRust = String(body[spreadRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        let info = fillStyles().first { $0.rust == ty }!
        let preset = info.presets.first { $0.rust == presetRust }!
        var f = preset.fill()

        var depth = 0
        var current = ""
        for ch in fieldsStr {
            switch ch {
            case "[", "(":
                depth += 1
                current.append(ch)
            case "]", ")":
                depth -= 1
                current.append(ch)
            case "," where depth == 0:
                applyField(&f, info: info, entry: current)
                current = ""
            default:
                current.append(ch)
            }
        }
        applyField(&f, info: info, entry: current)
        fill = f
    } else {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        let preset = fillStyles().flatMap(\.presets).first { $0.rust == trimmed }!
        fill = preset.fill()
    }
    fill.border = border
    fill.intensity = intensity
    return fill
}

private func parseHex(_ s: String) -> UInt32 {
    let trimmed = s.trimmingCharacters(in: .whitespaces)
    precondition(trimmed.hasPrefix("0x"), "Expected 0x prefix: \(s)")
    let hex = String(trimmed.dropFirst(2))
    #expect(hex.count == 6, "6-digit hex literal: \(s)")
    return UInt32(hex, radix: 16)!
}

private func parsePt(_ s: String) -> [Float] {
    let trimmed = s.trimmingCharacters(in: .whitespaces)
    precondition(trimmed.hasPrefix("[") && trimmed.hasSuffix("]"), "Expected [x, y]: \(s)")
    let inner = String(trimmed.dropFirst().dropLast())
    let parts = inner.split(separator: ",", maxSplits: 1)
    return [
        Float(parts[0].trimmingCharacters(in: .whitespaces))!,
        Float(parts[1].trimmingCharacters(in: .whitespaces))!,
    ]
}

private func applyField(_ f: inout FillParams, info: StyleInfo, entry: String) {
    let trimmed = entry.trimmingCharacters(in: .whitespaces)
    let sep = trimmed.range(of: ": ")!
    let id = String(trimmed[..<sep.lowerBound])
    let val = String(trimmed[sep.upperBound...])
    let param = info.params.first { $0.id == id }!
    let v: Value
    switch param.kind {
    case .number:
        #expect(val.contains(".") || val.contains("e") || val.contains("E"), "float literal has decimal or exp: \(val)")
        v = .number(Float(val)!)
    case .count:
        v = .count(UInt32(val)!)
    case .toggle:
        v = .toggle(val == "true")
    case .choice(let choices):
        let idx = choices.firstIndex { $0.rust == val }!
        v = .choice(idx)
    case .color:
        precondition(val.hasPrefix("rgb(") && val.hasSuffix(")"), "Expected rgb(...): \(val)")
        let hex = String(val.dropFirst(4).dropLast())
        v = .color(rgb(parseHex(hex)))
    case .colors:
        precondition(val.hasPrefix("Stops::hex(&[") && val.hasSuffix("])"), "Expected Stops::hex: \(val)")
        let list = String(val.dropFirst("Stops::hex(&[".count).dropLast(2))
        let hexes = list.split(separator: ",").map { parseHex(String($0)) }
        v = .colors(Stops.hex(hexes))
    case .point:
        v = .point(parsePt(val))
    case .points:
        precondition(val.hasPrefix("[") && val.hasSuffix("]"), "Expected points array: \(val)")
        let inner = String(val.dropFirst().dropLast())
        var pts: [[Float]] = []
        var depth = 0
        var cur = ""
        for ch in inner {
            switch ch {
            case "[":
                depth += 1
                cur.append(ch)
            case "]":
                depth -= 1
                cur.append(ch)
            case "," where depth == 0:
                pts.append(parsePt(cur))
                cur = ""
            default:
                cur.append(ch)
            }
        }
        pts.append(parsePt(cur))
        #expect(pts.count == maxStops)
        v = .points(pts)
    }
    let setOk = f.set(id, v)
    #expect(setOk, "\(info.id).\(id)")
}

@Suite("RuneFX Catalog")
struct CatalogTests {
    @Test("styles_are_in_variant_order_with_unique_ids")
    func stylesAreInVariantOrderWithUniqueIds() {
        for (k, s) in fillStyles().enumerated() {
            #expect(s.defaultFill().style.index() == k, "\(s.id)")
            #expect(s.defaultFill().info().id == s.id)
            #expect(fillStyle(s.id)?.id == s.id)
            #expect(!s.presets.isEmpty && !s.params.isEmpty)
            let paramIds = Set(s.params.map(\.id) + FillParams.common.map(\.id))
            #expect(paramIds.count == s.params.count + FillParams.common.count, "\(s.id): unique param ids")
            let presetIds = Set(s.presets.map(\.id))
            #expect(presetIds.count == s.presets.count)
        }
        let styleIds = Set(fillStyles().map(\.id))
        #expect(styleIds.count == fillStyles().count)
        #expect(fillStyle("nope") == nil)
    }

    @Test("first_preset_is_the_default")
    func firstPresetIsTheDefault() {
        let defaults: [FillStyle] = [
            LiquidMetalParams.default().intoFillStyle(),
            MeshGradientParams.default().intoFillStyle(),
            DitherParams.default().intoFillStyle(),
            GrainGradientParams.default().intoFillStyle(),
            FlutedGlassParams.default().intoFillStyle(),
            MetaballParams.default().intoFillStyle(),
            SwirlParams.default().intoFillStyle(),
            VoronoiParams.default().intoFillStyle(),
            WaveParams.default().intoFillStyle(),
            HalftoneParams.default().intoFillStyle(),
            PlasticParams.default().intoFillStyle(),
        ]
        #expect(defaults.count == fillStyles().count)
        for (s, d) in zip(fillStyles(), defaults) {
            #expect(s.presets[0].style() == d, "\(s.id)")
        }
    }

    @Test("every_param_gets_sets_and_sits_in_range")
    func everyParamGetsSetsAndSitsInRange() {
        let palette: [UInt32] = [0x112233, 0x445566, 0x778899, 0xaabbcc, 0xddeeff, 0x102030]
        for s in fillStyles() {
            for pr in s.presets {
                let f = pr.fill()
                for p in s.params + FillParams.common {
                    let v = try! #require(f.get(p.id), "\(s.id).\(p.id) reads")
                    switch (p.kind, v) {
                    case (.number(let minV, let maxV, _, _), .number(let x)):
                        #expect((minV...maxV).contains(x), "\(s.id)/\(pr.id).\(p.id) = \(x) outside \(minV)..\(maxV)")
                    case (.count(let minC, let maxC), .count(let n)):
                        #expect((minC...maxC).contains(n), "\(s.id).\(p.id)")
                    case (.choice(let c), .choice(let k)):
                        #expect(k >= 0 && k < c.count)
                    case (.colors(let minC, let maxC), .colors(let c)):
                        #expect((minC...maxC).contains(c.len()), "\(s.id)/\(pr.id).\(p.id)")
                    case (.toggle, .toggle), (.color, .color), (.point, .point), (.points, .points):
                        break
                    default:
                        Issue.record("\(s.id).\(p.id): unexpected kind/value mismatch")
                    }

                    var g = f
                    let wroteSame = g.set(p.id, v)
                    #expect(wroteSame, "\(s.id).\(p.id) writes")
                    #expect(g == f)
                    let isPoint: Bool
                    if case .point = p.kind { isPoint = true } else { isPoint = false }
                    let wroteWrongKind = g.set(p.id, .point([9.0, 9.0]))
                    #expect(!wroteWrongKind || isPoint, "\(s.id).\(p.id) rejects wrong kind")
                    let wroteNaN = g.set(p.id, .number(.nan))
                    #expect(!wroteNaN, "\(s.id).\(p.id) rejects NaN")
                    let wroteInf = g.set(p.id, .number(.infinity))
                    #expect(!wroteInf, "\(s.id).\(p.id) rejects inf")

                    let alt: Value
                    switch (p.kind, v) {
                    case (.number(let minV, let maxV, _, _), .number(let x)):
                        alt = .number(abs(x - maxV) > 1e-4 ? maxV : minV)
                    case (.count(let minC, let maxC), .count(let n)):
                        alt = .count(n != maxC ? maxC : minC)
                    case (.choice(let c), .choice(let k)):
                        alt = .choice((k + 1) % c.count)
                    case (.toggle, .toggle(let b)):
                        alt = .toggle(!b)
                    case (.color, _):
                        alt = .color(rgb(0x123456))
                    case (.colors(_, let maxC), _):
                        alt = .colors(Stops.hex(Array(palette.prefix(maxC))))
                    case (.point, _):
                        alt = .point([0.25, 0.75])
                    case (.points, _):
                        alt = .points(Array(repeating: [Float(0.1), Float(0.2)], count: maxStops))
                    default:
                        fatalError("Unreachable param kind/value")
                    }
                    #expect(alt != v, "\(s.id).\(p.id) has a distinct test value")
                    let wroteAlt = g.set(p.id, alt)
                    #expect(wroteAlt, "\(s.id).\(p.id) writes distinct value")
                    #expect(g.get(p.id) == alt, "\(s.id).\(p.id) round-trips distinct value")
                    #expect(g != f, "\(s.id).\(p.id) mutates FillParams")
                }
                #expect(f.get("nope") == nil)
            }
        }
    }

    @Test("changing_a_param_changes_the_fill")
    func changingAParamChangesTheFill() {
        let fx = Fx.fill(LiquidMetalParams.gold())
        guard case .fill(var p) = fx else {
            Issue.record("Expected Fx.fill")
            return
        }
        let setFlow = p.set("flow", .number(0.9))
        let setTint = p.set("tint", .color(rgb(0x808080)))
        let setBorder = p.set("border", .number(3.0))
        #expect(setFlow)
        #expect(setTint)
        #expect(setBorder)
        guard case .liquidMetal(let m) = p.style else {
            Issue.record("Expected LiquidMetal")
            return
        }
        #expect(m.flow == 0.9)
        #expect(p.border == 3.0)
        let setPatternInvalid = p.set("pattern", .choice(0))
        #expect(!setPatternInvalid, "not a liquid metal param")

        var d = FillParams.from(DitherParams.bayer())
        let setPatternValid = d.set("pattern", .choice(3))
        #expect(setPatternValid)
        guard case .dither(let dp) = d.style else {
            Issue.record("Expected Dither")
            return
        }
        #expect(dp.pattern == .blueNoise)
    }

    @Test("rust_is_written_against_the_closest_preset_and_parses_back")
    func rustIsWrittenAgainstTheClosestPresetAndParsesBack() {
        #expect(FillParams.from(LiquidMetalParams.gold()).toRust() == "Fx::fill(LiquidMetalParams::gold())")

        var rose = LiquidMetalParams.rose()
        rose.flow = 0.8
        let f = FillParams.from(rose).border(4.0)
        #expect(f.toRust() == "Fx::fill(LiquidMetalParams { flow: 0.8, ..LiquidMetalParams::rose() }.border(4.0))")

        var bayer = DitherParams.bayer()
        bayer.pattern = .bayer8
        bayer.colors = Stops.hex([0x000000, 0xffffff])
        let d = FillParams.from(bayer)
        #expect(d.toRust() == "Fx::fill(DitherParams { pattern: DitherPattern::Bayer8, colors: Stops::hex(&[0x000000, 0xffffff]), ..DitherParams::bayer() })")

        let palette: [UInt32] = [0x102030, 0x405060, 0x708090, 0xa0b0c0, 0xd0e0f0, 0x112233]
        for s in fillStyles() {
            for p in s.presets {
                let base = p.fill()
                #expect(base.toRust() == "Fx::fill(\(p.rust))")
                #expect(evalEmittedRust(base.toRust()) == base)

                var allChanged = base.border(3.5).intensity(0.75)
                for param in s.params {
                    let alt: Value
                    switch param.kind {
                    case .number(let minV, let maxV, _, _):
                        alt = .number((minV + maxV) * 0.5 + 0.125)
                    case .count(_, let maxC):
                        alt = .count(maxC)
                    case .toggle:
                        let curTrue = (base.get(param.id) == .toggle(true))
                        alt = .toggle(!curTrue)
                    case .choice(let c):
                        alt = .choice(c.count - 1)
                    case .color:
                        alt = .color(rgb(0xabcdef))
                    case .colors(let minC, _):
                        alt = .colors(Stops.hex(Array(palette.prefix(minC))))
                    case .point:
                        alt = .point([0.3, 0.7])
                    case .points:
                        alt = .points(Array(repeating: [Float(0.25), Float(0.75)], count: maxStops))
                    }
                    var one = base
                    let setOne = one.set(param.id, alt)
                    #expect(setOne)
                    #expect(evalEmittedRust(one.toRust()) == one, "\(s.id)/\(p.id).\(param.id)")
                    let setAll = allChanged.set(param.id, alt)
                    #expect(setAll)
                }
                #expect(evalEmittedRust(allChanged.toRust()) == allChanged, "\(s.id)/\(p.id) all fields")
            }
        }
    }

    @Test("colours_round_trip_through_hex")
    func coloursRoundTripThroughHex() {
        for h: UInt32 in [0x000000, 0xffffff, 0xf3c56b, 0x0b3d5c, 0x808080] {
            #expect(rgb(h).hex() == h)
        }
    }
}
