// Tests ported from: crates/rune/src/image.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if !os(WASI)
import Foundation
#endif
#if canImport(ImageIO) && canImport(CoreGraphics) && canImport(UniformTypeIdentifiers)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#endif
import Testing
@testable import Rune

#if !os(WASI)
private final class WakeChannel: @unchecked Sendable {
    private let condition = NSCondition()
    private var signals = 0

    func send() {
        condition.lock()
        signals += 1
        condition.signal()
        condition.unlock()
    }

    @discardableResult
    func recv(timeout: TimeInterval = 10.0) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        condition.lock()
        defer { condition.unlock() }
        while signals == 0 {
            if !condition.wait(until: deadline) && signals == 0 {
                return false
            }
        }
        signals -= 1
        return true
    }
}
#endif

@Suite("ImageTests")
struct ImageTests {
    @Test("mips filter linear premultiplied pixels including odd edges")
    func mipsFilterLinearPremultipliedPixelsIncludingOddEdges() throws {
        let d = try mipChain(3, 1, [255, 0, 0, 255, 0, 255, 0, 0, 255, 0, 0, 255]).get()
        #expect(d.mips.count == 2)
        #expect(Array(d.mips[0].pixels[4..<8]) == [0, 0, 0, 0])
        #expect(d.mips[1].pixels[3] == 170)
        #expect(d.mips[1].pixels[1] == 0)
        #expect(abs(Int(d.mips[1].pixels[0]) - 213) <= 1)

        let gray = try mipChain(2, 1, [0, 0, 0, 255, 255, 255, 255, 255]).get()
        #expect(gray.mips[1].pixels == [188, 188, 188, 255])

        let tail = try mipChain(3, 1, [255, 255, 255, 1, 0, 0, 0, 0, 0, 0, 0, 0]).get()
        #expect(tail.mips[1].pixels == [0, 0, 0, 0])
    }

    @Test("decoded pixels wake windows only once the image reports ready")
    func decodedPixelsWakeWindowsOnlyOnceImageReportsReady() {
        final class SeenRecorder: @unchecked Sendable {
            let lock = LiveLock()
            var entries: [(Bool, [UInt32]?)] = []
            func push(_ ready: Bool, _ sz: [UInt32]?) {
                lock.withLock { entries.append((ready, sz)) }
            }
        }
        let image = Image(ImageState(id: [UInt8](repeating: 0, count: 32)))
        let seen = SeenRecorder()
        let wake = LiveWake {
            seen.push(image.isReady(), image.size())
        }
        _ = image.pixels().source.subscribe(wake)
        image.finish(mipChain(2, 1, [0, 0, 0, 255, 255, 255, 255, 255]))
        let recorded = seen.lock.withLock { seen.entries }
        #expect(recorded.count == 1)
        #expect(recorded[0].0 == true && recorded[0].1 == [2, 1])
    }

    #if !os(WASI)
    @Test("a small image queued behind a large one decodes without waiting for it")
    func smallImageQueuedBehindLargeDecodesWithoutWaiting() {
        guard ProcessInfo.processInfo.activeProcessorCount >= 2 else { return }
        let ch = WakeChannel()
        let cache = ImageCache.new { ch.send() }
        // Warm up cache worker threads so OS thread startup jitter doesn't delay the fast lane.
        _ = cache.rgba(1, 1, [0, 0, 0, 255]).wait()
        _ = ch.recv(timeout: 5.0)

        let large = cache.rgba(3000, 3000, [UInt8](repeating: 128, count: 3000 * 3000 * 4))
        let small = cache.rgba(1, 1, [20, 40, 60, 255])
        #expect(ch.recv(timeout: 10.0))
        #expect(small.isReady() && !large.isReady())
        #expect(ch.recv(timeout: 20.0))
        #expect(large.isReady())
    }

    @Test("cache deduplicates and wakes after async completion")
    func cacheDeduplicatesAndWakesAfterAsyncCompletion() throws {
        let ch = WakeChannel()
        let cache = ImageCache.new { ch.send() }
        let first = cache.rgba(1, 1, [20, 40, 60, 255])
        let second = cache.rgba(1, 1, [20, 40, 60, 255])
        #expect(first.sharesIdentity(with: second))
        #expect(ch.recv(timeout: 5.0))
        #expect(first.size() == [1, 1])
        let decoded = try first.decoded()!.get()
        #expect(decoded.mips[0].pixels == [20, 40, 60, 255])

        let invalid = cache.load([0, 1, 2])
        #expect(ch.recv(timeout: 5.0))
        #expect(invalid.error() != nil)
    }

    @Test("a decoder panic fails its image and the worker goes on")
    func decoderPanicFailsImageAndWorkerGoesOn() {
        let ch = WakeChannel()
        let cache = ImageCache.new { ch.send() }
        let broken = cache.request([UInt8](repeating: 7, count: 32), .simulatedPanic("decoder bug"))
        #expect(ch.recv(timeout: 5.0))
        #expect(broken.error() == ImageError("image decoder panicked: decoder bug"))

        let next = cache.rgba(1, 1, [20, 40, 60, 255])
        #expect(ch.recv(timeout: 5.0))
        #expect(next.size() == [1, 1])
    }

    @Test("desktop entries resolve the closest theme size then scalable then pixmaps")
    func desktopEntriesResolveClosestThemeSizeThenScalableThenPixmaps() throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let root = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("rune-icon-theme-\(pid)-\(UUID().uuidString)")
        let fm = FileManager.default
        defer { try? fm.removeItem(atPath: root) }

        let user = (root as NSString).appendingPathComponent("user")
        let system = (root as NSString).appendingPathComponent("system")

        @discardableResult
        func put(_ relRoot: String, _ rel: String) throws -> String {
            let full = (relRoot as NSString).appendingPathComponent(rel)
            let parent = (full as NSString).deletingLastPathComponent
            try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
            try Data("icon".utf8).write(to: URL(fileURLWithPath: full))
            return full
        }

        var entrySeq = 0
        func makeEntry(_ icon: String) throws -> String {
            try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
            entrySeq += 1
            let path = (root as NSString).appendingPathComponent("entry-\(entrySeq).desktop")
            let body = "[Desktop Entry]\nName=App\nIcon=\(icon)\n[Desktop Action new]\nIcon=other\n"
            try Data(body.utf8).write(to: URL(fileURLWithPath: path))
            return path
        }

        let dirs = [user, system]
        try put(system, "icons/hicolor/32x32/apps/editor.png")
        let at64 = try put(user, "icons/hicolor/64x64/apps/editor.png")
        let at2x = try put(system, "icons/hicolor/48x48@2/apps/editor.png")
        try put(system, "icons/hicolor/256x256/apps/editor.png")
        let svg = try put(system, "icons/hicolor/scalable/apps/editor.svg")

        #expect(FreedesktopIconLookup.iconFile(entryPath: try makeEntry("editor"), px: 48, dataDirs: dirs) == at64)
        #expect(FreedesktopIconLookup.iconFile(entryPath: try makeEntry("editor"), px: 90, dataDirs: dirs) == at2x)
        #expect(FreedesktopIconLookup.iconFile(entryPath: try makeEntry("editor.png"), px: 48, dataDirs: dirs) == at64)

        try fm.removeItem(atPath: (system as NSString).appendingPathComponent("icons/hicolor/256x256"))
        #expect(FreedesktopIconLookup.iconFile(entryPath: try makeEntry("editor"), px: 512, dataDirs: dirs) == svg)

        let pixmap = try put(system, "pixmaps/legacy.png")
        #expect(FreedesktopIconLookup.iconFile(entryPath: try makeEntry("legacy"), px: 48, dataDirs: dirs) == pixmap)
        #expect(FreedesktopIconLookup.iconFile(entryPath: try makeEntry(pixmap), px: 48, dataDirs: dirs) == pixmap)
        #expect(FreedesktopIconLookup.iconFile(entryPath: try makeEntry("missing"), px: 48, dataDirs: dirs) == nil)
        #expect(FreedesktopIconLookup.iconName("[Desktop Action x]\nIcon=no\n") == nil)
    }
    #endif

    @Test("png and icns decode and malformed containers fail")
    func pngAndIcnsDecodeAndMalformedContainersFail() throws {
        var rgba = [UInt8]()
        for _ in 0..<(8 * 4) {
            rgba.append(contentsOf: [20, 40, 60, 255])
        }
        let pngBytes = RunePngCodec.encodeRgba8(width: 8, height: 4, rgba: rgba)
        let d = try decodeImageBytes(pngBytes).get()
        #expect(d.mips[0].width == 8 && d.mips[0].height == 4)
        #expect(d.mips.last?.width == 1 && d.mips.last?.height == 1)

        var icns = Array("icns".utf8)
        let totalLen = UInt32(pngBytes.count + 16).bigEndian
        withUnsafeBytes(of: totalLen) { icns.append(contentsOf: $0) }
        icns.append(contentsOf: Array("icp4".utf8))
        let chunkLen = UInt32(pngBytes.count + 8).bigEndian
        withUnsafeBytes(of: chunkLen) { icns.append(contentsOf: $0) }
        icns.append(contentsOf: pngBytes)
        let icnsDecoded = try decodeImageBytes(icns).get()
        #expect(icnsDecoded.mips[0].pixels == d.mips[0].pixels)

        icns.replaceSubrange(12..<16, with: [0, 0, 0, 0])
        if case .success = decodeImageBytes(icns) {
            Issue.record("expected malformed ICNS chunk size to fail")
        }
        if case .success = mipChain(0, 1, []) {
            Issue.record("expected 0-width mipChain to fail")
        }
        if case .success = mipChain(1, 1, [0]) {
            Issue.record("expected short byte length mipChain to fail")
        }
    }

    #if canImport(ImageIO) && canImport(CoreGraphics) && canImport(UniformTypeIdentifiers)
    @Test("a jpeg turns upright by its exif orientation")
    func jpegTurnsUprightByExifOrientation() throws {
        let w = 16
        let h = 8
        var rgba = [UInt8]()
        rgba.reserveCapacity(w * h * 4)
        for _ in 0..<h {
            for x in 0..<w {
                if x < 8 {
                    rgba.append(contentsOf: [255, 0, 0, 255])
                } else {
                    rgba.append(contentsOf: [0, 0, 255, 255])
                }
            }
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let cfData = Data(rgba) as CFData
        let provider = CGDataProvider(data: cfData)!
        let cgImage = CGImage(
            width: w,
            height: h,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        let jpegMutable = NSMutableData()
        let dest = CGImageDestinationCreateWithData(
            jpegMutable,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        )!
        CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        let plainJpeg = [UInt8](jpegMutable as Data)

        // An APP1 Exif segment after SOI: a little-endian TIFF header and one IFD entry,
        // Orientation (0x0112) = 6, "rotate 90° clockwise to display".
        var tiff: [UInt8] = Array("II*\0".utf8)
        tiff.append(contentsOf: [8, 0, 0, 0])
        tiff.append(contentsOf: [1, 0])
        tiff.append(contentsOf: [0x12, 0x01, 3, 0, 1, 0, 0, 0, 6, 0, 0, 0])
        tiff.append(contentsOf: [0, 0, 0, 0])
        var app1: [UInt8] = Array("Exif\0\0".utf8)
        app1.append(contentsOf: tiff)
        let segLen = UInt16(app1.count + 2)
        var rotatedJpeg = Array(plainJpeg[0..<2])
        rotatedJpeg.append(contentsOf: [0xFF, 0xE1, UInt8(segLen >> 8), UInt8(segLen & 0xFF)])
        rotatedJpeg.append(contentsOf: app1)
        rotatedJpeg.append(contentsOf: plainJpeg[2...])

        let plain = try decodeImageBytes(plainJpeg).get()
        #expect(plain.mips[0].width == 16 && plain.mips[0].height == 8)

        let upright = try decodeImageBytes(rotatedJpeg).get()
        let top = upright.mips[0]
        try #require(top.width == 8 && top.height == 16)
        func pixelAt(_ x: UInt32, _ y: UInt32) -> ArraySlice<UInt8> {
            let idx = Int((y * top.width + x) * 4)
            return top.pixels[idx..<(idx + 3)]
        }
        let upper = Array(pixelAt(4, 2))
        let lower = Array(pixelAt(4, 13))
        #expect(upper[0] > 200 && upper[2] < 60)
        #expect(lower[2] > 200 && lower[0] < 60)
    }
    #endif

    #if os(macOS)
    @Test("app icon rasterizes calculator off the main thread and shares handles")
    func appIconRasterizesCalculatorAndSharesHandles() throws {
        let calc = "/System/Applications/Calculator.app"
        guard FileManager.default.fileExists(atPath: calc) else { return }
        let cache = ImageCache.new {}
        let icon = cache.appIcon(calc, 32.0)
        #expect(icon.sharesIdentity(with: cache.appIcon(calc, 32.0)))
        #expect(!icon.sharesIdentity(with: cache.appIconScaled(calc, 32.0, 1.0)))
        #expect(try icon.wait().get() == [64, 64])
        let pixels = try icon.decoded()!.get().mips[0].pixels
        var opaque = 0
        for i in stride(from: 3, to: pixels.count, by: 4) where pixels[i] > 0 {
            opaque += 1
        }
        #expect(opaque > 64 * 64 / 4)
    }

    @Test("a small app icon matches the large one scaled down")
    func aSmallAppIconMatchesTheLargeOneScaledDown() throws {
        let fm = FileManager.default
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("rune-icon-bundle-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)")
        defer { try? fm.removeItem(atPath: dir) }

        let app = (dir as NSString).appendingPathComponent("Synthetic.app")
        let resources = (app as NSString).appendingPathComponent("Contents/Resources")
        try fm.createDirectory(atPath: resources, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>\
        <key>CFBundleIdentifier</key><string>dev.rune.synthetic-icon</string>\
        <key>CFBundleName</key><string>Synthetic</string>\
        <key>CFBundlePackageType</key><string>APPL</string>\
        <key>CFBundleIconFile</key><string>icon</string></dict></plist>
        """
        try plist.write(toFile: (app as NSString).appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)

        var rgba = [UInt8]()
        rgba.reserveCapacity(256 * 256 * 4)
        for y in 0..<256 {
            for x in 0..<256 {
                let inside = (16..<240).contains(x) && (16..<240).contains(y)
                rgba.append(UInt8(x))
                rgba.append(UInt8(y))
                rgba.append(UInt8((x + y) / 2))
                rgba.append(inside ? 255 : 0)
            }
        }
        let png = RunePngCodec.encodeRgba8(width: 256, height: 256, rgba: rgba)
        var icns: [UInt8] = Array("icns".utf8)
        let totalLen = UInt32(png.count + 16)
        icns.append(contentsOf: [UInt8((totalLen >> 24) & 0xFF), UInt8((totalLen >> 16) & 0xFF), UInt8((totalLen >> 8) & 0xFF), UInt8(totalLen & 0xFF)])
        icns.append(contentsOf: Array("ic08".utf8))
        let chunkLen = UInt32(png.count + 8)
        icns.append(contentsOf: [UInt8((chunkLen >> 24) & 0xFF), UInt8((chunkLen >> 16) & 0xFF), UInt8((chunkLen >> 8) & 0xFF), UInt8(chunkLen & 0xFF)])
        icns.append(contentsOf: png)
        try Data(icns).write(to: URL(fileURLWithPath: (resources as NSString).appendingPathComponent("icon.icns")))

        let small = try appIconRgba(app, 32).get().2
        let large = try appIconRgba(app, 256).get().2
        var total: UInt32 = 0
        var count: UInt32 = 0
        for y in 0..<32 {
            for x in 0..<32 {
                let solid = small[(y * 32 + x) * 4 + 3] >= 200
                for c in (solid ? 0 : 3)..<4 {
                    var block: UInt32 = 0
                    for dy in 0..<8 {
                        for dx in 0..<8 {
                            block += UInt32(large[((y * 8 + dy) * 256 + x * 8 + dx) * 4 + c])
                        }
                    }
                    let avg = block / 64
                    let sv = UInt32(small[(y * 32 + x) * 4 + c])
                    total += avg >= sv ? (avg - sv) : (sv - avg)
                    count += 1
                }
            }
        }
        let mean = Float(total) / Float(count)
        #expect(mean < 12.0, "the 32 px icon differs from the 256 px one by \(mean) on average")
    }
    #endif
}
