// Tests ported from: crates/rune/src/text/core_text_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import Foundation
import CoreText
import AppKit
#endif
import Testing
@testable import Rune

#if os(macOS)
@Suite("macOS CoreText advances, SystemMono, OpticalSize, and trak parity")
struct CoreTextAdvancesTests {
    private static let strings: [String] = [
        "Send dev-site captures to OpenCode",
        "Copy \u{2318}K",
        "General",
        "Appearance",
        "Hello, World",
        "The quick brown fox jumps over the lazy dog",
        "Launch at login 0123456789"
    ]

    private static let sizes: [Float] = [
        8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0, 16.3, 17.0, 20.0, 22.0, 24.0, 28.0, 33.0, 34.0
    ]

    private func fourCC(_ tag: String) -> Int32 {
        var v: UInt32 = 0
        for b in tag.utf8.prefix(4) {
            v = (v << 8) | UInt32(b)
        }
        return Int32(bitPattern: v)
    }

    private func systemFontOpsz(_ size: Float, _ weight: Float, _ opsz: Float) -> CTFont {
        let base = CTFontCreateUIFontForLanguage(.system, CGFloat(size), nil)!
        let axes: [NSNumber: NSNumber] = [
            NSNumber(value: fourCC("wght")): NSNumber(value: Double(weight)),
            NSNumber(value: fourCC("opsz")): NSNumber(value: Double(opsz))
        ]
        let desc = CTFontDescriptorCreateWithAttributes([kCTFontVariationAttribute: axes] as CFDictionary)
        return CTFontCreateCopyWithAttributes(base, CGFloat(size), nil, desc)
    }

    private func systemFont(_ size: Float, _ weight: Float) -> CTFont {
        systemFontOpsz(size, weight, min(max(size, 17.0), 96.0))
    }

    private func systemFontOptical(_ size: Float, _ optical: Float) -> CTFont {
        let base = CTFontCreateUIFontForLanguage(.system, CGFloat(size), nil)!
        let attrs = ["NSCTFontOpticalSizeAttribute" as CFString: NSNumber(value: Double(optical))] as CFDictionary
        let desc = CTFontDescriptorCreateWithAttributes(attrs)
        return CTFontCreateCopyWithAttributes(base, CGFloat(size), nil, desc)
    }

    private func coreTextWidth(_ text: String, _ font: CTFont) -> Double {
        let attr = CFAttributedStringCreate(
            nil,
            text as CFString,
            [kCTFontAttributeName: font] as CFDictionary
        )!
        let line = CTLineCreateWithAttributedString(attr)
        return CTLineGetTypographicBounds(line, nil, nil, nil)
    }

    private func runeWidth(_ ts: TextSystem, _ text: String, _ style: TextStyle, _ scale: Float) -> Double {
        Double(ts.layoutRich(text, [], style, scale, nil).fullWidth() / scale)
    }

    private func widths(_ ts: TextSystem, _ text: String, _ spans: [Span], _ style: TextStyle) -> [Float] {
        [Float(1.0), Float(2.0), Float(3.0)].map { scale in
            ts.layoutRich(text, spans, style, scale, nil).fullWidth() / scale
        }
    }

    private func assertScaleFree(_ w: [Float], _ what: String) {
        #expect(w.allSatisfy { abs($0 - w[0]) < 0.02 }, "\(what): \(w)")
    }

    @Test("system_font_advances_match_core_text_at_every_scale")
    func systemFontAdvancesMatchCoreTextAtEveryScale() {
        let ts = TextSystem()
        guard ts.hasFamily("System Font") else { return }
        let family = Family.named("System Font")
        var worst = 0.0
        for weight in [Float(400.0), Float(600.0)] {
            for size in Self.sizes {
                let font = systemFont(size, weight)
                let style = TextStyle.new(size, weight).family(family)
                for text in Self.strings {
                    let ct = coreTextWidth(text, font)
                    let glyphs = Double(text.unicodeScalars.count)
                    for scale in [Float(1.0), Float(2.0), Float(3.0)] {
                        let r = runeWidth(ts, text, style, scale)
                        worst = max(worst, abs(r - ct) / glyphs)
                    }
                }
            }
        }
        #expect(worst < 0.05, "worst per-glyph error \(worst) pt")
    }

    @Test("system_mono_matches_appkit_monospaced_system_font")
    func systemMonoMatchesAppkitMonospacedSystemFont() {
        let ts = TextSystem()
        #expect(ts.systemMono().first == ".SF NS Mono")
        #expect(ts.primaryTrak(.systemMono, 400.0, false) == nil, "SF Mono is untracked")
        var worst = 0.0
        for (weight, appkit) in [(Float(400.0), NSFont.Weight.regular), (Float(600.0), NSFont.Weight.semibold)] {
            for size in Self.sizes {
                let nsFont = NSFont.monospacedSystemFont(ofSize: CGFloat(size), weight: appkit)
                let ctFont = nsFont as CTFont
                let style = TextStyle.new(size, weight).family(.systemMono)
                for text in Self.strings where text.utf8.allSatisfy({ $0 < 128 }) {
                    let ct = coreTextWidth(text, ctFont)
                    let glyphs = Double(text.unicodeScalars.count)
                    for scale in [Float(1.0), Float(2.0), Float(3.0)] {
                        worst = max(worst, abs((runeWidth(ts, text, style, scale) - ct) / glyphs))
                    }
                }
            }
        }
        #expect(worst < 0.05, "worst per-glyph error \(worst) pt")

        let text = Self.strings[0]
        let n = Float(text.unicodeScalars.count)
        let style = TextStyle.new(13.0, 400.0).family(.systemMono)
        let plain = widths(ts, text, [], style)
        let untracked = widths(ts, text, [], style.features("'trak' 0"))
        let extra = widths(ts, text, [], style.tracking(0.5))
        for w in [plain, untracked, extra] {
            assertScaleFree(w, "width")
        }
        #expect(abs(plain[0] - untracked[0]) < 0.01)
        #expect(abs(extra[0] - plain[0] - 0.5 * n) < 0.05)
    }

    @Test("trak_opts_out_per_style_and_tracking_adds_to_it")
    func trakOptsOutPerStyleAndTrackingAddsToIt() {
        let ts = TextSystem()
        guard ts.hasFamily("System Font") else { return }
        let text = Self.strings[0]
        let n = Float(text.unicodeScalars.count)
        let style = TextStyle.new(14.0, 400.0).family(.named("System Font"))
        let tracked = widths(ts, text, [], style)
        let untracked = widths(ts, text, [], style.features("'tnum' 1, 'trak' 0"))
        let extra = widths(ts, text, [], style.tracking(0.5))
        for w in [tracked, untracked, extra] {
            assertScaleFree(w, "width")
        }
        let trakVal: Float = -22.0 / 2048.0 * 14.0
        #expect(abs(tracked[0] - untracked[0] - trakVal * n) < 0.05, "\(tracked) vs \(untracked)")
        #expect(abs(extra[0] - tracked[0] - 0.5 * n) < 0.05, "\(extra) vs \(tracked)")
    }

    @Test("spans_and_fallback_runs_track_at_their_own_point_size")
    func spansAndFallbackRunsTrackAtTheirOwnPointSize() {
        var plexFonts: [[UInt8]] = []
        if let crateDir = upstreamRuneCrateDir() {
            let plexPath = "\(crateDir)/../../themes/opencode/assets/fonts/IBMPlexMono-Regular.ttf"
            if let data = try? Data(contentsOf: URL(fileURLWithPath: plexPath)) {
                plexFonts = [[UInt8](data)]
            }
        }
        let ts = plexFonts.isEmpty ? TextSystem() : TextSystem(plexFonts, ("IBM Plex Mono", "IBM Plex Mono"))
        guard ts.hasFamily("System Font") else { return }
        let system = TextStyle.new(13.0, 400.0).family(.named("System Font"))
        let text = "Send dev-site captures to OpenCode"
        let spans = [
            Span.new(0, 4).size(20.0),
            Span.new(5, 13).weight(700.0),
            Span.new(14, 22).mono()
        ]
        assertScaleFree(widths(ts, text, spans, system), "spans")
        assertScaleFree(widths(ts, "Copy \u{2318}\u{21e7}K \u{2325}\u{2303}", [], TextStyle.new(13.0, 400.0)), "fallback")
    }

    @Test("carets_follow_corrected_glyph_positions")
    func caretsFollowCorrectedGlyphPositions() {
        let ts = TextSystem()
        guard ts.hasFamily("System Font") else { return }
        let text = "Send dev-site captures"
        let layout = ts.layoutRich(text, [], TextStyle.new(14.0, 400.0).family(.named("System Font")), 2.0, nil)
        var pens: [Float] = []
        for line in layout.lines() {
            for item in line.items() {
                guard case .glyphRun(let run) = item else { continue }
                var x = run.offset()
                for g in run.glyphs() {
                    pens.append(x + g.x)
                    x += g.advance
                }
            }
        }
        #expect(pens.count == text.utf8.count)
        for (i, pen) in pens.enumerated() {
            let caret = TextCursor.fromByteIndex(layout, i, .downstream).geometry(layout, 1.0)
            #expect(abs(Float(caret.x0) - pen) < 1e-3, "byte \(i): caret \(caret.x0) vs pen \(pen)")
        }
    }

    @Test("explicit_optical_size_picks_the_trak_entry")
    func explicitOpticalSizePicksTrakEntry() {
        let ts = TextSystem()
        guard ts.hasFamily("System Font") else { return }
        let family = Family.named("System Font")
        let text = Self.strings[0]
        let n = Float(text.unicodeScalars.count)
        let style = TextStyle.new(28.0, 400.0).family(family).opticalSize(14.0)
        assertScaleFree(widths(ts, text, [], style.features("'trak' 0")), "untracked")

        let plain = Float(coreTextWidth(text, systemFont(14.0, 400.0)))
        let optical = Float(coreTextWidth(text, systemFontOptical(28.0, 14.0)))
        let axis = Float(coreTextWidth(text, systemFontOpsz(28.0, 400.0, 14.0)))
        #expect(abs(optical - 2.0 * plain) < 0.01)

        let opszAxis = TextStyle.new(28.0, 400.0).family(family).variations("'opsz' 14")
        func trakPoints(_ s: TextStyle, _ scale: Float) -> Float {
            let w1 = ts.layoutRich(text, [], s, scale, nil).fullWidth() / scale
            let w0 = ts.layoutRich(text, [], s.features("'trak' 0"), scale, nil).fullWidth() / scale
            return w1 - w0
        }
        for scale in [Float(1.0), Float(2.0)] {
            let tracked = trakPoints(style, scale)
            #expect(abs(tracked - (-22.0 / 2048.0 * 28.0 * n)) < 0.05, "\(scale)x: \(tracked)")
            let wOpt = ts.layoutRich(text, [], style, scale, nil).fullWidth() / scale
            #expect(abs(wOpt - optical) / n < 0.05, "\(scale)x: \(wOpt) vs CoreText \(optical)")
            let wAxis = ts.layoutRich(text, [], opszAxis, scale, nil).fullWidth() / scale
            #expect(abs(wAxis - axis) / n < 0.05, "\(scale)x: \(wAxis) vs CoreText \(axis)")
        }
    }
}
#endif
