// Swift-only: Unit tests for PNGEncoder

import Foundation
import Testing
@testable import GPUIUtil

#if canImport(AppKit)
import AppKit
#endif

@Suite("PNGEncoderTests")
struct PNGEncoderTests {
    @Test("PNG signature and chunk structure")
    func testPngHeaderAndChunks() {
        let width = 2
        let height = 2
        let rgba: [UInt8] = [
            255, 0, 0, 255,     0, 255, 0, 255,
            0, 0, 255, 255,     255, 255, 255, 255,
        ]

        let data = PNGEncoder.encodeRGBA(width: width, height: height, rgba: rgba)
        #expect(data.count > 58)

        // Magic bytes
        let magic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        #expect(Array(data.prefix(8)) == magic)

        // IHDR chunk
        let ihdrLen = UInt32(data[8]) << 24 | UInt32(data[9]) << 16 | UInt32(data[10]) << 8 | UInt32(data[11])
        #expect(ihdrLen == 13)
        let ihdrTag = String(decoding: data[12..<16], as: UTF8.self)
        #expect(ihdrTag == "IHDR")

        // IEND chunk at end
        let endBytes = Array(data.suffix(12))
        let iendLen = UInt32(endBytes[0]) << 24 | UInt32(endBytes[1]) << 16 | UInt32(endBytes[2]) << 8 | UInt32(endBytes[3])
        #expect(iendLen == 0)
        let iendTag = String(decoding: endBytes[4..<8], as: UTF8.self)
        #expect(iendTag == "IEND")
        // Standard IEND CRC: 0xAE426082
        let iendCrc = UInt32(endBytes[8]) << 24 | UInt32(endBytes[9]) << 16 | UInt32(endBytes[10]) << 8 | UInt32(endBytes[11])
        #expect(iendCrc == 0xAE426082)
    }

    @Test("Multi-block uncompressed deflate handling for larger images")
    func testMultiBlockEncoding() {
        // 200 x 200 RGBA image: 200 * (1 + 800) = 160,200 bytes (> 65,535, requiring 3 deflate blocks)
        let width = 200
        let height = 200
        let rgba = [UInt8](repeating: 128, count: width * height * 4)

        let data = PNGEncoder.encodeRGBA(width: width, height: height, rgba: rgba)
        #expect(!data.isEmpty)

        let magic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        #expect(Array(data.prefix(8)) == magic)

        #if canImport(AppKit)
        // Verify native OS image parser decodes our pure-Swift generated PNG correctly
        let image = NSImage(data: data)
        #expect(image != nil)
        if let rep = image?.representations.first {
            #expect(rep.pixelsWide == width)
            #expect(rep.pixelsHigh == height)
        }
        #endif
    }
}
