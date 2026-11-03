// Ported from: crates/rune/src/text/fallback.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! System fallbacks loaded on first use: fonts for symbol blocks the eager symbol fallbacks
//! miss (math alphanumerics, enclosed alphanumerics, ...), and byte ranges of a text that should
//! try a fallback's fonts before the style's own.

/// Why a byte range is routed ahead of the style's own fonts.
enum Route: Sendable, Equatable {
    /// Mathematical Alphanumeric Symbols: one math font for a whole formula, so bold, italic
    /// and script letters don't mix designs when an earlier fallback covers a few of them.
    case math
    /// A grapheme asking for emoji presentation with `U+FE0F`: the colour emoji font first,
    /// so a text font with a plain text glyph doesn't take it.
    case emoji
}

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
let MATH_FONT_FILES: [String] = ["stixtwomath"]
let MATH_FAMILIES: [String] = ["STIX Two Math"]
#elseif os(Windows)
let MATH_FONT_FILES: [String] = ["cambriattc"]
let MATH_FAMILIES: [String] = ["Cambria Math"]
#else
let MATH_FONT_FILES: [String] = ["notosansmath", "stixtwomath", "notomusic", "symbola"]
let MATH_FAMILIES: [String] = ["Noto Sans Math", "STIX Two Math", "Noto Music", "Symbola"]
#endif

struct ScriptFonts: Sendable {
    var script: String
    var blocks: [(UInt32, UInt32)]
    var files: [String]

    func covers(_ scalar: UnicodeScalar) -> Bool {
        let v = scalar.value
        for (lo, hi) in blocks {
            if v >= lo && v <= hi { return true }
        }
        return false
    }
}

private let HEBREW_BLOCKS: [(UInt32, UInt32)] = [(0x0590, 0x05FF), (0xFB1D, 0xFB4F)]
private let ARABIC_BLOCKS: [(UInt32, UInt32)] = [(0x0600, 0x06FF), (0x0750, 0x077F), (0x0870, 0x08FF), (0xFB50, 0xFDFF), (0xFE70, 0xFEFF)]
private let DEVANAGARI_BLOCKS: [(UInt32, UInt32)] = [(0x0900, 0x097F), (0xA8E0, 0xA8FF)]
private let BENGALI_BLOCKS: [(UInt32, UInt32)] = [(0x0980, 0x09FF)]
private let THAI_BLOCKS: [(UInt32, UInt32)] = [(0x0E00, 0x0E7F)]

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
let SCRIPT_FONTS: [ScriptFonts] = [
    ScriptFonts(script: "Hebr", blocks: HEBREW_BLOCKS, files: ["sfhebrewttf", "arialhb"]),
    ScriptFonts(script: "Arab", blocks: ARABIC_BLOCKS, files: ["sfarabicttf", "geezapro"]),
    ScriptFonts(script: "Deva", blocks: DEVANAGARI_BLOCKS, files: ["kohinoorttc", "itfdevanagari"]),
    ScriptFonts(script: "Beng", blocks: BENGALI_BLOCKS, files: ["kohinoorbangla", "banglamn"]),
    ScriptFonts(script: "Thai", blocks: THAI_BLOCKS, files: ["thonburi"]),
]
#elseif os(Windows)
let SCRIPT_FONTS: [ScriptFonts] = [
    ScriptFonts(script: "Hebr", blocks: HEBREW_BLOCKS, files: ["segoeuittf", "arialttf"]),
    ScriptFonts(script: "Arab", blocks: ARABIC_BLOCKS, files: ["segoeuittf", "arialttf"]),
    ScriptFonts(script: "Deva", blocks: DEVANAGARI_BLOCKS, files: ["nirmala"]),
    ScriptFonts(script: "Beng", blocks: BENGALI_BLOCKS, files: ["nirmala"]),
    ScriptFonts(script: "Thai", blocks: THAI_BLOCKS, files: ["leelawui", "tahomattf"]),
]
#else
let SCRIPT_FONTS: [ScriptFonts] = [
    ScriptFonts(script: "Hebr", blocks: HEBREW_BLOCKS, files: ["notosanshebrew", "freesans"]),
    ScriptFonts(script: "Arab", blocks: ARABIC_BLOCKS, files: ["notosansarabic", "notonaskharabic", "freesans"]),
    ScriptFonts(script: "Deva", blocks: DEVANAGARI_BLOCKS, files: ["notosansdevanagari", "lohitdevanagari", "freesans"]),
    ScriptFonts(script: "Beng", blocks: BENGALI_BLOCKS, files: ["notosansbengali", "lohitbengali", "freesans"]),
    ScriptFonts(script: "Thai", blocks: THAI_BLOCKS, files: ["notosansthai", "tlwg", "freesans"]),
]
#endif

/// Whether `scalar` is in a symbol block the eager symbol fallbacks often miss.
func needsSymbols(_ scalar: UnicodeScalar) -> Bool {
    let v = scalar.value
    return (0x2100...0x2BFF).contains(v) ||
           (0x2E00...0x2E7F).contains(v) ||
           (0x1D000...0x1D7FF).contains(v) ||
           (0x1F000...0x1F0FF).contains(v) ||
           (0x1F100...0x1F1E5).contains(v) ||
           (0x1F650...0x1F67F).contains(v) ||
           (0x1F700...0x1F8FF).contains(v) ||
           (0x1FA00...0x1FA6F).contains(v) ||
           (0x1FB00...0x1FBFF).contains(v)
}

/// Math alphanumerics, plus the Letterlike Symbols that fill that block's holes (`R`, `h`, `B`, ...).
func isMathAlphanumeric(_ scalar: UnicodeScalar) -> Bool {
    let v = scalar.value
    if (0x1D400...0x1D7FF).contains(v) { return true }
    switch v {
    case 0x2102, 0x210A...0x2113, 0x2115, 0x2119...0x211D,
         0x2124, 0x2128, 0x212C...0x212D, 0x212F...0x2131,
         0x2133...0x2134, 0x2145...0x2149:
        return true
    default:
        return false
    }
}

/// Whether `scalar` is in an RTL script block (Hebrew, Arabic, Syriac, Thaana, NKo).
func isRtlScalar(_ scalar: UnicodeScalar) -> Bool {
    let v = scalar.value
    return (0x0590...0x08FF).contains(v) || (0xFB1D...0xFDFF).contains(v) || (0xFE70...0xFEFF).contains(v)
}

/// Routed UTF-8 byte ranges of `text`, merging neighbours on the same route.
func routes(_ text: String) -> [(Range<Int>, Route)] {
    var isAllAscii = true
    for b in text.utf8 where b >= 0x80 {
        isAllAscii = false
        break
    }
    if isAllAscii {
        return []
    }
    var out: [(Range<Int>, Route)] = []
    func push(_ range: Range<Int>, _ route: Route) {
        if let last = out.last, last.1 == route, last.0.upperBound == range.lowerBound {
            out[out.count - 1].0 = last.0.lowerBound..<range.upperBound
        } else {
            out.append((range, route))
        }
    }
    var byteOffset = 0
    for grapheme in text {
        let gBytes = grapheme.utf8.count
        if grapheme.unicodeScalars.contains("\u{FE0F}") {
            push(byteOffset..<(byteOffset + gBytes), .emoji)
            byteOffset += gBytes
            continue
        }
        var subOffset = byteOffset
        for sc in grapheme.unicodeScalars {
            let sLen = sc.utf8.count
            if isMathAlphanumeric(sc) {
                push(subOffset..<(subOffset + sLen), .math)
            }
            subOffset += sLen
        }
        byteOffset += gBytes
    }
    return out
}
