// Tests ported from: crates/rune/src/image/from_url_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if !os(WASI)
import Foundation
#endif
import Testing
@testable import Rune

@Suite("ImageFromUrlTests")
struct ImageFromUrlTests {
    @Test("fetched pixels land as mips and oversized or short ones fail naming the url")
    func fetchedPixelsLandAsMipsAndOversizedOrShortFailNamingUrl() throws {
        let decoded = try landFetchedImage("a.webp", .rgba(2, 1, [255, 0, 0, 255, 0, 0, 255, 255]), 1).get()
        #expect(decoded.mips[0].width == 2 && decoded.mips[0].height == 1)
        #expect(decoded.mips.count == 2)

        let side = IMAGE_URL_MAX_SIDE + 1
        switch landFetchedImage("huge.avif", .rgba(side, 1, [UInt8](repeating: 0, count: Int(side) * 4)), 1) {
        case .success:
            Issue.record("expected oversized fetched image to fail")
        case .failure(let huge):
            #expect(huge.message.hasPrefix("huge.avif: "))
        }

        if case .success = landFetchedImage("short.png", .rgba(2, 2, [0, 0, 0, 0]), 1) {
            Issue.record("byte length must match the size")
        }
    }

    @Test("native urls name files and refuse the network")
    func nativeUrlsNameFilesAndRefuseNetwork() throws {
        #expect(try imageFilePathFromUrl("assets/logo.png").get() == "assets/logo.png")
        #if !os(Windows)
        #expect(try imageFilePathFromUrl("file:///tmp/a%20b.png").get() == "/tmp/a b.png")
        #expect(try imageFilePathFromUrl("FILE://localhost/tmp/x.png").get() == "/tmp/x.png")
        #endif
        #expect(try imageFilePathFromUrl(#"C:\art\x.png"#).get() == #"C:\art\x.png"#)
        for bad in ["https://example.com/a.png", "data:image/png;base64,AAAA", "file:relative.png", "file:///bad%zz.png"] {
            if case .success = imageFilePathFromUrl(bad) {
                Issue.record("expected \(bad) to fail")
            }
        }
    }

    #if !os(WASI)
    @Test("the cache loads a url once and wakes when it lands")
    func cacheLoadsUrlOnceAndWakesWhenLanded() throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let dir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("rune-image-url-\(pid)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let path = (dir as NSString).appendingPathComponent("dot.png")
        var rgba = [UInt8]()
        for _ in 0..<(3 * 2) {
            rgba.append(contentsOf: [10, 20, 30, 255])
        }
        let pngBytes = RunePngCodec.encodeRgba8(width: 3, height: 2, rgba: rgba)
        try Data(pngBytes).write(to: URL(fileURLWithPath: path))

        final class Flag: @unchecked Sendable {
            let lock = LiveLock()
            var woke = false
            func mark() { lock.withLock { woke = true } }
            func get() -> Bool { lock.withLock { woke } }
        }
        let flag = Flag()
        let cache = ImageCache.new { flag.mark() }
        let byPath = cache.url(path, 16.0, 2.0)
        #expect(byPath.sharesIdentity(with: cache.url(path, 16.0, 2.0)))
        #expect(try byPath.wait().get() == [3, 2])
        #expect(byPath.size() == [3, 2])
        let deadline = Date(timeIntervalSinceNow: 2.0)
        while !flag.get() && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.002)
        }
        #expect(flag.get())

        #if !os(Windows)
        #expect(try cache.url("file://\(path)", 16.0, 2.0).wait().get() == [3, 2])
        #endif

        let remote = cache.url("https://example.com/dot.png", 16.0, 2.0)
        switch remote.wait() {
        case .success:
            Issue.record("expected remote URL on native to fail")
        case .failure(let err):
            #expect(err.message.contains("ImageCache::load"))
        }
    }
    #endif
}
