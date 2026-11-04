// Ported from: crates/rune/src/text.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Text shaping, layout caching, and greyscale glyph/SVG icon atlas.
//!
//! Invariants: layouts are in device pixels; every layout is cached by a 64-bit hash of
//! `(text, spans, style, scale, width)`, kept for two commits unused and then while a budget of
//! stale layouts lasts (`STALE_BYTES`), least recently used out first; a width not cached re-breaks
//! a cached layout of the same text and style rather than shaping it again; glyph keys include
//! the run's variation coordinates, so one variable font serves every weight.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#elseif os(Windows)
import CRT
#elseif os(WASI)
import WASILibc
#endif

#if !os(WASI)
import Foundation
#endif

#if canImport(CoreText) && canImport(CoreGraphics)
import CoreText
import CoreGraphics
#endif

#if canImport(AppKit)
import AppKit
#endif

/// Lean of a synthetic oblique, in degrees, for faces with no italic (`SYNTHETIC_OBLIQUE = 12`).
private let SYNTHETIC_OBLIQUE: UInt8 = 12
/// Synthetic oblique tangent in 1/64ths (`round(tan(12 deg) * 64) = 14`).
private let SYNTHETIC_OBLIQUE_SKEW64: Int8 = 14

struct PrimaryFontCacheKey: Sendable, Equatable, Hashable {
    var family: Family
    var weightBits: UInt32
    var italic: Bool

    init(_ family: Family, _ weight: Float, _ italic: Bool) {
        self.family = family
        self.weightBits = hashBits(weight)
        self.italic = italic
    }
}

// PORT NOTE: Immutable parsed face metadata; `ctDescriptor` on Apple platforms is an immutable
// CoreText descriptor created from in-memory font bytes (`CTFontManagerCreateFontDescriptorsFromData`).
struct RegisteredFontFace: @unchecked Sendable {
    let fontId: UInt64
    let index: UInt32
    let familyName: String
    let familyLower: String
    let postScriptName: String
    let weight: Float
    let italic: Bool
    let fvar: SfntFvar?
    let sfnt: SfntFont
    #if canImport(CoreText) && canImport(CoreGraphics)
    let ctDescriptor: CTFontDescriptor?
    #endif
}

private func fnvFontBlobId(_ bytes: [UInt8], index: UInt32) -> UInt64 {
    var h = KeyHasher()
    h.u64(UInt64(bytes.count))
    h.u32(index)
    bytes.withUnsafeBufferPointer { h.bytes($0) }
    return h.hash == 0 ? 1 : h.hash
}

private func fnvStringId(_ s: String) -> UInt64 {
    var h = KeyHasher()
    h.str(s)
    return h.hash == 0 ? 1 : h.hash
}

func parseCssVariations(_ css: String) -> [(UInt32, Float)] {
    guard !css.isEmpty else { return [] }
    var out: [(UInt32, Float)] = []
    for part in css.split(separator: ",") {
        let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        let pieces = trimmed.split(whereSeparator: { $0.isWhitespace })
        guard pieces.count >= 2 else { continue }
        let rawTag = pieces[0].trimmingCharacters(in: CharacterSetQuotes.set)
        guard let tag = SfntTag.fromString(rawTag),
              let val = Float(pieces[1])
        else { continue }
        if let idx = out.firstIndex(where: { $0.0 == tag }) {
            out[idx] = (tag, val)
        } else {
            out.append((tag, val))
        }
    }
    return out
}

func parseCssFeatures(_ css: String) -> [(UInt32, Int32)] {
    guard !css.isEmpty else { return [] }
    var out: [(UInt32, Int32)] = []
    for part in css.split(separator: ",") {
        let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        let pieces = trimmed.split(whereSeparator: { $0.isWhitespace })
        guard let first = pieces.first else { continue }
        let rawTag = first.trimmingCharacters(in: CharacterSetQuotes.set)
        guard let tag = SfntTag.fromString(rawTag) else { continue }
        let value: Int32
        if pieces.count == 1 {
            value = 1
        } else {
            let vStr = pieces[1].lowercased()
            if vStr == "on" {
                value = 1
            } else if vStr == "off" {
                value = 0
            } else if let n = Int32(vStr) {
                value = n
            } else {
                continue
            }
        }
        out.append((tag, value))
    }
    return out
}

func effectiveVariations(_ style: TextStyle, _ size: Float) -> [(UInt32, Float)] {
    var settings = parseCssVariations(style.variations)
    let opsz = SfntTag.opsz
    let value: Float?
    switch style.opticalSize {
    case .auto:
        if !settings.contains(where: { $0.0 == opsz }) {
            value = size
        } else {
            value = nil
        }
    case .fixed(let v):
        settings.removeAll { $0.0 == opsz }
        value = v
    case .fontDefault:
        value = nil
    }
    if let v = value, v.isFinite, v > 0.0 {
        settings.append((opsz, v))
    }
    return settings
}

private enum CharacterSetQuotes {
    static let chars: [Character] = ["\"", "'", " ", "\t", "\r", "\n"]
    static var set: [Character] { ["\"", "'"] }
}

private extension Substring {
    func trimmingCharacters(in chars: [Character]) -> String {
        var sub = self
        while let f = sub.first, chars.contains(f) { sub = sub.dropFirst() }
        while let l = sub.last, chars.contains(l) { sub = sub.dropLast() }
        return String(sub)
    }

    func trimmingCharacters(in _: Void) -> String {
        String(self)
    }
}

private extension String {
    func trimmingCharacters(in chars: [Character]) -> String {
        Substring(self).trimmingCharacters(in: chars)
    }
}

private func fourCharString(_ tag: UInt32) -> String {
    let b0 = UInt8((tag >> 24) & 0xFF)
    let b1 = UInt8((tag >> 16) & 0xFF)
    let b2 = UInt8((tag >> 8) & 0xFF)
    let b3 = UInt8(tag & 0xFF)
    return String(bytes: [b0, b1, b2, b3], encoding: .ascii) ?? "    "
}

private func isSoftBreakScalar(_ v: UInt32) -> Bool {
    switch v {
    case 0x20, 0x09, 0x2D, 0xAD, 0x200B, 0x2010, 0x2013, 0x2014:
        return true
    case 0x2E80...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0x3040...0x30FF, 0xFF00...0xFFEF:
        return true
    default:
        return false
    }
}

private func isDefaultEmojiScalar(_ v: UInt32) -> Bool {
    switch v {
    case 0x1F1E6...0x1F1FF,
         0x1F300...0x1F5FF,
         0x1F600...0x1F64F,
         0x1F680...0x1F6FF,
         0x1F900...0x1F9FF,
         0x1FA70...0x1FAFF,
         0x2614...0x2615,
         0x2648...0x2653,
         0x267F, 0x2693, 0x26A1, 0x26AA...0x26AB,
         0x26BD...0x26BE, 0x26C4...0x26C5, 0x26CE, 0x26D4, 0x26EA,
         0x26F2...0x26F3, 0x26F5, 0x26FA, 0x26FD,
         0x2705, 0x270A...0x270B, 0x2728, 0x274C, 0x274E,
         0x2753...0x2755, 0x2757, 0x2795...0x2797, 0x27B0, 0x27BF,
         0x2B1B...0x2B1C, 0x2B50, 0x2B55:
        return true
    default:
        return false
    }
}

private func graphemeWantsDefaultEmoji(_ ch: Character) -> Bool {
    if ch.unicodeScalars.contains("\u{FE0E}") { return false }
    if ch.unicodeScalars.contains("\u{FE0F}") || ch.unicodeScalars.contains("\u{200D}") { return true }
    for sc in ch.unicodeScalars where isDefaultEmojiScalar(sc.value) {
        return true
    }
    return false
}

// MARK: - TextSystem

public final class TextSystem {
    public var sans: String
    public var mono: String
    public var atlas: Atlas
    /// Layouts shaped, a running count (shaping work counter for perf gates).
    public var shaped: UInt32 = 0
    /// Layouts re-broken at a new width from an earlier shaping, a running count.
    public var rebroken: UInt32 = 0

    var smoothing: FontSmoothing
    var smoothingState: Smoothing
    var glide: [Float] = [0.0, 0.0]

    var layouts: [UInt64: LayoutCacheEntry<TextLayout>] = [:]
    var shapes: [UInt64: UInt64] = [:]
    var superseded: Set<UInt64> = []
    var runs: [UInt64: LayoutCacheEntry<RunLayout>] = [:]
    var generation: UInt32 = 0

    var chosenFamiliesPair: (String, String)
    var chosenEpoch: UInt64 = 0
    var slotSystemMono: Bool
    var sansCandidates: [String] = []
    var monoCandidates: [String] = []
    var systemMonoList: [String]? = nil

    var scriptsMask: UInt64 = 0
    var mathFamiliesLoaded: [String]? = nil
    var emojiFamilyName: String? = nil
    var symbolFamiliesLoaded: [String] = []

    var colorGlyphs: [GlyphKey: ColorGlyph] = [:]
    var colorPixels: [Pixels] = []
    var colorBytes: Int = 0
    var glyphCache = GlyphCache()
    var clusterScratch: [(Float, UInt32)] = []

    var traks: Traks = [:]
    var primaryTraks: [PrimaryFontCacheKey: Trak?] = [:]
    var primaryAxes: [PrimaryFontCacheKey: [VariationAxisSetting]] = [:]

    var registeredFaces: [RegisteredFontFace] = []
    private var systemSfntFaces: [RegisteredFontFace] = []
    private var scannedNonAppleSystemFonts: Bool = false

    public convenience init() {
        self.init([], ("Inter", "Inter"))
    }

    public init(_ fonts: [[UInt8]] = [], _ families: (String, String) = ("Inter", "Inter")) {
        noteMeasureFonts(fonts, families)
        let effectiveFamilies: (String, String)
        #if os(WASI)
        effectiveFamilies = fonts.isEmpty ? ("Inter", "IBM Plex Mono") : families
        #else
        effectiveFamilies = families
        #endif

        let resolvedSlots = slots(effectiveFamilies.0, effectiveFamilies.1)
        self.chosenFamiliesPair = effectiveFamilies
        self.sans = resolvedSlots.0
        self.mono = resolvedSlots.1
        self.slotSystemMono = namesSystemMono(effectiveFamilies.0) || namesSystemMono(effectiveFamilies.1)
        self.atlas = Atlas()
        let defaultSmoothing = FontSmoothing.default
        self.smoothing = defaultSmoothing
        self.smoothingState = Smoothing(pipeline: defaultSmoothing.pipeline())

        let blobs = fonts.isEmpty ? defaultFontBlobs() : fonts
        for blob in blobs {
            registerBlob(blob, into: &self.registeredFaces)
        }

        // Discover symbol & emoji families available on the platform.
        #if canImport(CoreText) && canImport(CoreGraphics)
        for sym in SYMBOL_FAMILIES where AppleFontFamilyCache.shared.has(sym) {
            self.symbolFamiliesLoaded.append(sym)
        }
        #elseif !os(WASI)
        let symPaths = systemFontFiles(SYMBOL_FONT_FILES)
        for path in symPaths.prefix(8) {
            loadSystemFontFile(path)
        }
        for sym in SYMBOL_FAMILIES where hasFamily(sym) {
            self.symbolFamiliesLoaded.append(sym)
        }
        #endif
        self.emojiFamilyName = self.symbolFamiliesLoaded.first(where: { $0.contains("Emoji") })

        let sysMono = slotSystemMono ? resolvedSystemMono() : []
        let picked = chooseFamiliesList(
            requested: resolvedSlots,
            systemMono: sysMono,
            hasFamily: { [self] name in
                Self.checkHasFamily(name, registeredFaces: self.registeredFaces, systemSfntFaces: self.systemSfntFaces)
            }
        )
        self.sansCandidates = picked.0
        self.monoCandidates = picked.1
    }

    private func registerBlob(_ blob: [UInt8], into list: inout [RegisteredFontFace]) {
        let count = SfntFont.faceCount(in: blob)
        guard count > 0 else { return }
        #if canImport(CoreText) && canImport(CoreGraphics)
        let cfData = Data(blob) as CFData
        let descriptors = (CTFontManagerCreateFontDescriptorsFromData(cfData) as? [CTFontDescriptor]) ?? []
        #endif
        for idx in 0..<count {
            guard let sfnt = SfntFont(data: blob, index: idx) else { continue }
            let fam = sfnt.familyName() ?? sfnt.fullName() ?? "Unknown"
            let ps = sfnt.postScriptName() ?? fam
            let (wU16, isItalic) = sfnt.os2WeightAndItalic()
            let fvar = sfnt.parseFvar()
            let fId = fnvFontBlobId(blob, index: UInt32(idx))
            #if canImport(CoreText) && canImport(CoreGraphics)
            let desc: CTFontDescriptor? = (idx < descriptors.count) ? descriptors[idx] : nil
            list.append(RegisteredFontFace(
                fontId: fId,
                index: UInt32(idx),
                familyName: fam,
                familyLower: fam.lowercased(),
                postScriptName: ps,
                weight: Float(wU16),
                italic: isItalic,
                fvar: fvar,
                sfnt: sfnt,
                ctDescriptor: desc
            ))
            #else
            list.append(RegisteredFontFace(
                fontId: fId,
                index: UInt32(idx),
                familyName: fam,
                familyLower: fam.lowercased(),
                postScriptName: ps,
                weight: Float(wU16),
                italic: isItalic,
                fvar: fvar,
                sfnt: sfnt
            ))
            #endif
        }
    }

    #if !os(WASI) && !(canImport(CoreText) && canImport(CoreGraphics))
    private func loadSystemFontFile(_ path: String) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), !data.isEmpty else { return }
        registerBlob([UInt8](data), into: &systemSfntFaces)
    }

    private func ensureNonAppleSystemFontsLoaded() {
        guard !scannedNonAppleSystemFonts else { return }
        scannedNonAppleSystemFonts = true
        let commonFragments = ["inter", "ibmplexmono", "dejavusans", "liberationsans", "liberationmono", "notosans", "roboto", "segoeui", "consola", "cascadia"]
        for path in systemFontFiles(commonFragments).prefix(24) {
            loadSystemFontFile(path)
        }
    }
    #endif

#if canImport(CoreText) && canImport(CoreGraphics)
// PORT NOTE: Synchronized via `LiveLock`; memoizes system font family probes across `TextSystem` instances
// so concurrent cooperative tasks do not saturate CoreText's synchronous `XTypeXPCClient` XPC channel.
private final class AppleFontFamilyCache: @unchecked Sendable {
    static let shared = AppleFontFamilyCache()
    private let lock = LiveLock()
    private var familyExists: [String: Bool] = [:]

    func has(_ name: String) -> Bool {
        let key = name.lowercased()
        return lock.withLock {
            if let hit = familyExists[key] {
                return hit
            }
            let result = Self.probe(name)
            familyExists[key] = result
            return result
        }
    }

    func withCoreTextQuery<T>(_ body: () -> T) -> T {
        lock.withLock(body)
    }

    private static func probe(_ name: String) -> Bool {
        if name == "System Font" || name == ".SF NS" {
            return CTFontCreateUIFontForLanguage(.system, 13.0, nil) != nil
        }
        if name == ".SF NS Mono" {
            return !systemFontFiles(["sfnsmono"]).isEmpty || CTFontCreateUIFontForLanguage(.userFixedPitch, 13.0, nil) != nil
        }
        let attrs: [CFString: Any] = [kCTFontFamilyNameAttribute: name]
        let desc = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
        guard let matched = CTFontDescriptorCreateMatchingFontDescriptor(desc, Set([kCTFontFamilyNameAttribute]) as CFSet) else {
            return false
        }
        let foundFam = (CTFontDescriptorCopyAttribute(matched, kCTFontFamilyNameAttribute) as? String) ?? ""
        return foundFam.caseInsensitiveCompare(name) == .orderedSame
    }
}

    private static func appleHasSystemFamily(_ name: String) -> Bool {
        AppleFontFamilyCache.shared.has(name)
    }
#endif

    private static func checkHasFamily(
        _ name: String,
        registeredFaces: [RegisteredFontFace],
        systemSfntFaces: [RegisteredFontFace]
    ) -> Bool {
        let lower = name.lowercased()
        if registeredFaces.contains(where: { $0.familyLower == lower }) {
            return true
        }
        if systemSfntFaces.contains(where: { $0.familyLower == lower }) {
            return true
        }
        #if canImport(CoreText) && canImport(CoreGraphics)
        return AppleFontFamilyCache.shared.has(name)
        #else
        return false
        #endif
    }

    func hasFamily(_ name: String) -> Bool {
        #if !os(WASI) && !(canImport(CoreText) && canImport(CoreGraphics))
        ensureNonAppleSystemFontsLoaded()
        #endif
        return Self.checkHasFamily(name, registeredFaces: registeredFaces, systemSfntFaces: systemSfntFaces)
    }

    func hasItalicFace(forFamily name: String) -> Bool {
        guard hasFamily(name) else { return false }
        let lower = name.lowercased()
        if registeredFaces.contains(where: { $0.familyLower == lower && $0.italic }) {
            return true
        }
        #if canImport(CoreText) && canImport(CoreGraphics)
        return AppleFontFamilyCache.shared.has(name)
        #else
        return systemSfntFaces.contains(where: { $0.familyLower == lower && $0.italic })
        #endif
    }

    func systemMono() -> [String] {
        if let existing = systemMonoList {
            return existing
        }
        var names: [String] = []
        #if !os(WASI) && !(canImport(CoreText) && canImport(CoreGraphics))
        for path in systemFontFiles(SYSTEM_MONO_FILES).prefix(12) {
            loadSystemFontFile(path)
        }
        #endif
        for candidate in SYSTEM_MONO_FAMILIES where hasFamily(candidate) {
            if !names.contains(candidate) {
                names.append(candidate)
            }
        }
        systemMonoList = names
        return names
    }

    func resolvedSystemMono() -> [String] {
        systemMono()
    }

    private func candidateFamilyNames(for family: Family) -> [String] {
        if family == .systemMono || slotSystemMono {
            _ = systemMono()
        }
        let sys = systemMonoList ?? []
        let namedFromList = { [sans] (list: String) -> [String] in
            parsedFamilyList(list, sys, sans).compactMap { $0.namedValue }
        }
        switch family {
        case .sans:
            return namedFromList(sans)
        case .mono:
            return namedFromList(mono)
        case .named(let name):
            return [name] + namedFromList(sans)
        case .systemMono:
            return sys + namedFromList(mono)
        }
    }

    private func matchRegisteredFace(in pool: [RegisteredFontFace], familyName: String, weight: Float, italic: Bool) -> (RegisteredFontFace, Bool)? {
        let lower = familyName.lowercased()
        let candidates = pool.filter { $0.familyLower == lower }
        guard !candidates.isEmpty else { return nil }
        let exactStyle = candidates.filter { $0.italic == italic }
        let usedPool: [RegisteredFontFace]
        let syntheticOblique: Bool
        if !exactStyle.isEmpty {
            usedPool = exactStyle
            syntheticOblique = false
        } else {
            usedPool = candidates
            syntheticOblique = italic
        }
        let best = usedPool.min { a, b in
            let aHasWght = a.fvar?.axes.contains(where: { $0.tag == SfntTag.wght }) ?? false
            let bHasWght = b.fvar?.axes.contains(where: { $0.tag == SfntTag.wght }) ?? false
            let da: Float = aHasWght ? 0.0 : abs(a.weight - weight)
            let db: Float = bHasWght ? 0.0 : abs(b.weight - weight)
            if abs(da - db) > 0.01 { return da < db }
            return a.index < b.index
        }!
        return (best, syntheticOblique)
    }

    func primaryTrak(_ family: Family, _ weight: Float, _ italic: Bool) -> Trak? {
        let key = PrimaryFontCacheKey(family, weight, italic)
        if let cached = primaryTraks[key] {
            return cached
        }
        let names = candidateFamilyNames(for: family)
        var resolved: Trak? = nil
        for name in names {
            if let (reg, _) = matchRegisteredFace(in: registeredFaces, familyName: name, weight: weight, italic: italic) {
                resolved = fontTrak(&traks, reg.fontId, reg.sfnt.data, reg.index)
                break
            }
            #if canImport(CoreText) && canImport(CoreGraphics)
            if hasFamily(name) {
                resolved = appleFontTrak(familyName: name, weight: weight, italic: italic)
                break
            }
            #else
            if let (sysFace, _) = matchRegisteredFace(in: systemSfntFaces, familyName: name, weight: weight, italic: italic) {
                resolved = fontTrak(&traks, sysFace.fontId, sysFace.sfnt.data, sysFace.index)
                break
            }
            #endif
        }
        primaryTraks[key] = .some(resolved)
        return resolved
    }

    #if canImport(CoreText) && canImport(CoreGraphics)
    private func appleFontTrak(familyName: String, weight: Float, italic: Bool) -> Trak? {
        guard let ct = makeAppleCTFont(
            familyName: familyName,
            ptSize: 14.0,
            weight: weight,
            italic: italic,
            variations: [],
            features: [],
            isMono: false
        )?.0 else {
            return nil
        }
        return ctFontTrak(ct)
    }

    private func ctFontTrak(_ ctFont: CTFont) -> Trak? {
        let psName = (CTFontCopyPostScriptName(ctFont) as String)
        let fId = fnvStringId(psName)
        let key = FontBlobKey(fId, 0)
        if let cached = traks[key] {
            return cached
        }
        guard let statData = CTFontCopyTable(ctFont, CTFontTableTag(SfntTag.STAT), []) as Data?,
              !statData.isEmpty,
              let trakData = CTFontCopyTable(ctFont, CTFontTableTag(SfntTag.trak), []) as Data?,
              !trakData.isEmpty
        else {
            traks[key] = .some(nil)
            return nil
        }
        let upem = UInt16(clamping: CTFontGetUnitsPerEm(ctFont))
        let parsed = Trak.parse([UInt8](trakData), upem)
        traks[key] = .some(parsed)
        return parsed
    }
    #endif

    // MARK: - Public Controls & Frame Lifecycle

    /// The RGBA image of a colour glyph quad (`GlyphQuad.color`, nonzero).
    public func colorGlyph(_ color: UInt32) -> Pixels {
        colorPixels[Int(color) - 1]
    }

    /// The colours the next glyphs draw in (`spans` by `Ink`). On macOS they choose each
    /// glyph's dilation, so glyphs in light and dark inks rasterize separately.
    public func setGlyphInks(_ element: Color, _ spans: [Span]) {
        smoothingState.setInks(element, spans)
    }

    /// How glyphs rasterise and place (`FontSmoothing`).
    public func fontSmoothing() -> FontSmoothing {
        smoothing
    }

    /// Rasterise and place glyphs in `mode` from the next placement on, with its CoreGraphics
    /// stages (`FontSmoothing.pipeline`). Glyphs already rasterised in another mode stay cached
    /// under their own keys.
    public func setFontSmoothing(_ mode: FontSmoothing) {
        smoothing = mode
        smoothingState.setPipeline(mode.pipeline())
    }

    /// The CoreGraphics stages glyphs rasterize with.
    public func applePipeline() -> ApplePipeline {
        smoothingState.pipeline
    }

    /// Overrides the stages `setFontSmoothing` chose, until the next call to it.
    public func setApplePipeline(_ pipeline: ApplePipeline) {
        smoothingState.setPipeline(pipeline)
    }

    /// Begins a new batch of glyph placements, reclaiming unused atlas storage.
    public func beginFrame() {
        beginFramePinned(0)
    }

    func beginFramePinned(_ pinnedMask: UInt32) {
        atlas.beginFrame(pinnedMask)
        glyphCache.beginFrame()
        if colorBytes > COLOR_GLYPH_BUDGET {
            let before = colorGlyphs.count
            colorGlyphs = colorGlyphs.filter { $0.value.used }
            if colorGlyphs.count != before {
                let old = colorPixels
                colorPixels = []
                colorBytes = 0
                for k in colorGlyphs.keys {
                    guard var c = colorGlyphs[k] else { continue }
                    colorPixels.append(old[Int(c.index) - 1])
                    c.index = UInt32(colorPixels.count)
                    colorBytes += Int(c.w) * Int(c.h) * 4
                    colorGlyphs[k] = c
                }
            }
        }
        for k in colorGlyphs.keys {
            colorGlyphs[k]?.used = false
        }
    }

    /// Size in points, rounded up to whole device pixels so layout stays on the pixel grid.
    public func measure(_ text: String, _ style: TextStyle, _ scale: Float) -> (Float, Float) {
        let l = layoutRich(text, [], style, scale, nil)
        return (l.fullWidth().rounded(.up) / scale, layoutHeight(l, style, scale) / scale)
    }

    /// The atlas quad for `icon` at `px` device pixels square, top-left at `origin`.
    public func iconQuad(_ icon: Icon, _ px: UInt32, _ origin: [Float]) -> GlyphQuad? {
        let ox = origin.count > 0 ? origin[0] : 0.0
        let oy = origin.count > 1 ? origin[1] : 0.0
        let key = IconCacheKey(icon, px)
        let entry: AtlasGlyph?
        if let cached = atlas.icons[key] {
            if let a = cached {
                atlas.touch(a.page, a.w * a.h)
            }
            entry = cached
        } else {
            switch rasterizeIcon(icon, px, &atlas) {
            case .placed(let g):
                atlas.icons[key] = .some(g)
                entry = g
            case .empty:
                atlas.icons[key] = .some(nil)
                entry = nil
            case .unplaced:
                entry = nil
            }
        }
        guard let a = entry else { return nil }
        return GlyphQuad(
            rect: [ox, oy, Float(px), Float(px)],
            uv: [Float(a.x + 1), Float(UInt32(a.page) * ATLAS_SIZE + a.y + 1)],
            ink: 0,
            byte: 0,
            color: 0
        )
    }

    // MARK: - Paragraph Shaping

    private struct StyleSlice {
        var byteRange: Range<Int>
        var ink: Ink
        var family: Family
        var isMono: Bool
        var sizePt: Float
        var lineHeightPx: Float
        var weight: Float
        var italic: Bool
        var route: Route?
    }

    func shapeParagraph(
        text: String,
        spans: [Span],
        pills: [PillChip],
        style: TextStyle,
        scale: Float
    ) -> TextLayout {
        let byteLen = text.utf8.count
        let utf8 = Array(text.utf8)

        // Validate pills and build lead/trail inline boxes (`PILL_BOX | (i << 1) | side`).
        let pm = PillMetrics(style.size)
        var inlineBoxes: [LayoutInlineBox] = []
        var validPillRanges: [(Int, Int)] = []
        for (i, p) in pills.enumerated() {
            let s = min(Int(p.start), byteLen)
            let e = min(Int(p.end), byteLen)
            guard s < e,
                  isUtf8ScalarBoundary(utf8, s),
                  isUtf8ScalarBoundary(utf8, e),
                  !utf8[s..<e].contains(UInt8(ascii: "\n"))
            else { continue }
            let lead = Float((pm.lead(p.icon != nil) * scale).rounded(.toNearestOrAwayFromZero))
            let trail = Float((pm.trail() * scale).rounded(.toNearestOrAwayFromZero))
            inlineBoxes.append(LayoutInlineBox(
                id: PILL_BOX | (UInt64(i) << 1) | 0,
                index: s,
                width: max(0.0, lead),
                height: 0.0
            ))
            inlineBoxes.append(LayoutInlineBox(
                id: PILL_BOX | (UInt64(i) << 1) | 1,
                index: e,
                width: max(0.0, trail),
                height: 0.0
            ))
            validPillRanges.append((s, e))
        }

        // Determine paragraph base direction (first strong directional scalar).
        var baseIsRtl = false
        for sc in text.unicodeScalars {
            if isRtlScalar(sc) {
                baseIsRtl = true
                break
            } else if (sc.value >= 0x41 && sc.value <= 0x5A) ||
                      (sc.value >= 0x61 && sc.value <= 0x7A) ||
                      (sc.value >= 0x00C0 && sc.value <= 0x02AF)
            {
                baseIsRtl = false
                break
            }
        }

        if byteLen == 0 {
            return TextLayout(
                text: text,
                scale: scale,
                baseStyle: style,
                isRtl: baseIsRtl,
                shapedRuns: [],
                inlineBoxesData: inlineBoxes,
                pillRanges: validPillRanges
            )
        }

        // Lazy script and math fallback discovery matching upstream `text.rs` lines 501-520.
        var isAsciiOnly = true
        for b in utf8 where b >= 0x80 {
            isAsciiOnly = false
            break
        }
        if !isAsciiOnly {
            var newScripts: UInt64 = 0
            var wantsSymbols = false
            for sc in text.unicodeScalars {
                for (i, sf) in SCRIPT_FONTS.enumerated() {
                    if ((scriptsMask | newScripts) & (1 << UInt64(i))) == 0 && sf.covers(sc) {
                        newScripts |= (1 << UInt64(i))
                    }
                }
                if mathFamiliesLoaded == nil && needsSymbols(sc) {
                    wantsSymbols = true
                }
            }
            if newScripts != 0 {
                scriptsMask |= newScripts
                #if !os(WASI) && !(canImport(CoreText) && canImport(CoreGraphics))
                for (i, sf) in SCRIPT_FONTS.enumerated() where (newScripts & (1 << UInt64(i))) != 0 {
                    for path in systemFontFiles(sf.files).prefix(4) {
                        loadSystemFontFile(path)
                    }
                }
                #endif
            }
            if wantsSymbols {
                #if !os(WASI) && !(canImport(CoreText) && canImport(CoreGraphics))
                for path in systemFontFiles(MATH_FONT_FILES).prefix(4) {
                    loadSystemFontFile(path)
                }
                #endif
                var loadedMath: [String] = []
                for mf in MATH_FAMILIES where hasFamily(mf) {
                    loadedMath.append(mf)
                }
                mathFamiliesLoaded = loadedMath
            }
        }

        let routeRanges = routes(text)
        let baseMono = (style.family == .mono || style.family == .systemMono)
        let baseLH = style.linePx() * scale
        let baseRatio = (style.size > 0.0) ? (style.linePx() / style.size) : 1.25

        // Build non-overlapping style slices across `[0, byteLen)` at span, route, and newline boundaries.
        var boundaries: [Int] = [0, byteLen]
        for sp in spans {
            let s = min(Int(sp.start), byteLen)
            let e = min(Int(sp.end), byteLen)
            if s < e {
                boundaries.append(s)
                boundaries.append(e)
            }
        }
        for (r, _) in routeRanges {
            boundaries.append(r.lowerBound)
            boundaries.append(r.upperBound)
        }
        for i in 0..<byteLen where utf8[i] == UInt8(ascii: "\n") {
            boundaries.append(i)
            boundaries.append(i + 1)
        }
        // Keep pill box boundaries crisp so runs split cleanly around inline boxes when needed.
        for (ps, pe) in validPillRanges {
            boundaries.append(ps)
            boundaries.append(pe)
        }
        boundaries.sort()
        var uniqueBounds: [Int] = []
        uniqueBounds.reserveCapacity(boundaries.count)
        for b in boundaries where isUtf8ScalarBoundary(utf8, b) {
            if uniqueBounds.last != b {
                uniqueBounds.append(b)
            }
        }
        if uniqueBounds.first != 0 { uniqueBounds.insert(0, at: 0) }
        if uniqueBounds.last != byteLen { uniqueBounds.append(byteLen) }

        var slices: [StyleSlice] = []
        slices.reserveCapacity(max(1, uniqueBounds.count - 1))
        for k in 0..<(uniqueBounds.count - 1) {
            let lo = uniqueBounds[k]
            let hi = uniqueBounds[k + 1]
            guard lo < hi else { continue }
            var ink = Ink(0)
            var fam = style.family
            var isMono = baseMono
            var sz = style.size
            var lhPx = baseLH
            var wt = style.weight
            var it = style.italic
            for (i, sp) in spans.enumerated() {
                let s = min(Int(sp.start), byteLen)
                let e = min(Int(sp.end), byteLen)
                guard s < e, s <= lo, hi <= e else { continue }
                ink = Ink(UInt16(clamping: i + 1))
                if sp.mono {
                    fam = .mono
                    isMono = true
                }
                if let w = sp.weight { wt = w }
                if sp.italic { it = true }
                if let customSz = sp.size {
                    sz = customSz
                    lhPx = customSz * baseRatio * scale
                }
            }
            let activeRoute = routeRanges.first(where: { $0.0.lowerBound <= lo && hi <= $0.0.upperBound })?.1
            slices.append(StyleSlice(
                byteRange: lo..<hi,
                ink: ink,
                family: fam,
                isMono: isMono,
                sizePt: sz,
                lineHeightPx: lhPx,
                weight: wt,
                italic: it,
                route: activeRoute
            ))
        }

        // Parse features once for the paragraph style (`'trak'` handled separately, matching `text.rs`).
        let parsedFeatures = parseCssFeatures(style.features)
        let trakTag = SfntTag.trak
        let tracked = parsedFeatures.last(where: { $0.0 == trakTag }).map { $0.1 != 0 } ?? true
        let activeFeatures = parsedFeatures.filter { $0.0 != trakTag }
        let opticalFixed: Float? = {
            if case .fixed(let o) = style.opticalSize, o.isFinite, o > 0.0, style.size > 0.0 {
                return o
            }
            return nil
        }()

        // Replace `\t` (1 byte) with `" "` (1 byte) for shaping while remembering exact tab bytes.
        let shapedText = text.contains("\t") ? text.replacingOccurrences(of: "\t", with: " ") : text

        var shapedRuns: [ShapedRun] = []
        for sl in slices {
            let subStart = shapedText.utf8.index(shapedText.utf8.startIndex, offsetBy: sl.byteRange.lowerBound)
            let subEnd = shapedText.utf8.index(shapedText.utf8.startIndex, offsetBy: sl.byteRange.upperBound)
            let subStr = String(shapedText[subStart..<subEnd])

            if sl.byteRange.count == 1 && utf8[sl.byteRange.lowerBound] == UInt8(ascii: "\n") {
                let nlRun = makeNewlineRun(
                    byteRange: sl.byteRange,
                    style: style,
                    slice: sl,
                    scale: scale,
                    isRtl: baseIsRtl
                )
                shapedRuns.append(nlRun)
                continue
            }

            let runsForSlice = shapeSlice(
                subStr: subStr,
                originalUtf8: utf8,
                slice: sl,
                style: style,
                scale: scale,
                tracked: tracked,
                opticalFixed: opticalFixed,
                activeFeatures: activeFeatures
            )
            shapedRuns.append(contentsOf: runsForSlice)
        }

        return TextLayout(
            text: text,
            scale: scale,
            baseStyle: style,
            isRtl: baseIsRtl,
            shapedRuns: shapedRuns,
            inlineBoxesData: inlineBoxes,
            pillRanges: validPillRanges
        )
    }

    private func isUtf8ScalarBoundary(_ utf8: [UInt8], _ index: Int) -> Bool {
        if index <= 0 || index >= utf8.count {
            return index == 0 || index == utf8.count
        }
        return (utf8[index] & 0xC0) != 0x80
    }

    private func makeNewlineRun(
        byteRange: Range<Int>,
        style: TextStyle,
        slice: StyleSlice,
        scale: Float,
        isRtl: Bool
    ) -> ShapedRun {
        let resolved = resolveFontFaceForRun(
            family: slice.family,
            isMono: slice.isMono,
            sizePt: slice.sizePt,
            weight: slice.weight,
            italic: slice.italic,
            style: style,
            opticalFixed: nil,
            activeFeatures: [],
            route: nil,
            sampleGrapheme: nil
        )
        let metrics = computeLayoutMetrics(face: resolved, sizePt: slice.sizePt, scale: scale)
        let cluster = LayoutCluster(
            textRange: byteRange,
            advance: 0.0,
            isHangingWhitespace: true,
            isWordSpace: false,
            isTab: false,
            isSoftBreakAfter: false,
            isHardBreak: true,
            isRtl: isRtl,
            glyphRange: 0..<0
        )
        return ShapedRun(
            font: resolved,
            fontSize: slice.sizePt * scale,
            lineHeightPx: slice.lineHeightPx,
            fontMetrics: metrics,
            ink: slice.ink,
            textRange: byteRange,
            isRtl: isRtl,
            isMono: slice.isMono,
            monoSpaceAdvance: 0.0,
            clusters: [cluster],
            glyphs: []
        )
    }

    private func shapeSlice(
        subStr: String,
        originalUtf8: [UInt8],
        slice: StyleSlice,
        style: TextStyle,
        scale: Float,
        tracked: Bool,
        opticalFixed: Float?,
        activeFeatures: [(UInt32, Int32)]
    ) -> [ShapedRun] {
        // Partition `subStr` into contiguous sub-runs sharing the same resolved `ShapedFontFace` and direction.
        var segments: [(Range<Int>, String, ShapedFontFace, Bool)] = []
        var curByte = slice.byteRange.lowerBound
        var segStartByte = curByte
        var segText = ""
        var segFace: ShapedFontFace? = nil
        var segRtl = false

        for ch in subStr {
            let chBytes = ch.utf8.count
            let chRoute: Route?
            if let r = slice.route {
                chRoute = r
            } else if emojiFamilyName != nil && graphemeWantsDefaultEmoji(ch) {
                chRoute = .emoji
            } else {
                chRoute = nil
            }
            let chRtl = ch.unicodeScalars.contains(where: { isRtlScalar($0) })
            let face = resolveFontFaceForRun(
                family: slice.family,
                isMono: slice.isMono,
                sizePt: slice.sizePt,
                weight: slice.weight,
                italic: slice.italic,
                style: style,
                opticalFixed: opticalFixed,
                activeFeatures: activeFeatures,
                route: chRoute,
                sampleGrapheme: ch
            )
            if let prevFace = segFace,
               prevFace.fontId == face.fontId,
               prevFace.index == face.index,
               prevFace.coordsHash == face.coordsHash,
               prevFace.skew == face.skew,
               segRtl == chRtl
            {
                segText.append(ch)
            } else {
                if let prevFace = segFace, !segText.isEmpty {
                    segments.append((segStartByte..<curByte, segText, prevFace, segRtl))
                }
                segStartByte = curByte
                segText = String(ch)
                segFace = face
                segRtl = chRtl
            }
            curByte += chBytes
        }
        if let lastFace = segFace, !segText.isEmpty {
            segments.append((segStartByte..<curByte, segText, lastFace, segRtl))
        }

        var out: [ShapedRun] = []
        out.reserveCapacity(segments.count)
        for (bRange, runText, face, isRtl) in segments {
            out.append(shapeResolvedSegment(
                runText: runText,
                byteRange: bRange,
                originalUtf8: originalUtf8,
                face: face,
                slice: slice,
                style: style,
                scale: scale,
                tracked: tracked,
                opticalFixed: opticalFixed,
                activeFeatures: activeFeatures,
                isRtl: isRtl
            ))
        }
        return out
    }

    // MARK: - Font Face Resolution

    private func resolveFontFaceForRun(
        family: Family,
        isMono: Bool,
        sizePt: Float,
        weight: Float,
        italic: Bool,
        style: TextStyle,
        opticalFixed: Float?,
        activeFeatures: [(UInt32, Int32)],
        route: Route?,
        sampleGrapheme: Character?
    ) -> ShapedFontFace {
        var candidates: [String] = []
        if route == .emoji, let emoji = emojiFamilyName {
            candidates.append(emoji)
        } else if route == .math, let mathList = mathFamiliesLoaded {
            candidates.append(contentsOf: mathList)
        }
        candidates.append(contentsOf: candidateFamilyNames(for: family))

        // Append script / CJK / symbol fallbacks when shaping a concrete grapheme.
        if let ch = sampleGrapheme {
            let scalars = Array(ch.unicodeScalars)
            let nonAscii = scalars.contains { $0.value >= 0x80 }
            if nonAscii {
                #if canImport(CoreText) && canImport(CoreGraphics)
                if scalars.contains(where: { (0xAC00...0xD7AF).contains($0.value) || (0x1100...0x11FF).contains($0.value) }) {
                    candidates.append(contentsOf: ["Apple SD Gothic Neo", "AppleGothic"])
                } else if scalars.contains(where: { (0x3040...0x30FF).contains($0.value) }) {
                    candidates.append(contentsOf: ["Hiragino Sans", "Hiragino Kaku Gothic ProN"])
                } else if scalars.contains(where: { (0x3400...0x9FFF).contains($0.value) || (0xF900...0xFAFF).contains($0.value) }) {
                    candidates.append(contentsOf: ["PingFang SC", "Hiragino Sans GB", "Heiti SC", "STHeiti", "Arial Unicode MS"])
                }
                if scalars.contains(where: { (0x0590...0x05FF).contains($0.value) || (0xFB1D...0xFB4F).contains($0.value) }) {
                    candidates.append(contentsOf: ["SF Hebrew", "Arial Hebrew"])
                }
                if scalars.contains(where: { (0x0600...0x06FF).contains($0.value) || (0xFB50...0xFDFF).contains($0.value) || (0xFE70...0xFEFF).contains($0.value) }) {
                    candidates.append(contentsOf: ["SF Arabic", "Geeza Pro"])
                }
                if scalars.contains(where: { (0x0900...0x097F).contains($0.value) }) {
                    candidates.append(contentsOf: ["Kohinoor Devanagari", "ITF Devanagari"])
                }
                if scalars.contains(where: { (0x0980...0x09FF).contains($0.value) }) {
                    candidates.append(contentsOf: ["Kohinoor Bangla", "Bangla MN"])
                }
                if scalars.contains(where: { (0x0E00...0x0E7F).contains($0.value) }) {
                    candidates.append("Thonburi")
                }
                #endif
                candidates.append(contentsOf: symbolFamiliesLoaded)
                if let mathList = mathFamiliesLoaded {
                    candidates.append(contentsOf: mathList)
                }
            }
        }

        let vars = effectiveVariations(style, sizePt)

        // Try each candidate family in priority order, checking glyph coverage when `sampleGrapheme` is non-nil.
        for name in candidates {
            if let (reg, synthOblique) = matchRegisteredFace(in: registeredFaces, familyName: name, weight: weight, italic: italic) {
                if let ch = sampleGrapheme, !registeredFaceCovers(reg, grapheme: ch) {
                    continue
                }
                return makeFaceFromRegistered(
                    reg,
                    sizePt: sizePt,
                    weight: weight,
                    syntheticOblique: synthOblique,
                    isMono: isMono,
                    variations: vars,
                    features: activeFeatures
                )
            }

            #if canImport(CoreText) && canImport(CoreGraphics)
            let mappedName: String
            if name == "Inter" && !Self.appleHasSystemFamily("Inter") {
                mappedName = "Helvetica Neue"
            } else if name == "IBM Plex Mono" && !Self.appleHasSystemFamily("IBM Plex Mono") {
                mappedName = "Menlo"
            } else {
                mappedName = name
            }
            if let (ctPt, synthOblique, isEmoji) = makeAppleCTFont(
                familyName: mappedName,
                ptSize: sizePt,
                weight: weight,
                italic: italic,
                variations: vars,
                features: activeFeatures,
                isMono: isMono
            ) {
                if let ch = sampleGrapheme, !ctFontCovers(ctPt, grapheme: ch) {
                    continue
                }
                return makeFaceFromCTFont(
                    ctPt: ctPt,
                    weight: weight,
                    isMono: isMono,
                    isColorEmoji: isEmoji,
                    syntheticOblique: synthOblique
                )
            }
            #else
            if let (sysFace, synthOblique) = matchRegisteredFace(in: systemSfntFaces, familyName: name, weight: weight, italic: italic) {
                if let ch = sampleGrapheme, !registeredFaceCovers(sysFace, grapheme: ch) {
                    continue
                }
                return makeFaceFromRegistered(
                    sysFace,
                    sizePt: sizePt,
                    weight: weight,
                    syntheticOblique: synthOblique,
                    isMono: isMono,
                    variations: vars,
                    features: activeFeatures
                )
            }
            #endif
        }

        // Last-resort CoreText system fallback for any exotic Unicode scalar before BuiltinVectorFont.
        #if canImport(CoreText) && canImport(CoreGraphics)
        if let ch = sampleGrapheme,
           let base = CTFontCreateUIFontForLanguage(.system, CGFloat(max(sizePt, 1.0)), nil)
        {
            let s = String(ch) as CFString
            let fallbackCT = CTFontCreateForString(base, s, CFRangeMake(0, CFStringGetLength(s)))
            if ctFontCovers(fallbackCT, grapheme: ch) {
                let ps = CTFontCopyPostScriptName(fallbackCT) as String
                let isEmoji = ps.localizedCaseInsensitiveContains("Emoji")
                return makeFaceFromCTFont(
                    ctPt: fallbackCT,
                    weight: weight,
                    isMono: isMono,
                    isColorEmoji: isEmoji,
                    syntheticOblique: false
                )
            }
        }
        #endif

        let builtinKind: BuiltinFontKind = isMono ? .mono : .sans
        let skew: Int8 = italic ? SYNTHETIC_OBLIQUE_SKEW64 : 0
        let skewDeg: UInt8 = italic ? SYNTHETIC_OBLIQUE : 0
        #if canImport(CoreText) && canImport(CoreGraphics)
        return ShapedFontFace(
            fontId: builtinKind.rawValue ^ UInt64(hashBits(weight)),
            index: 0,
            coordsHash: 0,
            weight: weight,
            isMono: isMono,
            isColorEmoji: false,
            skew: skew,
            skewDegrees: skewDeg,
            ctFontPoint: nil,
            ctFontUpem: nil,
            cachedHintMetrics: BuiltinVectorFont.hintMetrics,
            sfnt: nil,
            builtin: builtinKind
        )
        #else
        return ShapedFontFace(
            fontId: builtinKind.rawValue ^ UInt64(hashBits(weight)),
            index: 0,
            coordsHash: 0,
            weight: weight,
            isMono: isMono,
            isColorEmoji: false,
            skew: skew,
            skewDegrees: skewDeg,
            sfnt: nil,
            builtin: builtinKind
        )
        #endif
    }

    private func registeredFaceCovers(_ reg: RegisteredFontFace, grapheme: Character) -> Bool {
        for sc in grapheme.unicodeScalars {
            let v = sc.value
            if v == 0xFE0F || v == 0xFE0E || v == 0x200D { continue }
            guard let gid = reg.sfnt.glyphId(for: sc), gid != 0 else {
                return false
            }
        }
        return true
    }

    private func computeSfntCoordsHash(_ fvar: SfntFvar?, weight: Float, variations: [(UInt32, Float)], sfnt: SfntFont) -> (UInt64, [(UInt32, Float)]) {
        guard let fvar, !fvar.axes.isEmpty else {
            return (0, [])
        }
        var explicitTags = Set<UInt32>(variations.map(\.0))
        explicitTags.insert(SfntTag.wght)
        var hidden: [VariationAxisSetting] = []
        pushHiddenAxes(sfnt, weight: weight, explicitTags: explicitTags, out: &hidden)

        var applied: [(UInt32, Float)] = []
        var anyNonDefault = false
        for axis in fvar.axes {
            let rawVal: Float
            if let exp = variations.first(where: { $0.0 == axis.tag }) {
                rawVal = exp.1
            } else if axis.tag == SfntTag.wght {
                rawVal = weight
            } else if let hid = hidden.first(where: { $0.tag == axis.tag }) {
                rawVal = hid.value
            } else {
                rawVal = axis.defaultValue
            }
            let clamped = min(max(rawVal, axis.minValue), axis.maxValue)
            applied.append((axis.tag, clamped))
            if abs(clamped - axis.defaultValue) > 1e-4 {
                anyNonDefault = true
            }
        }
        guard anyNonDefault else { return (0, applied) }
        var h = KeyHasher()
        for (tag, val) in applied {
            h.u32(tag)
            h.f32(val)
        }
        return (h.hash == 0 ? 1 : h.hash, applied)
    }

    private func makeFaceFromRegistered(
        _ reg: RegisteredFontFace,
        sizePt: Float,
        weight: Float,
        syntheticOblique: Bool,
        isMono: Bool,
        variations: [(UInt32, Float)],
        features: [(UInt32, Int32)]
    ) -> ShapedFontFace {
        let (cHash, appliedAxes) = computeSfntCoordsHash(reg.fvar, weight: weight, variations: variations, sfnt: reg.sfnt)
        let skew: Int8 = syntheticOblique ? SYNTHETIC_OBLIQUE_SKEW64 : 0
        let skewDeg: UInt8 = syntheticOblique ? SYNTHETIC_OBLIQUE : 0
        #if canImport(CoreText) && canImport(CoreGraphics)
        var ctPt: CTFont? = nil
        var ctUpem: CTFont? = nil
        if let baseDesc = reg.ctDescriptor {
            let decorated = applyCTDescriptorSettings(
                baseDesc,
                axes: appliedAxes,
                features: features,
                isMono: isMono
            )
            let pt = CTFontCreateWithFontDescriptor(decorated, CGFloat(max(sizePt, 0.5)), nil)
            let upem = CGFloat(max(reg.sfnt.unitsPerEm() ?? 1000, 1))
            let up = CTFontCreateCopyWithAttributes(pt, upem, nil, nil)
            ctPt = pt
            ctUpem = up
        }
        return ShapedFontFace(
            fontId: reg.fontId,
            index: reg.index,
            coordsHash: cHash,
            weight: weight,
            isMono: isMono,
            isColorEmoji: false,
            skew: skew,
            skewDegrees: skewDeg,
            ctFontPoint: ctPt,
            ctFontUpem: ctUpem,
            cachedHintMetrics: truetypeMetrics(reg.sfnt),
            sfnt: reg.sfnt,
            builtin: nil
        )
        #else
        _ = (sizePt, features)
        return ShapedFontFace(
            fontId: reg.fontId,
            index: reg.index,
            coordsHash: cHash,
            weight: weight,
            isMono: isMono,
            isColorEmoji: false,
            skew: skew,
            skewDegrees: skewDeg,
            sfnt: reg.sfnt,
            builtin: nil
        )
        #endif
    }

    #if canImport(CoreText) && canImport(CoreGraphics)
    private func applyCTDescriptorSettings(
        _ base: CTFontDescriptor,
        axes: [(UInt32, Float)],
        features: [(UInt32, Int32)],
        isMono: Bool
    ) -> CTFontDescriptor {
        var attrs: [CFString: Any] = [:]
        if !axes.isEmpty {
            var varDict: [NSNumber: NSNumber] = [:]
            for (tag, val) in axes {
                varDict[NSNumber(value: tag)] = NSNumber(value: Double(val))
            }
            attrs[kCTFontVariationAttribute] = varDict
        }
        var featList: [[String: Any]] = []
        for (tag, val) in features {
            featList.append([
                "CTFeatureOpenTypeTag": fourCharString(tag),
                "CTFeatureOpenTypeValue": Int(val),
            ])
        }
        if isMono {
            for offTag in ["liga", "clig", "calt", "dlig"] {
                featList.append([
                    "CTFeatureOpenTypeTag": offTag,
                    "CTFeatureOpenTypeValue": 0,
                ])
            }
        }
        if !featList.isEmpty {
            attrs[kCTFontFeatureSettingsAttribute] = featList
        }
        guard !attrs.isEmpty else { return base }
        return CTFontDescriptorCreateCopyWithAttributes(base, attrs as CFDictionary)
    }

    private func makeAppleCTFont(
        familyName: String,
        ptSize: Float,
        weight: Float,
        italic: Bool,
        variations: [(UInt32, Float)],
        features: [(UInt32, Int32)],
        isMono: Bool
    ) -> (CTFont, Bool, Bool)? {
        let cgPt = CGFloat(max(ptSize, 0.5))

        if familyName == "System Font" || familyName == ".SF NS" {
            guard var ct = CTFontCreateUIFontForLanguage(.system, cgPt, nil) else { return nil }
            var synthOblique = false
            if italic {
                if let itCopy = CTFontCreateCopyWithSymbolicTraits(ct, cgPt, nil, .traitItalic, .traitItalic) {
                    ct = itCopy
                } else {
                    synthOblique = true
                }
            }
            var axes: [(UInt32, Float)] = [(SfntTag.wght, weight)]
            for (t, v) in variations {
                if t == SfntTag.wght {
                    axes[0] = (t, v)
                } else if t == SfntTag.opsz {
                    axes.append((t, min(max(v, 17.0), 96.0)))
                } else {
                    axes.append((t, v))
                }
            }
            let desc = applyCTDescriptorSettings(CTFontCopyFontDescriptor(ct), axes: axes, features: features, isMono: isMono)
            ct = CTFontCreateCopyWithAttributes(ct, cgPt, nil, desc)
            return (ct, synthOblique, false)
        }

        if familyName == ".SF NS Mono" {
            var ct: CTFont? = nil
            #if canImport(AppKit)
            let namedWeights: [(Float, NSFont.Weight)] = [
                (100, .ultraLight), (200, .thin), (300, .light),
                (400, .regular), (500, .medium), (600, .semibold),
                (700, .bold), (800, .heavy), (900, .black),
            ]
            let pickedWeight = namedWeights.min { abs($0.0 - weight) < abs($1.0 - weight) }?.1 ?? .regular
            ct = NSFont.monospacedSystemFont(ofSize: cgPt, weight: pickedWeight) as CTFont
            #else
            ct = CTFontCreateUIFontForLanguage(.userFixedPitch, cgPt, nil)
            #endif
            guard var font = ct else { return nil }
            var synthOblique = false
            if italic {
                if let itCopy = CTFontCreateCopyWithSymbolicTraits(font, cgPt, nil, .traitItalic, .traitItalic) {
                    font = itCopy
                } else {
                    synthOblique = true
                }
            }
            let desc = applyCTDescriptorSettings(CTFontCopyFontDescriptor(font), axes: [], features: features, isMono: true)
            font = CTFontCreateCopyWithAttributes(font, cgPt, nil, desc)
            return (font, synthOblique, false)
        }

        guard AppleFontFamilyCache.shared.has(familyName) else { return nil }
        let normalizedWeight = appleNormalizedCTWeight(weight)
        return AppleFontFamilyCache.shared.withCoreTextQuery {
            var traits: [CFString: Any] = [kCTFontWeightTrait: NSNumber(value: Double(normalizedWeight))]
            if italic {
                traits[kCTFontSymbolicTrait] = NSNumber(value: CTFontSymbolicTraits.traitItalic.rawValue)
            }
            let baseAttrs: [CFString: Any] = [
                kCTFontFamilyNameAttribute: familyName,
                kCTFontTraitsAttribute: traits,
            ]
            let rawDesc = CTFontDescriptorCreateWithAttributes(baseAttrs as CFDictionary)
            var ct = CTFontCreateWithFontDescriptor(rawDesc, cgPt, nil)
            let actualFam = CTFontCopyFamilyName(ct) as String
            if actualFam.caseInsensitiveCompare(familyName) != .orderedSame && italic {
                // Family exists upright without an italic member: load upright and apply synthetic oblique!
                let uprightAttrs: [CFString: Any] = [
                    kCTFontFamilyNameAttribute: familyName,
                    kCTFontTraitsAttribute: [kCTFontWeightTrait: NSNumber(value: Double(normalizedWeight))],
                ]
                ct = CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes(uprightAttrs as CFDictionary), cgPt, nil)
            }
            let finalFam = CTFontCopyFamilyName(ct) as String
            guard finalFam.caseInsensitiveCompare(familyName) == .orderedSame else { return nil }

            let hasItalicTrait = CTFontGetSymbolicTraits(ct).contains(.traitItalic)
            let synthOblique = italic && !hasItalicTrait
            let isEmoji = familyName.localizedCaseInsensitiveContains("Emoji")

            let supportedAxes = ctFontSupportedAxes(ct, requestedWeight: weight, variations: variations)
            let desc = applyCTDescriptorSettings(CTFontCopyFontDescriptor(ct), axes: supportedAxes, features: features, isMono: isMono)
            ct = CTFontCreateCopyWithAttributes(ct, cgPt, nil, desc)
            return (ct, synthOblique, isEmoji)
        }
    }

    private func appleNormalizedCTWeight(_ w: Float) -> Float {
        // Maps CSS 100..900 weight to CoreText's -0.8..+0.6 weight trait scale.
        if w <= 400.0 {
            return (w - 400.0) / 375.0
        } else {
            return min((w - 400.0) / 750.0, 0.8)
        }
    }

    private func ctFontSupportedAxes(_ ct: CTFont, requestedWeight: Float, variations: [(UInt32, Float)]) -> [(UInt32, Float)] {
        guard let axesCF = CTFontCopyVariationAxes(ct) as? [[CFString: Any]], !axesCF.isEmpty else {
            return []
        }
        var out: [(UInt32, Float)] = []
        for dict in axesCF {
            guard let num = dict[kCTFontVariationAxisIdentifierKey] as? NSNumber else { continue }
            let tag = num.uint32Value
            let minV = (dict[kCTFontVariationAxisMinimumValueKey] as? NSNumber)?.floatValue ?? 0.0
            let maxV = (dict[kCTFontVariationAxisMaximumValueKey] as? NSNumber)?.floatValue ?? 1000.0
            let defV = (dict[kCTFontVariationAxisDefaultValueKey] as? NSNumber)?.floatValue ?? minV
            let raw: Float
            if let exp = variations.first(where: { $0.0 == tag }) {
                raw = exp.1
            } else if tag == SfntTag.wght {
                raw = requestedWeight
            } else {
                raw = defV
            }
            out.append((tag, min(max(raw, minV), maxV)))
        }
        return out
    }

    private func ctFontCoordsHash(_ ct: CTFont) -> UInt64 {
        guard let axesCF = CTFontCopyVariationAxes(ct) as? [[CFString: Any]],
              !axesCF.isEmpty,
              let curCF = CTFontCopyVariation(ct) as? [NSNumber: NSNumber],
              !curCF.isEmpty
        else {
            return 0
        }
        var anyNonDefault = false
        var h = KeyHasher()
        for dict in axesCF {
            guard let idNum = dict[kCTFontVariationAxisIdentifierKey] as? NSNumber else { continue }
            let tag = idNum.uint32Value
            let defV = (dict[kCTFontVariationAxisDefaultValueKey] as? NSNumber)?.floatValue ?? 0.0
            let curV = curCF[idNum]?.floatValue ?? defV
            h.u32(tag)
            h.f32(curV)
            if abs(curV - defV) > 1e-4 {
                anyNonDefault = true
            }
        }
        return anyNonDefault ? (h.hash == 0 ? 1 : h.hash) : 0
    }

    private func ctFontCovers(_ ct: CTFont, grapheme: Character) -> Bool {
        let s = String(grapheme)
        var utf16: [UniChar] = []
        for sc in grapheme.unicodeScalars {
            let v = sc.value
            if v == 0xFE0F || v == 0xFE0E || v == 0x200D { continue }
            for u in String(sc).utf16 {
                utf16.append(u)
            }
        }
        if utf16.isEmpty {
            utf16 = Array(s.utf16)
        }
        guard !utf16.isEmpty else { return true }
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        let allMapped = CTFontGetGlyphsForCharacters(ct, &utf16, &glyphs, utf16.count)
        guard allMapped else { return false }
        for i in 0..<utf16.count {
            // Low surrogates (`0xDC00...0xDFFF`) receive `0` in `glyphs[i]` when a supplementary
            // plane scalar maps to `glyphs[i - 1]`.
            if (0xDC00...0xDFFF).contains(utf16[i]) { continue }
            if glyphs[i] == 0 { return false }
        }
        return true
    }

    private func computeCTHintMetrics(_ ctUpem: CTFont, postScriptName: String) -> HintMetrics? {
        let upem = Double(CTFontGetUnitsPerEm(ctUpem))
        guard upem > 0 else { return nil }
        var chars: [UniChar] = [0x006F, 0x0058] // 'o', 'X'
        var gids: [CGGlyph] = [0, 0]
        guard CTFontGetGlyphsForCharacters(ctUpem, &chars, &gids, 2),
              gids[0] != 0, gids[1] != 0
        else { return nil }
        var rects = [CGRect](repeating: .zero, count: 2)
        CTFontGetBoundingRectsForGlyphs(ctUpem, .default, &gids, &rects, 2)
        let xHeight = Double(rects[0].maxY)
        let capHeight = Double(rects[1].maxY)
        let maxY = Double(CTFontGetBoundingBox(ctUpem).maxY)
        guard xHeight > 0, capHeight > 0 else { return nil }
        return HintMetrics(
            upem: upem,
            xHeight: xHeight,
            capHeight: capHeight,
            maxY: maxY,
            stemHeight: descriptorStemHeight(postScriptName: postScriptName)
        )
    }

    private func makeFaceFromCTFont(
        ctPt: CTFont,
        weight: Float,
        isMono: Bool,
        isColorEmoji: Bool,
        syntheticOblique: Bool
    ) -> ShapedFontFace {
        let psName = CTFontCopyPostScriptName(ctPt) as String
        let fId = fnvStringId(psName)
        let cHash = ctFontCoordsHash(ctPt)
        let upem = CGFloat(max(CTFontGetUnitsPerEm(ctPt), 1))
        let ctUpem = CTFontCreateCopyWithAttributes(ctPt, upem, nil, nil)
        let skew: Int8 = syntheticOblique ? SYNTHETIC_OBLIQUE_SKEW64 : 0
        let skewDeg: UInt8 = syntheticOblique ? SYNTHETIC_OBLIQUE : 0
        let hMetrics = isColorEmoji ? nil : computeCTHintMetrics(ctUpem, postScriptName: psName)
        return ShapedFontFace(
            fontId: fId,
            index: 0,
            coordsHash: cHash,
            weight: weight,
            isMono: isMono,
            isColorEmoji: isColorEmoji,
            skew: skew,
            skewDegrees: skewDeg,
            ctFontPoint: ctPt,
            ctFontUpem: ctUpem,
            cachedHintMetrics: hMetrics,
            sfnt: nil,
            builtin: nil
        )
    }
    #endif

    // MARK: - Segment Shaping & Metrics

    private func computeLayoutMetrics(face: ShapedFontFace, sizePt: Float, scale: Float) -> LayoutFontMetrics {
        let px = sizePt * scale
        if let sfnt = face.sfnt, let upem = sfnt.unitsPerEm(), upem > 0, let hhea = sfnt.hheaMetrics() {
            let k = px / Float(upem)
            let asc = Float(hhea.ascent) * k
            let desc = abs(Float(hhea.descent)) * k
            let lead = Float(hhea.lineGap) * k
            let cap = sfnt.glyphId(for: UnicodeScalar("X")).flatMap { sfnt.glyphMaxY($0) }.map { Float($0) * k }
            let xh = sfnt.glyphId(for: UnicodeScalar("o")).flatMap { sfnt.glyphMaxY($0) }.map { Float($0) * k }
            let thick = max(1.0, (px * 0.065).rounded(.toNearestOrAwayFromZero))
            return LayoutFontMetrics(
                ascent: asc,
                descent: desc,
                leading: lead,
                capHeight: cap,
                xHeight: xh,
                strikethroughOffset: (xh ?? (asc * 0.5)) * 0.55,
                strikethroughSize: thick,
                underlineOffset: -max(1.0, px * 0.1),
                underlineSize: thick
            )
        }
        #if canImport(CoreText) && canImport(CoreGraphics)
        if let ct = face.ctFontPoint {
            let asc = Float(CTFontGetAscent(ct)) * scale
            let desc = Float(CTFontGetDescent(ct)) * scale
            let lead = Float(CTFontGetLeading(ct)) * scale
            let cap = Float(CTFontGetCapHeight(ct)) * scale
            let xh = Float(CTFontGetXHeight(ct)) * scale
            let ulPos = Float(CTFontGetUnderlinePosition(ct)) * scale
            let ulThick = max(1.0, Float(CTFontGetUnderlineThickness(ct)) * scale)
            return LayoutFontMetrics(
                ascent: asc,
                descent: desc,
                leading: lead,
                capHeight: cap > 0 ? cap : nil,
                xHeight: xh > 0 ? xh : nil,
                strikethroughOffset: (xh > 0 ? xh : asc * 0.5) * 0.55,
                strikethroughSize: ulThick,
                underlineOffset: ulPos,
                underlineSize: ulThick
            )
        }
        #endif
        let k = px / Float(BuiltinVectorFont.upem)
        let asc = BuiltinVectorFont.ascent * k
        let desc = BuiltinVectorFont.descent * k
        let thick = max(1.0, px * 0.07)
        return LayoutFontMetrics(
            ascent: asc,
            descent: desc,
            leading: 0.0,
            capHeight: 720.0 * k,
            xHeight: 520.0 * k,
            strikethroughOffset: 280.0 * k,
            strikethroughSize: thick,
            underlineOffset: -100.0 * k,
            underlineSize: thick
        )
    }

    private func computeMonoSpaceAdvance(face: ShapedFontFace, sizePt: Float, scale: Float, extraTrackingPx: Float) -> Float {
        let px = sizePt * scale
        #if canImport(CoreText) && canImport(CoreGraphics)
        if let ct = face.ctFontPoint {
            var ch: UniChar = 0x0020
            var gid: CGGlyph = 0
            if CTFontGetGlyphsForCharacters(ct, &ch, &gid, 1), gid != 0 {
                var adv = CGSize.zero
                CTFontGetAdvancesForGlyphs(ct, .default, &gid, &adv, 1)
                return Float(adv.width) * scale + extraTrackingPx
            }
        }
        #endif
        if let sfnt = face.sfnt, let upem = sfnt.unitsPerEm(), upem > 0,
           let gid = sfnt.glyphId(for: UnicodeScalar(0x20)),
           let advUnits = sfnt.advanceWidth(gid)
        {
            return Float(advUnits) * px / Float(upem) + extraTrackingPx
        }
        return BuiltinVectorFont.advanceUnits(for: UnicodeScalar(0x20), mono: true, weight: face.weight) * (px / Float(BuiltinVectorFont.upem)) + extraTrackingPx
    }

    private func shapeResolvedSegment(
        runText: String,
        byteRange: Range<Int>,
        originalUtf8: [UInt8],
        face: ShapedFontFace,
        slice: StyleSlice,
        style: TextStyle,
        scale: Float,
        tracked: Bool,
        opticalFixed: Float?,
        activeFeatures: [(UInt32, Int32)],
        isRtl: Bool
    ) -> ShapedRun {
        _ = activeFeatures
        let metrics = computeLayoutMetrics(face: face, sizePt: slice.sizePt, scale: scale)
        let lookupPt: Float
        if let opt = opticalFixed {
            lookupPt = (abs(slice.sizePt - style.size) <= style.size * 1e-6)
                ? opt
                : (opt * slice.sizePt / style.size)
        } else {
            lookupPt = slice.sizePt
        }

        // Compute per-glyph tracking adjustment in device px.
        var trackingDeltaPt: Float = style.tracking
        #if canImport(CoreText) && canImport(CoreGraphics)
        if let ct = face.ctFontPoint {
            let faceTrak: Trak?
            if let sfnt = face.sfnt {
                faceTrak = fontTrak(&traks, face.fontId, sfnt.data, face.index)
            } else {
                faceTrak = ctFontTrak(ct)
            }
            if let t = faceTrak {
                let appliedByCT = t.coreTextPoints(slice.sizePt, slice.sizePt)
                let wanted = tracked ? t.coreTextPoints(slice.sizePt, lookupPt) : 0.0
                trackingDeltaPt += (wanted - appliedByCT)
            }
        } else if let sfnt = face.sfnt, let t = fontTrak(&traks, face.fontId, sfnt.data, face.index) {
            if tracked {
                trackingDeltaPt += t.coreTextPoints(slice.sizePt, lookupPt)
            }
        }
        #else
        if let sfnt = face.sfnt, let t = fontTrak(&traks, face.fontId, sfnt.data, face.index), tracked {
            trackingDeltaPt += t.coreTextPoints(slice.sizePt, lookupPt)
        }
        #endif
        let extraTrackingPx = trackingDeltaPt * scale
        let monoSpaceAdv: Float = slice.isMono
            ? computeMonoSpaceAdvance(face: face, sizePt: slice.sizePt, scale: scale, extraTrackingPx: extraTrackingPx)
            : 0.0

        #if canImport(CoreText) && canImport(CoreGraphics)
        if let ct = face.ctFontPoint {
            return shapeWithCoreText(
                ct: ct,
                runText: runText,
                byteRange: byteRange,
                originalUtf8: originalUtf8,
                face: face,
                slice: slice,
                metrics: metrics,
                scale: scale,
                extraTrackingPx: extraTrackingPx,
                monoSpaceAdv: monoSpaceAdv,
                isRtl: isRtl
            )
        }
        #endif

        return shapeWithoutCoreText(
            runText: runText,
            byteRange: byteRange,
            originalUtf8: originalUtf8,
            face: face,
            slice: slice,
            metrics: metrics,
            scale: scale,
            extraTrackingPx: extraTrackingPx,
            monoSpaceAdv: monoSpaceAdv,
            isRtl: isRtl
        )
    }

    #if canImport(CoreText) && canImport(CoreGraphics)
    private func shapeWithCoreText(
        ct: CTFont,
        runText: String,
        byteRange: Range<Int>,
        originalUtf8: [UInt8],
        face: ShapedFontFace,
        slice: StyleSlice,
        metrics: LayoutFontMetrics,
        scale: Float,
        extraTrackingPx: Float,
        monoSpaceAdv: Float,
        isRtl: Bool
    ) -> ShapedRun {
        // Map UTF-16 code unit offsets of `runText` -> local UTF-8 byte offsets `[0...runUtf8Len]`.
        let runUtf8Len = byteRange.count
        var utf16ToByte: [Int] = []
        utf16ToByte.reserveCapacity(runText.utf16.count + 1)
        var bOff = 0
        for sc in runText.unicodeScalars {
            let u16Len = sc.utf16.count
            for _ in 0..<u16Len {
                utf16ToByte.append(bOff)
            }
            bOff += sc.utf8.count
        }
        utf16ToByte.append(runUtf8Len)

        // Grapheme boundaries in local UTF-8 bytes (`0..<runUtf8Len`).
        var graphemeRanges: [(Range<Int>, Character)] = []
        var gCursor = 0
        for ch in runText {
            let len = ch.utf8.count
            graphemeRanges.append((gCursor..<(gCursor + len), ch))
            gCursor += len
        }

        func graphemeIndex(forLocalByte lb: Int) -> Int {
            guard !graphemeRanges.isEmpty else { return 0 }
            var lo = 0
            var hi = graphemeRanges.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if graphemeRanges[mid].0.upperBound <= lb {
                    lo = mid + 1
                } else {
                    hi = mid
                }
            }
            return min(lo, graphemeRanges.count - 1)
        }

        var attrs: [CFString: Any] = [kCTFontAttributeName: ct]
        if slice.isMono {
            attrs[kCTLigatureAttributeName] = NSNumber(value: 0)
        }
        let attrStr = CFAttributedStringCreate(nil, runText as CFString, attrs as CFDictionary)!
        let ctLine = CTLineCreateWithAttributedString(attrStr)
        let ctRuns = (CTLineGetGlyphRuns(ctLine) as? [CTRun]) ?? []

        struct RawCTFurthermore {
            var gid: UInt16
            var posPt: CGPoint
            var advPt: CGFloat
            var localByte: Int
            var gIdx: Int
        }

        var rawGlyphs: [RawCTFurthermore] = []
        for ctRun in ctRuns {
            let count = CTRunGetGlyphCount(ctRun)
            guard count > 0 else { continue }
            var gids = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            var advances = [CGSize](repeating: .zero, count: count)
            var strIndices = [CFIndex](repeating: 0, count: count)
            let range = CFRangeMake(0, count)
            CTRunGetGlyphs(ctRun, range, &gids)
            CTRunGetPositions(ctRun, range, &positions)
            CTRunGetAdvances(ctRun, range, &advances)
            CTRunGetStringIndices(ctRun, range, &strIndices)
            for i in 0..<count {
                let u16Idx = max(0, min(strIndices[i], utf16ToByte.count - 1))
                let lb = utf16ToByte[u16Idx]
                rawGlyphs.append(RawCTFurthermore(
                    gid: gids[i],
                    posPt: positions[i],
                    advPt: advances[i].width,
                    localByte: lb,
                    gIdx: graphemeIndex(forLocalByte: lb)
                ))
            }
        }

        // Convert visual-order `rawGlyphs` into `LayoutGlyph`s and logical-order `LayoutCluster`s.
        // For RTL runs, reverse into logical cluster order first if needed, or keep `LayoutGlyph`s
        // aligned with clusters cleanly.
        let orderedRaw: [RawCTFurthermore]
        if isRtl && rawGlyphs.count > 1 && rawGlyphs.first!.gIdx > rawGlyphs.last!.gIdx {
            orderedRaw = rawGlyphs.reversed()
        } else {
            orderedRaw = rawGlyphs
        }

        // Bucket glyphs by grapheme index. Graphemes with zero glyphs (ligature continuations like 'f'+'i' -> 'fi')
        // merge into the preceding non-empty grapheme cluster!
        var buckets = [[RawCTFurthermore]](repeating: [], count: graphemeRanges.count)
        for rg in orderedRaw {
            if rg.gIdx >= 0 && rg.gIdx < buckets.count {
                buckets[rg.gIdx].append(rg)
            }
        }

        var layoutGlyphs: [LayoutGlyph] = []
        var clusters: [LayoutCluster] = []
        var runningAdvPx: Float = 0.0
        var extraAccumPx: Float = 0.0

        var gIdx = 0
        while gIdx < graphemeRanges.count {
            let startLocal = graphemeRanges[gIdx].0.lowerBound
            var endLocal = graphemeRanges[gIdx].0.upperBound
            let bucket = buckets[gIdx]
            var nextG = gIdx + 1
            if !bucket.isEmpty {
                while nextG < graphemeRanges.count && buckets[nextG].isEmpty {
                    endLocal = graphemeRanges[nextG].0.upperBound
                    nextG += 1
                }
            }

            let absStart = byteRange.lowerBound + startLocal
            let absEnd = byteRange.lowerBound + endLocal
            let gStart = layoutGlyphs.count
            var clusterAdvPx: Float = 0.0

            for (localK, rg) in bucket.enumerated() {
                let isLastInBucket = (localK == bucket.count - 1)
                let addTrack: Float = isLastInBucket ? extraTrackingPx : 0.0
                let targetX = Float(rg.posPt.x) * scale + extraAccumPx
                let relX = targetX - runningAdvPx
                let relY = -Float(rg.posPt.y) * scale
                let advPx = max(0.0, Float(rg.advPt) * scale + addTrack)
                layoutGlyphs.append(LayoutGlyph(
                    id: rg.gid,
                    x: relX,
                    y: relY,
                    advance: advPx,
                    textByteOffset: UInt32(absStart)
                ))
                runningAdvPx += advPx
                clusterAdvPx += advPx
                if isLastInBucket {
                    extraAccumPx += addTrack
                }
            }

            let gEnd = layoutGlyphs.count
            let origByte: UInt8 = (absStart < originalUtf8.count) ? originalUtf8[absStart] : 0
            let isTab = (absEnd - absStart == 1) && (origByte == UInt8(ascii: "\t"))
            let isSpace = (absEnd - absStart == 1) && (origByte == UInt8(ascii: " "))
            let isHanging = isSpace || isTab
            let lastScalar = graphemeRanges[nextG - 1].1.unicodeScalars.last?.value ?? 0
            let allowSoft = isSoftBreakScalar(lastScalar) || isTab

            clusters.append(LayoutCluster(
                textRange: absStart..<absEnd,
                advance: clusterAdvPx,
                isHangingWhitespace: isHanging,
                isWordSpace: isSpace,
                isTab: isTab,
                isSoftBreakAfter: allowSoft,
                isHardBreak: false,
                isRtl: isRtl,
                glyphRange: gStart..<gEnd
            ))
            gIdx = nextG
        }

        return ShapedRun(
            font: face,
            fontSize: slice.sizePt * scale,
            lineHeightPx: slice.lineHeightPx,
            fontMetrics: metrics,
            ink: slice.ink,
            textRange: byteRange,
            isRtl: isRtl,
            isMono: slice.isMono,
            monoSpaceAdvance: monoSpaceAdv,
            clusters: clusters,
            glyphs: layoutGlyphs
        )
    }
    #endif

    private func shapeWithoutCoreText(
        runText: String,
        byteRange: Range<Int>,
        originalUtf8: [UInt8],
        face: ShapedFontFace,
        slice: StyleSlice,
        metrics: LayoutFontMetrics,
        scale: Float,
        extraTrackingPx: Float,
        monoSpaceAdv: Float,
        isRtl: Bool
    ) -> ShapedRun {
        let px = slice.sizePt * scale
        var layoutGlyphs: [LayoutGlyph] = []
        var clusters: [LayoutCluster] = []
        var localByte = 0

        for ch in runText {
            let chLen = ch.utf8.count
            let absStart = byteRange.lowerBound + localByte
            let absEnd = absStart + chLen
            let gStart = layoutGlyphs.count
            var clusterAdv: Float = 0.0

            let scalars = Array(ch.unicodeScalars)
            for (sIdx, sc) in scalars.enumerated() {
                if sc.value == 0xFE0F || sc.value == 0xFE0E || sc.value == 0x200D { continue }
                let isCombining = (0x0300...0x036F).contains(sc.value)
                let gid: UInt16
                var rawAdvPx: Float
                if let sfnt = face.sfnt, let upem = sfnt.unitsPerEm(), upem > 0 {
                    gid = sfnt.glyphId(for: sc) ?? 0
                    rawAdvPx = isCombining ? 0.0 : (Float(sfnt.advanceWidth(gid) ?? 0) * px / Float(upem))
                } else {
                    gid = BuiltinVectorFont.glyphId(for: sc)
                    rawAdvPx = isCombining ? 0.0 : (BuiltinVectorFont.advanceUnits(
                        for: sc,
                        mono: face.builtin == .mono,
                        weight: face.weight
                    ) * (px / Float(BuiltinVectorFont.upem)))
                }
                if sIdx == scalars.count - 1 {
                    rawAdvPx = max(0.0, rawAdvPx + extraTrackingPx)
                }
                layoutGlyphs.append(LayoutGlyph(
                    id: gid,
                    x: isCombining ? (-clusterAdv * 0.5) : 0.0,
                    y: 0.0,
                    advance: rawAdvPx,
                    textByteOffset: UInt32(absStart)
                ))
                clusterAdv += rawAdvPx
            }

            let gEnd = layoutGlyphs.count
            let origByte: UInt8 = (absStart < originalUtf8.count) ? originalUtf8[absStart] : 0
            let isTab = (chLen == 1) && (origByte == UInt8(ascii: "\t"))
            let isSpace = (chLen == 1) && (origByte == UInt8(ascii: " "))
            let lastScalar = scalars.last?.value ?? 0
            clusters.append(LayoutCluster(
                textRange: absStart..<absEnd,
                advance: clusterAdv,
                isHangingWhitespace: isSpace || isTab,
                isWordSpace: isSpace,
                isTab: isTab,
                isSoftBreakAfter: isSoftBreakScalar(lastScalar) || isTab,
                isHardBreak: false,
                isRtl: isRtl,
                glyphRange: gStart..<gEnd
            ))
            localByte += chLen
        }

        return ShapedRun(
            font: face,
            fontSize: px,
            lineHeightPx: slice.lineHeightPx,
            fontMetrics: metrics,
            ink: slice.ink,
            textRange: byteRange,
            isRtl: isRtl,
            isMono: slice.isMono,
            monoSpaceAdvance: monoSpaceAdv,
            clusters: clusters,
            glyphs: layoutGlyphs
        )
    }

    // MARK: - Outline Extraction & Glyph Rasterization

    func extractDesignOutline(font: ShapedFontFace, glyph: UInt16, ppem: Double) -> MacosPath? {
        if let sfnt = font.sfnt, font.coordsHash == 0, let path = sfnt.glyphOutline(glyph, ppem: ppem) {
            return path
        }
        #if canImport(CoreText) && canImport(CoreGraphics)
        if let ctUpem = font.ctFontUpem {
            let upem = Double(CTFontGetUnitsPerEm(ctUpem))
            guard upem > 0 else { return nil }
            guard let cgPath = CTFontCreatePathForGlyph(ctUpem, CGGlyph(glyph), nil) else {
                return []
            }
            let scale = ppem / upem
            let sc = { (pt: CGPoint) -> MacosPoint in
                MacosPoint(Double(Float(pt.x)) * scale, Double(Float(pt.y)) * scale)
            }
            var out: MacosPath = []
            cgPath.applyWithBlock { elemPtr in
                let elem = elemPtr.pointee
                switch elem.type {
                case .moveToPoint:
                    out.append(.move(sc(elem.points[0])))
                case .addLineToPoint:
                    out.append(.line(sc(elem.points[0])))
                case .addQuadCurveToPoint:
                    out.append(.quad(sc(elem.points[0]), sc(elem.points[1])))
                case .addCurveToPoint:
                    out.append(.cubic(sc(elem.points[0]), sc(elem.points[1]), sc(elem.points[2])))
                case .closeSubpath:
                    out.append(.close)
                @unknown default:
                    break
                }
            }
            return out
        }
        #endif
        if let sfnt = font.sfnt {
            return sfnt.glyphOutline(glyph, ppem: ppem)
        }
        if let builtin = font.builtin {
            return BuiltinVectorFont.designOutline(
                glyph: glyph,
                mono: builtin == .mono,
                weight: font.weight,
                ppem: ppem
            )
        }
        return nil
    }

    private func hintMetrics(for font: ShapedFontFace) -> HintMetrics? {
        if let sfnt = font.sfnt, font.coordsHash == 0, let m = truetypeMetrics(sfnt) {
            return m
        }
        #if canImport(CoreText) && canImport(CoreGraphics)
        if let cached = font.cachedHintMetrics {
            return cached
        }
        #endif
        if font.builtin != nil {
            return BuiltinVectorFont.hintMetrics
        }
        return nil
    }

    func rasterizeGreyscaleGlyph(
        font: ShapedFontFace,
        glyph: UInt16,
        ppem: Float,
        phaseX: Float,
        shiftY: Float,
        radius: Double,
        skewDegrees: UInt8
    ) -> PlacedMask {
        guard ppem.isFinite, ppem > 0.0 else { return .empty }
        guard let outline = extractDesignOutline(font: font, glyph: glyph, ppem: Double(ppem)),
              !outline.isEmpty
        else {
            return .empty
        }
        let faceKey = FaceMetricsKey(font: font.fontId, index: font.index, coords: font.coordsHash)
        guard let (mask, placement) = smoothingState.maskForOutline(
            outline: outline,
            faceKey: faceKey,
            metricsProvider: { [self] in self.hintMetrics(for: font) },
            ppem: ppem,
            phaseX: phaseX,
            shiftY: shiftY,
            radius: radius,
            skewDegrees: skewDegrees
        ) else {
            return .empty
        }
        guard placement.w > 0, placement.h > 0, mask.contains(where: { $0 != 0 }) else {
            return .empty
        }
        guard let g = atlas.put(placement.w, placement.h, mask, placement.left, placement.top) else {
            return .unplaced
        }
        return .placed(g)
    }

    func rasterizeColorGlyph(font: ShapedFontFace, glyph: UInt16, ppem: Float) -> (Pixels, Rasterized)? {
        #if canImport(CoreText) && canImport(CoreGraphics)
        guard font.isColorEmoji, let baseCT = font.ctFontPoint, ppem > 0.0 else { return nil }
        let scaledCT = CTFontCreateCopyWithAttributes(baseCT, CGFloat(ppem), nil, nil)
        var cgGlyph = CGGlyph(glyph)
        var bbox = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(scaledCT, .default, &cgGlyph, &bbox, 1)
        if bbox.isNull || bbox.isEmpty {
            return nil
        }
        let left = Int32(floor(bbox.minX))
        let bottom = Int32(floor(bbox.minY))
        let right = Int32(ceil(bbox.maxX))
        let top = Int32(ceil(bbox.maxY))
        let w = UInt32(max(0, right - left))
        let h = UInt32(max(0, top - bottom))
        guard w > 0, h > 0, w <= 512, h <= 512 else { return nil }

        var premul = [UInt8](repeating: 0, count: Int(w * h * 4))
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &premul,
            width: Int(w),
            height: Int(h),
            bitsPerComponent: 8,
            bytesPerRow: Int(w) * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        var pos = CGPoint(x: CGFloat(-left), y: CGFloat(-bottom))
        CTFontDrawGlyphs(scaledCT, &cgGlyph, &pos, 1, ctx)

        var straight = [UInt8](repeating: 0, count: premul.count)
        var anyOpaque = false
        for i in 0..<Int(w * h) {
            let a = premul[i * 4 + 3]
            guard a > 0 else { continue }
            anyOpaque = true
            if a == 255 {
                straight[i * 4] = premul[i * 4]
                straight[i * 4 + 1] = premul[i * 4 + 1]
                straight[i * 4 + 2] = premul[i * 4 + 2]
                straight[i * 4 + 3] = 255
            } else {
                let af = Int(a)
                straight[i * 4] = UInt8(min(255, (Int(premul[i * 4]) * 255 + af / 2) / af))
                straight[i * 4 + 1] = UInt8(min(255, (Int(premul[i * 4 + 1]) * 255 + af / 2) / af))
                straight[i * 4 + 2] = UInt8(min(255, (Int(premul[i * 4 + 2]) * 255 + af / 2) / af))
                straight[i * 4 + 3] = a
            }
        }
        guard anyOpaque else { return nil }
        let pixels = Pixels.new()
        pixels.set(w, h, straight)
        return (pixels, Rasterized(left: left, top: top, w: w, h: h))
        #else
        _ = (font, glyph, ppem)
        return nil
        #endif
    }

    func rasterizeRawInkMask(
        font: ShapedFontFace,
        glyph: UInt16,
        ppem: Float,
        subpixelX: Float
    ) -> ([UInt8], Int, Rasterized)? {
        if font.isColorEmoji, let (pixels, pl) = rasterizeColorGlyph(font: font, glyph: glyph, ppem: ppem) {
            return (pixels.rgba(), 4, pl)
        }
        guard let outline = extractDesignOutline(font: font, glyph: glyph, ppem: Double(ppem)),
              !outline.isEmpty
        else {
            return nil
        }
        let skewed: MacosPath
        if font.skewDegrees == 0 {
            skewed = outline
        } else {
            let t = tan(Double(font.skewDegrees) * (.pi / 180.0))
            skewed = outline.map { c in c.map { p in MacosPoint(macosMulAdd(p.y, t, p.x), p.y) } }
        }
        let shifted = skewed.map { c in c.map { p in MacosPoint(p.x + Double(subpixelX), p.y) } }
        let (mask, pl) = macosMask(shifted)
        guard pl.w > 0, pl.h > 0 else { return nil }
        return (mask, 1, pl)
    }
}
