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
            guard FcPatternGetString(pat, FC_FILE, 0, &filePtr) == FcResultMatch,
                  let resolvedFilePtr = filePtr else {
                continue
            }
            let filePath = String(cString: resolvedFilePtr)

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
                guard let baseAddress = outBuf.baseAddress else { return }
                let outPtr = baseAddress.assumingMemoryBound(to: UInt8.self)
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
                guard let baseAddress = outBuf.baseAddress else { return }
                let outPtr = baseAddress.assumingMemoryBound(to: UInt8.self)
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

public typealias Font = GPUI.Font

// MARK: - Pure-Swift TrueType / OpenType Engine (Android, WASI, Windows)

// PORT NOTE: On platforms without desktop Fontconfig/FreeType/HarfBuzz (WASI, Android, Windows),
// CosmicTextSystem provides a self-contained thread-safe TrueType/OpenType (.ttf/.otf/.ttc)
// table parser, character-to-glyph mapper, horizontal shaper with kerning, and 4x supersampled
// analytical scanline + LCD subpixel BGRA rasterizer per ADR-0012 and ADR-0013.

private struct TrueTypeEdge: Sendable {
    let x0: Float
    let y0: Float
    let x1: Float
    let y1: Float
}

private struct TrueTypeGlyphOutline: Sendable {
    let edges: [TrueTypeEdge]
    let xMin: Float
    let yMin: Float
    let xMax: Float
    let yMax: Float
}

private struct TrueTypeTableRange: Sendable {
    let offset: Int
    let length: Int
}

private enum TrueTypeCmap: Sendable {
    case format12([(startCode: UInt32, endCode: UInt32, startGlyph: UInt32)])
    case format4(
        endCount: [UInt16],
        startCount: [UInt16],
        idDelta: [Int16],
        idRangeOffset: [UInt16],
        glyphIdArray: [UInt16]
    )
    case direct([UInt32: UInt16])

    func lookup(_ codepoint: UInt32) -> UInt32 {
        switch self {
        case .format12(let groups):
            var lo = 0
            var hi = groups.count - 1
            while lo <= hi {
                let mid = (lo + hi) >> 1
                let group = groups[mid]
                if codepoint < group.startCode {
                    hi = mid - 1
                } else if codepoint > group.endCode {
                    lo = mid + 1
                } else {
                    return group.startGlyph &+ (codepoint &- group.startCode)
                }
            }
            return 0

        case .format4(let endCount, let startCount, let idDelta, let idRangeOffset, let glyphIdArray):
            guard codepoint <= 0xFFFF, !endCount.isEmpty else { return 0 }
            let cp = UInt16(codepoint)
            var lo = 0
            var hi = endCount.count - 1
            var seg = -1
            while lo <= hi {
                let mid = (lo + hi) >> 1
                if cp > endCount[mid] {
                    lo = mid + 1
                } else {
                    if cp >= startCount[mid] {
                        seg = mid
                        break
                    }
                    hi = mid - 1
                }
            }
            guard seg >= 0 else { return 0 }
            let ro = idRangeOffset[seg]
            if ro == 0 {
                let mapped = (Int(cp) + Int(idDelta[seg])) & 0xFFFF
                return UInt32(mapped)
            } else {
                let wordOffsetFromRo = Int(ro) / 2 + Int(cp - startCount[seg]) - (endCount.count - seg)
                guard wordOffsetFromRo >= 0 && wordOffsetFromRo < glyphIdArray.count else {
                    return 0
                }
                let rawGlyph = glyphIdArray[wordOffsetFromRo]
                if rawGlyph == 0 {
                    return 0
                }
                let mapped = (Int(rawGlyph) + Int(idDelta[seg])) & 0xFFFF
                return UInt32(mapped)
            }

        case .direct(let map):
            return UInt32(map[codepoint] ?? 0)
        }
    }
}

private struct TrueTypeBinaryReader {
    let bytes: [UInt8]

    @inline(__always)
    func has(_ offset: Int, _ count: Int) -> Bool {
        offset >= 0 && count >= 0 && offset <= bytes.count - count
    }

    @inline(__always)
    func u8(_ offset: Int) -> UInt8? {
        guard has(offset, 1) else { return nil }
        return bytes[offset]
    }

    @inline(__always)
    func i8(_ offset: Int) -> Int8? {
        guard let v = u8(offset) else { return nil }
        return Int8(bitPattern: v)
    }

    @inline(__always)
    func u16(_ offset: Int) -> UInt16? {
        guard has(offset, 2) else { return nil }
        return (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    @inline(__always)
    func i16(_ offset: Int) -> Int16? {
        guard let v = u16(offset) else { return nil }
        return Int16(bitPattern: v)
    }

    @inline(__always)
    func u32(_ offset: Int) -> UInt32? {
        guard has(offset, 4) else { return nil }
        return (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }
}

// PORT NOTE: PureSwiftTrueTypeFace holds immutable font table data and synchronizes its lazy
// glyph outline cache with an NSLock so concurrent shaping and rasterization are safe.
private final class PureSwiftTrueTypeFace: @unchecked Sendable {
    let fontId: FontId
    let familyName: String
    let aliasFamilies: [String]
    let postscriptName: String
    let weight: Int
    let isItalic: Bool
    let features: FontFeatures
    let isKnownEmoji: Bool

    let unitsPerEm: UInt32
    let ascent: Float
    let descent: Float
    let lineGap: Float
    let underlinePosition: Float
    let underlineThickness: Float
    let capHeight: Float
    let xHeight: Float
    let bbox: Bounds<Float>

    let numGlyphs: Int
    private let advanceWidths: [UInt16]
    private let leftSideBearings: [Int16]
    private let cmap: TrueTypeCmap
    private let kernPairs: [UInt32: Int16]

    private let rawBytes: [UInt8]
    private let glyfRange: TrueTypeTableRange?
    private let locaOffsets: [Int]
    private let isSyntheticFallback: Bool

    private let cacheLock = NSLock()
    private var outlineCache: [UInt32: TrueTypeGlyphOutline] = [:]

    init(
        fontId: FontId,
        familyName: String,
        aliasFamilies: [String],
        postscriptName: String,
        weight: Int,
        isItalic: Bool,
        features: FontFeatures,
        isKnownEmoji: Bool,
        unitsPerEm: UInt32,
        ascent: Float,
        descent: Float,
        lineGap: Float,
        underlinePosition: Float,
        underlineThickness: Float,
        capHeight: Float,
        xHeight: Float,
        bbox: Bounds<Float>,
        numGlyphs: Int,
        advanceWidths: [UInt16],
        leftSideBearings: [Int16],
        cmap: TrueTypeCmap,
        kernPairs: [UInt32: Int16],
        rawBytes: [UInt8],
        glyfRange: TrueTypeTableRange?,
        locaOffsets: [Int],
        isSyntheticFallback: Bool
    ) {
        self.fontId = fontId
        self.familyName = familyName
        self.aliasFamilies = aliasFamilies
        self.postscriptName = postscriptName
        self.weight = weight
        self.isItalic = isItalic
        self.features = features
        self.isKnownEmoji = isKnownEmoji
        self.unitsPerEm = max(1, unitsPerEm)
        self.ascent = ascent
        self.descent = descent
        self.lineGap = lineGap
        self.underlinePosition = underlinePosition
        self.underlineThickness = underlineThickness
        self.capHeight = capHeight
        self.xHeight = xHeight
        self.bbox = bbox
        self.numGlyphs = max(1, numGlyphs)
        self.advanceWidths = advanceWidths
        self.leftSideBearings = leftSideBearings
        self.cmap = cmap
        self.kernPairs = kernPairs
        self.rawBytes = rawBytes
        self.glyfRange = glyfRange
        self.locaOffsets = locaOffsets
        self.isSyntheticFallback = isSyntheticFallback
    }

    func glyphIndex(for scalar: UInt32) -> UInt32 {
        let mapped = cmap.lookup(scalar)
        if Int(mapped) < numGlyphs {
            return mapped
        }
        return 0
    }

    func advanceWidthUnits(for glyphId: UInt32) -> Float {
        guard !advanceWidths.isEmpty else { return Float(unitsPerEm) * 0.6 }
        let idx = min(Int(glyphId), advanceWidths.count - 1)
        return Float(advanceWidths[max(0, idx)])
    }

    func kerningUnits(left: UInt32, right: UInt32) -> Float {
        guard !kernPairs.isEmpty, left <= 0xFFFF, right <= 0xFFFF else { return 0 }
        let key = (left << 16) | right
        if let val = kernPairs[key] {
            return Float(val)
        }
        return 0
    }

    func outline(for glyphId: UInt32) -> TrueTypeGlyphOutline {
        cacheLock.lock()
        if let cached = outlineCache[glyphId] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let computed = computeOutline(for: glyphId, depth: 0)

        cacheLock.lock()
        outlineCache[glyphId] = computed
        cacheLock.unlock()
        return computed
    }

    private func computeOutline(for glyphId: UInt32, depth: Int) -> TrueTypeGlyphOutline {
        if isSyntheticFallback {
            return computeSyntheticOutline(for: glyphId)
        }
        guard depth <= 8,
              let glyfRange = glyfRange,
              Int(glyphId) + 1 < locaOffsets.count else {
            return computeFallbackStemOutline(for: glyphId)
        }

        let relStart = locaOffsets[Int(glyphId)]
        let relEnd = locaOffsets[Int(glyphId) + 1]
        guard relEnd > relStart,
              relStart >= 0,
              relEnd <= glyfRange.length else {
            return TrueTypeGlyphOutline(edges: [], xMin: 0, yMin: 0, xMax: 0, yMax: 0)
        }

        let reader = TrueTypeBinaryReader(bytes: rawBytes)
        let glyphStart = glyfRange.offset + relStart
        let glyphLimit = glyfRange.offset + relEnd
        guard glyphStart + 10 <= glyphLimit,
              let numContours = reader.i16(glyphStart),
              let gxMin = reader.i16(glyphStart + 2),
              let gyMin = reader.i16(glyphStart + 4),
              let gxMax = reader.i16(glyphStart + 6),
              let gyMax = reader.i16(glyphStart + 8) else {
            return TrueTypeGlyphOutline(edges: [], xMin: 0, yMin: 0, xMax: 0, yMax: 0)
        }

        if numContours == 0 {
            return TrueTypeGlyphOutline(edges: [], xMin: 0, yMin: 0, xMax: 0, yMax: 0)
        }

        if numContours > 0 {
            let contourCount = Int(numContours)
            let endPtsBase = glyphStart + 10
            guard endPtsBase + contourCount * 2 + 2 <= glyphLimit else {
                return TrueTypeGlyphOutline(edges: [], xMin: 0, yMin: 0, xMax: 0, yMax: 0)
            }
            var endPts: [Int] = []
            endPts.reserveCapacity(contourCount)
            for i in 0..<contourCount {
                guard let ep = reader.u16(endPtsBase + i * 2) else {
                    return TrueTypeGlyphOutline(edges: [], xMin: 0, yMin: 0, xMax: 0, yMax: 0)
                }
                endPts.append(Int(ep))
            }
            guard let lastPt = endPts.last, lastPt >= 0 else {
                return TrueTypeGlyphOutline(edges: [], xMin: 0, yMin: 0, xMax: 0, yMax: 0)
            }
            let numPoints = lastPt + 1
            guard let instrLen = reader.u16(endPtsBase + contourCount * 2) else {
                return TrueTypeGlyphOutline(edges: [], xMin: 0, yMin: 0, xMax: 0, yMax: 0)
            }
            var pos = endPtsBase + contourCount * 2 + 2 + Int(instrLen)
            guard pos <= glyphLimit else {
                return TrueTypeGlyphOutline(edges: [], xMin: 0, yMin: 0, xMax: 0, yMax: 0)
            }

            var flags: [UInt8] = []
            flags.reserveCapacity(numPoints)
            while flags.count < numPoints {
                guard pos < glyphLimit, let flag = reader.u8(pos) else {
                    return TrueTypeGlyphOutline(edges: [], xMin: 0, yMin: 0, xMax: 0, yMax: 0)
                }
                pos += 1
                flags.append(flag)
                if (flag & 0x08) != 0 {
                    guard pos < glyphLimit, let repeatCount = reader.u8(pos) else {
                        return TrueTypeGlyphOutline(edges: [], xMin: 0, yMin: 0, xMax: 0, yMax: 0)
                    }
                    pos += 1
                    let remaining = min(Int(repeatCount), numPoints - flags.count)
                    for _ in 0..<remaining {
                        flags.append(flag)
                    }
                }
            }

            var xCoords = [Float](repeating: 0, count: numPoints)
            var curX: Int32 = 0
            for i in 0..<numPoints {
                let flag = flags[i]
                if (flag & 0x02) != 0 {
                    guard pos < glyphLimit, let dx = reader.u8(pos) else {
                        return TrueTypeGlyphOutline(edges: [], xMin: 0, yMin: 0, xMax: 0, yMax: 0)
                    }
                    pos += 1
                    curX += ((flag & 0x10) != 0) ? Int32(dx) : -Int32(dx)
                } else if (flag & 0x10) == 0 {
                    guard pos + 2 <= glyphLimit, let dx = reader.i16(pos) else {
                        return TrueTypeGlyphOutline(edges: [], xMin: 0, yMin: 0, xMax: 0, yMax: 0)
                    }
                    pos += 2
                    curX += Int32(dx)
                }
                xCoords[i] = Float(curX)
            }

            var yCoords = [Float](repeating: 0, count: numPoints)
            var curY: Int32 = 0
            for i in 0..<numPoints {
                let flag = flags[i]
                if (flag & 0x04) != 0 {
                    guard pos < glyphLimit, let dy = reader.u8(pos) else {
                        return TrueTypeGlyphOutline(edges: [], xMin: 0, yMin: 0, xMax: 0, yMax: 0)
                    }
                    pos += 1
                    curY += ((flag & 0x20) != 0) ? Int32(dy) : -Int32(dy)
                } else if (flag & 0x20) == 0 {
                    guard pos + 2 <= glyphLimit, let dy = reader.i16(pos) else {
                        return TrueTypeGlyphOutline(edges: [], xMin: 0, yMin: 0, xMax: 0, yMax: 0)
                    }
                    pos += 2
                    curY += Int32(dy)
                }
                yCoords[i] = Float(curY)
            }

            let tolerance = max(0.5, Float(unitsPerEm) / 1000.0)
            var edges: [TrueTypeEdge] = []
            var contourStart = 0
            for contourEnd in endPts {
                if contourEnd >= contourStart {
                    let count = contourEnd - contourStart + 1
                    if count >= 2 {
                        var pts: [(x: Float, y: Float, onCurve: Bool)] = []
                        pts.reserveCapacity(count)
                        for idx in contourStart...contourEnd {
                            pts.append((xCoords[idx], yCoords[idx], (flags[idx] & 0x01) != 0))
                        }
                        Self.flattenContour(pts, tolerance: tolerance, into: &edges)
                    }
                    contourStart = contourEnd + 1
                }
            }

            return TrueTypeGlyphOutline(
                edges: edges,
                xMin: Float(gxMin),
                yMin: Float(gyMin),
                xMax: Float(gxMax),
                yMax: Float(gyMax)
            )
        } else {
            // Composite glyph
            var pos = glyphStart + 10
            var allEdges: [TrueTypeEdge] = []
            var minX = Float.greatestFiniteMagnitude
            var minY = Float.greatestFiniteMagnitude
            var maxX = -Float.greatestFiniteMagnitude
            var maxY = -Float.greatestFiniteMagnitude

            while pos + 4 <= glyphLimit {
                guard let flags = reader.u16(pos),
                      let compGlyph = reader.u16(pos + 2) else {
                    break
                }
                pos += 4

                let arg1: Int32
                let arg2: Int32
                if (flags & 0x0001) != 0 {
                    guard pos + 4 <= glyphLimit,
                          let a1 = reader.i16(pos),
                          let a2 = reader.i16(pos + 2) else { break }
                    arg1 = Int32(a1)
                    arg2 = Int32(a2)
                    pos += 4
                } else {
                    guard pos + 2 <= glyphLimit,
                          let a1 = reader.i8(pos),
                          let a2 = reader.i8(pos + 1) else { break }
                    arg1 = Int32(a1)
                    arg2 = Int32(a2)
                    pos += 2
                }

                let dx: Float = ((flags & 0x0002) != 0) ? Float(arg1) : 0
                let dy: Float = ((flags & 0x0002) != 0) ? Float(arg2) : 0

                var m00: Float = 1
                var m01: Float = 0
                var m10: Float = 0
                var m11: Float = 1

                if (flags & 0x0008) != 0 {
                    guard pos + 2 <= glyphLimit, let s = reader.i16(pos) else { break }
                    pos += 2
                    let sf = Float(s) / 16384.0
                    m00 = sf
                    m11 = sf
                } else if (flags & 0x0040) != 0 {
                    guard pos + 4 <= glyphLimit,
                          let sx = reader.i16(pos),
                          let sy = reader.i16(pos + 2) else { break }
                    pos += 4
                    m00 = Float(sx) / 16384.0
                    m11 = Float(sy) / 16384.0
                } else if (flags & 0x0080) != 0 {
                    guard pos + 8 <= glyphLimit,
                          let a = reader.i16(pos),
                          let b = reader.i16(pos + 2),
                          let c = reader.i16(pos + 4),
                          let d = reader.i16(pos + 6) else { break }
                    pos += 8
                    m00 = Float(a) / 16384.0
                    m01 = Float(b) / 16384.0
                    m10 = Float(c) / 16384.0
                    m11 = Float(d) / 16384.0
                }

                let child = computeOutline(for: UInt32(compGlyph), depth: depth + 1)
                for edge in child.edges {
                    let tx0 = m00 * edge.x0 + m10 * edge.y0 + dx
                    let ty0 = m01 * edge.x0 + m11 * edge.y0 + dy
                    let tx1 = m00 * edge.x1 + m10 * edge.y1 + dx
                    let ty1 = m01 * edge.x1 + m11 * edge.y1 + dy
                    allEdges.append(TrueTypeEdge(x0: tx0, y0: ty0, x1: tx1, y1: ty1))
                    minX = min(minX, min(tx0, tx1))
                    minY = min(minY, min(ty0, ty1))
                    maxX = max(maxX, max(tx0, tx1))
                    maxY = max(maxY, max(ty0, ty1))
                }

                if (flags & 0x0020) == 0 {
                    break
                }
            }

            if allEdges.isEmpty {
                return TrueTypeGlyphOutline(edges: [], xMin: 0, yMin: 0, xMax: 0, yMax: 0)
            }
            return TrueTypeGlyphOutline(
                edges: allEdges,
                xMin: minX.isFinite ? minX : Float(gxMin),
                yMin: minY.isFinite ? minY : Float(gyMin),
                xMax: maxX.isFinite ? maxX : Float(gxMax),
                yMax: maxY.isFinite ? maxY : Float(gyMax)
            )
        }
    }

    private func computeFallbackStemOutline(for glyphId: UInt32) -> TrueTypeGlyphOutline {
        // CFF-only font ('OTTO') without glyf table: synthesize proportional glyph block
        // for visible non-space glyphs so layout and atlas rasterization remain non-empty.
        let adv = advanceWidthUnits(for: glyphId)
        guard glyphId != 0, adv > 0, glyfRange == nil else {
            return TrueTypeGlyphOutline(edges: [], xMin: 0, yMin: 0, xMax: 0, yMax: 0)
        }
        let x0 = adv * 0.12
        let x1 = adv * 0.88
        let y0: Float = 0
        let y1 = capHeight > 0 ? capHeight : (ascent * 0.7)
        guard x1 > x0, y1 > y0 else {
            return TrueTypeGlyphOutline(edges: [], xMin: 0, yMin: 0, xMax: 0, yMax: 0)
        }
        let edges = Self.rectEdges(x0: x0, y0: y0, x1: x1, y1: y1, clockwise: true)
        return TrueTypeGlyphOutline(edges: edges, xMin: x0, yMin: y0, xMax: x1, yMax: y1)
    }

    private func computeSyntheticOutline(for glyphId: UInt32) -> TrueTypeGlyphOutline {
        // Glyph 1 (space, 0x20) has empty outline; all other printable glyphs render a clean
        // hollow/solid geometric glyph box in design units [0..1000].
        if glyphId == 1 {
            return TrueTypeGlyphOutline(edges: [], xMin: 0, yMin: 0, xMax: 0, yMax: 0)
        }
        let adv = advanceWidthUnits(for: glyphId)
        let x0: Float = max(40, adv * 0.1)
        let x1: Float = max(x0 + 80, adv * 0.9)
        let y0: Float = 0
        let y1: Float = (glyphId >= 66 && glyphId <= 91) ? xHeight : capHeight
        var edges = Self.rectEdges(x0: x0, y0: y0, x1: x1, y1: y1, clockwise: true)
        let stroke: Float = 80
        if (x1 - x0) > stroke * 2.5 && (y1 - y0) > stroke * 2.5 {
            edges.append(contentsOf: Self.rectEdges(
                x0: x0 + stroke,
                y0: y0 + stroke,
                x1: x1 - stroke,
                y1: y1 - stroke,
                clockwise: false
            ))
        }
        return TrueTypeGlyphOutline(edges: edges, xMin: x0, yMin: y0, xMax: x1, yMax: y1)
    }

    private static func rectEdges(x0: Float, y0: Float, x1: Float, y1: Float, clockwise: Bool) -> [TrueTypeEdge] {
        if clockwise {
            return [
                TrueTypeEdge(x0: x0, y0: y0, x1: x0, y1: y1),
                TrueTypeEdge(x0: x0, y0: y1, x1: x1, y1: y1),
                TrueTypeEdge(x0: x1, y0: y1, x1: x1, y1: y0),
                TrueTypeEdge(x0: x1, y0: y0, x1: x0, y1: y0),
            ]
        } else {
            return [
                TrueTypeEdge(x0: x0, y0: y0, x1: x1, y1: y0),
                TrueTypeEdge(x0: x1, y0: y0, x1: x1, y1: y1),
                TrueTypeEdge(x0: x1, y0: y1, x1: x0, y1: y1),
                TrueTypeEdge(x0: x0, y0: y1, x1: x0, y1: y0),
            ]
        }
    }

    private static func flattenContour(
        _ pts: [(x: Float, y: Float, onCurve: Bool)],
        tolerance: Float,
        into edges: inout [TrueTypeEdge]
    ) {
        let n = pts.count
        guard n >= 2 else { return }

        let startPt: (Float, Float)
        let iterRange: Range<Int>
        if pts[0].onCurve {
            startPt = (pts[0].x, pts[0].y)
            iterRange = 1..<n
        } else if pts[n - 1].onCurve {
            startPt = (pts[n - 1].x, pts[n - 1].y)
            iterRange = 0..<(n - 1)
        } else {
            startPt = ((pts[n - 1].x + pts[0].x) * 0.5, (pts[n - 1].y + pts[0].y) * 0.5)
            iterRange = 0..<n
        }

        var currentOn = startPt
        var pendingOff: (Float, Float)? = nil

        for idx in iterRange {
            let p = pts[idx]
            if p.onCurve {
                if let ctrl = pendingOff {
                    subdivideQuad(p0: currentOn, ctrl: ctrl, p1: (p.x, p.y), tolerance: tolerance, depth: 0, into: &edges)
                    pendingOff = nil
                } else {
                    appendEdge(from: currentOn, to: (p.x, p.y), into: &edges)
                }
                currentOn = (p.x, p.y)
            } else {
                if let ctrl = pendingOff {
                    let mid = ((ctrl.0 + p.x) * 0.5, (ctrl.1 + p.y) * 0.5)
                    subdivideQuad(p0: currentOn, ctrl: ctrl, p1: mid, tolerance: tolerance, depth: 0, into: &edges)
                    currentOn = mid
                    pendingOff = (p.x, p.y)
                } else {
                    pendingOff = (p.x, p.y)
                }
            }
        }

        if let ctrl = pendingOff {
            subdivideQuad(p0: currentOn, ctrl: ctrl, p1: startPt, tolerance: tolerance, depth: 0, into: &edges)
        } else {
            appendEdge(from: currentOn, to: startPt, into: &edges)
        }
    }

    @inline(__always)
    private static func appendEdge(
        from p0: (Float, Float),
        to p1: (Float, Float),
        into edges: inout [TrueTypeEdge]
    ) {
        if p0.0 != p1.0 || p0.1 != p1.1 {
            edges.append(TrueTypeEdge(x0: p0.0, y0: p0.1, x1: p1.0, y1: p1.1))
        }
    }

    private static func subdivideQuad(
        p0: (Float, Float),
        ctrl: (Float, Float),
        p1: (Float, Float),
        tolerance: Float,
        depth: Int,
        into edges: inout [TrueTypeEdge]
    ) {
        let mx = (p0.0 + p1.0) * 0.5
        let my = (p0.1 + p1.1) * 0.5
        let dx = ctrl.0 - mx
        let dy = ctrl.1 - my
        if depth >= 5 || (dx * dx + dy * dy) <= tolerance * tolerance {
            appendEdge(from: p0, to: p1, into: &edges)
            return
        }
        let q0 = ((p0.0 + ctrl.0) * 0.5, (p0.1 + ctrl.1) * 0.5)
        let q1 = ((ctrl.0 + p1.0) * 0.5, (ctrl.1 + p1.1) * 0.5)
        let mid = ((q0.0 + q1.0) * 0.5, (q0.1 + q1.1) * 0.5)
        subdivideQuad(p0: p0, ctrl: q0, p1: mid, tolerance: tolerance, depth: depth + 1, into: &edges)
        subdivideQuad(p0: mid, ctrl: q1, p1: p1, tolerance: tolerance, depth: depth + 1, into: &edges)
    }

    static func makeSyntheticFallback(fontId: FontId, familyName: String, features: FontFeatures) -> PureSwiftTrueTypeFace {
        var charMap: [UInt32: UInt16] = [:]
        var advances: [UInt16] = [600] // 0 = .notdef
        var lsbs: [Int16] = [50]
        // 0x20 (space) -> glyph 1, 0x21..0x7E -> glyphs 2..95
        for cp: UInt32 in 0x20...0x7E {
            let gid = UInt16(advances.count)
            charMap[cp] = gid
            advances.append(cp == 0x20 ? 300 : 600)
            lsbs.append(cp == 0x20 ? 0 : 60)
        }
        return PureSwiftTrueTypeFace(
            fontId: fontId,
            familyName: familyName,
            aliasFamilies: [familyName, "sans-serif", "monospace", "serif"],
            postscriptName: familyName.replacingOccurrences(of: " ", with: ""),
            weight: 400,
            isItalic: false,
            features: features,
            isKnownEmoji: false,
            unitsPerEm: 1000,
            ascent: 850,
            descent: -200,
            lineGap: 0,
            underlinePosition: -100,
            underlineThickness: 50,
            capHeight: 700,
            xHeight: 500,
            bbox: Bounds(origin: Point(x: 0, y: -200), size: Size(width: 600, height: 1050)),
            numGlyphs: advances.count,
            advanceWidths: advances,
            leftSideBearings: lsbs,
            cmap: .direct(charMap),
            kernPairs: [:],
            rawBytes: [],
            glyfRange: nil,
            locaOffsets: [],
            isSyntheticFallback: true
        )
    }

    static func parseAll(from data: Data, nextFontId: inout Int) throws -> [PureSwiftTrueTypeFace] {
        let bytes = Array(data)
        let reader = TrueTypeBinaryReader(bytes: bytes)
        guard let magic = reader.u32(0) else {
            throw CosmicTextError("Font data too short")
        }

        if magic == 0x74746366 { // 'ttcf' TrueType Collection
            guard let numFonts = reader.u32(8), numFonts > 0, numFonts <= 256 else {
                throw CosmicTextError("Invalid TTC collection header")
            }
            var faces: [PureSwiftTrueTypeFace] = []
            for i in 0..<Int(numFonts) {
                guard let dirOffset = reader.u32(12 + i * 4) else { continue }
                if let face = try? parseSingleFace(
                    reader: reader,
                    directoryOffset: Int(dirOffset),
                    fontId: FontId(nextFontId)
                ) {
                    faces.append(face)
                    nextFontId += 1
                }
            }
            guard !faces.isEmpty else {
                throw CosmicTextError("No valid faces found in TTC collection")
            }
            return faces
        } else if magic == 0x00010000 || magic == 0x74727565 || magic == 0x4F54544F {
            let face = try parseSingleFace(reader: reader, directoryOffset: 0, fontId: FontId(nextFontId))
            nextFontId += 1
            return [face]
        } else {
            throw CosmicTextError("Unsupported font signature: 0x\(String(magic, radix: 16))")
        }
    }

    private static func tag(_ s: StaticString) -> UInt32 {
        s.withUTF8Buffer { buf in
            guard buf.count == 4 else { return 0 }
            return (UInt32(buf[0]) << 24)
                | (UInt32(buf[1]) << 16)
                | (UInt32(buf[2]) << 8)
                | UInt32(buf[3])
        }
    }

    private static func parseSingleFace(
        reader: TrueTypeBinaryReader,
        directoryOffset: Int,
        fontId: FontId
    ) throws -> PureSwiftTrueTypeFace {
        guard let numTables = reader.u16(directoryOffset + 4), numTables > 0 else {
            throw CosmicTextError("Missing sfnt table directory")
        }

        var tables: [UInt32: TrueTypeTableRange] = [:]
        let recordsBase = directoryOffset + 12
        for i in 0..<Int(numTables) {
            let rec = recordsBase + i * 16
            guard let t = reader.u32(rec),
                  let off = reader.u32(rec + 8),
                  let len = reader.u32(rec + 12) else {
                throw CosmicTextError("Truncated sfnt table record")
            }
            let ioff = Int(off)
            let ilen = Int(len)
            if reader.has(ioff, ilen) {
                tables[t] = TrueTypeTableRange(offset: ioff, length: ilen)
            }
        }

        guard let head = tables[tag("head")], head.length >= 54,
              let hhea = tables[tag("hhea")], hhea.length >= 36,
              let maxp = tables[tag("maxp")], maxp.length >= 6,
              let hmtx = tables[tag("hmtx")],
              let cmapRange = tables[tag("cmap")] else {
            throw CosmicTextError("Missing required OpenType tables (head/hhea/maxp/hmtx/cmap)")
        }

        let unitsPerEm = UInt32(max(1, Int(reader.u16(head.offset + 18) ?? 1000)))
        let xMin = Float(reader.i16(head.offset + 36) ?? 0)
        let yMin = Float(reader.i16(head.offset + 38) ?? -200)
        let xMax = Float(reader.i16(head.offset + 40) ?? Int16(clamping: unitsPerEm))
        let yMax = Float(reader.i16(head.offset + 42) ?? Int16(clamping: unitsPerEm))
        let macStyle = reader.u16(head.offset + 44) ?? 0
        let indexToLocFormat = reader.i16(head.offset + 50) ?? 0

        let rawAscent = Float(reader.i16(hhea.offset + 4) ?? 800)
        let rawDescent = Float(reader.i16(hhea.offset + 6) ?? -200)
        let ascent = rawAscent > 0 ? rawAscent : Float(unitsPerEm) * 0.8
        let descent = rawDescent <= 0 ? rawDescent : -rawDescent
        let lineGap = Float(max(0, Int(reader.i16(hhea.offset + 8) ?? 0)))
        let numHMetrics = max(1, Int(reader.u16(hhea.offset + 34) ?? 1))

        let numGlyphs = max(1, Int(reader.u16(maxp.offset + 4) ?? 1))

        var weight = ((macStyle & 0x01) != 0) ? 700 : 400
        var isItalic = ((macStyle & 0x02) != 0)
        var xHeight = ascent * 0.5
        var capHeight = ascent * 0.7

        if let os2 = tables[tag("OS/2")], os2.length >= 64 {
            let os2Ver = reader.u16(os2.offset) ?? 0
            if let w = reader.u16(os2.offset + 4), w >= 1 && w <= 1000 {
                weight = Int(w)
            }
            if let fsSel = reader.u16(os2.offset + 62) {
                if (fsSel & 0x0001) != 0 || (fsSel & 0x0200) != 0 {
                    isItalic = true
                }
            }
            if os2Ver >= 2 && os2.length >= 90 {
                if let sx = reader.i16(os2.offset + 86), sx > 0 {
                    xHeight = Float(sx)
                }
                if let sc = reader.i16(os2.offset + 88), sc > 0 {
                    capHeight = Float(sc)
                }
            }
        }

        var underlinePos = -Float(unitsPerEm) * 0.1
        var underlineThick = Float(unitsPerEm) * 0.05
        if let post = tables[tag("post")], post.length >= 12 {
            if let up = reader.i16(post.offset + 8) {
                underlinePos = Float(up)
            }
            if let ut = reader.i16(post.offset + 10), ut > 0 {
                underlineThick = Float(ut)
            }
        }

        let (familyName, aliasFamilies, postscriptName) = parseNames(reader: reader, range: tables[tag("name")])
        let isKnownEmoji = postscriptName.localizedCaseInsensitiveContains("emoji")
            || familyName.localizedCaseInsensitiveContains("emoji")

        let (advances, lsbs) = parseHmtx(
            reader: reader,
            range: hmtx,
            numGlyphs: numGlyphs,
            numHMetrics: numHMetrics
        )

        let parsedCmap = try parseCmap(reader: reader, range: cmapRange)
        let kernPairs = parseKern(reader: reader, range: tables[tag("kern")])

        let glyfRange = tables[tag("glyf")]
        var locaOffsets: [Int] = []
        if let loca = tables[tag("loca")], glyfRange != nil {
            locaOffsets = parseLoca(
                reader: reader,
                range: loca,
                numGlyphs: numGlyphs,
                indexToLocFormat: indexToLocFormat
            )
        }

        let bbox = Bounds(
            origin: Point(x: xMin, y: yMin),
            size: Size(width: max(1, xMax - xMin), height: max(1, yMax - yMin))
        )

        return PureSwiftTrueTypeFace(
            fontId: fontId,
            familyName: familyName,
            aliasFamilies: aliasFamilies,
            postscriptName: postscriptName,
            weight: weight,
            isItalic: isItalic,
            features: FontFeatures(),
            isKnownEmoji: isKnownEmoji,
            unitsPerEm: unitsPerEm,
            ascent: ascent,
            descent: descent,
            lineGap: lineGap,
            underlinePosition: underlinePos,
            underlineThickness: underlineThick,
            capHeight: capHeight,
            xHeight: xHeight,
            bbox: bbox,
            numGlyphs: numGlyphs,
            advanceWidths: advances,
            leftSideBearings: lsbs,
            cmap: parsedCmap,
            kernPairs: kernPairs,
            rawBytes: reader.bytes,
            glyfRange: glyfRange,
            locaOffsets: locaOffsets,
            isSyntheticFallback: false
        )
    }

    private static func parseNames(
        reader: TrueTypeBinaryReader,
        range: TrueTypeTableRange?
    ) -> (family: String, aliases: [String], postscript: String) {
        guard let range = range, range.length >= 6,
              let count = reader.u16(range.offset + 2),
              let stringOffset = reader.u16(range.offset + 4) else {
            return ("Sans", ["Sans"], "Sans")
        }

        let storageBase = range.offset + Int(stringOffset)
        var family1 = ""
        var family1Score = -1
        var family16 = ""
        var family16Score = -1
        var psName = ""
        var psScore = -1

        for i in 0..<Int(count) {
            let rec = range.offset + 6 + i * 12
            guard rec + 12 <= range.offset + range.length,
                  let platformID = reader.u16(rec),
                  let encodingID = reader.u16(rec + 2),
                  let languageID = reader.u16(rec + 4),
                  let nameID = reader.u16(rec + 6),
                  let strLen = reader.u16(rec + 8),
                  let strOff = reader.u16(rec + 10) else {
                continue
            }
            guard nameID == 1 || nameID == 6 || nameID == 16 else { continue }
            let start = storageBase + Int(strOff)
            let length = Int(strLen)
            guard start >= range.offset, start + length <= range.offset + range.length else { continue }

            let decoded: String
            var score = 1
            if platformID == 3 || platformID == 0 {
                guard length % 2 == 0 else { continue }
                var utf16Units: [UInt16] = []
                utf16Units.reserveCapacity(length / 2)
                for b in stride(from: start, to: start + length, by: 2) {
                    if let unit = reader.u16(b) {
                        utf16Units.append(unit)
                    }
                }
                decoded = String(decoding: utf16Units, as: UTF16.self)
                    .trimmingCharacters(in: .controlCharacters)
                score = (platformID == 3 && languageID == 0x0409) ? 4 : (platformID == 0 ? 3 : 2)
                _ = encodingID
            } else if platformID == 1 && encodingID == 0 {
                let slice = reader.bytes[start..<(start + length)]
                decoded = String(decoding: slice, as: UTF8.self)
                    .trimmingCharacters(in: .controlCharacters)
                score = (languageID == 0) ? 2 : 1
            } else {
                continue
            }

            guard !decoded.isEmpty else { continue }
            if nameID == 1 && score > family1Score {
                family1 = decoded
                family1Score = score
            } else if nameID == 16 && score > family16Score {
                family16 = decoded
                family16Score = score
            } else if nameID == 6 && score > psScore {
                psName = decoded
                psScore = score
            }
        }

        let primary = !family16.isEmpty ? family16 : (!family1.isEmpty ? family1 : "Sans")
        var aliases: [String] = [primary]
        if !family1.isEmpty && family1.lowercased() != primary.lowercased() {
            aliases.append(family1)
        }
        let resolvedPs = !psName.isEmpty ? psName : primary.replacingOccurrences(of: " ", with: "")
        return (primary, aliases, resolvedPs)
    }

    private static func parseHmtx(
        reader: TrueTypeBinaryReader,
        range: TrueTypeTableRange,
        numGlyphs: Int,
        numHMetrics: Int
    ) -> ([UInt16], [Int16]) {
        var advances = [UInt16](repeating: 500, count: numGlyphs)
        var lsbs = [Int16](repeating: 0, count: numGlyphs)
        let metricsCount = min(numGlyphs, numHMetrics)
        var lastAdvance: UInt16 = 500

        for i in 0..<metricsCount {
            let pos = range.offset + i * 4
            if pos + 4 <= range.offset + range.length,
               let adv = reader.u16(pos),
               let lsb = reader.i16(pos + 2) {
                advances[i] = adv
                lsbs[i] = lsb
                lastAdvance = adv
            }
        }
        let trailingBase = range.offset + metricsCount * 4
        for i in metricsCount..<numGlyphs {
            advances[i] = lastAdvance
            let pos = trailingBase + (i - metricsCount) * 2
            if pos + 2 <= range.offset + range.length, let lsb = reader.i16(pos) {
                lsbs[i] = lsb
            }
        }
        return (advances, lsbs)
    }

    private static func parseCmap(
        reader: TrueTypeBinaryReader,
        range: TrueTypeTableRange
    ) throws -> TrueTypeCmap {
        guard range.length >= 4, let numSubtables = reader.u16(range.offset + 2) else {
            throw CosmicTextError("Invalid cmap header")
        }

        var bestFormat12Offset: Int?
        var bestFormat4Offset: Int?
        var fallbackFormat6Or0Offset: Int?

        for i in 0..<Int(numSubtables) {
            let rec = range.offset + 4 + i * 8
            guard rec + 8 <= range.offset + range.length,
                  let platformID = reader.u16(rec),
                  let encodingID = reader.u16(rec + 2),
                  let subOff = reader.u32(rec + 4) else {
                continue
            }
            let absOff = range.offset + Int(subOff)
            guard absOff + 4 <= range.offset + range.length,
                  let format = reader.u16(absOff) else {
                continue
            }
            let isUnicode = (platformID == 0)
                || (platformID == 3 && (encodingID == 10 || encodingID == 1 || encodingID == 0))
            if format == 12 && isUnicode {
                bestFormat12Offset = absOff
            } else if format == 4 && (isUnicode || bestFormat4Offset == nil) {
                bestFormat4Offset = absOff
            } else if (format == 6 || format == 0) && fallbackFormat6Or0Offset == nil {
                fallbackFormat6Or0Offset = absOff
            }
        }

        if let off = bestFormat12Offset,
           let sub = parseCmapFormat12(reader: reader, offset: off, tableEnd: range.offset + range.length) {
            return sub
        }
        if let off = bestFormat4Offset,
           let sub = parseCmapFormat4(reader: reader, offset: off, tableEnd: range.offset + range.length) {
            return sub
        }
        if let off = fallbackFormat6Or0Offset,
           let sub = parseCmapFormat6Or0(reader: reader, offset: off, tableEnd: range.offset + range.length) {
            return sub
        }
        throw CosmicTextError("No supported Unicode cmap subtable found")
    }

    private static func parseCmapFormat12(
        reader: TrueTypeBinaryReader,
        offset: Int,
        tableEnd: Int
    ) -> TrueTypeCmap? {
        guard offset + 16 <= tableEnd,
              let numGroups = reader.u32(offset + 12) else {
            return nil
        }
        let count = Int(numGroups)
        guard count >= 0, offset + 16 + count * 12 <= tableEnd else { return nil }
        var groups: [(startCode: UInt32, endCode: UInt32, startGlyph: UInt32)] = []
        groups.reserveCapacity(count)
        for i in 0..<count {
            let pos = offset + 16 + i * 12
            guard let s = reader.u32(pos),
                  let e = reader.u32(pos + 4),
                  let g = reader.u32(pos + 8) else {
                return nil
            }
            groups.append((s, e, g))
        }
        return .format12(groups)
    }

    private static func parseCmapFormat4(
        reader: TrueTypeBinaryReader,
        offset: Int,
        tableEnd: Int
    ) -> TrueTypeCmap? {
        guard offset + 14 <= tableEnd,
              let length = reader.u16(offset + 2),
              let segCountX2 = reader.u16(offset + 6) else {
            return nil
        }
        let subEnd = min(tableEnd, offset + Int(length))
        let segCount = Int(segCountX2) / 2
        guard segCount > 0 else { return nil }
        let endCountBase = offset + 14
        let startCountBase = endCountBase + segCount * 2 + 2
        let idDeltaBase = startCountBase + segCount * 2
        let idRangeOffsetBase = idDeltaBase + segCount * 2
        let glyphArrayBase = idRangeOffsetBase + segCount * 2
        guard glyphArrayBase <= subEnd else { return nil }

        var endCount = [UInt16](repeating: 0, count: segCount)
        var startCount = [UInt16](repeating: 0, count: segCount)
        var idDelta = [Int16](repeating: 0, count: segCount)
        var idRangeOffset = [UInt16](repeating: 0, count: segCount)

        for i in 0..<segCount {
            endCount[i] = reader.u16(endCountBase + i * 2) ?? 0xFFFF
            startCount[i] = reader.u16(startCountBase + i * 2) ?? 0xFFFF
            idDelta[i] = reader.i16(idDeltaBase + i * 2) ?? 0
            idRangeOffset[i] = reader.u16(idRangeOffsetBase + i * 2) ?? 0
        }

        let glyphWords = max(0, (subEnd - glyphArrayBase) / 2)
        var glyphIdArray = [UInt16](repeating: 0, count: glyphWords)
        for i in 0..<glyphWords {
            glyphIdArray[i] = reader.u16(glyphArrayBase + i * 2) ?? 0
        }

        return .format4(
            endCount: endCount,
            startCount: startCount,
            idDelta: idDelta,
            idRangeOffset: idRangeOffset,
            glyphIdArray: glyphIdArray
        )
    }

    private static func parseCmapFormat6Or0(
        reader: TrueTypeBinaryReader,
        offset: Int,
        tableEnd: Int
    ) -> TrueTypeCmap? {
        guard let format = reader.u16(offset) else { return nil }
        var map: [UInt32: UInt16] = [:]
        if format == 0 {
            guard offset + 6 + 256 <= tableEnd else { return nil }
            for cp in 0..<256 {
                if let gid = reader.u8(offset + 6 + cp), gid != 0 {
                    map[UInt32(cp)] = UInt16(gid)
                }
            }
            return .direct(map)
        } else if format == 6 {
            guard offset + 10 <= tableEnd,
                  let firstCode = reader.u16(offset + 6),
                  let entryCount = reader.u16(offset + 8),
                  offset + 10 + Int(entryCount) * 2 <= tableEnd else {
                return nil
            }
            for i in 0..<Int(entryCount) {
                if let gid = reader.u16(offset + 10 + i * 2), gid != 0 {
                    map[UInt32(firstCode) + UInt32(i)] = gid
                }
            }
            return .direct(map)
        }
        return nil
    }

    private static func parseKern(
        reader: TrueTypeBinaryReader,
        range: TrueTypeTableRange?
    ) -> [UInt32: Int16] {
        guard let range = range, range.length >= 4,
              let version = reader.u16(range.offset), version == 0,
              let nTables = reader.u16(range.offset + 2) else {
            return [:]
        }
        var pairs: [UInt32: Int16] = [:]
        var pos = range.offset + 4
        let end = range.offset + range.length
        for _ in 0..<Int(nTables) {
            guard pos + 6 <= end,
                  let subLength = reader.u16(pos + 2),
                  let coverage = reader.u16(pos + 4) else {
                break
            }
            let format = coverage >> 8
            let isHorizontal = (coverage & 0x0001) != 0
            let isMinimum = (coverage & 0x0002) != 0
            let isCrossStream = (coverage & 0x0004) != 0
            if format == 0 && isHorizontal && !isMinimum && !isCrossStream && pos + 14 <= end {
                let nPairs = Int(reader.u16(pos + 6) ?? 0)
                let pairsBase = pos + 14
                if pairsBase + nPairs * 6 <= end {
                    pairs.reserveCapacity(pairs.count + nPairs)
                    for p in 0..<nPairs {
                        let pOff = pairsBase + p * 6
                        if let left = reader.u16(pOff),
                           let right = reader.u16(pOff + 2),
                           let val = reader.i16(pOff + 4) {
                            let key = (UInt32(left) << 16) | UInt32(right)
                            pairs[key] = val
                        }
                    }
                }
            }
            if subLength < 6 { break }
            pos += Int(subLength)
        }
        return pairs
    }

    private static func parseLoca(
        reader: TrueTypeBinaryReader,
        range: TrueTypeTableRange,
        numGlyphs: Int,
        indexToLocFormat: Int16
    ) -> [Int] {
        let count = numGlyphs + 1
        var offsets = [Int](repeating: 0, count: count)
        if indexToLocFormat == 0 {
            guard range.length >= count * 2 else { return [] }
            for i in 0..<count {
                offsets[i] = Int(reader.u16(range.offset + i * 2) ?? 0) * 2
            }
        } else {
            guard range.length >= count * 4 else { return [] }
            for i in 0..<count {
                offsets[i] = Int(reader.u32(range.offset + i * 4) ?? 0)
            }
        }
        return offsets
    }
}

// MARK: - Scanline & Subpixel LCD Rasterizer

private enum PureSwiftGlyphRasterizer {
    private static let verticalSamples = 4

    static func transformedBounds(
        outline: TrueTypeGlyphOutline,
        scale: Float,
        shiftX: Float,
        shiftY: Float
    ) -> Bounds<DevicePixels> {
        guard !outline.edges.isEmpty else {
            return Bounds(origin: .zero, size: .zero)
        }
        let sMinX = outline.xMin * scale + shiftX
        let sMaxX = outline.xMax * scale + shiftX
        let sMinY = -outline.yMax * scale + shiftY
        let sMaxY = -outline.yMin * scale + shiftY

        let left = Int32(sMinX.rounded(.down))
        let right = max(left + 1, Int32(sMaxX.rounded(.up)))
        let top = Int32(sMinY.rounded(.down))
        let bottom = max(top + 1, Int32(sMaxY.rounded(.up)))

        return Bounds(
            origin: Point(x: DevicePixels(left), y: DevicePixels(top)),
            size: Size(width: DevicePixels(right - left), height: DevicePixels(bottom - top))
        )
    }

    static func rasterize(
        outline: TrueTypeGlyphOutline,
        scale: Float,
        shiftX: Float,
        shiftY: Float,
        rasterBounds: Bounds<DevicePixels>,
        subpixelRendering: Bool
    ) -> Data {
        let outW = Int(rasterBounds.size.width.value)
        let outH = Int(rasterBounds.size.height.value)
        let bytesPerPixel = subpixelRendering ? 4 : 1
        guard outW > 0, outH > 0, !outline.edges.isEmpty else {
            return Data(count: max(0, outW * outH * bytesPerPixel))
        }

        // Transform edges into device pixel coordinates once per glyph rasterization.
        var screenEdges: [(x0: Float, y0: Float, x1: Float, y1: Float)] = []
        screenEdges.reserveCapacity(outline.edges.count)
        for e in outline.edges {
            let sx0 = e.x0 * scale + shiftX
            let sy0 = -e.y0 * scale + shiftY
            let sx1 = e.x1 * scale + shiftX
            let sy1 = -e.y1 * scale + shiftY
            if sy0 != sy1 {
                screenEdges.append((sx0, sy0, sx1, sy1))
            }
        }
        guard !screenEdges.isEmpty else {
            return Data(count: outW * outH * bytesPerPixel)
        }

        let originX = Float(rasterBounds.origin.x.value)
        let originY = Float(rasterBounds.origin.y.value)
        let columns = subpixelRendering ? (outW * 3) : outW
        let colScale: Float = subpixelRendering ? 3.0 : 1.0

        var data = Data(count: outW * outH * bytesPerPixel)
        var maxSampleCoverage: Float = 0
        var maxSampleRow = 0
        var maxSampleCol = 0

        data.withUnsafeMutableBytes { rawOut in
            guard let baseAddress = rawOut.baseAddress else { return }
            let outPtr = baseAddress.assumingMemoryBound(to: UInt8.self)
            var rowCov = [Float](repeating: 0, count: columns)
            var crossings: [(x: Float, dir: Int)] = []

            for r in 0..<outH {
                for c in 0..<columns { rowCov[c] = 0 }

                for sy in 0..<verticalSamples {
                    let sampleY = originY + Float(r) + (Float(sy) + 0.5) / Float(verticalSamples)
                    crossings.removeAll(keepingCapacity: true)

                    for edge in screenEdges {
                        if (edge.y0 <= sampleY && edge.y1 > sampleY) || (edge.y1 <= sampleY && edge.y0 > sampleY) {
                            let t = (sampleY - edge.y0) / (edge.y1 - edge.y0)
                            let ix = edge.x0 + t * (edge.x1 - edge.x0)
                            let dir = (edge.y1 > edge.y0) ? 1 : -1
                            crossings.append((ix, dir))
                        }
                    }

                    guard crossings.count >= 2 else { continue }
                    crossings.sort { $0.x < $1.x }

                    var winding = 0
                    var spanStart: Float = 0
                    for crossing in crossings {
                        let prevWinding = winding
                        winding += crossing.dir
                        if prevWinding == 0 && winding != 0 {
                            spanStart = crossing.x
                        } else if prevWinding != 0 && winding == 0 {
                            let spanEnd = crossing.x
                            let cStartF = (spanStart - originX) * colScale
                            let cEndF = (spanEnd - originX) * colScale
                            if cEndF > 0 && cStartF < Float(columns) {
                                let cMin = max(0, Int(cStartF.rounded(.down)))
                                let cMax = min(columns - 1, Int(cEndF.rounded(.down)))
                                if cMin <= cMax {
                                    for c in cMin...cMax {
                                        let left = max(cStartF, Float(c))
                                        let right = min(cEndF, Float(c + 1))
                                        if right > left {
                                            rowCov[c] += (right - left)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                let invSamples = 1.0 / Float(verticalSamples)
                if subpixelRendering {
                    let dstRow = outPtr + r * outW * 4
                    for px in 0..<outW {
                        let subIdx = px * 3
                        let c0 = min(1.0, max(0.0, rowCov[subIdx] * invSamples))
                        let c1 = min(1.0, max(0.0, rowCov[subIdx + 1] * invSamples))
                        let c2 = min(1.0, max(0.0, rowCov[subIdx + 2] * invSamples))

                        let prev = (subIdx > 0) ? min(1.0, max(0.0, rowCov[subIdx - 1] * invSamples)) : 0.0
                        let next = (subIdx + 3 < columns) ? min(1.0, max(0.0, rowCov[subIdx + 3] * invSamples)) : 0.0

                        // 3-tap LCD filter (1/6, 4/6, 1/6) to minimize color fringing
                        let rVal = (prev + 4.0 * c0 + c1) / 6.0
                        let gVal = (c0 + 4.0 * c1 + c2) / 6.0
                        let bVal = (c1 + 4.0 * c2 + next) / 6.0

                        let peak = max(rVal, max(gVal, bVal))
                        if peak > maxSampleCoverage {
                            maxSampleCoverage = peak
                            maxSampleRow = r
                            maxSampleCol = px
                        }

                        let redByte = UInt8(min(255, max(0, Int((rVal * 255.0).rounded()))))
                        let greenByte = UInt8(min(255, max(0, Int((gVal * 255.0).rounded()))))
                        let blueByte = UInt8(min(255, max(0, Int((bVal * 255.0).rounded()))))
                        let alphaByte = max(redByte, max(greenByte, blueByte))

                        dstRow[px * 4] = blueByte
                        dstRow[px * 4 + 1] = greenByte
                        dstRow[px * 4 + 2] = redByte
                        dstRow[px * 4 + 3] = alphaByte
                    }
                } else {
                    let dstRow = outPtr + r * outW
                    for px in 0..<outW {
                        let cov = min(1.0, max(0.0, rowCov[px] * invSamples))
                        if cov > maxSampleCoverage {
                            maxSampleCoverage = cov
                            maxSampleRow = r
                            maxSampleCol = px
                        }
                        dstRow[px] = UInt8(min(255, max(0, Int((cov * 255.0).rounded()))))
                    }
                }
            }

            // Ensure tiny 1px glyphs with positive sub-threshold coverage still emit visible ink.
            if maxSampleCoverage > 0 {
                var anyNonZero = false
                let totalBytes = outW * outH * bytesPerPixel
                for i in 0..<totalBytes where outPtr[i] != 0 {
                    anyNonZero = true
                    break
                }
                if !anyNonZero {
                    if subpixelRendering {
                        let idx = (maxSampleRow * outW + maxSampleCol) * 4
                        outPtr[idx] = 1
                        outPtr[idx + 1] = 1
                        outPtr[idx + 2] = 1
                        outPtr[idx + 3] = 1
                    } else {
                        outPtr[maxSampleRow * outW + maxSampleCol] = 1
                    }
                }
            } else {
                // Fallback for ultra-thin hairline glyph falling strictly between scanlines at 1px
                let midR = outH / 2
                let midC = outW / 2
                if subpixelRendering {
                    let idx = (midR * outW + midC) * 4
                    outPtr[idx] = 128
                    outPtr[idx + 1] = 128
                    outPtr[idx + 2] = 128
                    outPtr[idx + 3] = 128
                } else {
                    outPtr[midR * outW + midC] = 128
                }
            }
        }

        return data
    }
}

// MARK: - CosmicTextSystemState (Non-Linux)

// PORT NOTE: Non-Linux CosmicTextSystemState synchronizes its parsed font face table
// and family index via NSLock for safe concurrent layout and glyph rasterization.
private final class CosmicTextSystemState: @unchecked Sendable {
    private let lock = NSLock()
    private var loadedFaces: [PureSwiftTrueTypeFace] = []
    private var familyIndex: [String: [FontId]] = [:]
    private var didScanSystemFonts: Bool = false
    var systemFontFallback: String
    var loadSystemFonts: Bool = true

    init(systemFontFallback: String) {
        self.systemFontFallback = systemFontFallback
    }

    private func registerFaceLocked(_ face: PureSwiftTrueTypeFace) {
        loadedFaces.append(face)
        for alias in face.aliasFamilies {
            let key = alias.lowercased()
            if !familyIndex[key, default: []].contains(face.fontId) {
                familyIndex[key, default: []].append(face.fontId)
            }
        }
    }

    private func loadPlatformSystemFontsIfNeededLocked() {
        guard loadSystemFonts, !didScanSystemFonts else { return }
        didScanSystemFonts = true

        #if os(Android)
        let candidatePaths = [
            "/system/fonts/Roboto-Regular.ttf",
            "/system/fonts/Roboto-Bold.ttf",
            "/system/fonts/Roboto-Italic.ttf",
            "/system/fonts/RobotoStatic-Regular.ttf",
            "/system/fonts/DroidSansMono.ttf",
        ]
        #elseif os(Windows)
        let candidatePaths = [
            "C:\\Windows\\Fonts\\segoeui.ttf",
            "C:\\Windows\\Fonts\\segoeuib.ttf",
            "C:\\Windows\\Fonts\\segoeuii.ttf",
            "C:\\Windows\\Fonts\\arial.ttf",
            "C:\\Windows\\Fonts\\consola.ttf",
        ]
        #else
        let candidatePaths: [String] = []
        #endif

        var nextId = loadedFaces.count
        for path in candidatePaths {
            let url = URL(fileURLWithPath: path)
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  !data.isEmpty,
                  let parsed = try? PureSwiftTrueTypeFace.parseAll(from: data, nextFontId: &nextId) else {
                continue
            }
            for face in parsed {
                registerFaceLocked(face)
            }
        }
    }

    private func ensureAtLeastOneFaceLocked() -> PureSwiftTrueTypeFace {
        loadPlatformSystemFontsIfNeededLocked()
        if let first = loadedFaces.first {
            return first
        }
        let fallback = PureSwiftTrueTypeFace.makeSyntheticFallback(
            fontId: FontId(loadedFaces.count),
            familyName: systemFontFallback,
            features: FontFeatures()
        )
        registerFaceLocked(fallback)
        return fallback
    }

    private func face(for fontId: FontId) -> PureSwiftTrueTypeFace? {
        lock.lock()
        defer { lock.unlock() }
        let idx = fontId.value
        if idx >= 0 && idx < loadedFaces.count {
            return loadedFaces[idx]
        }
        return nil
    }

    func addFonts(_ fonts: [Data]) throws {
        lock.lock()
        defer { lock.unlock() }

        var nextId = loadedFaces.count
        for data in fonts {
            let parsedFaces = try PureSwiftTrueTypeFace.parseAll(from: data, nextFontId: &nextId)
            for face in parsedFaces {
                registerFaceLocked(face)
            }
        }
    }

    func allFontNames() -> [String] {
        lock.lock()
        defer { lock.unlock() }

        loadPlatformSystemFontsIfNeededLocked()
        var names = Set<String>()
        for face in loadedFaces {
            names.insert(face.familyName)
        }
        if names.isEmpty && loadSystemFonts {
            names.insert(systemFontFallback)
        }
        return names.sorted()
    }

    func fontId(descriptor: Font) throws -> FontId {
        lock.lock()
        defer { lock.unlock() }

        loadPlatformSystemFontsIfNeededLocked()

        let resolvedName = fontNameWithFallbacks(descriptor.family.value, system: systemFontFallback)
        let lookupKeys = [
            resolvedName.lowercased(),
            descriptor.family.value.lowercased(),
            systemFontFallback.lowercased(),
        ]

        for key in lookupKeys {
            if let ids = familyIndex[key], !ids.isEmpty {
                let candidates = ids.compactMap { id -> PureSwiftTrueTypeFace? in
                    let idx = id.value
                    return (idx >= 0 && idx < loadedFaces.count) ? loadedFaces[idx] : nil
                }
                if !candidates.isEmpty {
                    return findBestMatch(font: descriptor, candidates: candidates)
                }
            }
        }

        if !loadedFaces.isEmpty {
            return findBestMatch(font: descriptor, candidates: loadedFaces)
        }

        return ensureAtLeastOneFaceLocked().fontId
    }

    private func findBestMatch(font: Font, candidates: [PureSwiftTrueTypeFace]) -> FontId {
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

        return FontMetrics(
            unitsPerEm: loaded.unitsPerEm,
            ascent: loaded.ascent,
            descent: loaded.descent,
            lineGap: loaded.lineGap,
            underlinePosition: loaded.underlinePosition,
            underlineThickness: loaded.underlineThickness,
            capHeight: loaded.capHeight,
            xHeight: loaded.xHeight,
            boundingBox: loaded.bbox
        )
    }

    func typographicBounds(fontId: FontId, glyphId: GlyphId) throws -> Bounds<Float> {
        guard let loaded = face(for: fontId) else {
            throw CosmicTextError("Invalid FontId")
        }
        guard Int(glyphId.value) < loaded.numGlyphs else {
            throw CosmicTextError("Invalid GlyphId")
        }
        let adv = loaded.advanceWidthUnits(for: glyphId.value)
        let height = loaded.ascent - loaded.descent
        return Bounds(origin: .zero, size: Size(width: adv, height: height))
    }

    func advance(fontId: FontId, glyphId: GlyphId) throws -> Size<Float> {
        guard let loaded = face(for: fontId) else {
            throw CosmicTextError("Invalid FontId")
        }
        guard Int(glyphId.value) < loaded.numGlyphs else {
            throw CosmicTextError("Invalid GlyphId")
        }
        return Size(width: loaded.advanceWidthUnits(for: glyphId.value), height: 0)
    }

    func glyphForChar(fontId: FontId, ch: Character) -> GlyphId? {
        guard let loaded = face(for: fontId),
              let scalar = ch.unicodeScalars.first else {
            return nil
        }
        let gid = loaded.glyphIndex(for: scalar.value)
        return gid == 0 ? nil : GlyphId(gid)
    }

    func glyphRasterBounds(params: RenderGlyphParams) throws -> Bounds<DevicePixels> {
        guard let loaded = face(for: params.fontId) else {
            throw CosmicTextError("Invalid FontId")
        }
        guard Int(params.glyphId.value) < loaded.numGlyphs else {
            throw CosmicTextError("Invalid GlyphId")
        }

        let effectivePx = max(1.0, Float(params.fontSize.value) * params.scaleFactor)
        let scale = effectivePx / Float(loaded.unitsPerEm)
        let shiftX = Float(params.subpixelVariant.x) / Float(max(1, Int(subpixelVariantsX)))
        let shiftY = Float(params.subpixelVariant.y) / Float(max(1, Int(subpixelVariantsY)))
        let outline = loaded.outline(for: params.glyphId.value)

        return PureSwiftGlyphRasterizer.transformedBounds(
            outline: outline,
            scale: scale,
            shiftX: shiftX,
            shiftY: shiftY
        )
    }

    func rasterizeGlyph(
        params: RenderGlyphParams,
        rasterBounds: Bounds<DevicePixels>
    ) throws -> (Size<DevicePixels>, Data) {
        if rasterBounds.size.width.value <= 0 || rasterBounds.size.height.value <= 0 {
            throw CosmicTextError("Glyph bounds are empty")
        }
        guard let loaded = face(for: params.fontId) else {
            throw CosmicTextError("Invalid FontId")
        }
        guard Int(params.glyphId.value) < loaded.numGlyphs else {
            throw CosmicTextError("Invalid GlyphId")
        }

        let effectivePx = max(1.0, Float(params.fontSize.value) * params.scaleFactor)
        let scale = effectivePx / Float(loaded.unitsPerEm)
        let shiftX = Float(params.subpixelVariant.x) / Float(max(1, Int(subpixelVariantsX)))
        let shiftY = Float(params.subpixelVariant.y) / Float(max(1, Int(subpixelVariantsY)))
        let outline = loaded.outline(for: params.glyphId.value)

        let bitmap = PureSwiftGlyphRasterizer.rasterize(
            outline: outline,
            scale: scale,
            shiftX: shiftX,
            shiftY: shiftY,
            rasterBounds: rasterBounds,
            subpixelRendering: params.subpixelRendering
        )
        return (rasterBounds.size, bitmap)
    }

    private static func isZeroWidthMarkOrJoiner(_ v: UInt32) -> Bool {
        if v == 0x200B || v == 0x200C || v == 0x200D || v == 0xFEFF { return true }
        if (0xFE00...0xFE0F).contains(v) || (0xE0100...0xE01EF).contains(v) { return true }
        if (0x0300...0x036F).contains(v)
            || (0x1AB0...0x1AFF).contains(v)
            || (0x1DC0...0x1DFF).contains(v)
            || (0x20D0...0x20FF).contains(v)
            || (0xFE20...0xFE2F).contains(v) {
            return true
        }
        return false
    }

    func layoutLine(text: String, fontSize: Pixels, runs: [FontRun]) -> LineLayout {
        guard !text.isEmpty else {
            return LineLayout(fontSize: fontSize, width: .zero, ascent: .zero, descent: .zero, runs: [], len: 0)
        }

        lock.lock()
        let fallbackFace = ensureAtLeastOneFaceLocked()
        let facesSnapshot = loadedFaces
        lock.unlock()

        let textUtf8 = Array(text.utf8)
        let fontRuns: [FontRun]
        if runs.isEmpty {
            fontRuns = [FontRun(len: textUtf8.count, fontId: fallbackFace.fontId)]
        } else {
            fontRuns = runs
        }

        var shapedRuns: [ShapedRun] = []
        var currentX: Float = 0
        var maxAscent: Float = 0
        var maxDescent: Float = 0
        var currentOffset = 0

        for run in fontRuns {
            let runLen = min(run.len, textUtf8.count - currentOffset)
            guard runLen > 0 else { continue }

            let fontIdx = run.fontId.value
            let loaded: PureSwiftTrueTypeFace
            if fontIdx >= 0 && fontIdx < facesSnapshot.count {
                loaded = facesSnapshot[fontIdx]
            } else {
                loaded = fallbackFace
            }

            let effectiveFontSize = max(0.5, Float(fontSize.value))
            let scale = effectiveFontSize / Float(loaded.unitsPerEm)
            let runAscent = loaded.ascent * scale
            let runDescent = abs(loaded.descent) * scale
            if runAscent > maxAscent { maxAscent = runAscent }
            if runDescent > maxDescent { maxDescent = runDescent }

            let sliceBytes = textUtf8[currentOffset..<(currentOffset + runLen)]
            let sliceStr = String(decoding: sliceBytes, as: UTF8.self)

            var runGlyphs: [ShapedGlyph] = []
            var byteCursor = currentOffset
            var prevGlyphId: UInt32? = nil

            for scalar in sliceStr.unicodeScalars {
                let scalarUtf8Len = scalar.utf8.count
                let code = scalar.value

                if (code == 0x200D || (0xFE00...0xFE0F).contains(code) || (0xE0100...0xE01EF).contains(code)),
                   sliceStr.unicodeScalars.count > 1 {
                    byteCursor += scalarUtf8Len
                    continue
                }

                let gid = loaded.glyphIndex(for: code)
                if let prev = prevGlyphId {
                    let kern = loaded.kerningUnits(left: prev, right: gid) * scale
                    if currentX + kern >= 0 {
                        currentX += kern
                    }
                }

                let isEmojiScalar = loaded.isKnownEmoji || scalar.properties.isEmojiPresentation
                runGlyphs.append(
                    ShapedGlyph(
                        id: GlyphId(gid),
                        position: Point(x: Pixels(currentX), y: .zero),
                        index: byteCursor,
                        isEmoji: isEmojiScalar
                    )
                )

                let advUnits: Float
                if gid == 0 && Self.isZeroWidthMarkOrJoiner(code) {
                    advUnits = 0
                } else if code == 0x09 { // Horizontal tab = 4 spaces
                    let spaceGid = loaded.glyphIndex(for: 0x20)
                    advUnits = loaded.advanceWidthUnits(for: spaceGid) * 4.0
                } else {
                    advUnits = loaded.advanceWidthUnits(for: gid)
                }

                currentX += advUnits * scale
                prevGlyphId = gid
                byteCursor += scalarUtf8Len
            }

            shapedRuns.append(ShapedRun(fontId: run.fontId, glyphs: runGlyphs))
            currentOffset += runLen
        }

        return LineLayout(
            fontSize: fontSize,
            width: Pixels(currentX),
            ascent: Pixels(maxAscent),
            descent: Pixels(maxDescent),
            runs: shapedRuns,
            len: textUtf8.count
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
