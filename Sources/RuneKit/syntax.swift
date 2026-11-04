// Ported from: crates/rune-kit/src/syntax.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Syntax highlighting for code: kinds of token (`Syntax`) over byte ranges, coloured by a
//! `SyntaxTheme`. `Markdown` colours its code fences with it, and the same output paints any
//! other text, such as code in a composer or `DiffView`.

#if !os(WASI)
import Foundation
#endif
import Rune

/// A kind of token in code, each with its own colour in a ``SyntaxTheme``.
public enum Syntax: Int, CaseIterable, Sendable, Equatable, Hashable {
    /// Keywords, and markup tag names.
    case keyword = 0
    /// String, character and regex literals, and YAML's unquoted values.
    case string = 1
    /// Numbers, and constants such as `true`, `null` and `ALL_CAPS` names.
    case number = 2
    /// Comments, and a diff's header lines.
    case comment = 3
    /// Type names (capitalised names and built-in types), CSS classes and ids, YAML tags.
    case type = 4
    /// Functions where they are called or defined, macros, and shell commands.
    case function = 5
    /// JSON and YAML keys, CSS properties, markup attributes, and shell and SQL variables.
    case property = 6
    /// Brackets, operators and separators.
    case punctuation = 7
    /// A diff's added lines.
    case inserted = 8
    /// A diff's removed lines.
    case deleted = 9

    static let COUNT: Int = 10
}

/// What colours a highlighted range: a kind of token, coloured by the ``SyntaxTheme`` in use,
/// or a colour of the highlighter's own. Colour is all a highlight changes, never weight or
/// style, so highlighting never moves a glyph.
public enum SyntaxPaint: Sendable, Equatable, Hashable {
    case kind(Syntax)
    case color(Color)

    public init(_ k: Syntax) {
        self = .kind(k)
    }

    public init(_ c: Color) {
        self = .color(c)
    }
}

/// Value-typed highlighted UTF-8 byte span pairing `range` and `paint`.
public struct SyntaxTokenSpan: Sendable, Equatable, Hashable {
    public var range: Range<Int>
    public var paint: SyntaxPaint

    public init(_ range: Range<Int>, _ paint: SyntaxPaint) {
        self.range = range
        self.paint = paint
    }

    public init(range: Range<Int>, paint: SyntaxPaint) {
        self.range = range
        self.paint = paint
    }
}

/// Namespace mirroring `rune_kit::syntax`.
public enum syntax {
    public typealias Syntax = RuneKit.Syntax
    public typealias Paint = RuneKit.SyntaxPaint
    /// A highlighted byte range of the code.
    public typealias Highlight = (Range<Int>, SyntaxPaint)
    public typealias Highlighter = RuneKit.Highlighter
    public typealias SyntaxTheme = RuneKit.SyntaxTheme

    /// Whether the built-in scanners colour `lang`, a fence's language name (case-insensitive):
    /// `rust`/`rs`, `js`/`javascript`/`jsx`/`mjs`/`cjs`, `ts`/`typescript`/`mts`/`cts`, `tsx`,
    /// `json`/`jsonc`/`json5`, `python`/`py`/`python3`/`py3`/`pyi`, `go`/`golang`, `swift`,
    /// `sh`/`bash`/`zsh`/`shell`/`shellscript`, `sql`/`postgres`/`postgresql`/`mysql`/`sqlite`,
    /// `html`/`htm`/`xhtml`/`xml`/`svg`, `css`, `yaml`/`yml` and `diff`/`patch`.
    public static func known(_ lang: String) -> Bool {
        syntaxScan.Lang.fromName(lang) != nil
    }

    /// The built-in scanners' highlights of `code`, in order and not overlapping, uncached: empty
    /// for a language they don't know or none. For an app's ``Highlighter`` to fall back on; to
    /// highlight directly, use the cached ``highlight(_:_:)``.
    public static func builtin(_ lang: String?, _ code: String) -> [Highlight] {
        guard let lang, let resolved = syntaxScan.Lang.fromName(lang) else {
            return []
        }
        return syntaxScan.highlight(resolved, code).map { a, b, k in
            (Int(a)..<Int(b), .kind(k))
        }
    }

    /// ``builtin(_:_:)``, cached per language and code: the same call with the same code returns
    /// the cached result without scanning again.
    public static func highlight(_ lang: String?, _ code: String) -> [Highlight] {
        Highlighter.builtin().highlight(lang, code)
    }

    /// Highlight `code` and return `[SyntaxTokenSpan]` values.
    public static func highlightSpans(_ lang: String?, _ code: String) -> [SyntaxTokenSpan] {
        highlight(lang, code).map { SyntaxTokenSpan($0.0, $0.1) }
    }

    /// Internal cache-entry lookup for identity-reuse verification in unit tests.
    static func highlightCached(_ lang: String?, _ code: String) -> SyntaxCacheEntry {
        Highlighter.builtin().highlightCached(lang, code)
    }
}

/// Estimated bytes of highlights kept beyond those on screen (see `Budget`).
private let CACHE_BYTES: Int = 4 << 20

/// Immutable reference-counted cache entry mirroring `Entry` / `Rc<[Highlight]>` in `syntax.rs`.
final class SyntaxCacheEntry: Sendable {
    let id: UInt64
    let lang: String?
    let src: String
    let out: [syntax.Highlight]

    init(id: UInt64, lang: String?, src: String, out: [syntax.Highlight]) {
        self.id = id
        self.lang = lang
        self.src = src
        self.out = out
    }
}

private final class SyntaxCacheBox {
    var budget: Budget<UInt64, SyntaxCacheEntry> = Budget(CACHE_BYTES)
}

#if os(WASI)
// PORT NOTE: WASI (`wasm32-unknown-wasip1`) is single-threaded, matching Rust `thread_local!` in `syntax.rs`.
nonisolated(unsafe) private var wasiSyntaxCache = SyntaxCacheBox()
#else
private let syntaxCacheThreadKey = "gpua.runekit.syntax.cache"
#endif

private func withSyntaxCache<R>(_ body: (inout Budget<UInt64, SyntaxCacheEntry>) -> R) -> R {
    #if os(WASI)
    return body(&wasiSyntaxCache.budget)
    #else
    let dict = Thread.current.threadDictionary
    let box: SyntaxCacheBox
    if let existing = dict[syntaxCacheThreadKey] as? SyntaxCacheBox {
        box = existing
    } else {
        let created = SyntaxCacheBox()
        dict[syntaxCacheThreadKey] = created
        box = created
    }
    return body(&box.budget)
    #endif
}

private func fnv64(_ seed: UInt64 = 0xcbf2_9ce4_8422_2325, bytes: some Swift.Sequence<UInt8>) -> UInt64 {
    var h = seed
    for b in bytes {
        h ^= UInt64(b)
        h &*= 0x0000_0100_0000_01b3
    }
    return h
}

private func fnvMixUInt64(_ h: UInt64, _ value: UInt64) -> UInt64 {
    var cur = h
    var v = value
    for _ in 0..<8 {
        cur ^= (v & 0xFF)
        cur &*= 0x0000_0100_0000_01b3
        v >>= 8
    }
    return cur
}

private func syntaxCacheKey(id: UInt64, lang: String?, code: String) -> UInt64 {
    var h = fnvMixUInt64(0xcbf2_9ce4_8422_2325, id)
    if let lang {
        h = fnv64(h, bytes: [1])
        h = fnv64(h, bytes: lang.utf8)
        h = fnv64(h, bytes: [0xFF])
    } else {
        h = fnv64(h, bytes: [0])
    }
    h = fnv64(h, bytes: code.utf8)
    return h
}

private func callSiteHighlighterId(file: StaticString, line: UInt, column: UInt) -> UInt64 {
    var h = fnv64(bytes: String(describing: file).utf8)
    h = fnvMixUInt64(h, UInt64(line))
    h = fnvMixUInt64(h, UInt64(column))
    return h | 1
}

/// An app highlighter's ranges, sorted, in bounds, on character boundaries and not
/// overlapping, at most `syntaxScan.MAX_TOKENS` of them.
private func tidy(_ v: [syntax.Highlight], _ src: String) -> [syntax.Highlight] {
    let bytes = Array(src.utf8)
    let len = bytes.count
    var filtered: [syntax.Highlight] = []
    filtered.reserveCapacity(v.count)
    for item in v {
        let r = item.0
        guard r.lowerBound >= 0,
              r.lowerBound < r.upperBound,
              r.upperBound <= len,
              syntaxScan.isCharBoundary(bytes, r.lowerBound),
              syntaxScan.isCharBoundary(bytes, r.upperBound)
        else {
            continue
        }
        filtered.append(item)
    }
    filtered.sort { $0.0.lowerBound < $1.0.lowerBound }
    var out: [syntax.Highlight] = []
    out.reserveCapacity(min(filtered.count, syntaxScan.MAX_TOKENS))
    var last = 0
    for item in filtered {
        if item.0.lowerBound >= last {
            last = item.0.upperBound
            out.append(item)
            if out.count >= syntaxScan.MAX_TOKENS {
                break
            }
        }
    }
    return out
}

/// Turns code into highlights: the built-in scanners (``Highlighter/builtin()``, the default),
/// or an app's own function, such as a syntect or tree-sitter highlighter.
///
/// The function gets the code's language as written (a fence's first info word, `nil` when
/// it has none) and the code, and returns byte ranges of it with a ``SyntaxPaint``. Ranges may
/// come in any order; ones out of bounds, inside a character, empty or overlapping an earlier
/// one are dropped.
///
/// Output is cached per highlighter, language and code. Highlighters made at the same call site
/// share that cache, so one whose output depends on what it captures (a light or dark theme,
/// say) must name that with ``key(_:)``.
// PORT NOTE: Mirrors `Rc`-backed `Highlighter` in `crates/rune-kit/src/syntax.rs`; Swift closures
// lack per-closure `TypeId`, so call-site `#fileID`/`#line`/`#column` seeds `id` by default.
public struct Highlighter: @unchecked Sendable, CustomDebugStringConvertible {
    private let f: ((String?, String) -> [syntax.Highlight])?
    let id: UInt64

    private init(f: ((String?, String) -> [syntax.Highlight])?, id: UInt64) {
        self.f = f
        self.id = id
    }

    /// Creates the default built-in highlighter.
    public init() {
        self = .builtin()
    }

    /// The built-in scanners (see the module docs for the languages).
    public static func builtin() -> Highlighter {
        Highlighter(f: nil, id: 0)
    }

    public init(
        _ f: @escaping (String?, String) -> [syntax.Highlight],
        file: StaticString = #fileID,
        line: UInt = #line,
        column: UInt = #column
    ) {
        self.f = f
        self.id = callSiteHighlighterId(file: file, line: line, column: column)
    }

    public static func new(
        _ f: @escaping (String?, String) -> [syntax.Highlight],
        file: StaticString = #fileID,
        line: UInt = #line,
        column: UInt = #column
    ) -> Highlighter {
        Highlighter(f, file: file, line: line, column: column)
    }

    /// Keeps this highlighter's cached output apart from others made from the same closure:
    /// give it whatever its output depends on besides the language and code.
    public func key<K: Hashable>(_ key: K) -> Highlighter {
        var hasher = Hasher()
        hasher.combine(self.id)
        hasher.combine(key)
        let mixed = UInt64(bitPattern: Int64(hasher.finalize())) | 1
        return Highlighter(f: self.f, id: mixed)
    }

    /// The highlights of `code`'s first 32 KiB (cut at a line end), cached.
    public func highlight(_ lang: String?, _ code: String) -> [syntax.Highlight] {
        highlightCached(lang, code).out
    }

    func highlightCached(_ lang: String?, _ code: String) -> SyntaxCacheEntry {
        let len = syntaxScan.colouredLen(code)
        let sliced: String
        if len == code.utf8.count {
            sliced = code
        } else {
            sliced = String(decoding: code.utf8.prefix(len), as: UTF8.self)
        }
        let k = syntaxCacheKey(id: id, lang: lang, code: sliced)
        if let hit: SyntaxCacheEntry = withSyntaxCache({ cache in
            guard let candidate = cache.get(k),
                  candidate.id == id,
                  candidate.lang == lang,
                  candidate.src == sliced
            else {
                return nil
            }
            return candidate
        }) {
            return hit
        }

        let out: [syntax.Highlight]
        if let f {
            out = tidy(f(lang, sliced), sliced)
        } else {
            out = syntax.builtin(lang, sliced)
        }
        let bytes = sliced.utf8.count + out.count * MemoryLayout<syntax.Highlight>.stride + 96
        let entry = SyntaxCacheEntry(id: id, lang: lang, src: sliced, out: out)
        withSyntaxCache { cache in
            cache.insert(k, entry, bytes)
        }
        return entry
    }

    /// Whether this is ``Highlighter/builtin()``, which leaves languages ``syntax/known(_:)``
    /// doesn't list plain.
    public func isBuiltin() -> Bool {
        f == nil
    }

    public var debugDescription: String {
        "Highlighter { builtin: \(f == nil), id: \(id) }"
    }
}

/// A colour per kind of token. ``SyntaxTheme/fromKit(_:)`` follows the kit's light or dark
/// theme; ``SyntaxTheme/with(_:_:)`` overrides one kind.
public struct SyntaxTheme: Sendable, Equatable, Hashable {
    var colors: [Color]

    init(colors: [Color]) {
        precondition(colors.count == Syntax.COUNT)
        self.colors = colors
    }

    /// Muted token colours: the familiar hues (violet keywords, green strings, orange numbers,
    /// teal types, blue functions, rose properties) at one lightness a step from the text's, so
    /// contrast follows the theme. Comments and punctuation are the theme's quieter text greys,
    /// and a diff's lines its success and danger colours.
    ///
    /// The hues are fixed rather than taken from the theme's status colours: those vary too much
    /// between themes (OpenCode's "info" is magenta) to keep the token kinds apart.
    public static func fromKit(_ k: Kit) -> SyntaxTheme {
        let c = k.c
        let textL = c.textBase.toOklab()[0]
        let (l, chroma): (Float, Float) = if k.dark {
            (min(max(textL - 0.16, 0.62), 0.84), 0.1)
        } else {
            (min(max(textL + 0.3, 0.38), 0.52), 0.12)
        }
        func paint(_ h: Float) -> Color {
            oklch(l, chroma, h)
        }
        var s = [Color](repeating: c.textBase, count: Syntax.COUNT)
        s[Syntax.keyword.rawValue] = paint(305.0)
        s[Syntax.string.rawValue] = paint(145.0)
        s[Syntax.number.rawValue] = paint(60.0)
        s[Syntax.comment.rawValue] = c.textMuted.mix(c.textFaint, 0.4)
        s[Syntax.type.rawValue] = paint(195.0)
        s[Syntax.function.rawValue] = paint(255.0)
        s[Syntax.property.rawValue] = paint(15.0)
        s[Syntax.punctuation.rawValue] = c.textMuted
        s[Syntax.inserted.rawValue] = c.success.icon
        s[Syntax.deleted.rawValue] = c.danger.icon
        return SyntaxTheme(colors: s)
    }

    /// Rune's neutral light or dark look (``Kit/neutral(_:)``'s tokens), for apps without a kit.
    public static func neutral(_ dark: Bool) -> SyntaxTheme {
        SyntaxTheme.fromKit(Kit.neutral(dark))
    }

    public func color(_ kind: Syntax) -> Color {
        colors[kind.rawValue]
    }

    /// Colours one kind of token `c`.
    public func with(_ kind: Syntax, _ c: Color) -> SyntaxTheme {
        var copy = self
        copy.colors[kind.rawValue] = c
        return copy
    }

    public func paint(_ p: SyntaxPaint) -> Color {
        switch p {
        case .kind(let k):
            return color(k)
        case .color(let c):
            return c
        }
    }

    /// Colour-only `Span`s for `highlights`, each range moved `offset` bytes on: where the
    /// code starts in the text the spans style.
    public func spans(_ highlights: [syntax.Highlight], _ offset: Int) -> [Span] {
        var out: [Span] = []
        out.reserveCapacity(highlights.count)
        for (r, p) in highlights {
            var sp = Span.new(r.lowerBound + offset, r.upperBound + offset)
            sp.color = paint(p)
            out.append(sp)
        }
        return out
    }

    /// Overload converting `[SyntaxTokenSpan]` values into colour-only `Span`s shifted by `offset`.
    public func spans(_ highlights: [SyntaxTokenSpan], _ offset: Int) -> [Span] {
        var out: [Span] = []
        out.reserveCapacity(highlights.count)
        for h in highlights {
            var sp = Span.new(h.range.lowerBound + offset, h.range.upperBound + offset)
            sp.color = paint(h.paint)
            out.append(sp)
        }
        return out
    }
}
