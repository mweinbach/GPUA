// Ported from: crates/rune/src/drag_out/mod.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Dragging data out of a window into other apps: an OS drag source.

#if os(macOS)
import AppKit
#endif

/// Whether this platform's windows start OS drag sessions.
#if os(macOS)
let dragOutSupported = true
#else
let dragOutSupported = false
#endif

/// Pointer travel (points, straight-line) from the press before a drag session starts.
#if os(Linux)
public let DRAG_THRESHOLD: Float = 8.0
#else
public let DRAG_THRESHOLD: Float = 4.0
#endif

/// Whether a pointer that went down at `from` and is now at `to` has travelled past `threshold` points.
func pastDragThreshold(_ from: (Float, Float), _ to: (Float, Float), _ threshold: Float) -> Bool {
    let dx = to.0 - from.0
    let dy = to.1 - from.1
    return dx * dx + dy * dy > threshold * threshold
}

/// What a drag lets the target do with the data.
public enum DragOperation: Sendable, Equatable, Hashable {
    /// The target copies the data.
    case copy
    /// The target moves the files.
    case move
    /// The target makes a link or alias to the files.
    case link

    public static let Copy: DragOperation = .copy
    public static let Move: DragOperation = .move
    public static let Link: DragOperation = .link

    var bit: UInt8 {
        switch self {
        case .copy: return 1
        case .move: return 2
        case .link: return 4
        }
    }
}

/// How a drag out of the window ended.
public enum DragOutcome: Sendable, Equatable, Hashable {
    /// The target copied the data.
    case copied
    /// The target moved the files or asked the source to delete them (Trash).
    case moved
    /// The target made a link or alias to the files.
    case linked
    /// Dropped nowhere that accepted it, or cancelled with Escape.
    case cancelled

    public static let Copied: DragOutcome = .copied
    public static let Moved: DragOutcome = .moved
    public static let Linked: DragOutcome = .linked
    public static let Cancelled: DragOutcome = .cancelled

    /// Compatibility factory mapping a `DragOperation` to its completed `DragOutcome`.
    public static func completed(_ op: DragOperation) -> DragOutcome {
        switch op {
        case .copy: return .copied
        case .move: return .moved
        case .link: return .linked
        }
    }
}

/// Where a drag image starts, in window points.
enum DragPlacement: Sendable, Equatable {
    case pointer
    case element
    case at(Float, Float)
}

/// The picture a drag shows under the pointer, as PNG data.
public struct DragImage: Sendable, Equatable {
    public var width: UInt32
    public var height: UInt32
    public var rgba: [UInt8]
    var pngBytes: [UInt8]
    var pointSize: (Float, Float)?
    var placement: DragPlacement

    public init(width: UInt32, height: UInt32, rgba: [UInt8]) {
        self.width = width
        self.height = height
        self.rgba = rgba
        self.pngBytes = encodePng(width, height, rgba) ?? []
        self.pointSize = nil
        self.placement = .pointer
    }

    init(pngBytes: [UInt8], pointSize: (Float, Float)? = nil, placement: DragPlacement = .pointer) {
        if let decoded = decodePngHeaderSize(pngBytes) {
            self.width = decoded.0
            self.height = decoded.1
        } else {
            self.width = 0
            self.height = 0
        }
        self.rgba = []
        self.pngBytes = pngBytes
        self.pointSize = pointSize
        self.placement = placement
    }

    public static func == (lhs: DragImage, rhs: DragImage) -> Bool {
        let sameSize: Bool
        switch (lhs.pointSize, rhs.pointSize) {
        case (nil, nil): sameSize = true
        case (let a?, let b?): sameSize = a.0 == b.0 && a.1 == b.1
        default: sameSize = false
        }
        return lhs.pngData() == rhs.pngData() && sameSize && lhs.placement == rhs.placement
    }

    public static func png(_ bytes: [UInt8]) -> DragImage {
        DragImage(pngBytes: bytes, pointSize: nil, placement: .pointer)
    }

    /// Straight-alpha sRGB RGBA8 pixels. `nil` if `pixels` isn't `width * height * 4` bytes.
    public static func rgba(_ width: UInt32, _ height: UInt32, _ pixels: [UInt8]) -> DragImage? {
        guard let encoded = encodePng(width, height, pixels) else { return nil }
        var img = DragImage(pngBytes: encoded, pointSize: nil, placement: .pointer)
        img.width = width
        img.height = height
        img.rgba = pixels
        return img
    }

    /// Draw it this many points wide and high.
    public func size(_ width: Float, _ height: Float) -> DragImage {
        var copy = self
        copy.pointSize = (width, height)
        return copy
    }

    /// Start the drag with the image over the element, filling its bounds (scaled to fit).
    public func overElement() -> DragImage {
        var copy = self
        copy.placement = .element
        return copy
    }

    public func pngData() -> [UInt8] {
        pngBytes
    }

    public func points() -> (Float, Float)? {
        pointSize
    }

    /// Where the drag image starts (`[x, y, w, h]`) in window points.
    func frame(_ bounds: [Float], _ press: (Float, Float), _ natural: (Float, Float)) -> [Float] {
        let (w, h) = pointSize ?? natural
        switch placement {
        case .pointer:
            return [press.0 - w / 2.0, press.1 - h / 2.0, w, h]
        case .element:
            let (ew, eh) = pointSize ?? (bounds[2], bounds[3])
            return [bounds[0], bounds[1], max(ew, 1.0), max(eh, 1.0)]
        case .at(let x, let y):
            return [x, y, w, h]
        }
    }

    /// The image composited over an opaque `backing`, blended in linear light as the window blends.
    func over(_ backing: Color) -> DragImage? {
        let decoded: (width: UInt32, height: UInt32, rgba: [UInt8])
        if !rgba.isEmpty && Int(width) * Int(height) * 4 == rgba.count {
            decoded = (width, height, rgba)
        } else if let d = decodePng(pngBytes) {
            decoded = d
        } else {
            return nil
        }
        var pixels = decoded.rgba
        let bg = [backing.r, backing.g, backing.b]
        let count = pixels.count / 4
        for i in 0..<count {
            let base = i * 4
            let a = Float(pixels[base + 3]) / 255.0
            for c in 0..<3 {
                let v = srgbDecode(Float(pixels[base + c]) / 255.0) * a + bg[c] * (1.0 - a)
                let enc = (srgbEncode(v) * 255.0).rounded()
                pixels[base + c] = UInt8(min(max(enc, 0.0), 255.0))
            }
            pixels[base + 3] = 255
        }
        guard let newPng = encodePng(decoded.width, decoded.height, pixels) else { return nil }
        var out = self
        out.width = decoded.width
        out.height = decoded.height
        out.rgba = pixels
        out.pngBytes = newPng
        return out
    }
}

/// What a drag carries to another app: any of file URLs, PNG data and plain text, plus the
/// picture shown under the pointer.
public struct DragItem: Sendable, Equatable {
    private var filePaths: [String]
    private var pngBytes: [UInt8]?
    private var textValue: String?
    private var dragImageValue: DragImage?
    private var operationsMask: UInt8
    private var backingColor: Color?

    public init(text: String? = nil, paths: [String] = [], image: DragImage? = nil) {
        self.filePaths = paths
        self.pngBytes = nil
        self.textValue = text
        self.dragImageValue = image
        self.operationsMask = DragOperation.copy.bit
        self.backingColor = nil
    }

    public static func new() -> DragItem {
        DragItem()
    }

    /// Add a file (or folder or app bundle) by path; repeat for several.
    public func file(_ path: String) -> DragItem {
        var copy = self
        copy.filePaths.append(path)
        return copy
    }

    /// PNG-encoded image data, for targets that take an image rather than a file.
    public func png(_ bytes: [UInt8]) -> DragItem {
        var copy = self
        copy.pngBytes = bytes
        return copy
    }

    /// Straight-alpha sRGB RGBA8 pixels, encoded as PNG data. Ignored if the sizes disagree.
    public func rgba(_ width: UInt32, _ height: UInt32, _ pixels: [UInt8]) -> DragItem {
        guard let encoded = encodePng(width, height, pixels) else { return self }
        return png(encoded)
    }

    /// Plain text. Without it, a file's path is offered as text.
    public func text(_ text: String) -> DragItem {
        var copy = self
        copy.textValue = text
        return copy
    }

    /// The picture under the pointer. Defaults to a snapshot of the element.
    public func image(_ image: DragImage) -> DragItem {
        var copy = self
        copy.dragImageValue = image
        return copy
    }

    /// Show the drag image composited over `color`, so it's opaque even where the element is transparent.
    public func opaque(_ color: Color) -> DragItem {
        var copy = self
        copy.backingColor = color.alpha(1.0)
        return copy
    }

    /// Offer only `operation` to the target, instead of the default `DragOperation.copy`.
    public func operation(_ operation: DragOperation) -> DragItem {
        var copy = self
        copy.operationsMask = operation.bit
        return copy
    }

    /// Offer `operation` as well as those already offered; the target picks one.
    public func allow(_ operation: DragOperation) -> DragItem {
        var copy = self
        copy.operationsMask |= operation.bit
        return copy
    }

    /// Let the target move files instead of copying them.
    public func allowMove() -> DragItem {
        allow(.move)
    }

    public func paths() -> [String] { filePaths }
    public func pngData() -> [UInt8]? { pngBytes }
    public func plainText() -> String? { textValue }
    public func dragImage() -> DragImage? { dragImageValue }
    public func allowsMove() -> Bool { offers(.move) }
    public func offers(_ operation: DragOperation) -> Bool { (operationsMask & operation.bit) != 0 }
    public func backing() -> Color? { backingColor }
    public func isEmpty() -> Bool { filePaths.isEmpty && pngBytes == nil && textValue == nil }
}

/// A drag the runtime asked the host to start.
struct DragOutStart: Sendable {
    var path: String
    var item: DragItem
    var rect: [Float]
    var bounds: [Float]
    var press: (Float, Float)
}

/// `rect` (points) in device pixels, clamped to the frame: `[x, y, w, h]`. `nil` when empty.
func dragSnapshotCrop(_ rect: [Float], _ scale: Float, _ size: (UInt32, UInt32)) -> [UInt32]? {
    guard rect.count >= 4 else { return nil }
    let maxW = Float(size.0)
    let maxH = Float(size.1)
    let x0 = UInt32(min(max((rect[0] * scale).rounded(.down), 0.0), maxW))
    let y0 = UInt32(min(max((rect[1] * scale).rounded(.down), 0.0), maxH))
    let x1 = UInt32(min(max(((rect[0] + rect[2]) * scale).rounded(.up), 0.0), maxW))
    let y1 = UInt32(min(max(((rect[1] + rect[3]) * scale).rounded(.up), 0.0), maxH))
    guard x1 > x0 && y1 > y0 else { return nil }
    return [x0, y0, x1 - x0, y1 - y0]
}

/// Frame pixels are premultiplied, in the surface's channel order.
func dragToStraightRgba(_ pixels: inout [UInt8], _ bgra: Bool) {
    let count = pixels.count / 4
    for i in 0..<count {
        let base = i * 4
        if bgra {
            pixels.swapAt(base, base + 2)
        }
        let a = pixels[base + 3]
        if a != 0 && a != 255 {
            let au = UInt32(a)
            for c in 0..<3 {
                let v = (UInt32(pixels[base + c]) * 255 + au / 2) / au
                pixels[base + c] = UInt8(min(v, 255))
            }
        }
    }
}

/// The item's own image, else the snapshot, over the item's backing colour if it has one.
func dragPicture(_ item: DragItem, _ snapshot: DragImage?) -> DragImage? {
    guard let picture = item.dragImage() ?? snapshot else { return nil }
    if let backing = item.backing() {
        return picture.over(backing) ?? picture
    }
    return picture
}

// MARK: - Pure-Swift RGBA8 PNG Encoder / Decoder (`encode_png` / `decodePng`)

private let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

func decodePngHeaderSize(_ png: [UInt8]) -> (UInt32, UInt32)? {
    guard png.count >= 24 else { return nil }
    guard Array(png[0..<8]) == pngSignature else { return nil }
    guard png[12] == 0x49 && png[13] == 0x48 && png[14] == 0x44 && png[15] == 0x52 else { return nil }
    let w = (UInt32(png[16]) << 24) | (UInt32(png[17]) << 16) | (UInt32(png[18]) << 8) | UInt32(png[19])
    let h = (UInt32(png[20]) << 24) | (UInt32(png[21]) << 16) | (UInt32(png[22]) << 8) | UInt32(png[23])
    guard w > 0 && h > 0 else { return nil }
    return (w, h)
}

private func pngCrc32(_ typeBytes: [UInt8], _ data: [UInt8]) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for b in typeBytes {
        crc ^= UInt32(b)
        for _ in 0..<8 {
            crc = (crc & 1) != 0 ? ((crc >> 1) ^ 0xEDB8_8320) : (crc >> 1)
        }
    }
    for b in data {
        crc ^= UInt32(b)
        for _ in 0..<8 {
            crc = (crc & 1) != 0 ? ((crc >> 1) ^ 0xEDB8_8320) : (crc >> 1)
        }
    }
    return ~crc
}

private func appendPngU32BE(_ out: inout [UInt8], _ v: UInt32) {
    out.append(UInt8((v >> 24) & 0xFF))
    out.append(UInt8((v >> 16) & 0xFF))
    out.append(UInt8((v >> 8) & 0xFF))
    out.append(UInt8(v & 0xFF))
}

private func appendPngChunk(_ out: inout [UInt8], _ typeAscii: [UInt8], _ data: [UInt8]) {
    appendPngU32BE(&out, UInt32(data.count))
    out.append(contentsOf: typeAscii)
    out.append(contentsOf: data)
    appendPngU32BE(&out, pngCrc32(typeAscii, data))
}

/// Encodes 8-bit straight-alpha RGBA pixels as a valid PNG image with perceptual sRGB chunk.
func encodePng(_ width: UInt32, _ height: UInt32, _ rgba: [UInt8]) -> [UInt8]? {
    guard width > 0, height > 0 else { return nil }
    let w = Int(width)
    let h = Int(height)
    guard rgba.count == w * h * 4 else { return nil }

    let rowStride = w * 4
    var rawScanlines: [UInt8] = []
    rawScanlines.reserveCapacity((rowStride + 1) * h)
    for y in 0..<h {
        rawScanlines.append(0) // Filter type 0 (None)
        let start = y * rowStride
        rawScanlines.append(contentsOf: rgba[start..<(start + rowStride)])
    }

    // Wrap scanlines in RFC 1950 zlib stream using RFC 1951 uncompressed blocks + Adler-32.
    var zlib: [UInt8] = [0x78, 0x01]
    var s1: UInt32 = 1
    var s2: UInt32 = 0
    for b in rawScanlines {
        s1 = (s1 + UInt32(b)) % 65521
        s2 = (s2 + s1) % 65521
    }
    var offset = 0
    let total = rawScanlines.count
    while offset < total || total == 0 {
        let len = min(65535, total - offset)
        let isFinal: UInt8 = (offset + len >= total) ? 1 : 0
        zlib.append(isFinal)
        let ulen = UInt16(len)
        let nlen = ~ulen
        zlib.append(UInt8(ulen & 0xFF))
        zlib.append(UInt8((ulen >> 8) & 0xFF))
        zlib.append(UInt8(nlen & 0xFF))
        zlib.append(UInt8((nlen >> 8) & 0xFF))
        if len > 0 {
            zlib.append(contentsOf: rawScanlines[offset..<(offset + len)])
        }
        offset += len
        if total == 0 { break }
    }
    let adler = (s2 << 16) | s1
    appendPngU32BE(&zlib, adler)

    var out: [UInt8] = []
    out.reserveCapacity(64 + zlib.count)
    out.append(contentsOf: pngSignature)

    var ihdr: [UInt8] = []
    appendPngU32BE(&ihdr, width)
    appendPngU32BE(&ihdr, height)
    ihdr.append(contentsOf: [8, 6, 0, 0, 0]) // 8-bit RGBA, deflate, adaptive filter, no interlace
    appendPngChunk(&out, [0x49, 0x48, 0x44, 0x52], ihdr) // IHDR
    appendPngChunk(&out, [0x73, 0x52, 0x47, 0x42], [0]) // sRGB (Perceptual)
    appendPngChunk(&out, [0x49, 0x44, 0x41, 0x54], zlib) // IDAT
    appendPngChunk(&out, [0x49, 0x45, 0x4E, 0x44], []) // IEND
    return out
}

/// Decodes a PNG image into straight-alpha 8-bit RGBA pixels.
func decodePng(_ png: [UInt8]) -> (width: UInt32, height: UInt32, rgba: [UInt8])? {
    guard let (width, height) = decodePngHeaderSize(png), png.count >= 33 else { return nil }
    let bitDepth = png[24]
    let colorType = png[25]
    let interlace = png[28]

    // Fast path for 8-bit RGBA non-interlaced stored-deflate PNGs (including all `encodePng` output).
    if bitDepth == 8 && colorType == 6 && interlace == 0 {
        var idat: [UInt8] = []
        var pos = 8
        var validChunks = true
        while pos + 8 <= png.count {
            let chunkLen = (Int(png[pos]) << 24) | (Int(png[pos + 1]) << 16) | (Int(png[pos + 2]) << 8) | Int(png[pos + 3])
            guard chunkLen >= 0, pos + 12 + chunkLen <= png.count else {
                validChunks = false
                break
            }
            let t0 = png[pos + 4], t1 = png[pos + 5], t2 = png[pos + 6], t3 = png[pos + 7]
            if t0 == 0x49 && t1 == 0x44 && t2 == 0x41 && t3 == 0x54 {
                idat.append(contentsOf: png[(pos + 8)..<(pos + 8 + chunkLen)])
            } else if t0 == 0x49 && t1 == 0x45 && t2 == 0x4E && t3 == 0x44 {
                break
            }
            pos += 12 + chunkLen
        }
        if validChunks, let raw = inflateStoredZlib(idat) {
            let w = Int(width)
            let h = Int(height)
            let stride = w * 4
            if raw.count == (stride + 1) * h, let rgba = unfilterPngRgba8(raw, width: w, height: h) {
                return (width, height, rgba)
            }
        }
    }

    #if os(macOS)
    let data = Data(png)
    if let rep = NSBitmapImageRep(data: data) {
        let w = rep.pixelsWide
        let h = rep.pixelsHigh
        if w > 0 && h > 0,
           let cgImage = rep.cgImage,
           let space = CGColorSpace(name: CGColorSpace.sRGB)
        {
            var pixels = [UInt8](repeating: 0, count: w * h * 4)
            let ok = pixels.withUnsafeMutableBytes { buf -> Bool in
                guard let ctx = CGContext(
                    data: buf.baseAddress,
                    width: w,
                    height: h,
                    bitsPerComponent: 8,
                    bytesPerRow: w * 4,
                    space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            if ok {
                dragToStraightRgba(&pixels, false)
                return (UInt32(w), UInt32(h), pixels)
            }
        }
    }
    #endif
    return nil
}

private func inflateStoredZlib(_ zlib: [UInt8]) -> [UInt8]? {
    guard zlib.count >= 6 else { return nil }
    let cmf = zlib[0]
    let flg = zlib[1]
    guard (cmf & 0x0F) == 8, ((UInt16(cmf) << 8 | UInt16(flg)) % 31) == 0 else { return nil }
    var pos = 2
    if (flg & 0x20) != 0 {
        pos += 4
    }
    let end = zlib.count - 4 // 4-byte Adler-32 trailer
    var out: [UInt8] = []
    while pos < end {
        let header = zlib[pos]
        let bfinal = header & 1
        let btype = (header >> 1) & 3
        guard btype == 0 else { return nil } // Only stored blocks in pure-Swift fast path
        guard pos + 5 <= end else { return nil }
        let len = UInt16(zlib[pos + 1]) | (UInt16(zlib[pos + 2]) << 8)
        let nlen = UInt16(zlib[pos + 3]) | (UInt16(zlib[pos + 4]) << 8)
        guard len == ~nlen else { return nil }
        pos += 5
        let n = Int(len)
        guard pos + n <= end else { return nil }
        out.append(contentsOf: zlib[pos..<(pos + n)])
        pos += n
        if bfinal != 0 { break }
    }
    return out
}

private func unfilterPngRgba8(_ raw: [UInt8], width: Int, height: Int) -> [UInt8]? {
    let bpp = 4
    let stride = width * bpp
    var out = [UInt8](repeating: 0, count: stride * height)
    for y in 0..<height {
        let rowIn = y * (stride + 1)
        let filter = raw[rowIn]
        let srcStart = rowIn + 1
        let dstStart = y * stride
        for x in 0..<stride {
            let rawByte = raw[srcStart + x]
            let a: UInt8 = x >= bpp ? out[dstStart + x - bpp] : 0
            let b: UInt8 = y > 0 ? out[dstStart - stride + x] : 0
            let c: UInt8 = (x >= bpp && y > 0) ? out[dstStart - stride + x - bpp] : 0
            let recon: UInt8
            switch filter {
            case 0: recon = rawByte
            case 1: recon = rawByte &+ a
            case 2: recon = rawByte &+ b
            case 3: recon = rawByte &+ UInt8((UInt16(a) + UInt16(b)) >> 1)
            case 4:
                let p = Int(a) + Int(b) - Int(c)
                let pa = abs(p - Int(a))
                let pb = abs(p - Int(b))
                let pc = abs(p - Int(c))
                let pr: UInt8 = (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c)
                recon = rawByte &+ pr
            default:
                return nil
            }
            out[dstStart + x] = recon
        }
    }
    return out
}

/// Namespace mirroring `rune::drag_out` (`crates/rune/src/drag_out/mod.rs`).
public enum drag_out {
    public static let DRAG_THRESHOLD: Float = Rune.DRAG_THRESHOLD
    public typealias DragItem = Rune.DragItem
    public typealias DragImage = Rune.DragImage
    public typealias DragOperation = Rune.DragOperation
    public typealias DragOutcome = Rune.DragOutcome
}
