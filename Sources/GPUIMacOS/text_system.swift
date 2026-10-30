// Ported from: crates/gpui_macos/src/text_system.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(macOS)
import AppKit
import CoreFoundation
import CoreGraphics
import CoreText
import Foundation
import GPUI

/// Leniently reads `kCTFontFamilyNameAttribute` from a `CTFontDescriptor` without panicking on malformed fonts.
public func familyName(_ descriptor: CTFontDescriptor) -> String? {
    guard let value = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) else {
        return nil
    }
    guard CFGetTypeID(value) == CFStringGetTypeID() else {
        return nil
    }
    return (value as? String)
}

private struct FontKey: Hashable {
    var fontFamily: SharedString
    var fontFeatures: FontFeatures
    var fontFallbacks: FontFallbacks?
}

private struct LoadedFontFace {
    var ctFont: CTFont
    var cgFont: CGFont
    var postscriptName: String
    var fullName: String
    var weight: Float
    var style: FontStyle
    var stretch: Float
    var metrics: FontMetrics
}

private enum MacTextSystemError: Error, LocalizedError {
    case invalidEmbeddedFont
    case familyNotFound(String)
    case emptyGlyphBounds

    var errorDescription: String? {
        switch self {
        case .invalidEmbeddedFont:
            return "Could not load an embedded font."
        case .familyNotFound(let name):
            return "Font family '\(name)' could not be loaded."
        case .emptyGlyphBounds:
            return "Glyph bounds are empty."
        }
    }
}

/// Converts CoreText's normalized weight trait (`-1.0 ... 1.0`) to CSS/font-kit weight (`100 ... 900`).
private func cssWeightFromCoreTextTrait(_ trait: Double) -> Float {
    // CoreText weight trait: 0.0 is Regular (400), ~0.4 is Bold (700), -0.8 is Thin (100), 1.0 is Black (900).
    let clamped = min(max(trait, -1.0), 1.0)
    if clamped < 0.0 {
        // Map [-0.8, 0.0] -> [100, 400]
        return Float(max(100.0, 400.0 + (clamped / 0.8) * 300.0))
    } else if clamped <= 0.4 {
        // Map [0.0, 0.4] -> [400, 700]
        return Float(400.0 + (clamped / 0.4) * 300.0)
    } else {
        // Map [0.4, 1.0] -> [700, 900]
        return Float(min(900.0, 700.0 + ((clamped - 0.4) / 0.6) * 200.0))
    }
}

/// CSS Fonts Level 3 style/weight matching matching `font_kit::matching::find_best_match`.
private func findBestFontMatch(
    candidates: [LoadedFontFace],
    targetStyle: FontStyle,
    targetWeight: FontWeight
) -> Int? {
    guard !candidates.isEmpty else { return nil }

    // 1. Style preference order per CSS Fonts Level 3 §5.2
    let styleOrder: [FontStyle]
    switch targetStyle {
    case .italic:
        styleOrder = [.italic, .oblique, .normal]
    case .oblique:
        styleOrder = [.oblique, .italic, .normal]
    case .normal:
        styleOrder = [.normal, .oblique, .italic]
    }

    var matchingIndices: [Int] = []
    for preferredStyle in styleOrder {
        let filtered = candidates.indices.filter { candidates[$0].style == preferredStyle }
        if !filtered.isEmpty {
            matchingIndices = filtered
            break
        }
    }
    if matchingIndices.isEmpty {
        matchingIndices = Array(candidates.indices)
    }

    // 2. Weight matching per CSS Fonts Level 3 §5.2
    let targetW = targetWeight.value
    if let exact = matchingIndices.first(where: { abs(candidates[$0].weight - targetW) < 1.0 }) {
        return exact
    }

    if targetW >= 400.0 && targetW <= 500.0 {
        let between = matchingIndices
            .filter { candidates[$0].weight >= targetW && candidates[$0].weight <= 500.0 }
            .min(by: { candidates[$0].weight < candidates[$1].weight })
        if let between { return between }

        let lighter = matchingIndices
            .filter { candidates[$0].weight < targetW }
            .max(by: { candidates[$0].weight < candidates[$1].weight })
        if let lighter { return lighter }

        return matchingIndices.min(by: { candidates[$0].weight < candidates[$1].weight })
    } else if targetW < 400.0 {
        let lighter = matchingIndices
            .filter { candidates[$0].weight <= targetW }
            .max(by: { candidates[$0].weight < candidates[$1].weight })
        if let lighter { return lighter }

        return matchingIndices.min(by: { candidates[$0].weight < candidates[$1].weight })
    } else {
        let heavier = matchingIndices
            .filter { candidates[$0].weight >= targetW }
            .min(by: { candidates[$0].weight < candidates[$1].weight })
        if let heavier { return heavier }

        return matchingIndices.max(by: { candidates[$0].weight < candidates[$1].weight })
    }
}

private func buildLoadedFontFace(from baseFont: CTFont) -> LoadedFontFace? {
    guard let traits = CTFontCopyTraits(baseFont) as? [CFString: Any] else {
        return nil
    }
    guard let symbolicNum = traits[kCTFontSymbolicTrait] as? NSNumber,
          let widthNum = traits[kCTFontWidthTrait] as? NSNumber,
          let weightNum = traits[kCTFontWeightTrait] as? NSNumber,
          let slantNum = traits[kCTFontSlantTrait] as? NSNumber
    else {
        return nil
    }

    let symbolic = CTFontSymbolicTraits(rawValue: symbolicNum.uint32Value)
    let slant = slantNum.doubleValue
    let style: FontStyle
    if symbolic.contains(.italicTrait) {
        style = .italic
    } else if slant > 0.0 {
        style = .oblique
    } else {
        style = .normal
    }

    let weight = cssWeightFromCoreTextTrait(weightNum.doubleValue)
    let stretch = Float(widthNum.doubleValue)

    let unitsPerEmRaw = CTFontGetUnitsPerEm(baseFont)
    let unitsPerEm = unitsPerEmRaw > 0 ? UInt32(unitsPerEmRaw) : 1000
    // Create a metrics reference font at `size == unitsPerEm` so 1 point == 1 font design unit,
    // matching `font_kit`'s unscaled design-unit `Metrics` (`descent` is negative in `FontMetrics`).
    let metricsFont = CTFontCreateCopyWithAttributes(baseFont, CGFloat(unitsPerEm), nil, nil)
    let bbox = CTFontGetBoundingBox(metricsFont)
    let metrics = FontMetrics(
        unitsPerEm: unitsPerEm,
        ascent: Float(CTFontGetAscent(metricsFont)),
        descent: -Float(CTFontGetDescent(metricsFont)),
        lineGap: Float(CTFontGetLeading(metricsFont)),
        underlinePosition: Float(CTFontGetUnderlinePosition(metricsFont)),
        underlineThickness: Float(CTFontGetUnderlineThickness(metricsFont)),
        capHeight: Float(CTFontGetCapHeight(metricsFont)),
        xHeight: Float(CTFontGetXHeight(metricsFont)),
        boundingBox: Bounds(
            origin: point(Float(bbox.origin.x), Float(bbox.origin.y)),
            size: size(Float(bbox.size.width), Float(bbox.size.height))
        )
    )

    let cgFont = CTFontCopyGraphicsFont(baseFont, nil)
    let postscriptName = (CTFontCopyPostScriptName(baseFont) as String)
    let fullName = (CTFontCopyFullName(baseFont) as String)

    return LoadedFontFace(
        ctFont: baseFont,
        cgFont: cgFont,
        postscriptName: postscriptName,
        fullName: fullName,
        weight: weight,
        style: style,
        stretch: stretch,
        metrics: metrics
    )
}

private struct StringIndexConverter {
    let utf8Bytes: [UInt8]
    var utf8Ix: Int = 0
    var utf16Ix: Int = 0

    init(_ text: String) {
        self.utf8Bytes = Array(text.utf8)
    }

    mutating func advanceToUtf16Ix(_ utf16Target: Int) {
        let count = utf8Bytes.count
        while utf8Ix < count {
            if utf16Ix >= utf16Target {
                return
            }
            let b0 = utf8Bytes[utf8Ix]
            let charUtf8Len: Int
            let charUtf16Len: Int
            if b0 < 0x80 {
                charUtf8Len = 1
                charUtf16Len = 1
            } else if (b0 & 0xE0) == 0xC0 {
                charUtf8Len = 2
                charUtf16Len = 1
            } else if (b0 & 0xF0) == 0xE0 {
                charUtf8Len = 3
                charUtf16Len = 1
            } else {
                charUtf8Len = 4
                charUtf16Len = 2
            }
            utf8Ix = min(count, utf8Ix + charUtf8Len)
            utf16Ix += charUtf16Len
        }
    }
}

private final class MacTextSystemState {
    var memoryDescriptorsByFamily: [String: [CTFontDescriptor]] = [:]
    var fonts: [LoadedFontFace] = []
    var fontSelections: [Font: FontId] = [:]
    var fontIdsByPostscriptName: [String: FontId] = [:]
    var fontIdsByFontKey: [FontKey: [FontId]] = [:]
    var postscriptNamesByFontId: [FontId: String] = [:]

    func addFonts(_ fontBlobs: [Data]) throws {
        for data in fontBlobs {
            if let descriptors = CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor],
               !descriptors.isEmpty
            {
                CTFontManagerRegisterFontDescriptors(descriptors as CFArray, .process, true, nil)
                for descriptor in descriptors {
                    if let fam = familyName(descriptor) {
                        memoryDescriptorsByFamily[fam, default: []].append(descriptor)
                    }
                }
            } else {
                guard let provider = CGDataProvider(data: data as CFData),
                      let cgFont = CGFont(provider)
                else {
                    throw MacTextSystemError.invalidEmbeddedFont
                }
                CTFontManagerRegisterGraphicsFont(cgFont, nil)
                let ctFont = CTFontCreateWithGraphicsFont(cgFont, 16.0, nil, nil)
                let descriptor = CTFontCopyFontDescriptor(ctFont)
                if let fam = familyName(descriptor) {
                    memoryDescriptorsByFamily[fam, default: []].append(descriptor)
                }
            }
        }
    }

    func allFontNames() -> [String] {
        var names: [String] = []
        let options: [CFString: Any] = [kCTFontCollectionRemoveDuplicatesOption: kCFBooleanTrue as Any]
        let collection = CTFontCollectionCreateFromAvailableFonts(options as CFDictionary)
        if let descriptors = CTFontCollectionCreateMatchingFontDescriptors(collection) as? [CTFontDescriptor] {
            for descriptor in descriptors {
                if let fam = familyName(descriptor) {
                    names.append(fam)
                }
            }
        }
        names.append(contentsOf: memoryDescriptorsByFamily.keys)
        return names
    }

    func fontId(for font: Font) throws -> FontId {
        if let existing = fontSelections[font] {
            return existing
        }

        let key = FontKey(
            fontFamily: font.family,
            fontFeatures: font.features,
            fontFallbacks: font.fallbacks
        )
        let candidates: [FontId]
        if let existingCandidates = fontIdsByFontKey[key] {
            candidates = existingCandidates
        } else {
            let loaded = try loadFamily(
                name: font.family.asString,
                features: font.features,
                fallbacks: font.fallbacks
            )
            fontIdsByFontKey[key] = loaded
            candidates = loaded
        }

        let candidateFaces = candidates.map { fonts[$0.value] }
        guard let bestIdx = findBestFontMatch(
            candidates: candidateFaces,
            targetStyle: font.style,
            targetWeight: font.weight
        ) else {
            throw MacTextSystemError.familyNotFound(font.family.asString)
        }

        let selected = candidates[bestIdx]
        fontSelections[font] = selected
        return selected
    }

    private func descriptorsForFamily(_ resolvedName: String) -> [CTFontDescriptor] {
        if let mem = memoryDescriptorsByFamily[resolvedName], !mem.isEmpty {
            return mem
        }
        for (fam, descs) in memoryDescriptorsByFamily where fam.caseInsensitiveCompare(resolvedName) == .orderedSame {
            if !descs.isEmpty { return descs }
        }

        if resolvedName == ".AppleSystemUIFont" || resolvedName == ".SystemUIFont" {
            var systemDescs: [CTFontDescriptor] = []
            let weights: [NSFont.Weight] = [
                .ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black,
            ]
            for w in weights {
                let sysFont = NSFont.systemFont(ofSize: 16.0, weight: w)
                let ct = sysFont as CTFont
                systemDescs.append(CTFontCopyFontDescriptor(ct))
                if let italicCt = CTFontCreateCopyWithSymbolicTraits(ct, 16.0, nil, .italicTrait, .italicTrait) {
                    systemDescs.append(CTFontCopyFontDescriptor(italicCt))
                }
            }
            if !systemDescs.isEmpty {
                return systemDescs
            }
        }

        let queryAttrs: [CFString: Any] = [kCTFontFamilyNameAttribute: resolvedName as CFString]
        let queryDesc = CTFontDescriptorCreateWithAttributes(queryAttrs as CFDictionary)
        let mandatory = Set([kCTFontFamilyNameAttribute]) as CFSet
        if let matched = CTFontDescriptorCreateMatchingFontDescriptors(queryDesc, mandatory) as? [CTFontDescriptor],
           !matched.isEmpty
        {
            return matched
        }

        // Also check PostScript / display name fallback
        let nameDesc = CTFontDescriptorCreateWithNameAndSize(resolvedName as CFString, 16.0)
        if let matchedByName = CTFontDescriptorCreateMatchingFontDescriptors(nameDesc, nil) as? [CTFontDescriptor],
           !matchedByName.isEmpty
        {
            return matchedByName
        }

        return []
    }

    private func loadFamily(
        name: String,
        features: FontFeatures,
        fallbacks: FontFallbacks?
    ) throws -> [FontId] {
        let resolvedName = fontNameWithFallbacks(name, system: ".AppleSystemUIFont")
        let descriptors = descriptorsForFamily(resolvedName)
        guard !descriptors.isEmpty else {
            throw MacTextSystemError.familyNotFound(resolvedName)
        }

        var fontIds: [FontId] = []
        for descriptor in descriptors {
            var ctFont = CTFontCreateWithFontDescriptor(descriptor, 16.0, nil)
            applyFeaturesAndFallbacks(&ctFont, features, fallbacks)

            // Guard against fonts missing the 'm' glyph (with upstream exception for Segoe Fluent Icons).
            var mUtf16: [UniChar] = [UniChar(0x6D)]
            var mGlyph: [CGGlyph] = [0]
            let hasMGlyph = CTFontGetGlyphsForCharacters(ctFont, &mUtf16, &mGlyph, 1) && mGlyph[0] != 0
            let fullName = CTFontCopyFullName(ctFont) as String
            let isSegoeFluentIcons = fullName == "Segoe Fluent Icons"
            if !hasMGlyph && !isSegoeFluentIcons {
                continue
            }

            guard let face = buildLoadedFontFace(from: ctFont) else {
                continue
            }

            let id = FontId(fonts.count)
            fontIds.append(id)
            fontIdsByPostscriptName[face.postscriptName] = id
            postscriptNamesByFontId[id] = face.postscriptName
            fonts.append(face)
        }

        guard !fontIds.isEmpty else {
            throw MacTextSystemError.familyNotFound(resolvedName)
        }
        return fontIds
    }

    func idForNativeFont(_ requestedFont: CTFont) -> FontId {
        let postscriptName = CTFontCopyPostScriptName(requestedFont) as String
        if let existing = fontIdsByPostscriptName[postscriptName] {
            return existing
        }
        let cgFont = CTFontCopyGraphicsFont(requestedFont, nil)
        let unscaledCtFont = CTFontCreateWithGraphicsFont(cgFont, 16.0, nil, nil)
        let face = buildLoadedFontFace(from: unscaledCtFont) ?? LoadedFontFace(
            ctFont: unscaledCtFont,
            cgFont: cgFont,
            postscriptName: postscriptName,
            fullName: CTFontCopyFullName(unscaledCtFont) as String,
            weight: 400.0,
            style: .normal,
            stretch: 0.0,
            metrics: FontMetrics()
        )
        let id = FontId(fonts.count)
        fontIdsByPostscriptName[postscriptName] = id
        postscriptNamesByFontId[id] = postscriptName
        fonts.append(face)
        return id
    }

    func isEmoji(_ fontId: FontId) -> Bool {
        guard let psName = postscriptNamesByFontId[fontId] else {
            return false
        }
        return psName == "AppleColorEmoji" || psName == ".AppleColorEmojiUI"
    }

    func typographicBounds(fontId: FontId, glyphId: GlyphId) -> Bounds<Float> {
        let face = fonts[fontId.value]
        let metricsFont = CTFontCreateCopyWithAttributes(
            face.ctFont,
            CGFloat(face.metrics.unitsPerEm),
            nil,
            nil
        )
        var glyph = CGGlyph(glyphId.value)
        var rect = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(metricsFont, .default, &glyph, &rect, 1)
        return Bounds(
            origin: point(Float(rect.origin.x), Float(rect.origin.y)),
            size: size(Float(rect.size.width), Float(rect.size.height))
        )
    }

    func advance(fontId: FontId, glyphId: GlyphId) -> Size<Float> {
        let face = fonts[fontId.value]
        let metricsFont = CTFontCreateCopyWithAttributes(
            face.ctFont,
            CGFloat(face.metrics.unitsPerEm),
            nil,
            nil
        )
        var glyph = CGGlyph(glyphId.value)
        var adv = CGSize.zero
        _ = CTFontGetAdvancesForGlyphs(metricsFont, .default, &glyph, &adv, 1)
        return size(Float(adv.width), Float(adv.height))
    }

    func glyphForChar(fontId: FontId, ch: Character) -> GlyphId? {
        let face = fonts[fontId.value]
        var utf16 = Array(String(ch).utf16)
        guard !utf16.isEmpty else { return nil }
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        let ok = CTFontGetGlyphsForCharacters(face.ctFont, &utf16, &glyphs, utf16.count)
        guard ok, glyphs[0] != 0 else {
            return nil
        }
        return GlyphId(UInt32(glyphs[0]))
    }

    func rasterBounds(params: RenderGlyphParams) -> Bounds<DevicePixels> {
        let face = fonts[params.fontId.value]
        let scaledSize = CGFloat(params.fontSize.value * params.scaleFactor)
        let scaledFont = CTFontCreateCopyWithAttributes(face.ctFont, scaledSize, nil, nil)
        var glyph = CGGlyph(params.glyphId.value)
        var rect = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(scaledFont, .default, &glyph, &rect, 1)

        if rect.isEmpty || rect.width <= 0.0 || rect.height <= 0.0 {
            return .zero
        }

        let minX = Int32(floor(rect.minX))
        let minY = Int32(floor(-rect.maxY))
        let maxX = Int32(ceil(rect.maxX))
        let maxY = Int32(ceil(-rect.minY))
        let width = maxX - minX
        let height = maxY - minY
        if width <= 0 || height <= 0 {
            return .zero
        }

        var bounds = Bounds(
            origin: point(DevicePixels(minX), DevicePixels(minY)),
            size: size(DevicePixels(width), DevicePixels(height))
        )

        // Add 3% of font size as padding, clamped between 1 and 5 pixels, matching upstream.
        let rawPad = Int32(ceil(params.fontSize.value * 0.03 * params.scaleFactor))
        let pad = min(max(rawPad, 1), 5)
        bounds.origin.x -= DevicePixels(pad)
        bounds.size.width += DevicePixels(pad)
        return bounds
    }

    func rasterizeGlyph(
        params: RenderGlyphParams,
        glyphBounds: Bounds<DevicePixels>
    ) throws -> (Size<DevicePixels>, Data) {
        if glyphBounds.size.width.value <= 0 || glyphBounds.size.height.value <= 0 {
            throw MacTextSystemError.emptyGlyphBounds
        }

        var bitmapSize = glyphBounds.size
        if params.subpixelVariant.x > 0 {
            bitmapSize.width += DevicePixels(1)
        }
        if params.subpixelVariant.y > 0 {
            bitmapSize.height += DevicePixels(1)
        }

        let width = Int(bitmapSize.width.value)
        let height = Int(bitmapSize.height.value)
        let face = fonts[params.fontId.value]
        let drawFont = CTFontCreateCopyWithAttributes(face.ctFont, CGFloat(params.fontSize.value), nil, nil)

        let subpixelShiftX = Float(params.subpixelVariant.x) / Float(subpixelVariantsX)
        let subpixelShiftY = Float(params.subpixelVariant.y) / Float(subpixelVariantsX)

        if params.isEmoji {
            var bytes = [UInt8](repeating: 0, count: width * 4 * height)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            try bytes.withUnsafeMutableBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress,
                      let cx = CGContext(
                          data: baseAddress,
                          width: width,
                          height: height,
                          bitsPerComponent: 8,
                          bytesPerRow: width * 4,
                          space: colorSpace,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                      )
                else {
                    throw MacTextSystemError.emptyGlyphBounds
                }

                configureGlyphContext(cx, params: params, glyphBounds: glyphBounds)
                var glyph = CGGlyph(params.glyphId.value)
                var pos = CGPoint(
                    x: CGFloat(subpixelShiftX / params.scaleFactor),
                    y: CGFloat(subpixelShiftY / params.scaleFactor)
                )
                CTFontDrawGlyphs(drawFont, &glyph, &pos, 1, cx)
            }

            // Convert premultiplied RGBA to straight-alpha BGRA for Metal polychrome atlas.
            var offset = 0
            while offset + 4 <= bytes.count {
                var pixel: [UInt8] = [
                    bytes[offset],
                    bytes[offset + 1],
                    bytes[offset + 2],
                    bytes[offset + 3],
                ]
                swapRgbaPaToBgra(&pixel)
                bytes[offset] = pixel[0]
                bytes[offset + 1] = pixel[1]
                bytes[offset + 2] = pixel[2]
                bytes[offset + 3] = pixel[3]
                offset += 4
            }
            return (bitmapSize, Data(bytes))
        } else {
            let colorSpace = CGColorSpaceCreateDeviceGray()
            var bytes = [UInt8](repeating: 0, count: width * height)
            try bytes.withUnsafeMutableBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress,
                      let cx = CGContext(
                          data: baseAddress,
                          width: width,
                          height: height,
                          bitsPerComponent: 8,
                          bytesPerRow: width,
                          space: colorSpace,
                          bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
                      )
                else {
                    throw MacTextSystemError.emptyGlyphBounds
                }

                configureGlyphContext(cx, params: params, glyphBounds: glyphBounds)
                var glyph = CGGlyph(params.glyphId.value)
                var pos = CGPoint(
                    x: CGFloat(subpixelShiftX / params.scaleFactor),
                    y: CGFloat(subpixelShiftY / params.scaleFactor)
                )
                CTFontDrawGlyphs(drawFont, &glyph, &pos, 1, cx)
            }
            return (bitmapSize, Data(bytes))
        }
    }

    private func configureGlyphContext(
        _ cx: CGContext,
        params: RenderGlyphParams,
        glyphBounds: Bounds<DevicePixels>
    ) {
        cx.translateBy(
            x: CGFloat(-glyphBounds.origin.x.value),
            y: CGFloat(glyphBounds.origin.y.value + glyphBounds.size.height.value)
        )
        cx.scaleBy(
            x: CGFloat(params.scaleFactor),
            y: CGFloat(params.scaleFactor)
        )
        cx.setTextDrawingMode(.fill)
        cx.setFillColor(gray: 0.0, alpha: 1.0)
        cx.setAllowsAntialiasing(true)
        cx.setShouldAntialias(true)
        cx.setAllowsFontSubpixelPositioning(true)
        cx.setShouldSubpixelPositionFonts(true)
        cx.setAllowsFontSubpixelQuantization(false)
        cx.setShouldSubpixelQuantizeFonts(false)
    }

    func layoutLine(text: String, fontSize: Pixels, fontRuns: [FontRun]) -> LineLayout {
        guard let attrString = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0) else {
            return LineLayout(fontSize: fontSize, len: text.utf8.count)
        }

        var maxAscent: Float = 0.0
        var maxDescent: Float = 0.0

        let utf8View = text.utf8
        var utf8Cursor = utf8View.startIndex
        var breakLigature = true
        // Tracks `(attrStringUtf16Pos, droppedUtf16Count)` whenever CoreFoundation silently drops
        // code units (such as a leading U+FEFF BOM) during `CFAttributedStringReplaceString`.
        var droppedUtf16Deltas: [(attrPos: Int, dropped: Int)] = []

        for run in fontRuns {
            let remaining = utf8View.distance(from: utf8Cursor, to: utf8View.endIndex)
            let takeBytes = min(max(0, run.len), remaining)
            let nextCursor = utf8View.index(utf8Cursor, offsetBy: takeBytes)
            let runSlice = utf8View[utf8Cursor ..< nextCursor]
            utf8Cursor = nextCursor

            // PORT NOTE: `CFStringCreateWithBytes(..., isExternalRepresentation: true)` matches upstream
            // `CFString::new(text_run)` (stripping leading U+FEFF so CoreText never emits `kCGFontIndexInvalid`),
            // while `droppedUtf16Deltas` records the exact UTF-16 delta at `utf16Start` so mid-line `FontRun`s
            // starting with U+FEFF still map every glyph back to its true UTF-8 byte index in `text`.
            let expectedUtf16Len = String(decoding: runSlice, as: UTF8.self).utf16.count
            let runCFString: CFString = Array(runSlice).withUnsafeBufferPointer { buf in
                CFStringCreateWithBytes(
                    kCFAllocatorDefault,
                    buf.baseAddress,
                    buf.count,
                    CFStringBuiltInEncodings.UTF8.rawValue,
                    true
                ) ?? ("" as CFString)
            }

            let utf16Start = CFAttributedStringGetLength(attrString)
            CFAttributedStringReplaceString(
                attrString,
                CFRange(location: utf16Start, length: 0),
                runCFString
            )
            let utf16End = CFAttributedStringGetLength(attrString)
            let length = utf16End - utf16Start
            if length < expectedUtf16Len {
                droppedUtf16Deltas.append((attrPos: utf16Start, dropped: expectedUtf16Len - length))
            }
            let cfRange = CFRange(location: utf16Start, length: length)

            let face = fonts[run.fontId.value]
            let fontScale = fontSize.value / Float(face.metrics.unitsPerEm)
            maxAscent = max(maxAscent, face.metrics.ascent * fontScale)
            maxDescent = max(maxDescent, -face.metrics.descent * fontScale)

            let effectiveSize = breakLigature ? fontSize.value.nextUp : fontSize.value
            let sizedFont = CTFontCreateCopyWithAttributes(face.ctFont, CGFloat(effectiveSize), nil, nil)
            if length > 0 {
                CFAttributedStringSetAttribute(attrString, cfRange, kCTFontAttributeName, sizedFont)
            }
            breakLigature.toggle()
        }

        let ctLine = CTLineCreateWithAttributedString(attrString)
        let glyphRuns = (CTLineGetGlyphRuns(ctLine) as? [CTRun]) ?? []
        var shapedRuns: [ShapedRun] = []
        shapedRuns.reserveCapacity(glyphRuns.count)

        var ixConverter = StringIndexConverter(text)

        for ctRun in glyphRuns {
            let attrs = (CTRunGetAttributes(ctRun) as? [CFString: Any]) ?? [:]
            guard let fontVal = attrs[kCTFontAttributeName] else { continue }
            // CFType downcast verified via CoreText's CTFontGetTypeID()
            guard CFGetTypeID(fontVal as CFTypeRef) == CTFontGetTypeID() else { continue }
            // PORT NOTE: CFGetTypeID check above guarantees fontVal is a CTFont instance.
            let runFont = (fontVal as! CTFont)
            let fontId = idForNativeFont(runFont)

            let glyphCount = CTRunGetGlyphCount(ctRun)
            guard glyphCount > 0 else { continue }

            var glyphsBuf = [CGGlyph](repeating: 0, count: glyphCount)
            var positionsBuf = [CGPoint](repeating: .zero, count: glyphCount)
            var indicesBuf = [CFIndex](repeating: 0, count: glyphCount)
            let fullRange = CFRange(location: 0, length: glyphCount)
            CTRunGetGlyphs(ctRun, fullRange, &glyphsBuf)
            CTRunGetPositions(ctRun, fullRange, &positionsBuf)
            CTRunGetStringIndices(ctRun, fullRange, &indicesBuf)

            let emoji = isEmoji(fontId)
            var runGlyphs: [ShapedGlyph] = []
            runGlyphs.reserveCapacity(glyphCount)

            for i in 0 ..< glyphCount {
                let rawAttrIx = max(0, indicesBuf[i])
                var droppedOffset = 0
                for delta in droppedUtf16Deltas where delta.attrPos <= rawAttrIx {
                    droppedOffset += delta.dropped
                }
                let glyphUtf16Ix = rawAttrIx + droppedOffset
                if ixConverter.utf16Ix > glyphUtf16Ix {
                    ixConverter = StringIndexConverter(text)
                }
                ixConverter.advanceToUtf16Ix(glyphUtf16Ix)
                runGlyphs.append(ShapedGlyph(
                    id: GlyphId(UInt32(glyphsBuf[i])),
                    position: point(px(Float(positionsBuf[i].x)), px(Float(positionsBuf[i].y))),
                    index: ixConverter.utf8Ix,
                    isEmoji: emoji
                ))
            }

            if let lastIdx = shapedRuns.indices.last, shapedRuns[lastIdx].fontId == fontId {
                shapedRuns[lastIdx].glyphs.append(contentsOf: runGlyphs)
            } else {
                shapedRuns.append(ShapedRun(fontId: fontId, glyphs: runGlyphs))
            }
        }

        let typoWidth = CTLineGetTypographicBounds(ctLine, nil, nil, nil)
        return LineLayout(
            fontSize: fontSize,
            width: px(Float(typoWidth)),
            ascent: px(maxAscent),
            descent: px(maxDescent),
            runs: shapedRuns,
            len: text.utf8.count
        )
    }
}

/// CoreText + CoreGraphics implementation of `PlatformTextSystem` for macOS.
// PORT NOTE: Synchronized via NSLock matching upstream `RwLock<MacTextSystemState>`.
public final class MacTextSystem: PlatformTextSystem, @unchecked Sendable {
    private let lock = NSLock()
    private let state = MacTextSystemState()

    public init() {}

    public static func new() -> MacTextSystem {
        MacTextSystem()
    }

    public func addFonts(_ fonts: [Data]) throws {
        lock.lock()
        defer { lock.unlock() }
        try state.addFonts(fonts)
    }

    public func allFontNames() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return state.allFontNames()
    }

    public func fontId(descriptor: Font) throws -> FontId {
        lock.lock()
        defer { lock.unlock() }
        return try state.fontId(for: descriptor)
    }

    public func fontMetrics(fontId: FontId) -> FontMetrics {
        lock.lock()
        defer { lock.unlock() }
        return state.fonts[fontId.value].metrics
    }

    public func typographicBounds(fontId: FontId, glyphId: GlyphId) throws -> Bounds<Float> {
        lock.lock()
        defer { lock.unlock() }
        return state.typographicBounds(fontId: fontId, glyphId: glyphId)
    }

    public func advance(fontId: FontId, glyphId: GlyphId) throws -> Size<Float> {
        lock.lock()
        defer { lock.unlock() }
        return state.advance(fontId: fontId, glyphId: glyphId)
    }

    public func glyphForChar(fontId: FontId, ch: Character) -> GlyphId? {
        lock.lock()
        defer { lock.unlock() }
        return state.glyphForChar(fontId: fontId, ch: ch)
    }

    public func glyphRasterBounds(params: RenderGlyphParams) throws -> Bounds<DevicePixels> {
        lock.lock()
        defer { lock.unlock() }
        return state.rasterBounds(params: params)
    }

    public func rasterizeGlyph(
        params: RenderGlyphParams,
        rasterBounds: Bounds<DevicePixels>
    ) throws -> (Size<DevicePixels>, Data) {
        lock.lock()
        defer { lock.unlock() }
        return try state.rasterizeGlyph(params: params, glyphBounds: rasterBounds)
    }

    public func layoutLine(text: String, fontSize: Pixels, runs: [FontRun]) -> LineLayout {
        lock.lock()
        defer { lock.unlock() }
        return state.layoutLine(text: text, fontSize: fontSize, fontRuns: runs)
    }

    public func recommendedRenderingMode(fontId: FontId, fontSize: Pixels) -> TextRenderingMode {
        _ = fontId
        _ = fontSize
        return .grayscale
    }
}
#endif
