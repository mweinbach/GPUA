// Tests ported from: crates/rune/src/clipboard/macos.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import AppKit
import Foundation
import Testing
@testable import Rune

@Suite
struct ClipboardMacOSTests {
    private static let sampleRtf = #"{\rtf1\ansi\ansicpg1252\cocoartf2761"# + "\n"
        + #"{\fonttbl\f0\fswiss\fcharset0 Helvetica;}"# + "\n"
        + #"\pard\f0\fs24 Hello \b bold\b0  and \i italic\i0  caf\'e9}"#

    private func png2x3() -> [UInt8] {
        let rgba: [UInt8] = (0..<6).flatMap { i -> [UInt8] in
            let v = UInt8(i * 40)
            return [v, 255 &- v, 128, 255]
        }
        return encodePng(2, 3, rgba)!
    }

    private func tiffOf(_ png: [UInt8]) -> [UInt8] {
        [UInt8](pngToTiff(png)!)
    }

    @Test
    func rtfBecomesHtmlOffTheMainThread() {
        let sem = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable { var html: String? = nil }
        let box = Box()
        Thread.detachNewThread {
            box.html = rtfToHtml(Array(Self.sampleRtf.utf8))
            sem.signal()
        }
        #expect(sem.wait(timeout: .now() + 20.0) == .success)
        let html = box.html!
        let text = sanitizeHtml(html)
        #expect(text.contains("Hello") && text.contains("bold") && text.contains("café"))
        #expect(html.contains("font-weight: bold") || html.contains("<b>"))
        #expect(rtfToHtml(Array("not rtf".utf8)) == nil)
        #expect(rtfToHtml([]) == nil)
        #expect(rtfToHtml([UInt8](repeating: 0x61, count: MAX_RTF_CONVERT_BYTES + 1)) == nil)
    }

    @Test
    func everyFormRoundTripsInOneChange() {
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let before = pb.changeCount
        let content = ClipboardContent.new("Hi there")
            .withHtml("<b>Hi</b> there")
            .withRtf(Self.sampleRtf)
        if case .failure(let err) = writeMacPasteboard(pb, content) {
            Issue.record("Pasteboard write failed: \(err)")
            return
        }
        #expect(pb.changeCount == before + 1)
        let back = readMacPasteboard(pb, true)!
        #expect(back.text() == "Hi there")
        #expect(back.html()?.hasSuffix("<b>Hi</b> there") == true)
        #expect(back.rtf() == Self.sampleRtf)

        pb.clearContents()
        _ = pb.setData(Data(Self.sampleRtf.utf8), forType: .rtf)
        let rtfOnly = readMacPasteboard(pb, true)!
        #expect(rtfOnly.text() == "Hello bold and italic café")
        #expect(rtfOnly.html()?.contains("bold") == true)

        let tiff = tiffOf(png2x3())
        pb.clearContents()
        _ = pb.setData(Data(tiff), forType: .tiff)
        let tiffSize = readMacPasteboard(pb, true)?.image()?.size()
        #expect(tiffSize?.0 == 2 && tiffSize?.1 == 3)
        #expect(readMacPasteboard(pb, false) == nil)

        pb.clearContents()
        _ = pb.setString("shot.png", forType: .string)
        _ = pb.setData(Data(png2x3()), forType: .png)
        let both = readMacPasteboard(pb, true)!
        #expect(both.text() == "shot.png")
        #expect(both.image()?.png() == png2x3())
    }

    @Test
    func imagesAndFilesAreWrittenForOtherApps() {
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        let before = pb.changeCount
        let image = ClipboardImage.fromPng(png2x3())!
        if case .failure(let err) = writeMacPasteboard(pb, ClipboardContent().withImage(image)) {
            Issue.record("Pasteboard write failed: \(err)")
            return
        }
        #expect(pb.changeCount == before + 1)
        #expect(pb.data(forType: .png).map([UInt8].init) == png2x3())
        let convertedSize = pb.data(forType: .tiff).flatMap { tiffToPng([UInt8]($0)) }?.size()
        #expect(convertedSize?.0 == 2 && convertedSize?.1 == 3)
        #expect(pb.string(forType: .string) == nil)
        #expect(readMacPasteboard(pb, true) == ClipboardContent().withImage(image))

        let files = ["/fixtures/a.txt", "/fixtures/b c.png"]
        if case .failure(let err) = writeMacPasteboard(
            pb,
            ClipboardContent.new("a.txt b c.png").withHtml("<b>files</b>").withFiles(files)
        ) {
            Issue.record("Pasteboard write failed: \(err)")
            return
        }
        let items = pb.pasteboardItems!
        #expect(items.count == 2)
        #expect(items[1].string(forType: .fileURL) == "file:///fixtures/b%20c.png")
        #expect(items[1].string(forType: .string) == nil)
        let back = readMacPasteboard(pb, true)!
        #expect(back.text() == "a.txt b c.png")
        #expect(back.files() == files)
        #expect(readMacPasteboard(pb, false)?.files().isEmpty == true)
    }

    @Test
    func tiffBecomesPngOffTheMainThread() {
        let tiff = tiffOf(png2x3())
        let sem = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable { var result: ((UInt32, UInt32), Bool)? = nil }
        let box = Box()
        Thread.detachNewThread {
            if let img = tiffToPng(tiff) {
                box.result = (img.size(), Array(img.png().prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
            }
            sem.signal()
        }
        #expect(sem.wait(timeout: .now() + 20.0) == .success)
        #expect(box.result?.0.0 == 2 && box.result?.0.1 == 3 && box.result?.1 == true)
        #expect(tiffToPng(Array("not a tiff".utf8)) == nil)
        #expect(tiffToPng([]) == nil)

        var bomb: [UInt8] = [0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00, 0x02, 0x00]
        bomb.append(contentsOf: [0x00, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00])
        bomb.append(contentsOf: [0x01, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00])
        #expect(!tiffDimensionsOk(bomb))
        #expect(tiffToPng(bomb) == nil)
    }
}
#endif
