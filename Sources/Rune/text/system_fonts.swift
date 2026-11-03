// Ported from: crates/rune/src/text/system_fonts.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Platform font discovery and CSS `font-family` list parsing (`ui-monospace` resolution).

#if !os(WASI)
import Foundation
#endif

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
let SYSTEM_MONO_FAMILIES: [String] = [".SF NS Mono", "Menlo"]
let SYSTEM_MONO_FILES: [String] = ["sfnsmono", "menlo"]
let EMOJI_FAMILIES: [String] = ["Apple Color Emoji"]
let SYMBOL_FAMILIES: [String] = ["System Font", ".SF NS", "Apple Symbols", ".SF NS Symbols", "Menlo", "Apple Color Emoji"]
let SYMBOL_FONT_FILES: [String] = ["sfnsttf", "sfnsitalic", "applesymbols", "sfnssymbols", "menlo", "applecoloremoji"]
#elseif os(Windows)
let SYSTEM_MONO_FAMILIES: [String] = ["Cascadia Mono", "Consolas", "Courier New"]
let SYSTEM_MONO_FILES: [String] = ["cascadiamono", "consola", "cour"]
let EMOJI_FAMILIES: [String] = ["Segoe UI Emoji"]
let SYMBOL_FAMILIES: [String] = ["Segoe UI Symbol", "Segoe UI Emoji"]
let SYMBOL_FONT_FILES: [String] = ["seguisym", "seguiemj"]
#else
let SYSTEM_MONO_FAMILIES: [String] = ["DejaVu Sans Mono", "Liberation Mono", "Noto Sans Mono", "Ubuntu Mono"]
let SYSTEM_MONO_FILES: [String] = ["dejavusansmono", "liberationmono", "notosansmono", "ubuntumono"]
let EMOJI_FAMILIES: [String] = ["Noto Color Emoji"]
let SYMBOL_FAMILIES: [String] = ["DejaVu Sans", "Noto Sans Symbols2", "Noto Sans Symbols", "DejaVu Sans Mono", "Noto Color Emoji"]
let SYMBOL_FONT_FILES: [String] = ["dejavusans", "notosanssymbols", "notocoloremoji"]
#endif

let CJK_FONT_FILES: [String] = [
    "notosanscjk", "notosanssc", "notosansjp", "notosanstc", "notosanshk", "notosanskr", "sourcehansans",
    "notoserifcjk", "sourcehanserif", "pingfang", "hiragino", "applesdgothicneo", "msyh", "yugoth", "meiryo",
    "malgun", "msjh", "wqy", "wenquanyi", "droidsansfallback", "sarasa", "lxgw", "ukai", "uming", "simsun",
    "applegothic",
]

let KOREAN_FAMILIES: [String] = ["SD Gothic", "Malgun", " KR", "AppleGothic", "Nanum"]

enum GenericFontFamily: String, Sendable, Equatable {
    case serif = "Serif"
    case sansSerif = "SansSerif"
    case monospace = "Monospace"
    case cursive = "Cursive"
    case fantasy = "Fantasy"
    case systemUi = "SystemUi"
    case uiSerif = "UiSerif"
    case uiSansSerif = "UiSansSerif"
    case uiMonospace = "UiMonospace"
    case uiRounded = "UiRounded"
    case math = "Math"
    case emoji = "Emoji"
    case fangsong = "Fangsong"
}

enum ParsedFontFamily: Sendable, Equatable {
    case named(String)
    case generic(GenericFontFamily)

    var namedValue: String? {
        if case .named(let n) = self { return n }
        return nil
    }
}

func parseCssFamilyList(_ css: String) -> [ParsedFontFamily] {
    var out: [ParsedFontFamily] = []
    for raw in css.split(separator: ",", omittingEmptySubsequences: false) {
        let wasQuoted = raw.contains("\"") || raw.contains("'")
        let trimmed = trimQuotesAndSpaces(raw)
        if trimmed.isEmpty { continue }
        if !wasQuoted, let g = matchGenericFamily(trimmed) {
            out.append(.generic(g))
        } else {
            out.append(.named(trimmed))
        }
    }
    return out
}

private func matchGenericFamily(_ s: String) -> GenericFontFamily? {
    switch s.lowercased() {
    case "serif": return .serif
    case "sans-serif": return .sansSerif
    case "monospace": return .monospace
    case "cursive": return .cursive
    case "fantasy": return .fantasy
    case "system-ui": return .systemUi
    case "ui-serif": return .uiSerif
    case "ui-sans-serif": return .uiSansSerif
    case "ui-monospace": return .uiMonospace
    case "ui-rounded": return .uiRounded
    case "math": return .math
    case "emoji": return .emoji
    case "fangsong": return .fangsong
    default: return nil
    }
}

private func trimQuotesAndSpaces(_ s: Substring) -> String {
    var sub = s
    while let f = sub.first, f == " " || f == "\t" || f == "\n" || f == "\r" {
        sub = sub.dropFirst()
    }
    while let l = sub.last, l == " " || l == "\t" || l == "\n" || l == "\r" {
        sub = sub.dropLast()
    }
    if sub.count >= 2 {
        if (sub.first == "\"" && sub.last == "\"") || (sub.first == "'" && sub.last == "'") {
            sub = sub.dropFirst().dropLast()
        }
    }
    return String(sub)
}

/// Whether a CSS `font-family` list asks for the platform monospace font (`ui-monospace`).
func namesSystemMono(_ css: String) -> Bool {
    parseCssFamilyList(css).contains(.generic(.uiMonospace))
}

/// `list` parsed, with `ui-monospace` replaced by the installed `Family.systemMono` families.
/// When that leaves no named family (no monospace font installed, or the web), `sans` follows,
/// so text still finds a font.
func parsedFamilyList(_ list: String, _ systemMono: [String], _ sans: String) -> [ParsedFontFamily] {
    var sawUiMono = false
    var out: [ParsedFontFamily] = []
    for item in parseCssFamilyList(list) {
        if item == .generic(.uiMonospace) {
            sawUiMono = true
            for name in systemMono {
                out.append(.named(name))
            }
        } else {
            out.append(item)
        }
    }
    if sawUiMono && !out.contains(where: { $0.namedValue != nil }) {
        out.append(contentsOf: parseCssFamilyList(sans))
    }
    return out
}

/// Split a CSS `font-family` list into candidate family names, expanding `ui-monospace` into
/// `systemMono` (or `fallback` when no named family remains).
func familyList(_ css: String, _ systemMono: [String], _ fallback: [String]) -> [String] {
    var sawUiMono = false
    var out: [String] = []
    for item in parseCssFamilyList(css) {
        switch item {
        case .generic(.uiMonospace):
            sawUiMono = true
            out.append(contentsOf: systemMono)
        case .named(let name):
            out.append(name)
        case .generic(let g):
            out.append(g.rawValue)
        }
    }
    if sawUiMono && !out.contains(where: { name in
        matchGenericFamily(name) == nil && !["Serif", "SansSerif", "Monospace", "Cursive", "Fantasy", "SystemUi", "UiSerif", "UiSansSerif", "UiMonospace", "UiRounded", "Math", "Emoji", "Fangsong"].contains(name)
    }) {
        out.append(contentsOf: fallback)
    }
    return out
}

/// Choose available families from `(sansCss, monoCss)` given `hasFamily` predicate and `systemMono`.
func chooseFamiliesList(
    requested: (String, String),
    systemMono: [String],
    hasFamily: (String) -> Bool
) -> ([String], [String]) {
    let sans = parsedFamilyList(requested.0, systemMono, "").compactMap { $0.namedValue }
    let mono = parsedFamilyList(requested.1, systemMono, requested.0).compactMap { $0.namedValue }
    func pick(_ candidates: [String]) -> [String] {
        let present = candidates.filter { hasFamily($0) }
        return present.isEmpty ? candidates : present
    }
    return (pick(sans), pick(mono))
}

/// Candidate font directories on non-WASI platforms.
func systemFontDirectories() -> [String] {
    #if os(WASI)
    return []
    #elseif os(macOS)
    var dirs = ["/System/Library/Fonts", "/Library/Fonts"]
    if let entries = try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/AssetsV2") {
        for e in entries where e.hasPrefix("com_apple_MobileAsset_Font") {
            dirs.append("/System/Library/AssetsV2/\(e)")
        }
    }
    return dirs
    #elseif os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    return ["/System/Library/Fonts"]
    #elseif os(Windows)
    if let windir = ProcessInfo.processInfo.environment["WINDIR"], !windir.isEmpty {
        return ["\(windir)\\Fonts"]
    }
    return ["C:\\Windows\\Fonts"]
    #elseif os(Android)
    return ["/system/fonts", "/product/fonts"]
    #else
    var dirs: [String] = []
    let env = ProcessInfo.processInfo.environment
    let home = env["HOME"]
    if let xdgHome = env["XDG_DATA_HOME"], !xdgHome.isEmpty {
        dirs.append("\(xdgHome)/fonts")
    } else if let home, !home.isEmpty {
        dirs.append("\(home)/.local/share/fonts")
    }
    if let home, !home.isEmpty {
        dirs.append("\(home)/.fonts")
    }
    let dataDirs = env["XDG_DATA_DIRS"] ?? "/usr/local/share:/usr/share"
    for d in dataDirs.split(separator: ":") where !d.isEmpty {
        dirs.append("\(d)/fonts")
    }
    return dirs
    #endif
}

#if !os(WASI)
private let fontFilesCacheLock = LiveLock()
// PORT NOTE: Guarded by `fontFilesCacheLock`; walks system font directories once per process (`OnceLock` equivalent).
nonisolated(unsafe) private var cachedSystemFontFiles: [(String, String)]? = nil

private func normalizedFontFileStem(_ fileName: String) -> String? {
    let lower = fileName.lowercased()
    guard lower.hasSuffix(".ttf") || lower.hasSuffix(".otf") || lower.hasSuffix(".ttc") || lower.hasSuffix(".otc") else {
        return nil
    }
    var out = ""
    out.reserveCapacity(lower.count)
    for ch in lower where ch != " " && ch != "." {
        out.append(ch)
    }
    return out
}

private func walkSystemFontDirs() -> [(String, String)] {
    let fm = FileManager.default
    var stack = systemFontDirectories()
    var visited = Set<String>()
    var seen = Set<String>()
    var found: [(String, String)] = []

    while let dir = stack.popLast() {
        if visited.count > 4096 || !visited.insert(dir).inserted {
            continue
        }
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
        for entry in entries {
            let full = URL(fileURLWithPath: dir).appendingPathComponent(entry).path
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                stack.append(full)
            } else if let norm = normalizedFontFileStem(entry), seen.insert(full).inserted {
                found.append((norm, full))
            }
        }
    }
    return found
}

func systemFontFiles(_ fragments: [String]) -> [String] {
    guard !fragments.isEmpty else { return [] }
    let all = fontFilesCacheLock.withLock { () -> [(String, String)] in
        if let existing = cachedSystemFontFiles {
            return existing
        }
        let walked = walkSystemFontDirs()
        cachedSystemFontFiles = walked
        return walked
    }
    var matches: [(Int, String)] = []
    for (norm, path) in all {
        if let pos = fragments.firstIndex(where: { frag in frag.isEmpty || norm.contains(frag) }) {
            matches.append((pos, path))
        }
    }
    matches.sort { a, b in
        if a.0 != b.0 { return a.0 < b.0 }
        return a.1 < b.1
    }
    return matches.map { $0.1 }
}
#else
func systemFontFiles(_ fragments: [String]) -> [String] {
    _ = fragments
    return []
}
#endif
