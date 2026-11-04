// Ported from: crates/rune/src/text/pixel_compare.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Rune's text against CoreText, pixel for pixel. Fixed cases (four ink/paper pairs; Inter
//! Regular and Bold at seven sizes and the Rune vs macOS report's paragraph, or San Francisco
//! body and heading sizes, or SF Mono at code sizes; 1x and 2x) are drawn through Rune's real
//! glyph rasteriser, atlas and blend, and compared with CoreText reference sheets.

#if !os(WASI)
import Foundation

#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics
import ImageIO
#endif

// PORT NOTE: Mirrors `pub mod pixel_compare` on `rune::text` (`#[doc(hidden)]`, non-wasm).
// `Harness` composites `GlyphQuad`s directly from `TextSystem.atlas` using Rune's exact sRGB
// or linear alpha-blend formula so pixel comparisons run deterministically even without a
// headless GPU adapter, and `Image` decodes/encodes PNG sheets via `ImageIO`/`CoreGraphics` on
// Apple platforms with zero external crates.
public enum pixelCompare {
    /// A text colour on a page colour, sRGB hex.
    public struct Pair: Sendable, Equatable {
        public var name: String
        public var fg: String
        public var bg: String

        public init(name: String, fg: String, bg: String) {
            self.name = name
            self.fg = fg
            self.bg = bg
        }
    }

    public static let PAIRS: [Pair] = [
        Pair(name: "light", fg: "#1d1e22", bg: "#fcfcfb"),
        Pair(name: "dark", fg: "#e6e6e6", bg: "#1d1e22"),
        Pair(name: "white", fg: "#fcfcfb", bg: "#1d1e22"),
        Pair(name: "blue", fg: "#296d9a", bg: "#fcfcfb"),
    ]

    public static let SCALES: [Float] = [1.0, 2.0]
    public static let SIZES: [Float] = [9.0, 11.0, 13.0, 16.0, 20.0, 24.0, 32.0]
    public static let SAMPLE: String = "IHT\u{2014}/AVSog@8 Hamburgefonstiv"
    public static let MONO_SAMPLE: String = "It doesn't look like it; illicit 1111 mmmm @@ -33,3 +33,4 @@"
    public static let MONO_PARAGRAPH: String = "diff --git a/Welcome.md b/Welcome.md --- a/Welcome.md +++ b/Welcome.md @@ -33,3 +33,4 @@ $1 + 1$ It doesn't look like it +*Italics work though!* iiiiiiii llllllll mmmmmmmm"
    public static let PARAGRAPH: String = "The quick brown fox jumps over the lazy dog. AV To Wa Ty Yo LT fi fl ffi office flour 0123456789 ($4.50, 87%) \u{2014} \"quoted\" & semicolons; colons: question? Incomprehensibilities and HYPERVENTILATION."
    public static let SHEET_WIDTH: Float = 640.0

    private static let ROW_X: Float = 16.0
    private static let PARAGRAPH_HEIGHT: Float = 130.0
    private static let SYSTEM_FONT: String = "System Font"

    /// Which font's cases.
    public enum Set: Sendable, Equatable {
        case inter
        case sf
        case mono

        public func dir() -> URL {
            let base = refsDir()
            switch self {
            case .inter: return base
            case .sf: return base.appendingPathComponent("sf")
            case .mono: return base.appendingPathComponent("mono")
            }
        }

        public func name() -> String {
            switch self {
            case .inter: return "Inter"
            case .sf: return "San Francisco"
            case .mono: return "SF Mono"
            }
        }
    }

    /// Which CoreText rendering a sheet holds.
    public enum Reference: Sendable, Equatable {
        case smoothed
        case unsmoothed

        public static func forMode(_ mode: FontSmoothing) -> Reference {
            switch mode {
            case .on: return .smoothed
            case .off: return .unsmoothed
            }
        }

        func prefix() -> String {
            switch self {
            case .smoothed: return ""
            case .unsmoothed: return "flat-"
            }
        }

        public func pairs() -> [Pair] {
            switch self {
            case .smoothed: return PAIRS
            case .unsmoothed: return Array(PAIRS.prefix(2))
            }
        }
    }

    /// One case on a sheet; every length in points.
    public struct Case: Sendable, Equatable {
        public var name: String
        public var family: Family
        public var weight: Float
        public var size: Float
        public var lineHeight: Float
        public var wrap: Float?
        public var text: String
        public var origin: [Float]
        public var region: [Float]
        public var wholeRegion: Bool

        func font() -> String {
            switch (family, weight >= 700.0) {
            case (.named(SYSTEM_FONT), _): return "system"
            case (.systemMono, _): return "mono"
            case (_, true): return "bold"
            default: return "regular"
            }
        }
    }

    public static func cases(_ set: Set) -> [Case] {
        let sampleText = (set == .mono) ? MONO_SAMPLE : SAMPLE
        let family: Family
        var rows: [(String, Float, Float)] = []
        switch set {
        case .inter:
            family = .sans
            for (weight, font) in [(Float(400.0), "regular"), (Float(700.0), "bold")] {
                for size in SIZES {
                    rows.append((font, weight, size))
                }
            }
        case .sf:
            family = .named(SYSTEM_FONT)
            rows = [
                ("sf regular", 400.0, 16.0),
                ("sf bold", 700.0, 16.0),
                ("sf bold", 700.0, 28.0),
                ("sf bold", 700.0, 32.0),
            ]
        case .mono:
            family = .systemMono
            for size: Float in [11.0, 12.0, 13.0, 13.5, 14.0, 16.0] {
                rows.append(("mono", 400.0, size))
            }
        }

        var out: [Case] = []
        var y: Float = 4.0
        for (font, weight, size) in rows {
            let height = (size * 1.25).rounded(.up) + 6.0
            let sizeStr = (size.truncatingRemainder(dividingBy: 1.0) == 0.0)
                ? "\(Int(size))"
                : "\(size)"
            out.append(Case(
                name: "\(font) \(sizeStr)",
                family: family,
                weight: weight,
                size: size,
                lineHeight: 0.0,
                wrap: nil,
                text: sampleText,
                origin: [ROW_X, y + 3.0],
                region: [0.0, y, SHEET_WIDTH, height],
                wholeRegion: false
            ))
            y += height
        }
        let top = y.rounded(.up) + 4.0
        out.append(paragraphCase(family, top))
        return out
    }

    private static func paragraphCase(_ family: Family, _ top: Float) -> Case {
        if family == .systemMono {
            return Case(
                name: "mono paragraph 13.5/22",
                family: family,
                weight: 400.0,
                size: 13.5,
                lineHeight: 22.0,
                wrap: 567.0,
                text: MONO_PARAGRAPH,
                origin: [49.0, top + 40.0],
                region: [0.0, top + 30.0, SHEET_WIDTH, 90.0],
                wholeRegion: true
            )
        }
        return Case(
            name: (family == .sans) ? "paragraph 16/26" : "sf paragraph 16/26",
            family: family,
            weight: 400.0,
            size: 16.0,
            lineHeight: 26.0,
            wrap: 567.0,
            text: PARAGRAPH,
            origin: [49.0, top + 40.0],
            region: [0.0, top + 30.0, SHEET_WIDTH, 90.0],
            wholeRegion: true
        )
    }

    public static func sheetHeight(_ set: Set) -> Float {
        guard let last = cases(set).last else { return PARAGRAPH_HEIGHT }
        return last.region[1] - 30.0 + PARAGRAPH_HEIGHT
    }

    public static func refsDir() -> URL {
        #if !os(WASI)
        let repoTests = runeRepoRootDir().appendingPathComponent("Tests/RuneTests/tests/coretext")
        if FileManager.default.fileExists(atPath: repoTests.appendingPathComponent("layout.txt").path) {
            return repoTests
        }
        if let crateDir = upstreamRuneCrateDir() {
            return crateDir.appendingPathComponent("tests/coretext")
        }
        #endif
        return URL(fileURLWithPath: "Tests/RuneTests/tests/coretext")
    }

    public static func fontPaths() -> [URL] {
        #if !os(WASI)
        let interRegular = runeBundledAssetURL("Inter-Regular.ttf")
            ?? runeRepoRootDir().appendingPathComponent("Sources/Rune/assets/Inter-Regular.ttf")
        #else
        let interRegular = URL(fileURLWithPath: "Sources/Rune/assets/Inter-Regular.ttf")
        #endif
        return [
            interRegular,
            refsDir().appendingPathComponent("Inter-Bold-subset.ttf"),
        ]
    }

    public static func systemFontPath() -> URL? {
        #if os(macOS)
        if let first = systemFontFiles(["sfnsttf"]).first {
            return URL(fileURLWithPath: first)
        }
        #endif
        return nil
    }

    public static func systemMonoPath() -> URL? {
        #if os(macOS)
        if let found = systemFontFiles(["sfnsmono"]).first(where: { !$0.lowercased().contains("italic") }) {
            return URL(fileURLWithPath: found)
        }
        #endif
        return nil
    }

    private static func makeTextSystem() -> Result<TextSystem, PixelCompareError> {
        var fonts: [[UInt8]] = []
        for url in fontPaths() {
            guard let data = try? Data(contentsOf: url), !data.isEmpty else {
                return .failure(PixelCompareError("missing font file: \(url.path)"))
            }
            fonts.append([UInt8](data))
        }
        return .success(TextSystem(fonts, ("Inter", "Inter")))
    }

    private static func style(_ c: Case) -> TextStyle {
        var s = TextStyle.new(c.size, c.weight).family(c.family)
        s.lineHeight = c.lineHeight
        return s
    }

    static func positions(_ text: TextSystem, _ c: Case, _ scale: Float) -> [(UInt32, Float, Float)] {
        let layout = text.layoutRich(c.text, [], style(c), scale, c.wrap.map { $0 * scale })
        let ox = c.origin[0] * scale
        let oy = c.origin[1] * scale
        var out: [(UInt32, Float, Float)] = []
        for line in layout.lines() {
            for item in line.items() {
                guard case .glyphRun(let run) = item else { continue }
                let baseline = (oy + run.baseline()).rounded(.toNearestOrAwayFromZero)
                var rel = run.offset()
                for g in run.glyphs() {
                    out.append((UInt32(g.id), ox + rel + g.x, baseline + g.y))
                    rel += g.advance
                }
            }
        }
        return out
    }

    public struct PixelCompareError: Error, CustomStringConvertible, Sendable {
        public let message: String
        public init(_ message: String) { self.message = message }
        public var description: String { message }
    }

    public static func available(_ set: Set) -> Result<Void, PixelCompareError> {
        if set == .sf && systemFontPath() == nil {
            return .failure(PixelCompareError("no system font (SFNS) on this machine"))
        }
        if set == .mono && systemMonoPath() == nil {
            return .failure(PixelCompareError("no SF Mono (SFNSMono) on this machine"))
        }
        let fm = FileManager.default
        let layoutPath = set.dir().appendingPathComponent("layout.txt")
        guard fm.fileExists(atPath: layoutPath.path) else {
            return .failure(PixelCompareError("no \(set.name()) references in \(set.dir().path): run scripts/coretext-reference.sh"))
        }
        for p in fontPaths() where !fm.fileExists(atPath: p.path) {
            return .failure(PixelCompareError("missing font fixture \(p.path)"))
        }
        return .success(())
    }

    public static func layoutDigest(_ set: Set, _ scale: Float) -> Result<String, PixelCompareError> {
        switch makeTextSystem() {
        case .failure(let err):
            return .failure(err)
        case .success(let text):
            var h = KeyHasher()
            for c in cases(set) {
                for (id, x, y) in positions(text, c, scale) {
                    h.u32(id)
                    h.f32(x)
                    h.f32(y)
                }
            }
            return .success(String(format: "%016llx", h.hash))
        }
    }

    public static func layoutFile(_ set: Set) -> Result<String, PixelCompareError> {
        var out = ""
        for scale in SCALES {
            switch layoutDigest(set, scale) {
            case .failure(let err): return .failure(err)
            case .success(let digest):
                let scaleLabel = (scale.truncatingRemainder(dividingBy: 1.0) == 0.0) ? "\(Int(scale))" : "\(scale)"
                out += "\(scaleLabel)x \(digest)\n"
            }
        }
        return .success(out)
    }

    /// An opaque RGB image.
    public struct Image: Sendable {
        public var width: UInt32
        public var height: UInt32
        public var rgb: [UInt8]

        public init(width: UInt32, height: UInt32, rgb: [UInt8]) {
            self.width = width
            self.height = height
            self.rgb = rgb
        }

        func px(_ x: UInt32, _ y: UInt32) -> (UInt8, UInt8, UInt8) {
            let i = Int((y * width + x) * 3)
            return (rgb[i], rgb[i + 1], rgb[i + 2])
        }

        func green(_ x: Int64, _ y: Int64) -> UInt8? {
            guard x >= 0, y >= 0, x < Int64(width), y < Int64(height) else { return nil }
            return px(UInt32(x), UInt32(y)).1
        }

        public static func readPng(_ url: URL) -> Result<Image, PixelCompareError> {
            #if canImport(CoreGraphics) && canImport(ImageIO)
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImg = CGImageSourceCreateImageAtIndex(src, 0, nil)
            else {
                return .failure(PixelCompareError("failed to read PNG: \(url.path)"))
            }
            let w = cgImg.width
            let h = cgImg.height
            guard w > 0, h > 0 else {
                return .failure(PixelCompareError("empty PNG: \(url.path)"))
            }
            if cgImg.bitsPerPixel == 8 && cgImg.bitsPerComponent == 8,
               let dp = cgImg.dataProvider,
               let cfData = dp.data
            {
                let ptr = CFDataGetBytePtr(cfData)
                let len = CFDataGetLength(cfData)
                let bpr = cgImg.bytesPerRow
                if let ptr, len >= (h - 1) * bpr + w {
                    var rgb = [UInt8](repeating: 0, count: w * h * 3)
                    for row in 0..<h {
                        let rowBase = row * bpr
                        let dstBase = row * w * 3
                        for col in 0..<w {
                            let v = ptr[rowBase + col]
                            rgb[dstBase + col * 3] = v
                            rgb[dstBase + col * 3 + 1] = v
                            rgb[dstBase + col * 3 + 2] = v
                        }
                    }
                    return .success(Image(width: UInt32(w), height: UInt32(h), rgb: rgb))
                }
            }
            var rgba = [UInt8](repeating: 0, count: w * h * 4)
            let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(
                data: &rgba,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return .failure(PixelCompareError("failed to allocate CGContext for PNG"))
            }
            ctx.draw(cgImg, in: CGRect(x: 0, y: 0, width: w, height: h))
            var rgb = [UInt8](repeating: 0, count: w * h * 3)
            for i in 0..<(w * h) {
                rgb[i * 3] = rgba[i * 4]
                rgb[i * 3 + 1] = rgba[i * 4 + 1]
                rgb[i * 3 + 2] = rgba[i * 4 + 2]
            }
            return .success(Image(width: UInt32(w), height: UInt32(h), rgb: rgb))
            #else
            return .failure(PixelCompareError("PNG decoding requires ImageIO (unavailable on this platform)"))
            #endif
        }
    }

    /// Draws sheets of cases through Rune's `TextSystem` and atlas, blended in sRGB or linear space.
    public final class Harness {
        let text: TextSystem

        public init() throws {
            switch makeTextSystem() {
            case .success(let ts):
                self.text = ts
            case .failure(let err):
                throw err
            }
        }

        public func render(
            _ pair: Pair,
            _ scale: Float,
            _ srgbBlend: Bool,
            _ smoothing: FontSmoothing,
            _ cases: [Case],
            _ size: [Float]
        ) -> Image {
            text.beginFrame()
            text.setFontSmoothing(smoothing)
            let fg = hex(pair.fg) ?? .black
            let bg = hex(pair.bg) ?? .white
            let w = Int((size[0] * scale).rounded(.towardZero))
            let h = Int((size[1] * scale).rounded(.towardZero))
            var quads: [GlyphQuad] = []
            text.setGlyphInks(fg, [])
            for c in cases {
                let layout = text.layoutRich(c.text, [], style(c), scale, c.wrap.map { $0 * scale })
                text.glyphsForLayout(layout, scale, [c.origin[0] * scale, c.origin[1] * scale], false, &quads)
            }

            @inline(__always)
            func toByte(_ v: Float) -> UInt8 {
                UInt8(clamping: Int((min(max(v, 0.0), 1.0) * 255.0).rounded(.toNearestOrAwayFromZero)))
            }

            var rgb = [UInt8](repeating: 0, count: max(0, w * h * 3))
            guard w > 0, h > 0 else {
                return Image(width: UInt32(max(w, 0)), height: UInt32(max(h, 0)), rgb: rgb)
            }

            if srgbBlend {
                let bgR = srgbEncode(bg.r), bgG = srgbEncode(bg.g), bgB = srgbEncode(bg.b)
                let fgR = srgbEncode(fg.r), fgG = srgbEncode(fg.g), fgB = srgbEncode(fg.b)
                let bgBytes = (toByte(bgR), toByte(bgG), toByte(bgB))
                for i in 0..<(w * h) {
                    rgb[i * 3] = bgBytes.0
                    rgb[i * 3 + 1] = bgBytes.1
                    rgb[i * 3 + 2] = bgBytes.2
                }
                for q in quads where q.color == 0 {
                    let qx = Int(q.rect[0].rounded(.toNearestOrAwayFromZero))
                    let qy = Int(q.rect[1].rounded(.toNearestOrAwayFromZero))
                    let qw = Int(q.rect[2].rounded(.toNearestOrAwayFromZero))
                    let qh = Int(q.rect[3].rounded(.toNearestOrAwayFromZero))
                    let page = q.atlasPage()
                    let localUv = q.atlasUv()
                    let uvX = Int(localUv[0].rounded(.toNearestOrAwayFromZero))
                    let uvY = Int(localUv[1].rounded(.toNearestOrAwayFromZero))
                    guard let atlasData = text.atlas.pageData(page) else { continue }
                    let atlasStride = Int(ATLAS_SIZE)
                    for row in 0..<qh {
                        let dy = qy + row
                        if dy < 0 || dy >= h { continue }
                        let sy = uvY + row
                        if sy < 0 || sy >= atlasStride { continue }
                        for col in 0..<qw {
                            let dx = qx + col
                            if dx < 0 || dx >= w { continue }
                            let sx = uvX + col
                            if sx < 0 || sx >= atlasStride { continue }
                            let cov = atlasData[sy * atlasStride + sx]
                            if cov == 0 { continue }
                            let a = Float(cov) / 255.0
                            let pIdx = (dy * w + dx) * 3
                            let dR = Float(rgb[pIdx]) / 255.0
                            let dG = Float(rgb[pIdx + 1]) / 255.0
                            let dB = Float(rgb[pIdx + 2]) / 255.0
                            rgb[pIdx] = toByte(fgR * a + dR * (1.0 - a))
                            rgb[pIdx + 1] = toByte(fgG * a + dG * (1.0 - a))
                            rgb[pIdx + 2] = toByte(fgB * a + dB * (1.0 - a))
                        }
                    }
                }
            } else {
                var lin = [Float](repeating: 0, count: w * h * 3)
                for i in 0..<(w * h) {
                    lin[i * 3] = bg.r
                    lin[i * 3 + 1] = bg.g
                    lin[i * 3 + 2] = bg.b
                }
                for q in quads where q.color == 0 {
                    let qx = Int(q.rect[0].rounded(.toNearestOrAwayFromZero))
                    let qy = Int(q.rect[1].rounded(.toNearestOrAwayFromZero))
                    let qw = Int(q.rect[2].rounded(.toNearestOrAwayFromZero))
                    let qh = Int(q.rect[3].rounded(.toNearestOrAwayFromZero))
                    let page = q.atlasPage()
                    let localUv = q.atlasUv()
                    let uvX = Int(localUv[0].rounded(.toNearestOrAwayFromZero))
                    let uvY = Int(localUv[1].rounded(.toNearestOrAwayFromZero))
                    guard let atlasData = text.atlas.pageData(page) else { continue }
                    let atlasStride = Int(ATLAS_SIZE)
                    for row in 0..<qh {
                        let dy = qy + row
                        if dy < 0 || dy >= h { continue }
                        let sy = uvY + row
                        if sy < 0 || sy >= atlasStride { continue }
                        for col in 0..<qw {
                            let dx = qx + col
                            if dx < 0 || dx >= w { continue }
                            let sx = uvX + col
                            if sx < 0 || sx >= atlasStride { continue }
                            let cov = atlasData[sy * atlasStride + sx]
                            if cov == 0 { continue }
                            let a = Float(cov) / 255.0
                            let pIdx = (dy * w + dx) * 3
                            lin[pIdx] = fg.r * a + lin[pIdx] * (1.0 - a)
                            lin[pIdx + 1] = fg.g * a + lin[pIdx + 1] * (1.0 - a)
                            lin[pIdx + 2] = fg.b * a + lin[pIdx + 2] * (1.0 - a)
                        }
                    }
                }
                for i in 0..<(w * h) {
                    rgb[i * 3] = toByte(srgbEncode(lin[i * 3]))
                    rgb[i * 3 + 1] = toByte(srgbEncode(lin[i * 3 + 1]))
                    rgb[i * 3 + 2] = toByte(srgbEncode(lin[i * 3 + 2]))
                }
            }
            return Image(width: UInt32(w), height: UInt32(h), rgb: rgb)
        }
    }

    public struct Stats: Sendable, Equatable {
        public var pixels: UInt64 = 0
        public var differing: UInt64 = 0
        public var over8: UInt64 = 0
        public var max: UInt8 = 0
        public var absSum: Double = 0.0
        public var inkRune: Double = 0.0
        public var inkRef: Double = 0.0

        public init() {}

        public mutating func add(_ o: Stats) {
            pixels += o.pixels
            differing += o.differing
            over8 += o.over8
            max = Swift.max(max, o.max)
            absSum += o.absSum
            inkRune += o.inkRune
            inkRef += o.inkRef
        }

        public func meanabs() -> Double { absSum / Double(Swift.max(pixels, 1)) }
        public func inkRatio() -> Double { inkRune / Swift.max(inkRef, 1.0) }
        public func differingShare() -> Double { Double(differing) / Double(Swift.max(pixels, 1)) }
        public func over8Share() -> Double { Double(over8) / Double(Swift.max(pixels, 1)) }
    }

    private static func statsIn(_ rune: Image, _ reference: Image, _ rect: [UInt32], _ shift: [Int64]) -> Stats {
        let paperRune = rune.px(0, 0).1
        let paperRef = reference.px(0, 0).1
        var s = Stats()
        let x0 = rect[0], y0 = rect[1], x1 = rect[2], y1 = rect[3]
        for y in y0..<y1 {
            for x in x0..<x1 {
                let a = rune.green(Int64(x) - shift[0], Int64(y) - shift[1]) ?? paperRune
                let b = reference.px(x, y).1
                let d = (a >= b) ? (a - b) : (b - a)
                s.pixels += 1
                if d > 0 { s.differing += 1 }
                if d > 8 { s.over8 += 1 }
                if d > s.max { s.max = d }
                s.absSum += Double(d)
                s.inkRune += Double((a >= paperRune) ? (a - paperRune) : (paperRune - a))
                s.inkRef += Double((b >= paperRef) ? (b - paperRef) : (paperRef - b))
            }
        }
        return s
    }

    private static func inkBounds(_ images: [Image], _ rect: [UInt32]) -> [UInt32]? {
        let x0 = rect[0], y0 = rect[1], x1 = rect[2], y1 = rect[3]
        var loX = UInt32.max, loY = UInt32.max
        var hiX: UInt32 = 0, hiY: UInt32 = 0
        for image in images {
            let paper = image.px(0, 0).1
            let maxY = min(y1, image.height)
            let maxX = min(x1, image.width)
            guard y0 < maxY, x0 < maxX else { continue }
            for y in y0..<maxY {
                for x in x0..<maxX {
                    if image.px(x, y).1 != paper {
                        loX = min(loX, x)
                        loY = min(loY, y)
                        hiX = max(hiX, x + 1)
                        hiY = max(hiY, y + 1)
                    }
                }
            }
        }
        guard hiX > 0 else { return nil }
        return [
            max(loX > 0 ? loX - 1 : 0, x0),
            max(loY > 0 ? loY - 1 : 0, y0),
            min(hiX + 1, x1),
            min(hiY + 1, y1),
        ]
    }

    public static func compare(_ rune: Image, _ reference: Image, _ c: Case, _ scale: Float) -> Stats {
        let rx = UInt32(max(0, Int((c.region[0] * scale).rounded(.toNearestOrAwayFromZero))))
        let ry = UInt32(max(0, Int((c.region[1] * scale).rounded(.toNearestOrAwayFromZero))))
        let rw = UInt32(max(0, Int((c.region[2] * scale).rounded(.toNearestOrAwayFromZero))))
        let rh = UInt32(max(0, Int((c.region[3] * scale).rounded(.toNearestOrAwayFromZero))))
        let region: [UInt32] = [rx, ry, min(rx + rw, rune.width), min(ry + rh, rune.height)]
        let rect = c.wholeRegion ? region : inkBounds([rune, reference], region)
        guard let r = rect else { return Stats() }
        return statsIn(rune, reference, r, [0, 0])
    }

    public static func referencePath(_ set: Set, _ reference: Reference, _ pair: Pair, _ scale: Float) -> URL {
        let scaleStr = (scale.truncatingRemainder(dividingBy: 1.0) == 0.0) ? "\(Int(scale))" : "\(scale)"
        return set.dir().appendingPathComponent("\(reference.prefix())\(pair.name)-\(scaleStr)x.png")
    }

    public struct Row: Sendable {
        public var pair: Pair
        public var scale: Float
        public var `case`: Case
        public var stats: Stats
    }

    public struct Options: Sendable {
        public var set: Set
        public var smoothing: FontSmoothing?
        public var srgbBlend: Bool?
        public var reference: Reference?

        public init(
            set: Set,
            smoothing: FontSmoothing? = nil,
            srgbBlend: Bool? = nil,
            reference: Reference? = nil
        ) {
            self.set = set
            self.smoothing = smoothing
            self.srgbBlend = srgbBlend
            self.reference = reference
        }

        public static func new(_ set: Set) -> Options {
            Options(set: set)
        }

        public func resolvedSmoothing() -> FontSmoothing { smoothing ?? .default }
        public func resolvedSrgbBlend() -> Bool { srgbBlend ?? true }
        public func resolvedReference() -> Reference { reference ?? Reference.forMode(resolvedSmoothing()) }
    }

    public static func run(
        _ o: Options,
        _ keep: (Pair, Float, Image, Image) -> Void = { _, _, _, _ in }
    ) -> Result<[Row], PixelCompareError> {
        if case .failure(let err) = available(o.set) {
            return .failure(err)
        }
        let caseList = cases(o.set)
        let harness: Harness
        do {
            harness = try Harness()
        } catch let e as PixelCompareError {
            return .failure(e)
        } catch {
            return .failure(PixelCompareError("\(error)"))
        }
        var rows: [Row] = []
        let ref = o.resolvedReference()
        for scale in SCALES {
            for pair in ref.pairs() {
                let refUrl = referencePath(o.set, ref, pair, scale)
                let reference: Image
                switch Image.readPng(refUrl) {
                case .success(let img): reference = img
                case .failure(let err): return .failure(err)
                }
                let rune = harness.render(
                    pair,
                    scale,
                    o.resolvedSrgbBlend(),
                    o.resolvedSmoothing(),
                    caseList,
                    [SHEET_WIDTH, sheetHeight(o.set)]
                )
                if rune.width != reference.width || rune.height != reference.height {
                    return .failure(PixelCompareError(
                        "\(pair.name) \(scale)x: reference is \(reference.width)x\(reference.height), Rune \(rune.width)x\(rune.height)"
                    ))
                }
                keep(pair, scale, rune, reference)
                for c in caseList {
                    let s = compare(rune, reference, c, scale)
                    rows.append(Row(pair: pair, scale: scale, case: c, stats: s))
                }
            }
        }
        return .success(rows)
    }

    public static func paragraph(_ rows: [Row], _ pair: String, _ scale: Float) -> Stats? {
        rows.first(where: { $0.pair.name == pair && $0.scale == scale && $0.case.wholeRegion })?.stats
    }

    public static func pooled(_ rows: [Row], _ pair: String, _ scale: Float) -> Stats {
        var s = Stats()
        for r in rows where r.pair.name == pair && r.scale == scale && !r.case.wholeRegion {
            s.add(r.stats)
        }
        return s
    }

    public static func table(_ o: Options, _ rows: [Row]) -> String {
        var out = ""
        let against = (o.resolvedReference() == .smoothed) ? "smoothing on" : "smoothing off"
        let blendName = o.resolvedSrgbBlend() ? "sRGB" : "linear"
        out += "\(o.set.name()): Rune \(o.resolvedSmoothing()) (\(blendName) blending) vs CoreText with \(against)\n"
        let head = "case                           differ       >8  max  meanabs     ink\n"
        func appendLine(_ label: String, _ s: Stats) {
            let padded = label.count < 28 ? (label + String(repeating: " ", count: 28 - label.count)) : label
            out += padded + " " + String(
                format: "%7.2f%% %7.2f%% %4u %8.3f %7.3f\n",
                100.0 * s.differingShare(),
                100.0 * s.over8Share(),
                s.max,
                s.meanabs(),
                s.inkRatio()
            )
        }
        for scale in SCALES {
            for pair in o.resolvedReference().pairs() {
                out += "\n\(pair.name) (\(pair.fg) on \(pair.bg)), \(scale)x\n"
                out += head
                for r in rows where r.pair.name == pair.name && r.scale == scale {
                    appendLine(r.case.name, r.stats)
                }
            }
        }
        out += "\nsummary: paragraph (report band) and all sample rows pooled\n"
        out += head
        for scale in SCALES.reversed() {
            for pair in o.resolvedReference().pairs() {
                if let p = paragraph(rows, pair.name, scale) {
                    appendLine("\(pair.name) \(scale)x paragraph", p)
                }
                appendLine("\(pair.name) \(scale)x rows", pooled(rows, pair.name, scale))
            }
        }
        return out
    }

    public static func heatmap(_ rune: Image, _ reference: Image) -> Image {
        let paperRune = Int32(rune.px(0, 0).1)
        let paperRef = Int32(reference.px(0, 0).1)
        let n = min(rune.rgb.count, reference.rgb.count) / 3
        var out = [UInt8](repeating: 0, count: n * 3)
        for i in 0..<n {
            let a1 = Int32(rune.rgb[i * 3 + 1])
            let b1 = Int32(reference.rgb[i * 3 + 1])
            let ia = abs(a1 - paperRune)
            let ib = abs(b1 - paperRef)
            let k = UInt8(min(abs(ib - ia) * 4, 255))
            if a1 == b1 {
                let g = UInt8(clamping: Int(252 - ia / 4))
                out[i * 3] = g
                out[i * 3 + 1] = g
                out[i * 3 + 2] = g
            } else if ib > ia {
                out[i * 3] = 255
                out[i * 3 + 1] = 255 - k
                out[i * 3 + 2] = 255 - k
            } else {
                out[i * 3] = 255 - k
                out[i * 3 + 1] = 255 - k
                out[i * 3 + 2] = 255
            }
        }
        return Image(width: rune.width, height: rune.height, rgb: out)
    }
}
#endif
