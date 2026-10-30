// Ported from: crates/gpui_ios/src/text_system.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(iOS) || os(visionOS)
import CoreFoundation
import CoreGraphics
import CoreText
import Foundation
import GPUI
import UIKit

// MARK: - Errors

/// Errors emitted by `IosTextSystem` during font registration, lookup, or glyph rasterization.
public enum IosTextSystemError: Error, LocalizedError, Sendable {
    case invalidFontData
    case fontNotFound(String)
    case invalidFontId(FontId)
    case emptyGlyphBounds
    case bitmapContextCreationFailed

    public var errorDescription: String? {
        switch self {
        case .invalidFontData:
            return "Could not decode CoreText font descriptors from provided font data"
        case .fontNotFound(let family):
            return "Font family '\(family)' could not be resolved on iOS"
        case .invalidFontId(let id):
            return "Invalid FontId(\(id.value)) in IosTextSystem"
        case .emptyGlyphBounds:
            return "Glyph raster bounds are empty"
        case .bitmapContextCreationFailed:
            return "Failed to allocate CoreGraphics bitmap context for glyph rasterization"
        }
    }
}

// MARK: - Lenient Font Attribute Helper

/// Reads `kCTFontFamilyNameAttribute` from a `CTFontDescriptor`, matching upstream
/// `lenient_font_attributes::family_name`.
public func familyName(_ descriptor: CTFontDescriptor) -> String? {
    CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String
}

// MARK: - UTF-8 <-> UTF-16 Run Index Converter

/// Incrementally maps CoreText UTF-16 `CTRun` string indices to GPUI UTF-8 byte offsets,
/// matching upstream `StringIndexConverter`.
private struct StringIndexConverter {
    let text: String
    var utf8Index: String.UTF8View.Index
    var utf8ByteOffset: Int
    var utf16Offset: Int

    init(_ text: String) {
        self.text = text
        self.utf8Index = text.utf8.startIndex
        self.utf8ByteOffset = 0
        self.utf16Offset = 0
    }

    mutating func advanceToUtf16Index(_ targetUtf16: Int) {
        if utf16Offset > targetUtf16 {
            self = StringIndexConverter(text)
        }
        guard let startScalarIdx = String.Index(utf8Index, within: text) else {
            utf8ByteOffset = text.utf8.count
            utf8Index = text.utf8.endIndex
            return
        }

        var cursor = startScalarIdx
        while cursor < text.endIndex {
            if utf16Offset >= targetUtf16 {
                utf8Index = cursor.samePosition(in: text.utf8) ?? text.utf8.endIndex
                return
            }
            let ch = text[cursor]
            let chUtf16 = ch.utf16.count
            let chUtf8 = ch.utf8.count
            utf16Offset += chUtf16
            utf8ByteOffset += chUtf8
            cursor = text.index(after: cursor)
        }
        utf8ByteOffset = text.utf8.count
        utf8Index = text.utf8.endIndex
    }
}

// MARK: - Internal Mutable State

private final class IosTextSystemState {
    /// Indexed by `FontId.value`.
    var fonts: [CTFont] = []
    var fontIdsByDescriptor: [Font: FontId] = [:]
    var fontIdsByPostScriptName: [String: FontId] = [:]
    var postScriptNamesByFontId: [FontId: String] = [:]
    var customDescriptorsByFamily: [String: [CTFontDescriptor]] = [:]
    var customPostScriptFonts: [String: CTFont] = [:]

    func registerNativeFont(_ ctFont: CTFont) -> FontId {
        let psName = CTFontCopyPostScriptName(ctFont) as String
        if let existing = fontIdsByPostScriptName[psName] {
            return existing
        }
        let id = FontId(fonts.count)
        fonts.append(ctFont)
        fontIdsByPostScriptName[psName] = id
        postScriptNamesByFontId[id] = psName
        return id
    }

    func registerConfiguredFont(_ ctFont: CTFont, for descriptor: Font) -> FontId {
        let psName = CTFontCopyPostScriptName(ctFont) as String
        let id = FontId(fonts.count)
        fonts.append(ctFont)
        fontIdsByDescriptor[descriptor] = id
        if fontIdsByPostScriptName[psName] == nil {
            fontIdsByPostScriptName[psName] = id
        }
        postScriptNamesByFontId[id] = psName
        return id
    }

    func isEmoji(_ fontId: FontId) -> Bool {
        if let psName = postScriptNamesByFontId[fontId],
           psName == "AppleColorEmoji" || psName == ".AppleColorEmojiUI"
        {
            return true
        }
        guard fontId.value >= 0, fontId.value < fonts.count else {
            return false
        }
        let traits = CTFontGetSymbolicTraits(fonts[fontId.value])
        return traits.contains(.traitColorGlyphs)
    }
}

// MARK: - CoreText PlatformTextSystem for iOS

/// CoreText + CoreGraphics implementation of `PlatformTextSystem` for iOS and visionOS.
// PORT NOTE: Synchronized via `NSLock` protecting `IosTextSystemState` font tables, matching
// upstream `RwLock<IosTextSystemState>`.
public final class IosTextSystem: PlatformTextSystem, @unchecked Sendable {
    private let lock = NSLock()
    private let state = IosTextSystemState()

    public init() {}

    /// Creates a new `IosTextSystem` matching upstream `IosTextSystem::new()`.
    public static func new() -> IosTextSystem {
        IosTextSystem()
    }

    // MARK: - PlatformTextSystem Conformance

    public func addFonts(_ fonts: [Data]) throws {
        var parsedDescriptors: [(family: String, postScript: String?, descriptor: CTFontDescriptor, font: CTFont)] = []

        for fontData in fonts {
            guard !fontData.isEmpty else { continue }
            if let descriptors = CTFontManagerCreateFontDescriptorsFromData(fontData as CFData) as? [CTFontDescriptor],
               !descriptors.isEmpty
            {
                for desc in descriptors {
                    let ctFont = CTFontCreateWithFontDescriptor(desc, 16.0, nil)
                    let fam = familyName(desc) ?? (CTFontCopyFamilyName(ctFont) as String)
                    let ps = CTFontDescriptorCopyAttribute(desc, kCTFontNameAttribute) as? String
                    parsedDescriptors.append((fam, ps, desc, ctFont))
                }
            } else if let provider = CGDataProvider(data: fontData as CFData),
                      let cgFont = CGFont(provider)
            {
                var regError: Unmanaged<CFError>?
                _ = CTFontManagerRegisterGraphicsFont(cgFont, &regError)
                let ctFont = CTFontCreateWithGraphicsFont(cgFont, 16.0, nil, nil)
                let desc = CTFontCopyFontDescriptor(ctFont)
                let fam = familyName(desc) ?? (CTFontCopyFamilyName(ctFont) as String)
                let ps = CTFontCopyPostScriptName(ctFont) as String
                parsedDescriptors.append((fam, ps, desc, ctFont))
            } else {
                throw IosTextSystemError.invalidFontData
            }
        }

        lock.lock()
        defer { lock.unlock() }
        for item in parsedDescriptors {
            state.customDescriptorsByFamily[item.family, default: []].append(item.descriptor)
            if let ps = item.postScript {
                state.customPostScriptFonts[ps] = item.font
            }
        }
    }

    public func allFontNames() -> [String] {
        var names = Set<String>()

        let collection = CTFontCollectionCreateFromAvailableFonts(nil)
        if let descriptors = CTFontCollectionCreateMatchingFontDescriptors(collection) as? [CTFontDescriptor] {
            for desc in descriptors {
                if let fam = familyName(desc), !fam.isEmpty {
                    names.insert(fam)
                }
            }
        }

        lock.lock()
        for customFamily in state.customDescriptorsByFamily.keys {
            names.insert(customFamily)
        }
        lock.unlock()

        return names.sorted()
    }

    public func fontId(descriptor: Font) throws -> FontId {
        lock.lock()
        if let cached = state.fontIdsByDescriptor[descriptor] {
            lock.unlock()
            return cached
        }
        let customFamilyDescriptors = state.customDescriptorsByFamily
        lock.unlock()

        var ctFont = resolveBaseFont(descriptor: descriptor, customFamilies: customFamilyDescriptors)
        applyFeaturesAndFallbacks(&ctFont, descriptor.features, descriptor.fallbacks)

        lock.lock()
        defer { lock.unlock() }
        if let existing = state.fontIdsByDescriptor[descriptor] {
            return existing
        }
        return state.registerConfiguredFont(ctFont, for: descriptor)
    }

    public func fontMetrics(fontId: FontId) -> FontMetrics {
        guard let ctFont = font(for: fontId) else {
            return FontMetrics()
        }

        let unitsPerEm = max(UInt32(1), CTFontGetUnitsPerEm(ctFont))
        let pointSize = Float(max(CGFloat(1.0), CTFontGetSize(ctFont)))
        // Convert metrics from CTFont's point-size coordinates into font design units
        // (`unitsPerEm`), matching `font_kit::Metrics` expectations in `GPUI.FontMetrics`.
        let toFontUnits = Float(unitsPerEm) / pointSize

        let ascent = Float(CTFontGetAscent(ctFont)) * toFontUnits
        // CoreText `CTFontGetDescent` returns a positive magnitude; GPUI `FontMetrics.descent`
        // follows `font_kit` where descent below baseline is negative.
        let descent = -Float(CTFontGetDescent(ctFont)) * toFontUnits
        let leading = Float(CTFontGetLeading(ctFont)) * toFontUnits
        let underlinePosition = Float(CTFontGetUnderlinePosition(ctFont)) * toFontUnits
        let underlineThickness = Float(CTFontGetUnderlineThickness(ctFont)) * toFontUnits
        let capHeight = Float(CTFontGetCapHeight(ctFont)) * toFontUnits
        let xHeight = Float(CTFontGetXHeight(ctFont)) * toFontUnits
        let bbox = CTFontGetBoundingBox(ctFont)

        return FontMetrics(
            unitsPerEm: unitsPerEm,
            ascent: ascent,
            descent: descent,
            lineGap: leading,
            underlinePosition: underlinePosition,
            underlineThickness: underlineThickness,
            capHeight: capHeight,
            xHeight: xHeight,
            boundingBox: Bounds(
                origin: Point(
                    x: Float(bbox.origin.x) * toFontUnits,
                    y: Float(bbox.origin.y) * toFontUnits
                ),
                size: Size(
                    width: Float(bbox.size.width) * toFontUnits,
                    height: Float(bbox.size.height) * toFontUnits
                )
            )
        )
    }

    public func typographicBounds(fontId: FontId, glyphId: GlyphId) throws -> Bounds<Float> {
        guard let ctFont = font(for: fontId) else {
            throw IosTextSystemError.invalidFontId(fontId)
        }
        let unitsPerEm = Float(max(UInt32(1), CTFontGetUnitsPerEm(ctFont)))
        let pointSize = Float(max(CGFloat(1.0), CTFontGetSize(ctFont)))
        let toFontUnits = unitsPerEm / pointSize

        var cgGlyph = CGGlyph(truncatingIfNeeded: glyphId.value)
        var rect = CGRect.zero
        _ = CTFontGetBoundingRectsForGlyphs(ctFont, .default, &cgGlyph, &rect, 1)

        return Bounds(
            origin: Point(
                x: Float(rect.origin.x) * toFontUnits,
                y: Float(rect.origin.y) * toFontUnits
            ),
            size: Size(
                width: Float(rect.size.width) * toFontUnits,
                height: Float(rect.size.height) * toFontUnits
            )
        )
    }

    public func advance(fontId: FontId, glyphId: GlyphId) throws -> Size<Float> {
        guard let ctFont = font(for: fontId) else {
            throw IosTextSystemError.invalidFontId(fontId)
        }
        let unitsPerEm = Float(max(UInt32(1), CTFontGetUnitsPerEm(ctFont)))
        let pointSize = Float(max(CGFloat(1.0), CTFontGetSize(ctFont)))
        let toFontUnits = unitsPerEm / pointSize

        var cgGlyph = CGGlyph(truncatingIfNeeded: glyphId.value)
        var advance = CGSize.zero
        _ = CTFontGetAdvancesForGlyphs(ctFont, .default, &cgGlyph, &advance, 1)

        return Size(
            width: Float(advance.width) * toFontUnits,
            height: Float(advance.height) * toFontUnits
        )
    }

    public func glyphForChar(fontId: FontId, ch: Character) -> GlyphId? {
        guard let ctFont = font(for: fontId) else {
            return nil
        }
        let utf16Units = Array(String(ch).utf16)
        guard !utf16Units.isEmpty else {
            return nil
        }
        var glyphs = [CGGlyph](repeating: 0, count: utf16Units.count)
        let mapped = CTFontGetGlyphsForCharacters(ctFont, utf16Units, &glyphs, utf16Units.count)
        if mapped && glyphs[0] != 0 {
            return GlyphId(UInt32(glyphs[0]))
        }
        return nil
    }

    public func glyphRasterBounds(params: RenderGlyphParams) throws -> Bounds<DevicePixels> {
        guard let baseFont = font(for: params.fontId) else {
            throw IosTextSystemError.invalidFontId(params.fontId)
        }

        let devicePointSize = CGFloat(params.fontSize.value * params.scaleFactor)
        guard devicePointSize > 0 else {
            return .zero
        }

        let scaledFont = CTFontCreateCopyWithAttributes(baseFont, devicePointSize, nil, nil)
        var cgGlyph = CGGlyph(truncatingIfNeeded: params.glyphId.value)
        var rect = CGRect.zero
        _ = CTFontGetBoundingRectsForGlyphs(scaledFont, .default, &cgGlyph, &rect, 1)

        if rect.isNull || rect.isEmpty || rect.width <= 0 || rect.height <= 0 {
            return .zero
        }

        // Pad by 1px on edges for antialiasing / optical overhang and convert CoreText Y-up
        // coordinates (baseline = 0, ascender > 0) to GPUI Y-down screen coordinates
        // (baseline = 0, ascender < 0).
        let minX = Int32(floor(rect.minX))
        let maxX = Int32(ceil(rect.maxX))
        let minY = Int32(floor(rect.minY))
        let maxY = Int32(ceil(rect.maxY))

        let width = max(Int32(0), maxX - minX)
        let height = max(Int32(0), maxY - minY)
        if width == 0 || height == 0 {
            return .zero
        }

        return Bounds(
            origin: Point(
                x: DevicePixels(minX),
                y: DevicePixels(-maxY)
            ),
            size: Size(
                width: DevicePixels(width),
                height: DevicePixels(height)
            )
        )
    }

    public func rasterizeGlyph(
        params: RenderGlyphParams,
        rasterBounds: Bounds<DevicePixels>
    ) throws -> (Size<DevicePixels>, Data) {
        if rasterBounds.size.width.value <= 0 || rasterBounds.size.height.value <= 0 {
            throw IosTextSystemError.emptyGlyphBounds
        }
        guard let baseFont = font(for: params.fontId) else {
            throw IosTextSystemError.invalidFontId(params.fontId)
        }

        var bitmapSize = rasterBounds.size
        if params.subpixelVariant.x > 0 {
            bitmapSize.width = DevicePixels(bitmapSize.width.value + 1)
        }
        if params.subpixelVariant.y > 0 {
            bitmapSize.height = DevicePixels(bitmapSize.height.value + 1)
        }

        let width = Int(bitmapSize.width.value)
        let height = Int(bitmapSize.height.value)

        let scale = CGFloat(max(0.001, params.scaleFactor))
        let subpixelShiftX = Float(params.subpixelVariant.x) / Float(subpixelVariantsX)
        let subpixelShiftY = Float(params.subpixelVariant.y) / Float(subpixelVariantsY)
        let sizedFont = CTFontCreateCopyWithAttributes(
            baseFont,
            CGFloat(params.fontSize.value),
            nil,
            nil
        )

        func configureAndDraw(_ context: CGContext) {
            context.translateBy(
                x: CGFloat(-rasterBounds.origin.x.value),
                y: CGFloat(rasterBounds.origin.y.value + rasterBounds.size.height.value)
            )
            context.scaleBy(x: scale, y: scale)
            context.setTextDrawingMode(.fill)
            context.setFillColor(gray: 0.0, alpha: 1.0)
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)
            context.setAllowsFontSubpixelPositioning(true)
            context.setShouldSubpixelPositionFonts(true)
            context.setAllowsFontSubpixelQuantization(false)
            context.setShouldSubpixelQuantizeFonts(false)

            var cgGlyph = CGGlyph(truncatingIfNeeded: params.glyphId.value)
            var position = CGPoint(
                x: CGFloat(subpixelShiftX / params.scaleFactor),
                y: CGFloat(subpixelShiftY / params.scaleFactor)
            )
            CTFontDrawGlyphs(sizedFont, &cgGlyph, &position, 1, context)
            context.flush()
        }

        if params.isEmoji {
            let bytesPerRow = width * 4
            var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            try pixels.withUnsafeMutableBytes { rawPtr in
                guard let baseAddress = rawPtr.baseAddress,
                      let context = CGContext(
                          data: baseAddress,
                          width: width,
                          height: height,
                          bitsPerComponent: 8,
                          bytesPerRow: bytesPerRow,
                          space: colorSpace,
                          bitmapInfo: bitmapInfo
                      )
                else {
                    throw IosTextSystemError.bitmapContextCreationFailed
                }
                configureAndDraw(context)
            }

            // Convert premultiplied RGBA (`kCGImageAlphaPremultipliedLast`) to BGRA expected by
            // `MetalAtlas` polychrome `.bgra8Unorm` textures, matching `swap_rgba_pa_to_bgra`.
            var idx = 0
            while idx + 3 < pixels.count {
                let r = UInt16(pixels[idx])
                let g = UInt16(pixels[idx + 1])
                let b = UInt16(pixels[idx + 2])
                let a = UInt16(pixels[idx + 3])
                if a == 0 {
                    pixels[idx] = 0
                    pixels[idx + 1] = 0
                    pixels[idx + 2] = 0
                    pixels[idx + 3] = 0
                } else {
                    pixels[idx] = UInt8(min(255, (b * 255 + a / 2) / a))
                    pixels[idx + 1] = UInt8(min(255, (g * 255 + a / 2) / a))
                    pixels[idx + 2] = UInt8(min(255, (r * 255 + a / 2) / a))
                    pixels[idx + 3] = UInt8(a)
                }
                idx += 4
            }
            return (bitmapSize, Data(pixels))
        } else {
            let bytesPerRow = width
            var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
            let colorSpace = CGColorSpaceCreateDeviceGray()
            // Alpha-only 8-bit mask (`kCGImageAlphaOnly`) matching upstream grayscale glyph atlas.
            let bitmapInfo = CGImageAlphaInfo.alphaOnly.rawValue
            try pixels.withUnsafeMutableBytes { rawPtr in
                guard let baseAddress = rawPtr.baseAddress,
                      let context = CGContext(
                          data: baseAddress,
                          width: width,
                          height: height,
                          bitsPerComponent: 8,
                          bytesPerRow: bytesPerRow,
                          space: colorSpace,
                          bitmapInfo: bitmapInfo
                      )
                else {
                    throw IosTextSystemError.bitmapContextCreationFailed
                }
                configureAndDraw(context)
            }
            return (bitmapSize, Data(pixels))
        }
    }

    public func layoutLine(text: String, fontSize: Pixels, runs: [FontRun]) -> LineLayout {
        if text.isEmpty {
            var maxAscent: Float = 0.0
            var maxDescent: Float = 0.0
            for run in runs {
                let m = fontMetrics(fontId: run.fontId)
                let scale = fontSize.value / Float(max(UInt32(1), m.unitsPerEm))
                maxAscent = max(maxAscent, m.ascent * scale)
                maxDescent = max(maxDescent, -m.descent * scale)
            }
            if maxAscent == 0.0 && maxDescent == 0.0 {
                maxAscent = fontSize.value * 0.8
                maxDescent = fontSize.value * 0.2
            }
            return LineLayout(
                fontSize: fontSize,
                width: .zero,
                ascent: px(maxAscent),
                descent: px(maxDescent),
                runs: [],
                len: 0
            )
        }

        let attrString = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0)
        var maxAscent: Float = 0.0
        var maxDescent: Float = 0.0

        let utf8View = text.utf8
        var utf8Cursor = utf8View.startIndex
        var breakLigature = true

        for run in runs where run.len > 0 {
            let remainingBytes = utf8View.distance(from: utf8Cursor, to: utf8View.endIndex)
            guard remainingBytes > 0 else { break }
            let sliceBytes = min(run.len, remainingBytes)
            let nextUtf8 = utf8View.index(utf8Cursor, offsetBy: sliceBytes)
            let runSubstring: String
            if let startIdx = String.Index(utf8Cursor, within: text),
               let endIdx = String.Index(nextUtf8, within: text)
            {
                runSubstring = String(text[startIdx..<endIdx])
            } else {
                runSubstring = String(decoding: utf8View[utf8Cursor..<nextUtf8], as: UTF8.self)
            }
            utf8Cursor = nextUtf8

            let baseFont = font(for: run.fontId) ?? CTFontCreateUIFontForLanguage(.system, CGFloat(fontSize.value), nil)
            let metrics = fontMetrics(fontId: run.fontId)
            let fontScale = fontSize.value / Float(max(UInt32(1), metrics.unitsPerEm))
            maxAscent = max(maxAscent, metrics.ascent * fontScale)
            maxDescent = max(maxDescent, -metrics.descent * fontScale)

            // Alternate `nextUp` on adjacent runs to prevent CoreText from forming ligatures
            // across distinct styled `FontRun` boundaries, matching upstream `layout_line`.
            let effectiveFontSize = breakLigature ? fontSize.value.nextUp : fontSize.value
            breakLigature.toggle()

            if let attrString {
                let utf16Start = CFAttributedStringGetLength(attrString)
                CFAttributedStringReplaceString(
                    attrString,
                    CFRange(location: utf16Start, length: 0),
                    runSubstring as CFString
                )
                let utf16End = CFAttributedStringGetLength(attrString)
                let cfRange = CFRange(location: utf16Start, length: utf16End - utf16Start)
                if let baseFont {
                    let runFont = CTFontCreateCopyWithAttributes(
                        baseFont,
                        CGFloat(effectiveFontSize),
                        nil,
                        nil
                    )
                    CFAttributedStringSetAttribute(attrString, cfRange, kCTFontAttributeName, runFont)
                }
            }
        }

        // If any trailing UTF-8 bytes weren't covered by `runs`, append them with the default font.
        if utf8Cursor < utf8View.endIndex, let attrString {
            let tailString = String(decoding: utf8View[utf8Cursor..<utf8View.endIndex], as: UTF8.self)
            let utf16Start = CFAttributedStringGetLength(attrString)
            CFAttributedStringReplaceString(
                attrString,
                CFRange(location: utf16Start, length: 0),
                tailString as CFString
            )
            let utf16End = CFAttributedStringGetLength(attrString)
            let fallbackId = runs.last?.fontId ?? (try? fontId(descriptor: Font())) ?? FontId(0)
            if let fallbackFont = font(for: fallbackId) {
                let runFont = CTFontCreateCopyWithAttributes(fallbackFont, CGFloat(fontSize.value), nil, nil)
                CFAttributedStringSetAttribute(
                    attrString,
                    CFRange(location: utf16Start, length: utf16End - utf16Start),
                    kCTFontAttributeName,
                    runFont
                )
            }
        }

        guard let finalAttrString = attrString else {
            return LineLayout(
                fontSize: fontSize,
                width: .zero,
                ascent: px(maxAscent),
                descent: px(maxDescent),
                runs: [],
                len: text.utf8.count
            )
        }

        let ctLine = CTLineCreateWithAttributedString(finalAttrString)
        let ctRuns = (CTLineGetGlyphRuns(ctLine) as? [CTRun]) ?? []

        var shapedRuns: [ShapedRun] = []
        shapedRuns.reserveCapacity(ctRuns.count)
        var ixConverter = StringIndexConverter(text)

        for ctRun in ctRuns {
            let glyphCount = CTRunGetGlyphCount(ctRun)
            guard glyphCount > 0 else { continue }

            let attrs = CTRunGetAttributes(ctRun) as? [CFString: Any]
            let runFontObj = attrs?[kCTFontAttributeName]
            let runFontId: FontId
            if let obj = runFontObj {
                // CoreFoundation toll-free / CFTypeRef check for CTFont.
                let cfObj = obj as AnyObject
                if CFGetTypeID(cfObj) == CTFontGetTypeID() {
                    // Safe CoreFoundation downcast verified by `CTFontGetTypeID()`.
                    let ctFont = unsafeBitCast(cfObj, to: CTFont.self)
                    lock.lock()
                    runFontId = state.registerNativeFont(ctFont)
                    lock.unlock()
                } else {
                    runFontId = runs.first?.fontId ?? FontId(0)
                }
            } else {
                runFontId = runs.first?.fontId ?? FontId(0)
            }

            lock.lock()
            let isEmojiFont = state.isEmoji(runFontId)
            lock.unlock()

            var cgGlyphs = [CGGlyph](repeating: 0, count: glyphCount)
            var positions = [CGPoint](repeating: .zero, count: glyphCount)
            var stringIndices = [CFIndex](repeating: 0, count: glyphCount)
            let fullRange = CFRange(location: 0, length: glyphCount)
            CTRunGetGlyphs(ctRun, fullRange, &cgGlyphs)
            CTRunGetPositions(ctRun, fullRange, &positions)
            CTRunGetStringIndices(ctRun, fullRange, &stringIndices)

            var runGlyphs: [ShapedGlyph] = []
            runGlyphs.reserveCapacity(glyphCount)

            for i in 0..<glyphCount {
                let utf16Ix = max(0, stringIndices[i])
                ixConverter.advanceToUtf16Index(utf16Ix)
                runGlyphs.append(
                    ShapedGlyph(
                        id: GlyphId(UInt32(cgGlyphs[i])),
                        position: Point(
                            x: px(Float(positions[i].x)),
                            y: px(Float(positions[i].y))
                        ),
                        index: ixConverter.utf8ByteOffset,
                        isEmoji: isEmojiFont
                    )
                )
            }

            if let last = shapedRuns.last, last.fontId == runFontId {
                shapedRuns[shapedRuns.count - 1].glyphs.append(contentsOf: runGlyphs)
            } else {
                shapedRuns.append(ShapedRun(fontId: runFontId, glyphs: runGlyphs))
            }
        }

        var lineAscent: CGFloat = 0
        var lineDescent: CGFloat = 0
        var lineLeading: CGFloat = 0
        let typographicWidth = CTLineGetTypographicBounds(ctLine, &lineAscent, &lineDescent, &lineLeading)

        if maxAscent == 0.0 {
            maxAscent = Float(lineAscent)
        }
        if maxDescent == 0.0 {
            maxDescent = Float(lineDescent)
        }

        return LineLayout(
            fontSize: fontSize,
            width: px(Float(max(0.0, typographicWidth))),
            ascent: px(maxAscent),
            descent: px(maxDescent),
            runs: shapedRuns,
            len: text.utf8.count
        )
    }

    public func recommendedRenderingMode(fontId: FontId, fontSize: Pixels) -> TextRenderingMode {
        _ = fontId
        _ = fontSize
        // High-DPI Retina displays on iOS/iPadOS/visionOS always use grayscale antialiasing.
        return .grayscale
    }

    // MARK: - Font Resolution Helpers

    private func font(for fontId: FontId) -> CTFont? {
        lock.lock()
        defer { lock.unlock() }
        guard fontId.value >= 0, fontId.value < state.fonts.count else {
            return nil
        }
        return state.fonts[fontId.value]
    }

    private func resolveBaseFont(
        descriptor: Font,
        customFamilies: [String: [CTFontDescriptor]]
    ) -> CTFont {
        let rawFamily = descriptor.family.asString
        let mappedFamily = fontNameWithFallbacks(rawFamily, system: ".AppleSystemUIFont")
        let uiWeight = uiFontWeight(from: descriptor.weight)
        let isItalic = descriptor.style == .italic || descriptor.style == .oblique

        // 1. Check custom in-memory fonts registered via `addFonts`.
        if let customList = customFamilies[mappedFamily] ?? customFamilies[rawFamily],
           let firstDesc = customList.first
        {
            var ctFont = CTFontCreateWithFontDescriptor(firstDesc, 16.0, nil)
            if isItalic,
               let italicCopy = CTFontCreateCopyWithSymbolicTraits(
                   ctFont,
                   16.0,
                   nil,
                   .traitItalic,
                   .traitItalic
               )
            {
                ctFont = italicCopy
            }
            return ctFont
        }

        // 2. Check `.AppleSystemUIFont` / `.SystemUIFont` via UIKit system font descriptor.
        if mappedFamily == ".AppleSystemUIFont" || rawFamily == ".SystemUIFont" {
            var uiFont = UIFont.systemFont(ofSize: 16.0, weight: uiWeight)
            if isItalic,
               let italicDesc = uiFont.fontDescriptor.withSymbolicTraits(.traitItalic)
            {
                uiFont = UIFont(descriptor: italicDesc, size: 16.0)
            }
            return uiFont as CTFont
        }

        // 3. Monospace virtual aliases (`.ZedMono` -> `Lilex` -> `Menlo` fallback on iOS).
        if rawFamily == ".ZedMono" || rawFamily == "Zed Plex Mono" {
            if let lilex = tryCreateNamedFont(family: "Lilex", weight: descriptor.weight, isItalic: isItalic) {
                return lilex
            }
            var monoFont = UIFont.monospacedSystemFont(ofSize: 16.0, weight: uiWeight)
            if isItalic,
               let italicDesc = monoFont.fontDescriptor.withSymbolicTraits(.traitItalic)
            {
                monoFont = UIFont(descriptor: italicDesc, size: 16.0)
            }
            return monoFont as CTFont
        }

        // 4. Named system font family lookup via CoreText traits, falling back to system UI font.
        if let named = tryCreateNamedFont(family: mappedFamily, weight: descriptor.weight, isItalic: isItalic) {
            return named
        }

        var fallbackUiFont = UIFont.systemFont(ofSize: 16.0, weight: uiWeight)
        if isItalic,
           let italicDesc = fallbackUiFont.fontDescriptor.withSymbolicTraits(.traitItalic)
        {
            fallbackUiFont = UIFont(descriptor: italicDesc, size: 16.0)
        }
        return fallbackUiFont as CTFont
    }

    private func tryCreateNamedFont(
        family: String,
        weight: FontWeight,
        isItalic: Bool
    ) -> CTFont? {
        let ctWeight = coreTextWeight(from: weight)
        var traitsDict: [CFString: Any] = [
            kCTFontWeightTrait: NSNumber(value: ctWeight),
        ]
        if isItalic {
            traitsDict[kCTFontSymbolicTrait] = NSNumber(value: CTFontSymbolicTraits.traitItalic.rawValue)
            traitsDict[kCTFontSlantTrait] = NSNumber(value: 0.2)
        }
        let attrs: [CFString: Any] = [
            kCTFontFamilyNameAttribute: family as CFString,
            kCTFontTraitsAttribute: traitsDict as CFDictionary,
        ]
        let desc = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
        let ctFont = CTFontCreateWithFontDescriptor(desc, 16.0, nil)
        let actualFamily = CTFontCopyFamilyName(ctFont) as String
        if actualFamily.caseInsensitiveCompare(family) == .orderedSame {
            return ctFont
        }
        if let uiFont = UIFont(name: family, size: 16.0) {
            return uiFont as CTFont
        }
        return nil
    }

    private func uiFontWeight(from weight: FontWeight) -> UIFont.Weight {
        let v = weight.value
        if v < 150 { return .ultraLight }
        if v < 250 { return .thin }
        if v < 350 { return .light }
        if v < 450 { return .regular }
        if v < 550 { return .medium }
        if v < 650 { return .semibold }
        if v < 750 { return .bold }
        if v < 850 { return .heavy }
        return .black
    }

    private func coreTextWeight(from weight: FontWeight) -> Double {
        // Maps CSS weight [100, 900] onto CoreText normalized weight [-0.8, +0.6].
        let clamped = Double(min(max(weight.value, 100.0), 900.0))
        if clamped <= 400.0 {
            return ((clamped - 400.0) / 300.0) * 0.8
        } else {
            return ((clamped - 400.0) / 500.0) * 0.6
        }
    }
}
#endif
