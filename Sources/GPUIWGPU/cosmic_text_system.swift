// Ported from: crates/gpui_wgpu/src/cosmic_text_system.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux) || os(Windows) || os(Android) || os(WASI)
import Foundation
import GPUI
import GPUICollections

// PORT NOTE: On Linux, cosmic-text (rustybuzz + swash + fontdb) is substituted with
// HarfBuzz (text shaping), FreeType 2 (glyph rasterization and metrics), and
// Fontconfig (system font discovery and fallback) per ADR-0006.

public struct CosmicTextError: Error, CustomStringConvertible, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

#if os(Linux)
import CLinuxSys

public typealias Font = GPUI.Font

// MARK: - Pinned Font Buffer (for FT_New_Memory_Face lifetime)

// PORT NOTE: PinnedFontBuffer manages an immutable heap-allocated byte buffer
// for the lifetime of FT_New_Memory_Face.
private final class PinnedFontBuffer: @unchecked Sendable {
    let pointer: UnsafeMutablePointer<FT_Byte>
    let count: Int

    init(data: Data) {
        self.count = data.count
        self.pointer = UnsafeMutablePointer<FT_Byte>.allocate(capacity: data.count)
        data.copyBytes(to: self.pointer, count: data.count)
    }

    deinit {
        pointer.deallocate()
    }
}

// MARK: - Loaded Font Face (FreeType + HarfBuzz)

// PORT NOTE: LoadedFontFace wraps thread-safe pointers (FT_Face, hb_font_t)
// synchronized via CosmicTextSystemState's NSLock.
private final class LoadedFontFace: @unchecked Sendable {
    let fontId: FontId
    let face: FT_Face
    let hbFont: OpaquePointer // hb_font_t
    let pinnedBuffer: PinnedFontBuffer? // Retains memory buffer for FT_New_Memory_Face
    let familyName: String
    let postscriptName: String
    let weight: Int
    let isItalic: Bool
    let features: FontFeatures
    let isKnownEmoji: Bool

    init(
        fontId: FontId,
        face: FT_Face,
        hbFont: OpaquePointer,
        pinnedBuffer: PinnedFontBuffer?,
        familyName: String,
        postscriptName: String,
        weight: Int,
        isItalic: Bool,
        features: FontFeatures,
        isKnownEmoji: Bool
    ) {
        self.fontId = fontId
        self.face = face
        self.hbFont = hbFont
        self.pinnedBuffer = pinnedBuffer
        self.familyName = familyName
        self.postscriptName = postscriptName
        self.weight = weight
        self.isItalic = isItalic
        self.features = features
        self.isKnownEmoji = isKnownEmoji
    }

    deinit {
        hb_font_destroy(hbFont)
        FT_Done_Face(face)
    }
}

// MARK: - CosmicTextSystemState (Linux)

// PORT NOTE: CosmicTextSystemState synchronizes FreeType, HarfBuzz, and Fontconfig
// calls internally with NSLock to provide safe concurrent access.
private final class CosmicTextSystemState: @unchecked Sendable {
    private let lock = NSLock()
    private var ftLibrary: FT_Library?
    private var loadedFaces: [LoadedFontFace] = []
    private var familyIndex: [String: [FontId]] = [:]
    var systemFontFallback: String
    var loadSystemFonts: Bool = true

    init(systemFontFallback: String) {
        self.systemFontFallback = systemFontFallback
        var lib: FT_Library? = nil
        let err = FT_Init_FreeType(&lib)
        if err == 0 {
            self.ftLibrary = lib
        }
        _ = FcInit()
    }

    deinit {
        loadedFaces.removeAll()
        if let lib = ftLibrary {
            FT_Done_FreeType(lib)
        }
    }

    func face(for fontId: FontId) -> LoadedFontFace? {
        lock.lock()
        defer { lock.unlock() }
        let idx = fontId.value
        if idx < loadedFaces.count {
            return loadedFaces[Int(idx)]
        }
        return nil
    }

    func addFonts(_ fonts: [Data]) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let lib = ftLibrary else {
            throw CosmicTextError("FreeType library not initialized")
        }

        for data in fonts {
            let pinnedBuffer = PinnedFontBuffer(data: data)
            var initialFace: FT_Face? = nil
            let err = FT_New_Memory_Face(
                lib,
                pinnedBuffer.pointer,
                FT_Long(pinnedBuffer.count),
                0,
                &initialFace
            )
            guard err == 0, let initialFace = initialFace else {
                throw CosmicTextError("Failed to parse font data via FreeType")
            }
            let numFaces = initialFace.pointee.num_faces
            FT_Done_Face(initialFace)

            for faceIdx in 0..<numFaces {
                var face: FT_Face? = nil
                let err = FT_New_Memory_Face(
                    lib,
                    pinnedBuffer.pointer,
                    FT_Long(pinnedBuffer.count),
                    FT_Long(faceIdx),
                    &face
                )
                guard err == 0, let face = face else { continue }
                guard let hbFont = hb_ft_font_create_referenced(face) else {
                    FT_Done_Face(face)
                    continue
                }

                let famName: String
                if let cFam = face.pointee.family_name {
                    famName = String(cString: cFam)
                } else {
                    famName = "Unknown"
                }

                let psName: String
                if let cPs = FT_Get_Postscript_Name(face) {
                    psName = String(cString: cPs)
                } else {
                    psName = famName
                }

                let weight = (face.pointee.style_flags & FT_Long(FT_STYLE_FLAG_BOLD) != 0) ? 700 : 400
                let isItalic = (face.pointee.style_flags & FT_Long(FT_STYLE_FLAG_ITALIC) != 0)
                let isKnownEmoji = psName.contains("Emoji")

                let nextId = FontId(loadedFaces.count)
                let loadedFace = LoadedFontFace(
                    fontId: nextId,
                    face: face,
                    hbFont: hbFont,
                    pinnedBuffer: pinnedBuffer,
                    familyName: famName,
                    postscriptName: psName,
                    weight: weight,
                    isItalic: isItalic,
                    features: FontFeatures(),
                    isKnownEmoji: isKnownEmoji
                )
                loadedFaces.append(loadedFace)
                familyIndex[famName.lowercased(), default: []].append(nextId)
            }
        }
    }

    func allFontNames() -> [String] {
        lock.lock()
        defer { lock.unlock() }

        var names = Set<String>()
        for loaded in loadedFaces {
            names.insert(loaded.familyName)
        }

        if loadSystemFonts {
            let pattern = FcPatternCreate()
            defer { FcPatternDestroy(pattern) }

            let os = FcObjectSetCreate()
            defer { FcObjectSetDestroy(os) }
            FcObjectSetAdd(os, FC_FAMILY)

            if let fs = FcFontList(nil, pattern, os) {
                defer { FcFontSetDestroy(fs) }
                for i in 0..<fs.pointee.nfont {
                    if let pat = fs.pointee.fonts[Int(i)] {
                        var famPtr: UnsafeMutablePointer<FcChar8>? = nil
                        if FcPatternGetString(pat, FC_FAMILY, 0, &famPtr) == FcResultMatch, let famPtr = famPtr {
                            names.insert(String(cString: famPtr))
                        }
                    }
                }
            }
        }
        return names.sorted()
    }

    func fontId(descriptor: Font) throws -> FontId {
        lock.lock()
        defer { lock.unlock() }

        let famKey = descriptor.family.value.lowercased()
        if let existing = familyIndex[famKey], !existing.isEmpty {
            let candidates = existing.compactMap { id -> LoadedFontFace? in
                let idx = id.value
                return idx < loadedFaces.count ? loadedFaces[Int(idx)] : nil
            }
            if !candidates.isEmpty {
                return findBestMatch(font: descriptor, candidates: candidates)
            }
        }

        if loadSystemFonts {
            let loaded = loadFamilyFromFontconfig(
                name: descriptor.family.value,
                features: descriptor.features
            )
            if !loaded.isEmpty {
                return findBestMatch(font: descriptor, candidates: loaded)
            }
        }

        // Fallback to system font fallback if not already tried
        if descriptor.family.value.lowercased() != systemFontFallback.lowercased() {
            let fallbackDescriptor = Font(
                family: SharedString(systemFontFallback),
                features: descriptor.features,
                weight: descriptor.weight,
                style: descriptor.style
            )
            let famFallbackKey = systemFontFallback.lowercased()
            if let existing = familyIndex[famFallbackKey], !existing.isEmpty {
                let candidates = existing.compactMap { id -> LoadedFontFace? in
                    let idx = id.value
                    return idx < loadedFaces.count ? loadedFaces[Int(idx)] : nil
                }
                if !candidates.isEmpty {
                    return findBestMatch(font: fallbackDescriptor, candidates: candidates)
                }
            }

            if loadSystemFonts {
                let loaded = loadFamilyFromFontconfig(
                    name: systemFontFallback,
                    features: descriptor.features
                )
                if !loaded.isEmpty {
                    return findBestMatch(font: fallbackDescriptor, candidates: loaded)
                }
            }
        }

        if let first = loadedFaces.first {
            return first.fontId
        }

        throw CosmicTextError("No font available for family \(descriptor.family.value)")
    }

    private func findBestMatch(font: Font, candidates: [LoadedFontFace]) -> FontId {
        if candidates.count == 1 {
            return candidates[0].fontId
        }
        let targetWeight = Int(font.weight.value)
        let targetItalic = (font.style == .italic || font.style == .oblique)

        var bestIndex = 0
        var bestScore = Int.max

        for (index, candidate) in candidates.enumerated() {
            let stylePenalty = (candidate.isItalic == targetItalic) ? 0 : 1000
            let weightDiff = abs(candidate.weight - targetWeight)
            let score = stylePenalty + weightDiff
            if score < bestScore {
                bestScore = score
                bestIndex = index
            }
        }
        return candidates[bestIndex].fontId
    }

    private func loadFamilyFromFontconfig(
        name: String,
        features: FontFeatures
    ) -> [LoadedFontFace] {
        guard let lib = ftLibrary else { return [] }

        let pattern = FcPatternCreate()
        defer { FcPatternDestroy(pattern) }

        _ = name.withCString { cName in
            FcPatternAddString(pattern, FC_FAMILY, cName)
        }
        FcConfigSubstitute(nil, pattern, FcMatchPattern)
        FcDefaultSubstitute(pattern)

        var result = FcResultMatch
        guard let fontSet = FcFontSort(nil, pattern, FcFalse, nil, &result) else {
            return []
        }
        defer { FcFontSetDestroy(fontSet) }

        var loaded: [LoadedFontFace] = []
        let nFonts = fontSet.pointee.nfont
        let maxLoad = min(nFonts, 16)

        for i in 0..<maxLoad {
            guard let pat = fontSet.pointee.fonts[Int(i)] else { continue }
            var filePtr: UnsafeMutablePointer<FcChar8>? = nil
            if FcPatternGetString(pat, FC_FILE, 0, &filePtr) != FcResultMatch || filePtr == nil {
                continue
            }
            let filePath = String(cString: filePtr!)

            var indexVal: Int32 = 0
            FcPatternGetInteger(pat, FC_INDEX, 0, &indexVal)

            var famPtr: UnsafeMutablePointer<FcChar8>? = nil
            var fontFam = ""
            if FcPatternGetString(pat, FC_FAMILY, 0, &famPtr) == FcResultMatch, let famPtr = famPtr {
                fontFam = String(cString: famPtr)
            }

            var face: FT_Face? = nil
            let err = filePath.withCString { cPath in
                FT_New_Face(lib, cPath, FT_Long(indexVal), &face)
            }
            guard err == 0, let face = face else { continue }
            guard let hbFont = hb_ft_font_create_referenced(face) else {
                FT_Done_Face(face)
                continue
            }

            let famName = fontFam.isEmpty ? (face.pointee.family_name.map { String(cString: $0) } ?? name) : fontFam
            let psName = FT_Get_Postscript_Name(face).map { String(cString: $0) } ?? famName
            let weight = (face.pointee.style_flags & FT_Long(FT_STYLE_FLAG_BOLD) != 0) ? 700 : 400
            let isItalic = (face.pointee.style_flags & FT_Long(FT_STYLE_FLAG_ITALIC) != 0)
            let isKnownEmoji = psName.contains("Emoji")

            let nextId = FontId(loadedFaces.count)
            let loadedFace = LoadedFontFace(
                fontId: nextId,
                face: face,
                hbFont: hbFont,
                pinnedBuffer: nil,
                familyName: famName,
                postscriptName: psName,
                weight: weight,
                isItalic: isItalic,
                features: features,
                isKnownEmoji: isKnownEmoji
            )
            loadedFaces.append(loadedFace)
            familyIndex[famName.lowercased(), default: []].append(nextId)
            loaded.append(loadedFace)
            if loaded.count >= 4 { break }
        }

        return loaded
    }

    func fontMetrics(fontId: FontId) -> FontMetrics {
        guard let loaded = face(for: fontId) else {
            return FontMetrics(
                unitsPerEm: 1000,
                ascent: 800,
                descent: -200,
                lineGap: 0,
                underlinePosition: -100,
                underlineThickness: 50,
                capHeight: 700,
                xHeight: 500,
                boundingBox: Bounds(origin: .zero, size: Size(width: 1000, height: 1000))
            )
        }

        lock.lock()
        defer { lock.unlock() }

        let ftFace = loaded.face
        let unitsPerEm = UInt32(max(1, ftFace.pointee.units_per_EM))
        let ascent = Float(ftFace.pointee.ascender)
        let descent = Float(ftFace.pointee.descender)
        let lineGap = Float(max(0, Int32(ftFace.pointee.height) - Int32(ftFace.pointee.ascender - ftFace.pointee.descender)))
        let underlinePos = Float(ftFace.pointee.underline_position)
        let underlineThick = Float(ftFace.pointee.underline_thickness)

        let hIndex = FT_Get_Char_Index(ftFace, 72)
        let capHeight: Float
        if hIndex != 0 && FT_Load_Glyph(ftFace, hIndex, FT_Int32(FT_LOAD_NO_SCALE)) == 0 {
            capHeight = Float(ftFace.pointee.glyph.pointee.metrics.height)
        } else {
            capHeight = ascent * 0.7
        }

        let xIndex = FT_Get_Char_Index(ftFace, 120)
        let xHeight: Float
        if xIndex != 0 && FT_Load_Glyph(ftFace, xIndex, FT_Int32(FT_LOAD_NO_SCALE)) == 0 {
            xHeight = Float(ftFace.pointee.glyph.pointee.metrics.height)
        } else {
            xHeight = ascent * 0.5
        }

        let bbox = Bounds(
            origin: Point(x: Float(ftFace.pointee.bbox.xMin), y: Float(ftFace.pointee.bbox.yMin)),
            size: Size(
                width: Float(ftFace.pointee.bbox.xMax - ftFace.pointee.bbox.xMin),
                height: Float(ftFace.pointee.bbox.yMax - ftFace.pointee.bbox.yMin)
            )
        )

        return FontMetrics(
            unitsPerEm: unitsPerEm,
            ascent: ascent,
            descent: descent,
            lineGap: lineGap,
            underlinePosition: underlinePos,
            underlineThickness: underlineThick > 0 ? underlineThick : (Float(unitsPerEm) * 0.05),
            capHeight: capHeight,
            xHeight: xHeight,
            boundingBox: bbox
        )
    }

    func typographicBounds(fontId: FontId, glyphId: GlyphId) throws -> Bounds<Float> {
        guard let loaded = face(for: fontId) else {
            throw CosmicTextError("Invalid FontId")
        }
        lock.lock()
        defer { lock.unlock() }

        let ftFace = loaded.face
        guard FT_Load_Glyph(ftFace, glyphId.value, FT_Int32(FT_LOAD_NO_SCALE)) == 0 else {
            throw CosmicTextError("Failed to load glyph")
        }
        let metrics = ftFace.pointee.glyph.pointee.metrics
        return Bounds(
            origin: .zero,
            size: Size(
                width: Float(metrics.horiAdvance),
                height: Float(metrics.vertAdvance != 0 ? metrics.vertAdvance : metrics.height)
            )
        )
    }

    func advance(fontId: FontId, glyphId: GlyphId) throws -> Size<Float> {
        guard let loaded = face(for: fontId) else {
            throw CosmicTextError("Invalid FontId")
        }
        lock.lock()
        defer { lock.unlock() }

        let ftFace = loaded.face
        guard FT_Load_Glyph(ftFace, glyphId.value, FT_Int32(FT_LOAD_NO_SCALE)) == 0 else {
            throw CosmicTextError("Failed to load glyph")
        }
        let metrics = ftFace.pointee.glyph.pointee.metrics
        return Size(width: Float(metrics.horiAdvance), height: Float(metrics.vertAdvance))
    }

    func glyphForChar(fontId: FontId, ch: Character) -> GlyphId? {
        guard let loaded = face(for: fontId) else { return nil }
        guard let scalar = ch.unicodeScalars.first else { return nil }

        lock.lock()
        defer { lock.unlock() }

        let index = FT_Get_Char_Index(loaded.face, FT_ULong(scalar.value))
        if index == 0 { return nil }
        return GlyphId(UInt32(index))
    }

    func glyphRasterBounds(params: RenderGlyphParams) throws -> Bounds<DevicePixels> {
        guard let loaded = face(for: params.fontId) else {
            throw CosmicTextError("Invalid FontId")
        }
        lock.lock()
        defer { lock.unlock() }

        let ftFace = loaded.face
        let pixelSize = UInt32(max(1, (Float(params.fontSize.value) * params.scaleFactor).rounded()))
        FT_Set_Pixel_Sizes(ftFace, 0, pixelSize)

        let loadFlags = FT_Int32(FT_LOAD_DEFAULT)
        guard FT_Load_Glyph(ftFace, params.glyphId.value, loadFlags) == 0 else {
            throw CosmicTextError("Failed to load glyph")
        }

        if ftFace.pointee.glyph.pointee.format == FT_GLYPH_FORMAT_OUTLINE {
            let subpixelX = FT_Pos(Int(params.subpixelVariant.x) * 64 / Int(subpixelVariantsX))
            let subpixelY = FT_Pos(Int(params.subpixelVariant.y) * 64 / Int(subpixelVariantsY))
            if subpixelX != 0 || subpixelY != 0 {
                FT_Outline_Translate(&ftFace.pointee.glyph.pointee.outline, subpixelX, -subpixelY)
            }
        }

        let renderMode = params.subpixelRendering ? FT_RENDER_MODE_LCD : FT_RENDER_MODE_NORMAL
        guard FT_Render_Glyph(ftFace.pointee.glyph, renderMode) == 0 else {
            throw CosmicTextError("Failed to render glyph")
        }

        let glyph = ftFace.pointee.glyph.pointee
        let pixelWidth = params.subpixelRendering ? Int(glyph.bitmap.width) / 3 : Int(glyph.bitmap.width)
        let rows = Int(glyph.bitmap.rows)

        return Bounds(
            origin: Point(x: DevicePixels(glyph.bitmap_left), y: DevicePixels(-glyph.bitmap_top)),
            size: Size(width: DevicePixels(Int32(pixelWidth)), height: DevicePixels(Int32(rows)))
        )
    }

    func rasterizeGlyph(
        params: RenderGlyphParams,
        rasterBounds: Bounds<DevicePixels>
    ) throws -> (Size<DevicePixels>, Data) {
        if rasterBounds.size.width.value == 0 || rasterBounds.size.height.value == 0 {
            throw CosmicTextError("Glyph bounds are empty")
        }

        guard let loaded = face(for: params.fontId) else {
            throw CosmicTextError("Invalid FontId")
        }
        lock.lock()
        defer { lock.unlock() }

        let ftFace = loaded.face
        let pixelSize = UInt32(max(1, (Float(params.fontSize.value) * params.scaleFactor).rounded()))
        FT_Set_Pixel_Sizes(ftFace, 0, pixelSize)

        let loadFlags = FT_Int32(FT_LOAD_DEFAULT)
        guard FT_Load_Glyph(ftFace, params.glyphId.value, loadFlags) == 0 else {
            throw CosmicTextError("Failed to load glyph")
        }

        if ftFace.pointee.glyph.pointee.format == FT_GLYPH_FORMAT_OUTLINE {
            let subpixelX = FT_Pos(Int(params.subpixelVariant.x) * 64 / Int(subpixelVariantsX))
            let subpixelY = FT_Pos(Int(params.subpixelVariant.y) * 64 / Int(subpixelVariantsY))
            if subpixelX != 0 || subpixelY != 0 {
                FT_Outline_Translate(&ftFace.pointee.glyph.pointee.outline, subpixelX, -subpixelY)
            }
        }

        let renderMode = params.subpixelRendering ? FT_RENDER_MODE_LCD : FT_RENDER_MODE_NORMAL
        guard FT_Render_Glyph(ftFace.pointee.glyph, renderMode) == 0 else {
            throw CosmicTextError("Failed to render glyph")
        }

        let glyph = ftFace.pointee.glyph.pointee
        let pixelWidth = params.subpixelRendering ? Int(glyph.bitmap.width) / 3 : Int(glyph.bitmap.width)
        let rows = Int(glyph.bitmap.rows)
        let pitch = Int(glyph.bitmap.pitch)

        let outWidth = rasterBounds.size.width.value
        let outHeight = rasterBounds.size.height.value

        guard let srcBuffer = glyph.bitmap.buffer else {
            let count = Int(outWidth * outHeight * (params.subpixelRendering ? 4 : 1))
            return (rasterBounds.size, Data(count: count))
        }

        if params.subpixelRendering {
            var data = Data(count: Int(outWidth * outHeight * 4))
            data.withUnsafeMutableBytes { outBuf in
                let outPtr = outBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                let copyRows = min(rows, Int(outHeight))
                let copyCols = min(pixelWidth, Int(outWidth))
                for r in 0..<copyRows {
                    let srcRowOffset = pitch >= 0 ? r * pitch : (rows - 1 - r) * (-pitch)
                    let srcRow = srcBuffer + srcRowOffset
                    let dstRow = outPtr + r * Int(outWidth) * 4
                    for c in 0..<copyCols {
                        let red = srcRow[c * 3]
                        let green = srcRow[c * 3 + 1]
                        let blue = srcRow[c * 3 + 2]
                        let alpha = max(red, max(green, blue))
                        dstRow[c * 4] = blue
                        dstRow[c * 4 + 1] = green
                        dstRow[c * 4 + 2] = red
                        dstRow[c * 4 + 3] = alpha
                    }
                }
            }
            return (rasterBounds.size, data)
        } else {
            var data = Data(count: Int(outWidth * outHeight))
            data.withUnsafeMutableBytes { outBuf in
                let outPtr = outBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                let copyRows = min(rows, Int(outHeight))
                let copyCols = min(pixelWidth, Int(outWidth))
                for r in 0..<copyRows {
                    let srcRowOffset = pitch >= 0 ? r * pitch : (rows - 1 - r) * (-pitch)
                    let srcRow = srcBuffer + srcRowOffset
                    let dstRow = outPtr + r * Int(outWidth)
                    for c in 0..<copyCols {
                        dstRow[c] = srcRow[c]
                    }
                }
            }
            return (rasterBounds.size, data)
        }
    }

    func layoutLine(text: String, fontSize: Pixels, runs: [FontRun]) -> LineLayout {
        guard !text.isEmpty else {
            return LineLayout(fontSize: fontSize, width: .zero, ascent: .zero, descent: .zero, runs: [], len: 0)
        }

        let fontRuns: [FontRun]
        if runs.isEmpty {
            let defaultId = loadedFaces.first?.fontId ?? FontId(0)
            fontRuns = [FontRun(len: text.utf8.count, fontId: defaultId)]
        } else {
            fontRuns = runs
        }

        lock.lock()
        defer { lock.unlock() }

        var shapedRuns: [ShapedRun] = []
        var currentX: Float = 0.0
        var maxAscent: Float = 0.0
        var maxDescent: Float = 0.0
        var currentOffset = 0

        let textUtf8 = Array(text.utf8)

        for run in fontRuns {
            let runLen = min(run.len, textUtf8.count - currentOffset)
            guard runLen > 0 else { continue }

            let fontIdx = run.fontId.value
            guard fontIdx < loadedFaces.count else {
                currentOffset += runLen
                continue
            }
            let loaded = loadedFaces[Int(fontIdx)]
            let ftFace = loaded.face

            let pixelSize = UInt32(max(1, (Float(fontSize.value)).rounded()))
            FT_Set_Pixel_Sizes(ftFace, 0, pixelSize)
            hb_ft_font_changed(loaded.hbFont)

            let hbBuffer = hb_buffer_create()
            defer { hb_buffer_destroy(hbBuffer) }

            text.withCString { cText in
                hb_buffer_add_utf8(
                    hbBuffer,
                    cText,
                    Int32(textUtf8.count),
                    UInt32(currentOffset),
                    Int32(runLen)
                )
            }
            hb_buffer_guess_segment_properties(hbBuffer)

            var hbFeatures: [hb_feature_t] = []
            for entry in loaded.features.entries {
                var feat = hb_feature_t()
                let str = "\(entry.tag)=\(entry.value)"
                if hb_feature_from_string(str, Int32(str.utf8.count), &feat) != 0 {
                    feat.start = 0
                    feat.end = UInt32.max
                    hbFeatures.append(feat)
                }
            }

            hb_shape(loaded.hbFont, hbBuffer, hbFeatures, UInt32(hbFeatures.count))

            let glyphCount = Int(hb_buffer_get_length(hbBuffer))
            var dummyLen: UInt32 = 0
            let glyphInfosPtr = hb_buffer_get_glyph_infos(hbBuffer, &dummyLen)
            let glyphPositionsPtr = hb_buffer_get_glyph_positions(hbBuffer, &dummyLen)

            var runGlyphs: [ShapedGlyph] = []
            if let infos = glyphInfosPtr, let positions = glyphPositionsPtr {
                for i in 0..<glyphCount {
                    let info = infos[i]
                    let pos = positions[i]

                    let xAdvance = Float(pos.x_advance) / 64.0
                    let xOffset = Float(pos.x_offset) / 64.0
                    let yOffset = Float(pos.y_offset) / 64.0

                    let glyphPos = Point(x: Pixels(currentX + xOffset), y: Pixels(yOffset))
                    runGlyphs.append(ShapedGlyph(
                        id: GlyphId(info.codepoint),
                        position: glyphPos,
                        index: Int(info.cluster),
                        isEmoji: loaded.isKnownEmoji
                    ))
                    currentX += xAdvance
                }
            }

            let scale = Float(fontSize.value) / Float(max(1, ftFace.pointee.units_per_EM))
            let runAscent = Float(ftFace.pointee.ascender) * scale
            let runDescent = abs(Float(ftFace.pointee.descender)) * scale
            if runAscent > maxAscent { maxAscent = runAscent }
            if runDescent > maxDescent { maxDescent = runDescent }

            shapedRuns.append(ShapedRun(fontId: run.fontId, glyphs: runGlyphs))
            currentOffset += runLen
        }

        return LineLayout(
            fontSize: fontSize,
            width: Pixels(currentX),
            ascent: Pixels(maxAscent),
            descent: Pixels(maxDescent),
            runs: shapedRuns,
            len: text.utf8.count
        )
    }
}

#else

// MARK: - Non-Linux Fallback (macOS host build, Windows, Android, WASI)

// PORT NOTE: Non-Linux CosmicTextSystemState is an immutable fallback state safe across threads.
private final class CosmicTextSystemState: @unchecked Sendable {
    var systemFontFallback: String
    var loadSystemFonts: Bool = true

    init(systemFontFallback: String) {
        self.systemFontFallback = systemFontFallback
    }

    func addFonts(_ fonts: [Data]) throws {}
    func allFontNames() -> [String] { [systemFontFallback] }
    func fontId(descriptor: Font) throws -> FontId { FontId(0) }
    func fontMetrics(fontId: FontId) -> FontMetrics {
        FontMetrics(
            unitsPerEm: 1000,
            ascent: 800,
            descent: -200,
            lineGap: 0,
            underlinePosition: -100,
            underlineThickness: 50,
            capHeight: 700,
            xHeight: 500,
            boundingBox: Bounds(origin: .zero, size: Size(width: 1000, height: 1000))
        )
    }
    func typographicBounds(fontId: FontId, glyphId: GlyphId) throws -> Bounds<Float> {
        Bounds(origin: .zero, size: Size(width: 600, height: 1000))
    }
    func advance(fontId: FontId, glyphId: GlyphId) throws -> Size<Float> {
        Size(width: 600, height: 0)
    }
    func glyphForChar(fontId: FontId, ch: Character) -> GlyphId? {
        GlyphId(ch.asciiValue.map { UInt32($0) } ?? 65)
    }
    func glyphRasterBounds(params: RenderGlyphParams) throws -> Bounds<DevicePixels> {
        Bounds(origin: .zero, size: Size(width: DevicePixels(10), height: DevicePixels(16)))
    }
    func rasterizeGlyph(
        params: RenderGlyphParams,
        rasterBounds: Bounds<DevicePixels>
    ) throws -> (Size<DevicePixels>, Data) {
        let count = Int(rasterBounds.size.width.value * rasterBounds.size.height.value * (params.subpixelRendering ? 4 : 1))
        return (rasterBounds.size, Data(count: count))
    }
    func layoutLine(text: String, fontSize: Pixels, runs: [FontRun]) -> LineLayout {
        LineLayout(
            fontSize: fontSize,
            width: Pixels(Float(text.count) * Float(fontSize.value) * 0.6),
            ascent: Pixels(Float(fontSize.value) * 0.8),
            descent: Pixels(Float(fontSize.value) * 0.2),
            runs: [],
            len: text.utf8.count
        )
    }
}
#endif

// MARK: - CosmicTextSystem

// PORT NOTE: CosmicTextSystem wraps thread-safe CosmicTextSystemState.
public final class CosmicTextSystem: PlatformTextSystem, @unchecked Sendable {
    private let state: CosmicTextSystemState

    public init(systemFontFallback: String = "sans-serif") {
        self.state = CosmicTextSystemState(systemFontFallback: systemFontFallback)
    }

    public static func new(_ systemFontFallback: String = "sans-serif") -> CosmicTextSystem {
        CosmicTextSystem(systemFontFallback: systemFontFallback)
    }

    public static func newWithoutSystemFonts(_ systemFontFallback: String = "sans-serif") -> CosmicTextSystem {
        let system = CosmicTextSystem(systemFontFallback: systemFontFallback)
        system.state.loadSystemFonts = false
        return system
    }

    public func addFonts(_ fonts: [Data]) throws {
        try state.addFonts(fonts)
    }

    public func allFontNames() -> [String] {
        state.allFontNames()
    }

    public func fontId(descriptor: Font) throws -> FontId {
        try state.fontId(descriptor: descriptor)
    }

    public func fontMetrics(fontId: FontId) -> FontMetrics {
        state.fontMetrics(fontId: fontId)
    }

    public func typographicBounds(fontId: FontId, glyphId: GlyphId) throws -> Bounds<Float> {
        try state.typographicBounds(fontId: fontId, glyphId: glyphId)
    }

    public func advance(fontId: FontId, glyphId: GlyphId) throws -> Size<Float> {
        try state.advance(fontId: fontId, glyphId: glyphId)
    }

    public func glyphForChar(fontId: FontId, ch: Character) -> GlyphId? {
        state.glyphForChar(fontId: fontId, ch: ch)
    }

    public func glyphRasterBounds(params: RenderGlyphParams) throws -> Bounds<DevicePixels> {
        try state.glyphRasterBounds(params: params)
    }

    public func rasterizeGlyph(
        params: RenderGlyphParams,
        rasterBounds: Bounds<DevicePixels>
    ) throws -> (Size<DevicePixels>, Data) {
        try state.rasterizeGlyph(params: params, rasterBounds: rasterBounds)
    }

    public func layoutLine(text: String, fontSize: Pixels, runs: [FontRun]) -> LineLayout {
        state.layoutLine(text: text, fontSize: fontSize, runs: runs)
    }

    public func recommendedRenderingMode(fontId: FontId, fontSize: Pixels) -> TextRenderingMode {
        .subpixel
    }
}
#endif
