// Tests ported from: crates/rune/src/platform/macos/drop.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

#if os(macOS)
import AppKit
import Foundation

@Suite("MacosDropTests")
struct MacosDropTests {
    private static func pasteboardAvailable() -> Bool {
        let pb = NSPasteboard.withUniqueName()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        let item = NSPasteboardItem()
        let kind = NSPasteboard.PasteboardType("public.utf8-plain-text")
        guard item.setString("probe", forType: kind),
              pb.writeObjects([item]),
              pb.string(forType: kind) == "probe"
        else {
            return false
        }
        return true
    }

    private final class ScopedBoard {
        let pb: NSPasteboard
        init(_ pb: NSPasteboard) { self.pb = pb }
        deinit { pb.releaseGlobally() }
    }

    private func makeBoard(_ items: [[(String, [UInt8])]]) -> ScopedBoard? {
        guard Self.pasteboardAvailable() else { return nil }
        let board = ScopedBoard(NSPasteboard.withUniqueName())
        board.pb.clearContents()
        let pbItems: [NSPasteboardItem] = items.map { pairs in
            let item = NSPasteboardItem()
            for (t, bytes) in pairs {
                item.setData(Data(bytes), forType: NSPasteboard.PasteboardType(t))
            }
            return item
        }
        #expect(board.pb.writeObjects(pbItems))
        return board
    }

    private func makePng() -> [UInt8] {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 8,
            bitsPerPixel: 32
        ), let ptr = rep.bitmapData else {
            return []
        }
        let rgba: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255]
        for (i, b) in rgba.enumerated() { ptr[i] = b }
        return [UInt8](rep.representation(using: .png, properties: [:]) ?? Data())
    }

    private func found(_ pb: NSPasteboard) -> [MacDropItem] {
        macDropItems(pb).map(\.1)
    }

    @Test("a file url is its path")
    func fileUrlIsItsPath() {
        guard let board = makeBoard([[(macDropFileUrlType, Array("file:///tmp/notes%20one.txt".utf8))]]) else { return }
        #expect(found(board.pb) == [.file("/tmp/notes one.txt")])
    }

    @Test("image data without a file is an image")
    func imageDataWithoutAFileIsAnImage() {
        let png = makePng()
        guard let board = makeBoard([
            [("public.png", png)],
            [("public.url", Array("https://e.com/a.png".utf8)), ("public.tiff", Array("II*\0".utf8))],
        ]) else { return }
        #expect(found(board.pb) == [.image("public.png", "png"), .image("public.tiff", "png")])
    }

    @Test("a file url wins over the image beside it")
    func fileUrlWinsOverTheImageBesideIt() {
        let png = makePng()
        guard let board = makeBoard([
            [(macDropFileUrlType, Array("file:///tmp/a.png".utf8)), ("public.png", png)],
        ]) else { return }
        #expect(found(board.pb) == [.file("/tmp/a.png")])
    }

    @Test("a promise is named for its type")
    func promiseIsNamedForItsType() {
        guard let board = makeBoard([
            [
                ("com.apple.NSFilePromiseItemMetaData", Array("x".utf8)),
                (macDropPromisedType, Array("public.png".utf8)),
            ],
        ]) else { return }
        #expect(found(board.pb) == [.promise("png")])
    }

    @Test("hover paths stand in for files to come")
    func hoverPathsStandInForFilesToCome() {
        #expect(MacDropItem.file("/tmp/a.txt").hoverPath() == "/tmp/a.txt")
        #expect(MacDropItem.promise("png").hoverPath() == "File.png")
        #expect(MacDropItem.promise(nil).hoverPath() == "File")
        #expect(MacDropItem.image("public.tiff", "png").hoverPath() == "Image.png")
    }

    @Test("promised types map to extensions")
    func promisedTypesMapToExtensions() {
        #expect(macDropExtension("public.jpeg") == "jpg")
        #expect(macDropExtension("com.adobe.pdf") == "pdf")
        #expect(macDropExtension("public.data") == nil)
    }

    @Test("file urls resolve to paths")
    func fileUrlsResolveToPaths() {
        #expect(macDropFilePath("file:///tmp/notes%20one.txt") == "/tmp/notes one.txt")
        #expect(macDropFilePath("https://e.com/a.png") == nil)
    }

    @Test("taken names are numbered")
    func takenNamesAreNumbered() throws {
        let dir = try #require(macDropMakeDir())
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(macDropFreeName(dir, "Image", "png") == dir.appendingPathComponent("Image.png"))
        try Data().write(to: dir.appendingPathComponent("Image.png"))
        try Data().write(to: dir.appendingPathComponent("Image 2.png"))
        #expect(macDropFreeName(dir, "Image", "png") == dir.appendingPathComponent("Image 3.png"))
    }

    @Test("text alone gives nothing")
    func textAloneGivesNothing() {
        guard let board = makeBoard([
            [("public.utf8-plain-text", Array("hello".utf8))],
            [("public.url", Array("https://e.com/".utf8))],
        ]) else { return }
        #expect(found(board.pb).isEmpty)
    }

    @Test("images are written named for their url")
    func imagesAreWrittenNamedForTheirUrl() throws {
        let png = makePng()
        guard let board = makeBoard([
            [("public.png", png)],
            [("public.png", png)],
            [("public.url", Array("https://e.com/img/kitten.jpg?w=2".utf8)), ("public.png", png)],
        ]) else { return }
        let dir = try #require(macDropMakeDir())
        defer { try? FileManager.default.removeItem(at: dir) }
        let paths: [URL] = macDropItems(board.pb).compactMap { item, f in
            if case .image(let k, let e) = f {
                return macDropWriteImage(item, k, e, dir)
            }
            return nil
        }
        let names = paths.map(\.lastPathComponent)
        #expect(names == ["Image.png", "Image 2.png", "kitten.png"])
        let bytes = try [UInt8](Data(contentsOf: paths[0]))
        #expect(bytes == png)
    }

    @Test("url stems")
    func urlStems() {
        #expect(macDropUrlStem("https://e.com/a/cat.photo.png?x=1") == "cat.photo")
        #expect(macDropUrlStem("https://e.com/") == nil)
        #expect(macDropUrlStem("https://e.com") == nil)
        #expect(macDropUrlStem("data:image/png;base64,AAAA") == nil)
    }

    @Test("the operation follows the source")
    func operationFollowsTheSource() {
        #expect(macDropOperation(1 | 2 | 16) == 1)
        #expect(macDropOperation(4) == 4)
        #expect(macDropOperation(0) == 0)
        #expect(macDropOperation(2) == 0)
    }

    @Test("moves coalesce and steps track the drag")
    func movesCoalesceAndStepsTrackTheDrag() {
        let key: UInt = 0xd0d0
        _ = macDropTakeSteps(key)
        macDropPush(key, .enter(["a"], (1.0, 1.0)))
        macDropPush(key, .move((2.0, 2.0)))
        macDropPush(key, .move((3.0, 3.0)))
        #expect(macDropOver(key))
        macDropPush(key, .drop(["a"], (3.0, 3.0)))
        #expect(!macDropOver(key))
        let steps = macDropTakeSteps(key)
        #expect(
            steps == [
                .enter(["a"], (1.0, 1.0)),
                .move((3.0, 3.0)),
                .drop(["a"], (3.0, 3.0)),
            ]
        )
    }
}
#endif
