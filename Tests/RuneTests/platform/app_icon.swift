// Tests ported from: crates/rune/src/platform/app_icon.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

#if os(macOS)
import AppKit

@Suite("AppIconTests", .serialized)
struct AppIconTests {
    private func makeTestPng() -> [UInt8] {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 16,
            pixelsHigh: 16,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 16 * 4,
            bitsPerPixel: 32
        ), let ptr = rep.bitmapData else {
            return []
        }
        for i in 0..<(16 * 16) {
            ptr[i * 4 + 0] = 40
            ptr[i * 4 + 1] = 120
            ptr[i * 4 + 2] = 220
            ptr[i * 4 + 3] = 255
        }
        guard let data = rep.representation(using: .png, properties: [:]) else {
            return []
        }
        return [UInt8](data)
    }

    @Test("an icon must be an image and waits for launch")
    func iconMustBeAnImageAndWaitsForLaunch() {
        switch setAppIcon(Array("not an image".utf8)) {
        case .success:
            Issue.record("Expected non-image bytes to fail")
        case .failure:
            break
        }
        switch setAppIcon(makeTestPng()) {
        case .success:
            break
        case .failure(let err):
            Issue.record("Expected PNG icon bytes to succeed: \(err)")
        }
        // Without an event loop nothing touches NSApplication, so a headless run stays windowless.
        #expect(!isAppIconLaunchedForTests())
        #expect(hasPendingAppIconForTests())
    }
}
#endif
