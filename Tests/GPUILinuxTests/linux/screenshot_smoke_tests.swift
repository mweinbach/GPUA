// Swift-only: Native screenshot smoke test on Linux X11 with Lavapipe WebGPU

#if os(Linux)
import Foundation
import Testing
@testable import GPUILinux
import GPUI
import GPUIWGPU
import GPUIUtil
import CLinuxSys

// MARK: - HelloWorld View Model
// PORT NOTE: HelloWorldView declared in test target to avoid linker collisions with executable target.
struct HelloWorldView: Render, @unchecked Sendable {
    var text: SharedString

    init(text: SharedString = "World") {
        self.text = text
    }

    mutating func render(_ window: inout GPUI.Window, _ cx: inout Context<HelloWorldView>) -> AnyElement {
        div()
            .flex()
            .flexCol()
            .gap3()
            .bg(Hsla(rgba: rgb(0x505050)))
            .size(px(500.0))
            .justifyCenter()
            .itemsCenter()
            .shadowLg()
            .border1()
            .borderColor(Hsla(rgba: rgb(0x0000ff)))
            .textXl()
            .textColor(Hsla(rgba: rgb(0xffffff)))
            .child("Hello, \(text)!")
            .child(
                div()
                    .flex()
                    .gap2()
                    .child(div().size8().bg(GPUI.red()).border1().borderDashed().roundedMd().borderColor(GPUI.white()))
                    .child(div().size8().bg(GPUI.green()).border1().borderDashed().roundedMd().borderColor(GPUI.white()))
                    .child(div().size8().bg(GPUI.blue()).border1().borderDashed().roundedMd().borderColor(GPUI.white()))
                    .child(div().size8().bg(GPUI.yellow()).border1().borderDashed().roundedMd().borderColor(GPUI.white()))
                    .child(div().size8().bg(GPUI.black()).border1().borderDashed().roundedMd().borderColor(GPUI.white()))
                    .child(div().size8().bg(GPUI.white()).border1().borderDashed().roundedMd().borderColor(GPUI.black()))
            )
            .intoAnyElement()
    }
}

@Suite("Linux Native Window Screenshot Smoke Tests")
struct LinuxScreenshotSmokeTests {
    private static func findRepoRoot() -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return dir
    }

    private static func loadFontFixture(repoRoot: URL) -> Data? {
        let candidates = [
            repoRoot.appendingPathComponent("Tests/GPUITests/Fixtures/fonts/ibm-plex-sans/IBMPlexSans-Regular.ttf").path,
            "Tests/GPUITests/Fixtures/fonts/ibm-plex-sans/IBMPlexSans-Regular.ttf",
            "/workspace/Tests/GPUITests/Fixtures/fonts/ibm-plex-sans/IBMPlexSans-Regular.ttf",
        ]
        for path in candidates {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)), !data.isEmpty {
                return data
            }
        }
        return nil
    }

    @Test("Render HelloWorld on real X11Window with Lavapipe WebGPU, verify frame pixels, write PNG artifact")
    @MainActor
    func testLinuxHelloWorldScreenshotSmoke() throws {
        // Only run when DISPLAY is available (e.g. under xvfb-run or real X11)
        guard let displayEnv = ProcessInfo.processInfo.environment["DISPLAY"], !displayEnv.isEmpty else {
            return
        }

        let repoRoot = Self.findRepoRoot()
        let client = try X11Client.new()

        // Seed font fixture into text system for font rasterization under headless X11
        if let fontData = Self.loadFontFixture(repoRoot: repoRoot) {
            try? client.ptr.state.common.textSystem.addFonts([fontData])
        }

        let platform = LinuxPlatform(inner: client)
        let app = App.newApp(platform: platform)

        let windowOptions = WindowOptions(
            windowBounds: .windowed(Bounds(origin: .zero, size: Size(width: px(500), height: px(500)))),
            kind: .normal
        )

        let handle = try app.openWindow(windowOptions) { _, cx in
            cx.new { _ in HelloWorldView(text: "World") }
        }

        var capturedFrame: (width: UInt32, height: UInt32, rgba: [UInt8])? = nil

        try app.updateWindow(handle.anyHandle) { _, window, cx in
            if let x11 = window.platformWindow as? X11Window {
                x11.captureFrames = true
                if let conn = x11.ptr.connection {
                    xcb_map_window(conn, x11.ptr.xWindow)
                    xcb_flush(conn)
                }
            }
            var appCx = cx
            window.draw(cx: &appCx)
            capturedFrame = (window.platformWindow as? X11Window)?.lastCapturedFrame
        }

        let frame = try #require(capturedFrame, "Expected non-nil lastCapturedFrame from X11Window")
        let w = Int(frame.width)
        let h = Int(frame.height)
        #expect(w >= 450 && h >= 450)
        #expect(frame.rgba.count == w * h * 4)

        // 1. Verify background pixel at (10, 10) matches rgb(0x505050)
        let bgOffset = (10 * w + 10) * 4
        let bgR = frame.rgba[bgOffset + 0]
        let bgG = frame.rgba[bgOffset + 1]
        let bgB = frame.rgba[bgOffset + 2]
        #expect(abs(Int(bgR) - 0x50) <= 10, "Expected red channel ~0x50, got \(bgR)")
        #expect(abs(Int(bgG) - 0x50) <= 10, "Expected green channel ~0x50, got \(bgG)")
        #expect(abs(Int(bgB) - 0x50) <= 10, "Expected blue channel ~0x50, got \(bgB)")

        // 2. Count non-background pixels and verify colored squares and text glyphs
        var nonBgCount = 0
        var hasRed = false
        var hasGreen = false
        var hasBlue = false
        // Locate the row of colored squares (red square is first, blue square is third)
        var minRedY = h
        var minRedX = w

        for y in 0..<h {
            for x in 0..<w {
                let offset = (y * w + x) * 4
                let r = frame.rgba[offset + 0]
                let g = frame.rgba[offset + 1]
                let b = frame.rgba[offset + 2]

                if abs(Int(r) - 0x50) > 20 || abs(Int(g) - 0x50) > 20 || abs(Int(b) - 0x50) > 20 {
                    nonBgCount += 1
                }
                if r > 200 && g < 50 && b < 50 {
                    hasRed = true
                    if y < minRedY { minRedY = y }
                    if x < minRedX { minRedX = x }
                }
                if r < 50 && g > 100 && b < 50 {
                    hasGreen = true
                }
            }
        }

        // Find blue square in the same horizontal band as the red square (avoiding outer window border)
        var minBlueX = w
        if minRedY < h {
            for y in minRedY..<min(minRedY + 32, h) {
                for x in 20..<min(w - 20, 480) {
                    let offset = (y * w + x) * 4
                    let r = frame.rgba[offset + 0]
                    let g = frame.rgba[offset + 1]
                    let b = frame.rgba[offset + 2]
                    if r < 50 && g < 50 && b > 200 {
                        hasBlue = true
                        if x < minBlueX { minBlueX = x }
                    }
                }
            }
        }

        #expect(nonBgCount > 500, "Expected >500 non-background pixels, found \(nonBgCount)")
        #expect(hasRed, "Expected red square pixels")
        #expect(hasGreen, "Expected green square pixels")
        #expect(hasBlue, "Expected blue square pixels")
        #expect(minRedX < minBlueX, "Expected red square (x=\(minRedX)) to the left of blue square (x=\(minBlueX)), verifying RGBA channel order")

        // Count bright text glyph pixels strictly in the text band above the colored squares
        var textGlyphPixels = 0
        var minTextX = w
        var maxTextX = 0
        var minTextY = h
        var maxTextY = 0

        let textMaxY = min(minRedY - 4, 400)
        if textMaxY > 50 {
            for y in 50..<textMaxY {
                for x in 80...min(420, w - 20) {
                    let offset = (y * w + x) * 4
                    let r = frame.rgba[offset + 0]
                    let g = frame.rgba[offset + 1]
                    let b = frame.rgba[offset + 2]
                    if r > 160 && g > 160 && b > 160 {
                        textGlyphPixels += 1
                        if x < minTextX { minTextX = x }
                        if x > maxTextX { maxTextX = x }
                        if y < minTextY { minTextY = y }
                        if y > maxTextY { maxTextY = y }
                    }
                }
            }
        }
        #expect(textGlyphPixels > 10, "Expected white text glyph pixels in text band above squares, found \(textGlyphPixels)")

        // Anti-aliased letterform gap assertion:
        // Inside the tight bounding box [minTextX...maxTextX, minTextY...maxTextY], assert that dark background pixels
        // (abs(r - 0x50) <= 20 && abs(g - 0x50) <= 20 && abs(b - 0x50) <= 20) also appear (> 50 pixels).
        // This proves genuine anti-aliased letterforms with background visible between letter strokes/counters, NOT solid bounding boxes!
        var textBgPixelsInBBox = 0
        if minTextX <= maxTextX && minTextY <= maxTextY {
            for y in minTextY...maxTextY {
                for x in minTextX...maxTextX {
                    let offset = (y * w + x) * 4
                    let r = frame.rgba[offset + 0]
                    let g = frame.rgba[offset + 1]
                    let b = frame.rgba[offset + 2]
                    if abs(Int(r) - 0x50) <= 20 && abs(Int(g) - 0x50) <= 20 && abs(Int(b) - 0x50) <= 20 {
                        textBgPixelsInBBox += 1
                    }
                }
            }
        }
        #expect(textBgPixelsInBBox > 50, "Expected >50 background pixels between anti-aliased glyph strokes in text bounding box, found \(textBgPixelsInBBox)")

        // 3. Encode via pure-Swift PNGEncoder and verify PNG structure
        let pngData = PNGEncoder.encodeRGBA(width: w, height: h, rgba: frame.rgba)
        #expect(pngData.count > 100)
        let magic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        #expect(Array(pngData.prefix(8)) == magic)

        // 4. Write screenshot artifact to <repo_root>/artifacts/screenshots/hello_world_linux.png
        let artifactDir = repoRoot.appendingPathComponent("artifacts/screenshots")
        try FileManager.default.createDirectory(at: artifactDir, withIntermediateDirectories: true)
        let fileURL = artifactDir.appendingPathComponent("hello_world_linux.png")
        try pngData.write(to: fileURL)

        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        #expect(fileSize > 100)
    }
}
#endif
