// Ported from: crates/gpui_windows/src/direct_write.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Windows)
import Foundation
import CWinSys
import GPUI
import GPUICollections

// MARK: - Error Type

public enum DirectWriteError: Error, CustomStringConvertible, Sendable {
    case initializationFailure(Int32)
    case fontNotFound(String)
    case metricsFailure(Int32)
    case layoutFailure(Int32)
    case rasterizationFailure(Int32)

    public var description: String {
        switch self {
        case .initializationFailure(let hr):
            return "DirectWrite initialization failure: HRESULT 0x\(String(UInt32(bitPattern: hr), radix: 16))"
        case .fontNotFound(let name):
            return "DirectWrite font not found: \(name)"
        case .metricsFailure(let hr):
            return "DirectWrite metrics query failure: HRESULT 0x\(String(UInt32(bitPattern: hr), radix: 16))"
        case .layoutFailure(let hr):
            return "DirectWrite layout failure: HRESULT 0x\(String(UInt32(bitPattern: hr), radix: 16))"
        case .rasterizationFailure(let hr):
            return "DirectWrite rasterization failure: HRESULT 0x\(String(UInt32(bitPattern: hr), radix: 16))"
        }
    }
}

// MARK: - Cluster Analyzer

public struct ClusterAnalyzer: IteratorProtocol {
    private var utf16Idx: Int = 0
    private var glyphIdx: Int = 0
    private let glyphCount: Int
    private let clusterMap: [UInt16]

    public init(clusterMap: [UInt16], glyphCount: Int) {
        self.clusterMap = clusterMap
        self.glyphCount = glyphCount
    }

    public mutating func next() -> (utf16Len: Int, glyphCount: Int)? {
        if utf16Idx >= clusterMap.count {
            return nil
        }
        let startUtf16Idx = utf16Idx
        let currentGlyph = Int(clusterMap[startUtf16Idx])

        var endUtf16Idx = startUtf16Idx + 1
        while endUtf16Idx < clusterMap.count && Int(clusterMap[endUtf16Idx]) == currentGlyph {
            endUtf16Idx += 1
        }

        let utf16Len = endUtf16Idx - startUtf16Idx
        let nextGlyph: Int
        if endUtf16Idx < clusterMap.count {
            nextGlyph = Int(clusterMap[endUtf16Idx])
        } else {
            nextGlyph = glyphCount
        }
        let count = max(0, nextGlyph - currentGlyph)
        utf16Idx = endUtf16Idx
        glyphIdx = nextGlyph
        return (utf16Len, count)
    }
}

// MARK: - Font Info

private final class FontInfo {
    let familyName: String
    let familyNameWide: [UInt16]
    let fontFace: WinHandle
    let collection: WinHandle
    let weight: UInt32
    let style: UInt32
    let features: FontFeatures
    let isColor: Bool

    init(
        familyName: String,
        familyNameWide: [UInt16],
        fontFace: WinHandle,
        collection: WinHandle,
        weight: UInt32,
        style: UInt32,
        features: FontFeatures,
        isColor: Bool
    ) {
        cwin_addref_com_object(fontFace)
        cwin_addref_com_object(collection)
        self.familyName = familyName
        self.familyNameWide = familyNameWide
        self.fontFace = fontFace
        self.collection = collection
        self.weight = weight
        self.style = style
        self.features = features
        self.isColor = isColor
    }

    deinit {
        cwin_release_com_object(fontFace)
        cwin_release_com_object(collection)
    }
}

// MARK: - DirectWriteTextSystem

// PORT NOTE: DirectWriteTextSystem synchronizes internal DirectWrite factory,
// collections, and font caches with NSLock for thread-safe concurrent access.
public final class DirectWriteTextSystem: PlatformTextSystem, @unchecked Sendable {
    private let lock = NSLock()
    private let factory: WinHandle
    private let inMemoryLoader: WinHandle?
    private let fontSetBuilder: WinHandle?
    private let systemFontCollection: WinHandle
    private var customFontCollection: WinHandle?

    private var fonts: [FontInfo] = []
    private var fontToFontId: [Font: FontId] = [:]
    private var cachedFontFaces: [UnsafeMutableRawPointer: FontId] = [:]
    private var allFontNamesCache: [String]? = nil

    public var systemUiFontName: String = "Segoe UI"
    public var systemSubpixelRendering: Bool = true

    public init(directxDevices: DirectXDevices? = nil) throws {
        var fact: UnsafeMutableRawPointer?
        let hrFact = cwin_dwrite_create_factory(&fact)
        guard hrFact == 0, let factory = fact else {
            throw DirectWriteError.initializationFailure(hrFact)
        }
        self.factory = factory

        var loader: UnsafeMutableRawPointer?
        _ = cwin_dwrite_register_in_memory_font_loader(factory, &loader)
        self.inMemoryLoader = loader

        var builder: UnsafeMutableRawPointer?
        _ = cwin_dwrite_create_font_set_builder(factory, &builder)
        self.fontSetBuilder = builder

        var sysCol: UnsafeMutableRawPointer?
        let hrSys = cwin_dwrite_get_system_font_collection(factory, &sysCol)
        if hrSys == 0, let sysCol = sysCol {
            self.systemFontCollection = sysCol
        } else {
            // Fallback to empty collection if system collection fails
            self.systemFontCollection = factory
        }

        if let b = builder {
            var custCol: UnsafeMutableRawPointer?
            if cwin_dwrite_font_set_builder_create_collection(b, factory, &custCol) == 0, let custCol = custCol {
                self.customFontCollection = custCol
            }
        }
    }

    public static func new(directxDevices: DirectXDevices? = nil) throws -> DirectWriteTextSystem {
        try DirectWriteTextSystem(directxDevices: directxDevices)
    }

    deinit {
        for f in fonts {
            _ = f
        }
        if let cust = customFontCollection {
            cwin_release_com_object(cust)
        }
        if systemFontCollection != factory {
            cwin_release_com_object(systemFontCollection)
        }
        if let b = fontSetBuilder {
            cwin_release_com_object(b)
        }
        if let l = inMemoryLoader {
            cwin_release_com_object(l)
        }
        cwin_release_com_object(factory)
    }

    // MARK: - PlatformTextSystem Conformance

    public func addFonts(_ fontDataArray: [Data]) throws {
        lock.lock()
        defer { lock.unlock() }

        guard let loader = inMemoryLoader, let builder = fontSetBuilder else {
            return
        }

        var anyAdded = false
        for data in fontDataArray {
            if data.isEmpty { continue }
            var fontFile: UnsafeMutableRawPointer?
            let hrFile = data.withUnsafeBytes { rawBytes in
                cwin_dwrite_create_font_file_reference(
                    loader,
                    rawBytes.baseAddress,
                    data.count,
                    &fontFile
                )
            }
            if hrFile == 0, let fontFile = fontFile {
                _ = cwin_dwrite_font_set_builder_add_file(builder, fontFile)
                cwin_release_com_object(fontFile)
                anyAdded = true
            }
        }

        if anyAdded {
            var newCol: UnsafeMutableRawPointer?
            let hrCol = cwin_dwrite_font_set_builder_create_collection(builder, factory, &newCol)
            if hrCol == 0, let newCol = newCol {
                if let old = customFontCollection {
                    cwin_release_com_object(old)
                }
                self.customFontCollection = newCol
                self.allFontNamesCache = nil
            }
        }
    }

    public func allFontNames() -> [String] {
        lock.lock()
        defer { lock.unlock() }

        if let cached = allFontNamesCache {
            return cached
        }

        var namesSet = Set<String>()
        var nameBuf = [UInt16](repeating: 0, count: 256)

        func readCollectionNames(_ col: WinHandle?) {
            guard let col = col else { return }
            let count = cwin_dwrite_collection_get_family_count(col)
            for idx in 0..<count {
                nameBuf.withUnsafeMutableBufferPointer { ptr in
                    if cwin_dwrite_collection_get_family_name(col, idx, ptr.baseAddress, 256) == 0 {
                        let name = fromWideString(ptr.baseAddress)
                        if !name.isEmpty {
                            namesSet.insert(name)
                        }
                    }
                }
            }
        }

        readCollectionNames(customFontCollection)
        readCollectionNames(systemFontCollection)

        let sorted = namesSet.sorted()
        self.allFontNamesCache = sorted
        return sorted
    }

    public func fontId(descriptor: Font) throws -> FontId {
        lock.lock()
        defer { lock.unlock() }

        if let existing = fontToFontId[descriptor] {
            return existing
        }

        let familyName = descriptor.family
        let familyWide = toWideString(familyName)

        var selectedCol: WinHandle?
        var familyIndex: UInt32 = 0
        var found = false

        if let cust = customFontCollection {
            var exists: Int32 = 0
            if cwin_dwrite_collection_find_family(cust, familyWide, &familyIndex, &exists) == 0 && exists != 0 {
                selectedCol = cust
                found = true
            }
        }

        if !found {
            var exists: Int32 = 0
            if cwin_dwrite_collection_find_family(systemFontCollection, familyWide, &familyIndex, &exists) == 0 && exists != 0 {
                selectedCol = systemFontCollection
                found = true
            }
        }

        if !found {
            // Fall back to system UI font name
            let uiWide = toWideString(systemUiFontName)
            var exists: Int32 = 0
            if cwin_dwrite_collection_find_family(systemFontCollection, uiWide, &familyIndex, &exists) == 0 && exists != 0 {
                selectedCol = systemFontCollection
                found = true
            } else if cwin_dwrite_collection_get_family_count(systemFontCollection) > 0 {
                selectedCol = systemFontCollection
                familyIndex = 0
                found = true
            }
        }

        guard let col = selectedCol else {
            throw DirectWriteError.fontNotFound(familyName)
        }

        let weight: UInt32 = UInt32(descriptor.weight.rawValue)
        let style: UInt32 = (descriptor.style == .italic) ? 2 : 0

        var face: UnsafeMutableRawPointer?
        var hr = cwin_dwrite_collection_get_font_face(col, familyIndex, weight, style, &face)
        if hr != 0 || face == nil {
            // Fallback to normal weight and normal style
            hr = cwin_dwrite_collection_get_font_face(col, familyIndex, 400, 0, &face)
        }

        guard hr == 0, let fontFace = face else {
            throw DirectWriteError.fontNotFound(familyName)
        }
        defer { cwin_release_com_object(fontFace) }

        var metrics = CWinFontMetrics()
        _ = cwin_dwrite_font_face_get_metrics(fontFace, &metrics)

        let info = FontInfo(
            familyName: familyName,
            familyNameWide: familyWide,
            fontFace: fontFace,
            collection: col,
            weight: weight,
            style: style,
            features: descriptor.features,
            isColor: metrics.is_color != 0
        )

        let newId = FontId(fonts.count)
        fonts.append(info)
        fontToFontId[descriptor] = newId
        cachedFontFaces[fontFace] = newId
        return newId
    }

    public func fontMetrics(fontId: FontId) -> FontMetrics {
        lock.lock()
        defer { lock.unlock() }

        guard fontId.value < fonts.count else {
            return FontMetrics(
                unitsPerEm: 1000,
                ascent: 1000.0,
                descent: -250.0,
                lineGap: 0.0,
                underlinePosition: -100.0,
                underlineThickness: 50.0,
                capHeight: 700.0,
                xHeight: 500.0,
                boundingBox: Bounds(
                    origin: Point(x: Pixels(0), y: Pixels(-250)),
                    size: Size(width: Pixels(1000), height: Pixels(1250))
                )
            )
        }

        let info = fonts[fontId.value]
        var metrics = CWinFontMetrics()
        _ = cwin_dwrite_font_face_get_metrics(info.fontFace, &metrics)

        let uem = metrics.units_per_em > 0 ? metrics.units_per_em : 1000
        return FontMetrics(
            unitsPerEm: uem,
            ascent: metrics.ascent,
            descent: metrics.descent,
            lineGap: metrics.line_gap,
            underlinePosition: metrics.underline_position,
            underlineThickness: metrics.underline_thickness,
            capHeight: metrics.cap_height,
            xHeight: metrics.x_height,
            boundingBox: Bounds(
                origin: Point(x: Pixels(metrics.glyph_box_left), y: Pixels(metrics.glyph_box_bottom)),
                size: Size(
                    width: Pixels(metrics.glyph_box_right - metrics.glyph_box_left),
                    height: Pixels(metrics.glyph_box_top - metrics.glyph_box_bottom)
                )
            )
        )
    }

    public func typographicBounds(fontId: FontId, glyphId: GlyphId) throws -> Bounds<Float> {
        lock.lock()
        defer { lock.unlock() }

        guard fontId.value < fonts.count else {
            throw DirectWriteError.fontNotFound("FontId \(fontId.value)")
        }

        let info = fonts[fontId.value]
        var gm = CWinGlyphDesignMetrics()
        var gId = UInt16(glyphId.value)
        let hr = cwin_dwrite_font_face_get_design_glyph_metrics(info.fontFace, &gId, 1, &gm)
        guard hr == 0 else { throw DirectWriteError.metricsFailure(hr) }

        var fm = CWinFontMetrics()
        _ = cwin_dwrite_font_face_get_metrics(info.fontFace, &fm)
        let units = Float(fm.units_per_em > 0 ? fm.units_per_em : 1000)

        return Bounds(
            origin: Point(
                x: gm.left_side_bearing / units,
                y: (gm.vertical_origin_y - gm.top_side_bearing) / units
            ),
            size: Size(
                width: (gm.advance_width - gm.left_side_bearing - gm.right_side_bearing) / units,
                height: (gm.advance_height - gm.top_side_bearing - gm.bottom_side_bearing) / units
            )
        )
    }

    public func advance(fontId: FontId, glyphId: GlyphId) throws -> Size<Float> {
        lock.lock()
        defer { lock.unlock() }

        guard fontId.value < fonts.count else {
            throw DirectWriteError.fontNotFound("FontId \(fontId.value)")
        }

        let info = fonts[fontId.value]
        var gm = CWinGlyphDesignMetrics()
        var gId = UInt16(glyphId.value)
        let hr = cwin_dwrite_font_face_get_design_glyph_metrics(info.fontFace, &gId, 1, &gm)
        guard hr == 0 else { throw DirectWriteError.metricsFailure(hr) }

        var fm = CWinFontMetrics()
        _ = cwin_dwrite_font_face_get_metrics(info.fontFace, &fm)
        let units = Float(fm.units_per_em > 0 ? fm.units_per_em : 1000)

        return Size(width: gm.advance_width / units, height: 0.0)
    }

    public func glyphForChar(fontId: FontId, ch: Character) -> GlyphId? {
        lock.lock()
        defer { lock.unlock() }

        guard fontId.value < fonts.count else { return nil }
        let info = fonts[fontId.value]

        guard let scalar = ch.unicodeScalars.first else { return nil }
        var codepoint = UInt32(scalar.value)
        var glyphIdx: UInt16 = 0
        let hr = cwin_dwrite_font_face_get_glyph_indices(info.fontFace, &codepoint, 1, &glyphIdx)
        guard hr == 0, glyphIdx != 0 else { return nil }
        return GlyphId(UInt32(glyphIdx))
    }

    public func glyphRasterBounds(params: RenderGlyphParams) throws -> Bounds<DevicePixels> {
        lock.lock()
        defer { lock.unlock() }

        guard params.fontId.value < fonts.count else {
            throw DirectWriteError.fontNotFound("FontId \(params.fontId.value)")
        }

        let info = fonts[params.fontId.value]
        let biasX = Float(params.subpixelVariant.x) / Float(subpixelVariantsX) / params.scaleFactor
        let biasY = Float(params.subpixelVariant.y) / Float(subpixelVariantsY) / params.scaleFactor

        var cParams = CWinGlyphRasterParams(
            font_face: info.fontFace,
            glyph_id: UInt16(params.glyphId.value),
            font_size: params.fontSize.value,
            scale_factor: params.scaleFactor,
            subpixel_bias_x: biasX,
            subpixel_bias_y: biasY,
            subpixel_rendering: params.subpixelRendering ? 1 : 0,
            is_emoji: params.isEmoji ? 1 : 0
        )

        var result = CWinGlyphRasterResult()
        let hr = cwin_dwrite_rasterize_glyph(factory, &cParams, &result)
        guard hr == 0 else { throw DirectWriteError.rasterizationFailure(hr) }
        defer { cwin_dwrite_free_raster_result(&result) }

        return Bounds(
            origin: Point(x: DevicePixels(Int(result.left)), y: DevicePixels(Int(result.top))),
            size: Size(width: DevicePixels(Int(result.width)), height: DevicePixels(Int(result.height)))
        )
    }

    public func rasterizeGlyph(
        params: RenderGlyphParams,
        rasterBounds: Bounds<DevicePixels>
    ) throws -> (Size<DevicePixels>, Data) {
        lock.lock()
        defer { lock.unlock() }

        guard params.fontId.value < fonts.count else {
            throw DirectWriteError.fontNotFound("FontId \(params.fontId.value)")
        }

        let info = fonts[params.fontId.value]
        let biasX = Float(params.subpixelVariant.x) / Float(subpixelVariantsX) / params.scaleFactor
        let biasY = Float(params.subpixelVariant.y) / Float(subpixelVariantsY) / params.scaleFactor

        var cParams = CWinGlyphRasterParams(
            font_face: info.fontFace,
            glyph_id: UInt16(params.glyphId.value),
            font_size: params.fontSize.value,
            scale_factor: params.scaleFactor,
            subpixel_bias_x: biasX,
            subpixel_bias_y: biasY,
            subpixel_rendering: params.subpixelRendering ? 1 : 0,
            is_emoji: params.isEmoji ? 1 : 0
        )

        var result = CWinGlyphRasterResult()
        let hr = cwin_dwrite_rasterize_glyph(factory, &cParams, &result)
        guard hr == 0 else { throw DirectWriteError.rasterizationFailure(hr) }
        defer { cwin_dwrite_free_raster_result(&result) }

        let size = Size(width: DevicePixels(Int(result.width)), height: DevicePixels(Int(result.height)))
        if let pixels = result.pixels, result.pixel_bytes > 0 {
            let data = Data(bytes: pixels, count: Int(result.pixel_bytes))
            return (size, data)
        }
        return (size, Data())
    }

    public func layoutLine(text: String, fontSize: Pixels, runs: [FontRun]) -> LineLayout {
        if runs.isEmpty || text.isEmpty {
            return LineLayout(
                fontSize: fontSize,
                width: .zero,
                ascent: .zero,
                descent: .zero,
                runs: [],
                len: text.utf8.count
            )
        }

        lock.lock()
        defer { lock.unlock() }

        let textWide: [UInt16] = text.utf16.map { $0 }
        let firstRun = runs[0]
        let firstInfo: FontInfo
        if firstRun.fontId.value < fonts.count {
            firstInfo = fonts[firstRun.fontId.value]
        } else {
            return LineLayout(fontSize: fontSize, width: .zero, ascent: .zero, descent: .zero, runs: [], len: text.utf8.count)
        }

        var format: WinHandle?
        let hrFormat = cwin_dwrite_create_text_format(
            factory,
            firstInfo.familyNameWide,
            firstInfo.collection,
            firstInfo.weight,
            firstInfo.style,
            fontSize.value,
            &format
        )
        guard hrFormat == 0, let format = format else {
            return LineLayout(fontSize: fontSize, width: .zero, ascent: .zero, descent: .zero, runs: [], len: text.utf8.count)
        }
        defer { cwin_release_com_object(format) }

        var layout: WinHandle?
        let hrLayout = cwin_dwrite_create_text_layout(
            factory,
            textWide,
            UInt32(textWide.count),
            format,
            Float.infinity,
            Float.infinity,
            &layout
        )
        guard hrLayout == 0, let layout = layout else {
            return LineLayout(fontSize: fontSize, width: .zero, ascent: .zero, descent: .zero, runs: [], len: text.utf8.count)
        }
        defer { cwin_release_com_object(layout) }

        var utf16ToUtf8 = [Int](repeating: 0, count: text.utf16.count + 1)
        var u16Count = 0
        var u8Count = 0
        for scalar in text.unicodeScalars {
            let s16 = scalar.utf16.count
            let s8 = scalar.utf8.count
            for _ in 0..<s16 {
                utf16ToUtf8[u16Count] = u8Count
                u16Count += 1
            }
            u8Count += s8
        }
        utf16ToUtf8[u16Count] = u8Count

        var utf8Offset = 0
        var utf16Offset: UInt32 = 0
        for (i, run) in runs.enumerated() {
            let fontInfo = (run.fontId.value < fonts.count) ? fonts[run.fontId.value] : firstInfo
            let runSlice = text.utf8.dropFirst(utf8Offset).prefix(run.len)
            let runText = String(decoding: runSlice, as: UTF8.self)
            let runUtf16Len = UInt32(runText.utf16.count)

            if i > 0 {
                _ = cwin_dwrite_layout_set_font_collection(layout, fontInfo.collection, utf16Offset, runUtf16Len)
                _ = cwin_dwrite_layout_set_font_family_name(layout, fontInfo.familyNameWide, utf16Offset, runUtf16Len)
                _ = cwin_dwrite_layout_set_font_size(layout, fontSize.value, utf16Offset, runUtf16Len)
                _ = cwin_dwrite_layout_set_font_weight(layout, fontInfo.weight, utf16Offset, runUtf16Len)
                _ = cwin_dwrite_layout_set_font_style(layout, fontInfo.style, utf16Offset, runUtf16Len)
            }

            var typo: WinHandle?
            if cwin_dwrite_create_typography(factory, &typo) == 0, let typo = typo {
                applyFontFeatures(typography: typo, features: fontInfo.features)
                _ = cwin_dwrite_layout_set_typography(layout, typo, utf16Offset, runUtf16Len)
                cwin_release_com_object(typo)
            }

            utf8Offset += run.len
            utf16Offset += runUtf16Len
        }

        var layoutWidth: Float = 0
        var layoutHeight: Float = 0
        var layoutBaseline: Float = 0
        _ = cwin_dwrite_layout_get_metrics(layout, &layoutWidth, &layoutHeight, &layoutBaseline)
        let ascent = Pixels(layoutBaseline)
        let descent = Pixels(max(0, layoutHeight - layoutBaseline))

        var runsHandle: WinHandle?
        var runCount: UInt32 = 0
        let hrExtract = cwin_dwrite_layout_extract_runs(layout, &runsHandle, &runCount)
        guard hrExtract == 0, let runsHandle = runsHandle else {
            return LineLayout(
                fontSize: fontSize,
                width: Pixels(layoutWidth),
                ascent: ascent,
                descent: descent,
                runs: [],
                len: text.utf8.count
            )
        }
        defer { cwin_dwrite_free_extracted_runs(runsHandle) }

        var shapedRuns: [ShapedRun] = []
        var currentX: Float = 0.0

        for rIdx in 0..<runCount {
            var runView = CWinShapedRunView()
            guard cwin_dwrite_get_extracted_run(runsHandle, rIdx, &runView) == 0 else { continue }

            let fontId: FontId
            if let facePtr = runView.font_face, let cached = cachedFontFaces[facePtr] {
                fontId = cached
            } else if Int(rIdx) < runs.count {
                fontId = runs[Int(rIdx)].fontId
            } else {
                fontId = firstRun.fontId
            }

            let glyphCount = Int(runView.glyph_count)
            guard glyphCount > 0, let gIndices = runView.glyph_indices else { continue }

            var shapedGlyphs: [ShapedGlyph] = []
            shapedGlyphs.reserveCapacity(glyphCount)

            let isColor = runView.is_color != 0

            if runView.cluster_count > 0, let cMap = runView.cluster_map {
                let clusterArray = Array(UnsafeBufferPointer(start: cMap, count: Int(runView.cluster_count)))
                var analyzer = ClusterAnalyzer(clusterMap: clusterArray, glyphCount: glyphCount)
                var currentUtf16 = Int(runView.text_position)
                var currentGlyphIndex = 0

                while let cluster = analyzer.next() {
                    let u8Idx = (currentUtf16 < utf16ToUtf8.count) ? utf16ToUtf8[currentUtf16] : text.utf8.count
                    currentUtf16 += cluster.utf16Len

                    for i in 0..<cluster.glyphCount {
                        let gIdx = currentGlyphIndex + i
                        guard gIdx < glyphCount else { break }
                        let gid = gIndices[gIdx]
                        let offX = runView.glyph_offsets_x != nil ? runView.glyph_offsets_x[gIdx] : 0.0
                        let offY = runView.glyph_offsets_y != nil ? runView.glyph_offsets_y[gIdx] : 0.0
                        let adv = runView.glyph_advances != nil ? runView.glyph_advances[gIdx] : 0.0

                        shapedGlyphs.append(
                            ShapedGlyph(
                                id: GlyphId(UInt32(gid)),
                                position: Point(x: Pixels(currentX + offX), y: Pixels(-offY)),
                                index: u8Idx,
                                isEmoji: isColor
                            )
                        )
                        currentX += adv
                    }
                    currentGlyphIndex += cluster.glyphCount
                }
            } else {
                for gIdx in 0..<glyphCount {
                    let gid = gIndices[gIdx]
                    let offX = runView.glyph_offsets_x != nil ? runView.glyph_offsets_x[gIdx] : 0.0
                    let offY = runView.glyph_offsets_y != nil ? runView.glyph_offsets_y[gIdx] : 0.0
                    let adv = runView.glyph_advances != nil ? runView.glyph_advances[gIdx] : 0.0
                    let u16Idx = Int(runView.text_position) + gIdx
                    let u8Idx = (u16Idx < utf16ToUtf8.count) ? utf16ToUtf8[u16Idx] : text.utf8.count

                    shapedGlyphs.append(
                        ShapedGlyph(
                            id: GlyphId(UInt32(gid)),
                            position: Point(x: Pixels(currentX + offX), y: Pixels(-offY)),
                            index: u8Idx,
                            isEmoji: isColor
                        )
                    )
                    currentX += adv
                }
            }

            shapedRuns.append(ShapedRun(fontId: fontId, glyphs: shapedGlyphs))
        }

        return LineLayout(
            fontSize: fontSize,
            width: Pixels(max(layoutWidth, currentX)),
            ascent: ascent,
            descent: descent,
            runs: shapedRuns,
            len: text.utf8.count
        )
    }

    public func recommendedRenderingMode(fontId: FontId, fontSize: Pixels) -> TextRenderingMode {
        if systemSubpixelRendering {
            return .subpixel
        }
        return .grayscale
    }
}

#endif
