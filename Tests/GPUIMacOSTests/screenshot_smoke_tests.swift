// Swift-only: Native macOS AppKit + Metal + CoreText screenshot smoke test

#if os(macOS)
import AppKit
import CoreGraphics
import Foundation
import GPUI
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import GPUIMacOS

// PORT NOTE: HelloWorldSmokeView mirrors crates/gpui_examples/examples/hello_world.rs to verify
// full end-to-end rendering across AppKit + MetalRenderer + CoreText (MacTextSystem).
private struct HelloWorldSmokeView: Render, Sendable {
    var text: SharedString

    init(text: SharedString = "World") {
        self.text = text
    }

    mutating func render(_ window: inout Window, _ cx: inout Context<HelloWorldSmokeView>) -> AnyElement {
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
                    .child(
                        div()
                            .size8()
                            .bg(GPUI.red())
                            .border1()
                            .borderDashed()
                            .roundedMd()
                            .borderColor(GPUI.white())
                    )
                    .child(
                        div()
                            .size8()
                            .bg(GPUI.green())
                            .border1()
                            .borderDashed()
                            .roundedMd()
                            .borderColor(GPUI.white())
                    )
                    .child(
                        div()
                            .size8()
                            .bg(GPUI.blue())
                            .border1()
                            .borderDashed()
                            .roundedMd()
                            .borderColor(GPUI.white())
                    )
                    .child(
                        div()
                            .size8()
                            .bg(GPUI.yellow())
                            .border1()
                            .borderDashed()
                            .roundedMd()
                            .borderColor(GPUI.white())
                    )
                    .child(
                        div()
                            .size8()
                            .bg(GPUI.black())
                            .border1()
                            .borderDashed()
                            .roundedMd()
                            .borderColor(GPUI.white())
                    )
                    .child(
                        div()
                            .size8()
                            .bg(GPUI.white())
                            .border1()
                            .borderDashed()
                            .roundedMd()
                            .borderColor(GPUI.black())
                    )
            )
            .intoAnyElement()
    }
}

@Suite("GPUIMacOS Screenshot Smoke Tests")
struct MacScreenshotSmokeTests {
    @Test("Renders HelloWorldView through MacPlatform + MacWindow + MetalRenderer + MacTextSystem and saves PNG")
    @MainActor
    func testRenderHelloWorldMacOSScreenshot() throws {
        let platform = MacPlatform.new(headless: false)
        let cx = App.newApp(platform: platform)

        let windowBounds = Bounds(
            origin: point(px(100.0), px(100.0)),
            size: size(px(500.0), px(500.0))
        )
        let options = WindowOptions(
            windowBounds: .windowed(windowBounds),
            titlebar: TitlebarOptions(title: "Hello World", appearsTransparent: true),
            focus: false,
            show: false
        )

        let handle = try cx.openWindow(options) { _, app in
            app.new { _ in
                HelloWorldSmokeView(text: "World")
            }
        }

        var capturedFrame: (width: UInt32, height: UInt32, rgba: [UInt8])?
        var renderedScaleFactor: Float = 1.0

        try cx.updateWindow(handle.anyHandle) { _, window, app in
            let macWin = try #require(window.platformWindow as? MacWindow)
            macWin.captureFrames = true
            renderedScaleFactor = macWin.scaleFactor()
            var appMut = app
            window.draw(cx: &appMut)
            capturedFrame = macWin.lastCapturedFrame
        }

        let frame = try #require(capturedFrame, "Expected Metal readback frame from MacWindow.draw")
        let expectedWidth = UInt32((500.0 * renderedScaleFactor).rounded())
        let expectedHeight = UInt32((500.0 * renderedScaleFactor).rounded())
        #expect(frame.width == expectedWidth)
        #expect(frame.height == expectedHeight)
        #expect(frame.rgba.count == Int(frame.width * frame.height * 4))

        let w = Int(frame.width)
        let h = Int(frame.height)
        let s = Double(renderedScaleFactor)

        func rgbaAt(logicalX: Double, logicalY: Double) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            let pxX = min(max(Int((logicalX * s).rounded()), 0), w - 1)
            let pxY = min(max(Int((logicalY * s).rounded()), 0), h - 1)
            let idx = (pxY * w + pxX) * 4
            return (frame.rgba[idx], frame.rgba[idx + 1], frame.rgba[idx + 2], frame.rgba[idx + 3])
        }

        // 1. Verify gray container background (rgb(0x505050) = (80, 80, 80)) inside the 500x500 box.
        let bgSample = rgbaAt(logicalX: 40, logicalY: 40)
        #expect(abs(Int(bgSample.r) - 0x50) <= 6, "Expected gray background R≈80, got \(bgSample)")
        #expect(abs(Int(bgSample.g) - 0x50) <= 6, "Expected gray background G≈80, got \(bgSample)")
        #expect(abs(Int(bgSample.b) - 0x50) <= 6, "Expected gray background B≈80, got \(bgSample)")
        #expect(bgSample.a == 255)

        // 2. Verify blue border (rgb(0x0000ff)) at edge pixel (0, 250).
        var foundBlueBorder = false
        for bx in 0..<max(Int((3.0 * s).rounded()), 2) {
            let idx = (Int((250.0 * s).rounded()) * w + bx) * 4
            if frame.rgba[idx + 2] > 200 && frame.rgba[idx] < 50 && frame.rgba[idx + 1] < 50 {
                foundBlueBorder = true
                break
            }
        }
        #expect(foundBlueBorder, "Expected 1px blue border along the left edge")

        // 3. Verify crisp white CoreText glyph pixels for "Hello, World!" in the upper-center band
        //    (logical X: 170..330, logical Y: 205..250).
        var brightTextPixels = 0
        let textXStart = Int((170.0 * s).rounded())
        let textXEnd = Int((330.0 * s).rounded())
        let textYStart = Int((205.0 * s).rounded())
        let textYEnd = Int((250.0 * s).rounded())
        for py in textYStart..<textYEnd {
            for pxX in textXStart..<textXEnd {
                let idx = (py * w + pxX) * 4
                let r = frame.rgba[idx]
                let g = frame.rgba[idx + 1]
                let b = frame.rgba[idx + 2]
                if r > 200 && g > 200 && b > 200 {
                    brightTextPixels += 1
                }
            }
        }
        #expect(brightTextPixels > 80, "Expected rendered white 'Hello, World!' text glyphs, found \(brightTextPixels) bright pixels")

        // 4. Verify the 6 colored squares (Red, Green, Blue, Yellow, Black, White) in the lower-center band
        //    (logical Y: 245..295).
        let swatchYStart = Int((245.0 * s).rounded())
        let swatchYEnd = Int((295.0 * s).rounded())
        var foundRed = false
        var foundGreen = false
        var foundBlueSwatch = false
        var foundYellow = false
        var foundBlack = false
        var foundWhite = false

        for py in swatchYStart..<swatchYEnd {
            for pxX in Int((120.0 * s).rounded())..<Int((380.0 * s).rounded()) {
                let idx = (py * w + pxX) * 4
                let r = Int(frame.rgba[idx])
                let g = Int(frame.rgba[idx + 1])
                let b = Int(frame.rgba[idx + 2])
                if r > 180 && g < 100 && b < 100 { foundRed = true }
                if g > 140 && r < 110 && b < 110 { foundGreen = true }
                if b > 180 && r < 100 && g < 120 { foundBlueSwatch = true }
                if r > 180 && g > 150 && b < 100 { foundYellow = true }
                if r < 30 && g < 30 && b < 30 { foundBlack = true }
                if r > 240 && g > 240 && b > 240 { foundWhite = true }
            }
        }
        #expect(foundRed, "Expected Red square in swatch row")
        #expect(foundGreen, "Expected Green square in swatch row")
        #expect(foundBlueSwatch, "Expected Blue square in swatch row")
        #expect(foundYellow, "Expected Yellow square in swatch row")
        #expect(foundBlack, "Expected Black square in swatch row")
        #expect(foundWhite, "Expected White square in swatch row")

        // 5. Encode RGBA8 pixels to PNG and save to artifacts/screenshots/hello_world_macos.png.
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // GPUIMacOSTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        let outputURL = repoRoot
            .appendingPathComponent("artifacts", isDirectory: true)
            .appendingPathComponent("screenshots", isDirectory: true)
            .appendingPathComponent("hello_world_macos.png")

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let data = Data(frame.rgba)
        let provider = try #require(CGDataProvider(data: data as CFData))
        let cgImage = try #require(
            CGImage(
                width: w,
                height: h,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: w * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        )

        let pngData = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(pngData as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, cgImage, nil)
        #expect(CGImageDestinationFinalize(destination))

        try (pngData as Data).write(to: outputURL, options: .atomic)

        let savedBytes = try Data(contentsOf: outputURL)
        #expect(savedBytes.count > 1_000)
        // PNG magic header: 89 50 4E 47 0D 0A 1A 0A
        #expect(Array(savedBytes.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }
}
#endif
