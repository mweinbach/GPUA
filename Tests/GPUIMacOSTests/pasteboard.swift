// Tests ported from: crates/gpui_macos/src/pasteboard.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(macOS)
import AppKit
import Foundation
import GPUI
import Testing
@testable import GPUIMacOS

@Suite("GPUIMacOS Pasteboard Tests")
struct MacPasteboardTests {
    /// Simulates an external file copy on an isolated unique pasteboard (matching Finder's
    /// legacy `NSFilenamesPboardType` + plain-text path representation).
    private func simulateExternalFileCopy(_ pasteboard: GPUIMacOS.Pasteboard, _ paths: [String]) {
        pasteboard.inner.clearContents()
        let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        pasteboard.inner.declareTypes([filenamesType, .string], owner: nil)
        _ = pasteboard.inner.setPropertyList(paths, forType: filenamesType)
        let joined = paths.joined(separator: "\n")
        _ = pasteboard.inner.setData(Data(joined.utf8), forType: .string)
    }

    @Test("test_string read/write and metadata hash invalidation")
    func testString() {
        let pasteboard = GPUIMacOS.Pasteboard.unique()
        #expect(pasteboard.read() == nil)

        let item1 = PasteboardItem.newString("1")
        pasteboard.write(item1)
        #expect(pasteboard.read() == item1)

        let item2 = PasteboardItem(entries: [
            .string(ClipboardString.new("2").withJsonMetadata([3, 4]))
        ])
        pasteboard.write(item2)
        #expect(pasteboard.read() == item2)

        // Simulate another app overwriting string data without updating `"zed-text-hash"`.
        _ = pasteboard.inner.setData(Data("text from other app".utf8), forType: .string)
        #expect(pasteboard.read() == PasteboardItem.newString("text from other app"))
    }

    @Test("test_read_external_path")
    func testReadExternalPath() throws {
        let pasteboard = GPUIMacOS.Pasteboard.unique()
        simulateExternalFileCopy(pasteboard, ["/test.txt"])

        let item = try #require(pasteboard.read())
        #expect(item.entries.count == 2)
        #expect(item.entries[0] == .externalPaths(ExternalPaths(paths: ["/test.txt"])))
        #expect(item.entries[1] == .string(ClipboardString(text: "/test.txt")))
    }

    @Test("test_read_external_paths_with_spaces")
    func testReadExternalPathsWithSpaces() throws {
        let pasteboard = GPUIMacOS.Pasteboard.unique()
        simulateExternalFileCopy(pasteboard, ["/some file with spaces.txt"])

        let item = try #require(pasteboard.read())
        #expect(item.entries[0] == .externalPaths(ExternalPaths(paths: ["/some file with spaces.txt"])))
    }

    @Test("test_read_multiple_external_paths")
    func testReadMultipleExternalPaths() throws {
        let pasteboard = GPUIMacOS.Pasteboard.unique()
        simulateExternalFileCopy(pasteboard, ["/file.txt", "/image.png"])

        let item = try #require(pasteboard.read())
        #expect(item.entries.count == 2)
        #expect(item.entries[0] == .externalPaths(ExternalPaths(paths: ["/file.txt", "/image.png"])))
        #expect(item.entries[1] == .string(ClipboardString(text: "/file.txt\n/image.png", metadata: nil)))
    }

    @Test("test_read_image")
    func testReadImage() throws {
        let pasteboard = GPUIMacOS.Pasteboard.unique()

        // Valid 1x1 transparent PNG (67 bytes), matching upstream `pasteboard.rs`.
        let pngBytes: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
            0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
            0x54, 0x78, 0x9C, 0x62, 0x00, 0x00, 0x00, 0x02,
            0x00, 0x01, 0xE5, 0x27, 0xDE, 0xFC, 0x00, 0x00,
            0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,
            0x60, 0x82,
        ]

        pasteboard.inner.clearContents()
        pasteboard.inner.declareTypes([.png], owner: nil)
        _ = pasteboard.inner.setData(Data(pngBytes), forType: .png)

        let item = try #require(pasteboard.read())
        #expect(item.entries.count == 1)
        if case .image(let img) = item.entries[0] {
            #expect(img.format == .png)
            #expect(img.bytes == pngBytes)
        } else {
            Issue.record("Expected ClipboardEntry.image, got \(item.entries[0])")
        }
    }
}
#endif
