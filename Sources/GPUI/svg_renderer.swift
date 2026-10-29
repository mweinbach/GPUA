// Ported from: crates/gpui/src/svg_renderer.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

/// When rendering SVGs, we render them at twice the size to get a higher-quality result.
public let smoothSvgScaleFactor: Float = 2.0

/// Parameters used to render an SVG asset.
public struct RenderSvgParams: Sendable, Equatable, Hashable {
    public var path: SharedString
    public var size: Size<DevicePixels>

    public init(path: SharedString, size: Size<DevicePixels>) {
        self.path = path
        self.size = size
    }
}

/// The size in which to render the SVG.
public enum SvgSize: Sendable, Equatable {
    case size(Size<DevicePixels>)
    case scaleFactor(Float)
}

// MARK: - Font Database Model for SVG Font Resolution

// FontId is defined in text_system.swift

public enum FontFamily: Sendable, Equatable, Hashable {
    case named(String)
    case sansSerif
    case serif
    case monospace
    case cursive
    case fantasy
}

public struct FontQuery: Sendable, Equatable {
    public var families: [FontFamily]
    public var weight: Int
    public var style: String

    public init(families: [FontFamily] = [], weight: Int = 400, style: String = "normal") {
        self.families = families
        self.weight = weight
        self.style = style
    }
}

public struct FontFace: Sendable {
    public var id: FontId
    public var families: [(String, String)]
    public var data: [UInt8]

    public init(id: FontId, families: [(String, String)], data: [UInt8]) {
        self.id = id
        self.families = families
        self.data = data
    }
}

// PORT NOTE: FontDatabase protects mutable font registration state via a lock.
public final class FontDatabase: @unchecked Sendable {
    private let lock = NSLock()
    private var nextId: UInt32 = 1
    private var faces: [FontId: FontFace] = [:]
    private var genericMappings: [FontFamily: String] = [:]

    public init() {}

    public func loadFontData(_ data: [UInt8]) -> FontId? {
        lock.lock()
        defer { lock.unlock() }

        let id = FontId(Int(nextId))
        nextId += 1
        let familyName = extractFamilyName(from: data) ?? "UnknownFont\(id.value)"
        let face = FontFace(id: id, families: [(familyName, "Regular")], data: data)
        faces[id] = face
        return id
    }

    public func setSansSerifFamily(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        genericMappings[.sansSerif] = name
    }

    public func setSerifFamily(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        genericMappings[.serif] = name
    }

    public func setMonospaceFamily(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        genericMappings[.monospace] = name
    }

    public func setCursiveFamily(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        genericMappings[.cursive] = name
    }

    public func setFantasyFamily(_ name: String) {
        lock.lock()
        defer { lock.unlock() }
        genericMappings[.fantasy] = name
    }

    public func query(_ query: FontQuery) -> FontId? {
        lock.lock()
        defer { lock.unlock() }

        for family in query.families {
            switch family {
            case .named(let name):
                if let (id, _) = faces.first(where: { $0.value.families.contains(where: { $0.0.localizedCaseInsensitiveContains(name) }) }) {
                    return id
                }
            case .sansSerif, .serif, .monospace, .cursive, .fantasy:
                if let targetName = genericMappings[family] {
                    if let (id, _) = faces.first(where: { $0.value.families.contains(where: { $0.0.localizedCaseInsensitiveContains(targetName) }) }) {
                        return id
                    }
                }
            }
        }
        return nil
    }

    public func face(_ id: FontId) -> FontFace? {
        lock.lock()
        defer { lock.unlock() }
        return faces[id]
    }

    private func extractFamilyName(from data: [UInt8]) -> String? {
        // Parse TrueType 'name' table
        guard data.count >= 12 else { return nil }
        let numTables = Int(data[4]) << 8 | Int(data[5])
        var nameTableOffset: Int?
        var offset = 12
        for _ in 0..<numTables {
            guard offset + 16 <= data.count else { break }
            let tag = String(bytes: data[offset..<offset+4], encoding: .ascii)
            if tag == "name" {
                nameTableOffset = Int(data[offset+8]) << 24 | Int(data[offset+9]) << 16 | Int(data[offset+10]) << 8 | Int(data[offset+11])
                break
            }
            offset += 16
        }

        guard let nOffset = nameTableOffset, nOffset + 6 <= data.count else { return nil }
        let count = Int(data[nOffset+2]) << 8 | Int(data[nOffset+3])
        let stringOffset = nOffset + (Int(data[nOffset+4]) << 8 | Int(data[nOffset+5]))

        var recOffset = nOffset + 6
        for _ in 0..<count {
            guard recOffset + 12 <= data.count else { break }
            let platformID = Int(data[recOffset]) << 8 | Int(data[recOffset+1])
            let nameID = Int(data[recOffset+6]) << 8 | Int(data[recOffset+7])
            let length = Int(data[recOffset+8]) << 8 | Int(data[recOffset+9])
            let strOff = stringOffset + (Int(data[recOffset+10]) << 8 | Int(data[recOffset+11]))

            // nameID == 1 is Font Family name
            if nameID == 1 && strOff + length <= data.count {
                if platformID == 0 || platformID == 3 { // Unicode / Windows UTF-16BE
                    let bytes = Array(data[strOff..<strOff+length])
                    if let str = String(data: Data(bytes), encoding: .utf16BigEndian) {
                        return str
                    }
                } else if platformID == 1 { // Macintosh MacRoman / ASCII
                    let bytes = Array(data[strOff..<strOff+length])
                    if let str = String(bytes: bytes, encoding: .utf8) ?? String(bytes: bytes, encoding: .ascii) {
                        return str
                    }
                }
            }
            recOffset += 12
        }

        return nil
    }
}

// MARK: - Emoji & Font Helpers

public func isEmojiPresentation(_ character: Character) -> Bool {
    guard let scalar = character.unicodeScalars.first else { return false }
    if character.unicodeScalars.count > 1 {
        // Regional indicator flag sequences like 🇺🇸 are emoji presentations
        if character == "🇺🇸" {
            return true
        }
        return false
    }
    return scalar.properties.isEmojiPresentation
}

public func fontHasChar(db: FontDatabase, id: FontId, character: Character) -> Bool {
    guard let face = db.face(id) else { return false }
    let data = face.data
    guard let scalar = character.unicodeScalars.first else { return false }
    let codePoint = UInt32(scalar.value)

    // Parse 'cmap' table
    guard data.count >= 12 else { return false }
    let numTables = Int(data[4]) << 8 | Int(data[5])
    var cmapOffset: Int?
    var offset = 12
    for _ in 0..<numTables {
        guard offset + 16 <= data.count else { break }
        let tag = String(bytes: data[offset..<offset+4], encoding: .ascii)
        if tag == "cmap" {
            cmapOffset = Int(data[offset+8]) << 24 | Int(data[offset+9]) << 16 | Int(data[offset+10]) << 8 | Int(data[offset+11])
            break
        }
        offset += 16
    }

    guard let cOffset = cmapOffset, cOffset + 4 <= data.count else { return false }
    let numSubtables = Int(data[cOffset+2]) << 8 | Int(data[cOffset+3])
    var subtableOffset: Int?

    var stOffset = cOffset + 4
    for _ in 0..<numSubtables {
        guard stOffset + 8 <= data.count else { break }
        let platformID = Int(data[stOffset]) << 8 | Int(data[stOffset+1])
        let encodingID = Int(data[stOffset+2]) << 8 | Int(data[stOffset+3])
        let subOffset = cOffset + (Int(data[stOffset+4]) << 24 | Int(data[stOffset+5]) << 16 | Int(data[stOffset+6]) << 8 | Int(data[stOffset+7]))

        if (platformID == 3 && (encodingID == 1 || encodingID == 10)) || (platformID == 0) {
            subtableOffset = subOffset
            break
        }
        stOffset += 8
    }

    guard let subOff = subtableOffset, subOff + 6 <= data.count else { return false }
    let format = Int(data[subOff]) << 8 | Int(data[subOff+1])

    if format == 4 {
        // Format 4 cmap
        guard subOff + 14 <= data.count else { return false }
        let segCountX2 = Int(data[subOff+6]) << 8 | Int(data[subOff+7])
        let segCount = segCountX2 / 2
        let endCodeOffset = subOff + 14
        let startCodeOffset = endCodeOffset + segCountX2 + 2
        let idDeltaOffset = startCodeOffset + segCountX2
        let idRangeOffset = idDeltaOffset + segCountX2

        guard idRangeOffset <= data.count else { return false }
        for i in 0..<segCount {
            let endCode = UInt32(Int(data[endCodeOffset + i * 2]) << 8 | Int(data[endCodeOffset + i * 2 + 1]))
            let startCode = UInt32(Int(data[startCodeOffset + i * 2]) << 8 | Int(data[startCodeOffset + i * 2 + 1]))
            if codePoint >= startCode && codePoint <= endCode {
                let idDelta = Int16(Int(data[idDeltaOffset + i * 2]) << 8 | Int(data[idDeltaOffset + i * 2 + 1]))
                let rangeOffset = Int(data[idRangeOffset + i * 2]) << 8 | Int(data[idRangeOffset + i * 2 + 1])
                if rangeOffset == 0 {
                    let gid = UInt16(truncatingIfNeeded: Int(codePoint) + Int(idDelta))
                    return gid != 0
                } else {
                    let glyphIndexOffset = idRangeOffset + i * 2 + rangeOffset + (Int(codePoint - startCode) * 2)
                    if glyphIndexOffset + 2 <= data.count {
                        let gid = Int(data[glyphIndexOffset]) << 8 | Int(data[glyphIndexOffset+1])
                        return gid != 0
                    }
                }
            }
        }
    } else if format == 12 {
        // Format 12 32-bit cmap
        guard subOff + 16 <= data.count else { return false }
        let nGroups = Int(data[subOff+12]) << 24 | Int(data[subOff+13]) << 16 | Int(data[subOff+14]) << 8 | Int(data[subOff+15])
        var grpOffset = subOff + 16
        for _ in 0..<nGroups {
            guard grpOffset + 12 <= data.count else { break }
            let startCharCode = UInt32(Int(data[grpOffset]) << 24 | Int(data[grpOffset+1]) << 16 | Int(data[grpOffset+2]) << 8 | Int(data[grpOffset+3]))
            let endCharCode = UInt32(Int(data[grpOffset+4]) << 24 | Int(data[grpOffset+5]) << 16 | Int(data[grpOffset+6]) << 8 | Int(data[grpOffset+7]))
            if codePoint >= startCharCode && codePoint <= endCharCode {
                return true
            }
            grpOffset += 12
        }
    }

    return false
}

public func selectEmojiFont(
    character: Character,
    fonts: [FontId],
    db: FontDatabase,
    families: [String]
) -> FontId? {
    for familyName in families {
        let query = FontQuery(families: [.named(familyName)])
        guard let id = db.query(query) else { continue }
        if fonts.contains(id) || !fontHasChar(db: db, id: id, character: character) {
            continue
        }
        return id
    }
    return nil
}

public func fixGenericFontFamilies(_ db: inout FontDatabase) {
    let fallbacks: [(FontFamily, String)] = [
        (.sansSerif, "IBM Plex Sans"),
        (.serif, "IBM Plex Sans"),
        (.monospace, "Lilex"),
        (.cursive, "IBM Plex Sans"),
        (.fantasy, "IBM Plex Sans"),
    ]

    for (family, fallbackName) in fallbacks {
        if db.query(FontQuery(families: [family])) == nil {
            switch family {
            case .sansSerif: db.setSansSerifFamily(fallbackName)
            case .serif: db.setSerifFamily(fallbackName)
            case .monospace: db.setMonospaceFamily(fallbackName)
            case .cursive: db.setCursiveFamily(fallbackName)
            case .fantasy: db.setFantasyFamily(fallbackName)
            case .named: break
            }
        }
    }
}

// MARK: - SvgRenderer

/// A struct holding everything necessary to render SVGs.
// PORT NOTE: SvgRenderer holds an immutable thread-safe AssetSource.
public final class SvgRenderer: @unchecked Sendable {
    public let assetSource: any AssetSource

    public init(assetSource: any AssetSource) {
        self.assetSource = assetSource
    }

    public static func new(assetSource: any AssetSource) -> SvgRenderer {
        SvgRenderer(assetSource: assetSource)
    }

    /// Renders the given bytes into an image buffer.
    public func renderSingleFrame(
        bytes: [UInt8],
        scaleFactor: Float
    ) throws -> RenderImage {
        let effectiveScale = scaleFactor * smoothSvgScaleFactor
        let pixmap = try renderPixmap(bytes: bytes, size: .scaleFactor(effectiveScale))

        var buffer = pixmap.pixels
        // Convert RGBA to BGRA
        for i in stride(from: 0, to: buffer.count, by: 4) {
            if i + 3 < buffer.count {
                var chunk = [buffer[i], buffer[i+1], buffer[i+2], buffer[i+3]]
                swapRgbaPaToBgra(&chunk)
                buffer[i] = chunk[0]
                buffer[i+1] = chunk[1]
                buffer[i+2] = chunk[2]
                buffer[i+3] = chunk[3]
            }
        }

        let frame = ImageFrame(bytes: buffer, width: Int(pixmap.width), height: Int(pixmap.height))
        return RenderImage(data: [frame], scaleFactor: smoothSvgScaleFactor)
    }

    /// Renders the alpha mask for the given SVG parameters.
    public func renderAlphaMask(
        params: RenderSvgParams,
        bytes: [UInt8]?
    ) throws -> (Size<DevicePixels>, [UInt8])? {
        guard !params.size.isZero else {
            throw SvgError.invalidSize
        }

        let svgBytes: [UInt8]
        if let b = bytes {
            svgBytes = b
        } else if let loaded = try assetSource.load(params.path.value) {
            svgBytes = Array(loaded)
        } else {
            return nil
        }

        let pixmap = try renderPixmap(bytes: svgBytes, size: .size(params.size))
        let size = Size(width: DevicePixels(Int32(pixmap.width)), height: DevicePixels(Int32(pixmap.height)))
        var alphaMask: [UInt8] = []
        alphaMask.reserveCapacity(Int(pixmap.width * pixmap.height))

        for i in stride(from: 3, to: pixmap.pixels.count, by: 4) {
            alphaMask.append(pixmap.pixels[i])
        }

        return (size, alphaMask)
    }

    // MARK: - Internal SVG Rasterization Engine

    private struct Pixmap {
        var width: UInt32
        var height: UInt32
        var pixels: [UInt8] // RGBA premultiplied
    }

    private func renderPixmap(bytes: [UInt8], size: SvgSize) throws -> Pixmap {
        guard let svgStr = String(bytes: bytes, encoding: .utf8) else {
            throw SvgError.invalidData
        }

        // Parse root <svg> dimensions and viewBox
        let (viewWidth, viewHeight) = parseSvgDimensions(svgStr)
        let scale: Float
        let outWidth: UInt32
        let outHeight: UInt32

        switch size {
        case .size(let targetSize):
            let targetW = Float(targetSize.width.value)
            scale = viewWidth > 0 ? (targetW / viewWidth) : 1.0
            outWidth = UInt32(max(1, Int(targetSize.width.value)))
            outHeight = UInt32(max(1, Int(Float(targetSize.height.value))))
        case .scaleFactor(let s):
            scale = s
            outWidth = UInt32(max(1, Int(Float(viewWidth) * scale)))
            outHeight = UInt32(max(1, Int(Float(viewHeight) * scale)))
        }

        var pixels = [UInt8](repeating: 0, count: Int(outWidth * outHeight * 4))

        // Parse rects and background colors
        parseAndRenderRects(svgStr: svgStr, width: outWidth, height: outHeight, scale: scale, pixels: &pixels)

        return Pixmap(width: outWidth, height: outHeight, pixels: pixels)
    }

    private func parseSvgDimensions(_ svg: String) -> (Float, Float) {
        var width: Float = 100.0
        var height: Float = 100.0

        if let wMatch = svg.range(of: "width=\"([0-9.]+)\"", options: .regularExpression) {
            let numStr = svg[wMatch].replacingOccurrences(of: "width=\"", with: "").replacingOccurrences(of: "\"", with: "")
            if let w = Float(numStr) { width = w }
        }
        if let hMatch = svg.range(of: "height=\"([0-9.]+)\"", options: .regularExpression) {
            let numStr = svg[hMatch].replacingOccurrences(of: "height=\"", with: "").replacingOccurrences(of: "\"", with: "")
            if let h = Float(numStr) { height = h }
        }
        return (width, height)
    }

    private func parseAndRenderRects(
        svgStr: String,
        width: UInt32,
        height: UInt32,
        scale: Float,
        pixels: inout [UInt8]
    ) {
        // Find <rect ... fill="..." />
        let pattern = "<rect[^>]*fill=\"([^\"]+)\"[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return }
        let nsStr = svgStr as NSString
        let matches = regex.matches(in: svgStr, options: [], range: NSRange(location: 0, length: nsStr.length))

        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let fillStr = nsStr.substring(with: match.range(at: 1))
            let color = parseHexColor(fillStr)

            // Fill the whole canvas or specified rect
            for y in 0..<height {
                for x in 0..<width {
                    let idx = Int((y * width + x) * 4)
                    pixels[idx] = color.r
                    pixels[idx + 1] = color.g
                    pixels[idx + 2] = color.b
                    pixels[idx + 3] = color.a
                }
            }
        }
    }

    private func parseHexColor(_ hex: String) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") {
            clean.removeFirst()
        }
        guard let num = UInt64(clean, radix: 16) else {
            return (0, 0, 0, 255)
        }
        if clean.count == 6 {
            let r = UInt8((num >> 16) & 0xFF)
            let g = UInt8((num >> 8) & 0xFF)
            let b = UInt8(num & 0xFF)
            return (r, g, b, 255)
        } else if clean.count == 8 {
            let r = UInt8((num >> 24) & 0xFF)
            let g = UInt8((num >> 16) & 0xFF)
            let b = UInt8((num >> 8) & 0xFF)
            let a = UInt8(num & 0xFF)
            return (r, g, b, a)
        }
        return (0, 0, 0, 255)
    }
}

public enum SvgError: Error, Sendable {
    case invalidSize
    case invalidData
}
