// Swift-only: Unit tests for Windows clipboard format mapping and DIB-to-BMP conversion

#if os(Windows)
import Foundation
import Testing
import GPUI
@testable import GPUIWindows

@Suite("WindowsClipboardTests")
struct WindowsClipboardTests {
    @Test
    func testFormatMapping() {
        #expect(formatToType(CF_UNICODETEXT) == .text)
        #expect(formatToType(CF_DIB) == .image)
        #expect(formatToType(CF_HDROP) == .files)
        #expect(formatToType(999999) == nil)
    }

    @Test
    func testConvertDibToBmpInvalidLength() {
        let shortData = Data(repeating: 0, count: 20)
        #expect(convertDibToBmp(shortData) == nil)
    }

    @Test
    func testConvertDibToBmp24bpp() {
        // Create minimal 40-byte BITMAPINFOHEADER for 24bpp (no color table)
        var dibData = Data(count: 40 + 12) // 40 header + 12 pixel bytes (4 pixels)
        // biSize = 40
        var biSize: UInt32 = 40
        withUnsafeBytes(of: &biSize) { dibData.replaceSubrange(0..<4, with: $0) }
        // biWidth = 2, biHeight = 2
        var biWidth: Int32 = 2
        var biHeight: Int32 = 2
        withUnsafeBytes(of: &biWidth) { dibData.replaceSubrange(4..<8, with: $0) }
        withUnsafeBytes(of: &biHeight) { dibData.replaceSubrange(8..<12, with: $0) }
        // biPlanes = 1
        var biPlanes: UInt16 = 1
        withUnsafeBytes(of: &biPlanes) { dibData.replaceSubrange(12..<14, with: $0) }
        // biBitCount = 24
        var biBitCount: UInt16 = 24
        withUnsafeBytes(of: &biBitCount) { dibData.replaceSubrange(14..<16, with: $0) }
        // biCompression = 0 (BI_RGB)
        var biCompression: UInt32 = 0
        withUnsafeBytes(of: &biCompression) { dibData.replaceSubrange(16..<20, with: $0) }

        guard let bmp = convertDibToBmp(dibData) else {
            Issue.record("Failed to convert 24bpp DIB to BMP")
            return
        }

        #expect(bmp.count == 14 + dibData.count)
        #expect(bmp[0] == 0x42) // 'B'
        #expect(bmp[1] == 0x4D) // 'M'

        // Check pixel offset (14 + 40 = 54)
        let pixelOffset = bmp.withUnsafeBytes { $0.load(fromByteOffset: 10, as: UInt32.self) }
        #expect(pixelOffset == 54)
    }

    @Test
    func testConvertDibToBmp8bppWithPalette() {
        // 8bpp has 256 colors * 4 = 1024 bytes color table
        var dibData = Data(count: 40 + 1024 + 4)
        var biSize: UInt32 = 40
        withUnsafeBytes(of: &biSize) { dibData.replaceSubrange(0..<4, with: $0) }
        var biBitCount: UInt16 = 8
        withUnsafeBytes(of: &biBitCount) { dibData.replaceSubrange(14..<16, with: $0) }
        var biCompression: UInt32 = 0
        withUnsafeBytes(of: &biCompression) { dibData.replaceSubrange(16..<20, with: $0) }

        guard let bmp = convertDibToBmp(dibData) else {
            Issue.record("Failed to convert 8bpp DIB to BMP")
            return
        }

        #expect(bmp.count == 14 + dibData.count)
        let pixelOffset = bmp.withUnsafeBytes { $0.load(fromByteOffset: 10, as: UInt32.self) }
        #expect(pixelOffset == 14 + 40 + 1024) // 1078
    }
}
#endif
