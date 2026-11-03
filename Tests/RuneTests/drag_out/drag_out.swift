// Tests ported from: crates/rune/src/drag_out/mod.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite struct DragOutTests {
    @Test func thresholdIsStraightLineTravelBeyondPlatformDistance() {
        let t = DRAG_THRESHOLD
        #expect(!pastDragThreshold((10.0, 10.0), (10.0, 10.0), t))
        #expect(!pastDragThreshold((10.0, 10.0), (10.0 + t, 10.0), t))
        #expect(pastDragThreshold((10.0, 10.0), (10.0 + t + 0.1, 10.0), t))
        let d = t * 0.75
        #expect(pastDragThreshold((0.0, 0.0), (d, d), t))
    }

    @Test func dragItemCollectsFilesImageAndText() {
        let item = DragItem.new().file("/a.png").file("/b.txt").text("hello").png([1, 2, 3])
        #expect(item.paths() == ["/a.png", "/b.txt"])
        #expect(item.plainText() == "hello")
        #expect(item.pngData() == [1, 2, 3])
        #expect(!item.allowsMove() && item.dragImage() == nil && !item.isEmpty())
        #expect(DragItem.new().isEmpty())
        #expect(DragItem.new().allowMove().allowsMove())
    }

    @Test func dragOffersCopyUnlessToldOtherwise() {
        let item = DragItem.new()
        #expect(item.offers(.copy) && !item.offers(.move) && !item.offers(.link))
        let m1 = DragItem.new().allowMove()
        #expect(m1.offers(.copy) && m1.offers(.move))
        let m2 = DragItem.new().operation(.move)
        #expect(!m2.offers(.copy) && m2.offers(.move) && m2.allowsMove())
        let m3 = DragItem.new().operation(.link).allow(.copy)
        #expect(m3.offers(.copy) && m3.offers(.link) && !m3.offers(.move))
    }

    @Test func dragImageFramesStartOverElementOrUnderPointer() {
        let rect: [Float] = [20.0, 40.0, 200.0, 32.0]
        let press: (Float, Float) = (50.0, 60.0)
        let image = DragImage.rgba(1, 1, [0, 0, 0, 0])!
        #expect(image.frame(rect, press, (64.0, 64.0)) == [18.0, 28.0, 64.0, 64.0])
        #expect(image.size(10.0, 20.0).frame(rect, press, (64.0, 64.0)) == [45.0, 50.0, 10.0, 20.0])
        #expect(image.overElement().frame(rect, press, (64.0, 64.0)) == rect)
        #expect(image.size(10.0, 12.0).overElement().frame(rect, press, (64.0, 64.0)) == [20.0, 40.0, 10.0, 12.0])
        #expect(image.overElement().frame([5.0, 5.0, 0.0, 0.0], press, (1.0, 1.0)) == [5.0, 5.0, 1.0, 1.0])
    }

    @Test func snapshotFrameIsItsPixelAlignedCrop() {
        var image = DragImage.rgba(41, 21, [UInt8](repeating: 0, count: 41 * 21 * 4))!.size(20.5, 10.5)
        image.placement = .at(10.0, 5.0)
        #expect(image.frame([10.2, 5.3, 20.0, 10.0], (0.0, 0.0), (41.0, 21.0)) == [10.0, 5.0, 20.5, 10.5])
    }

    @Test func opaqueBackingFillsTransparentPixelsAndKeepsOpaqueOnes() {
        let image = DragImage.rgba(3, 1, [255, 0, 0, 255, 0, 0, 0, 0, 255, 255, 255, 128])!
            .size(3.0, 1.0)
            .overElement()
        let flat = image.over(Color(r: 0.0, g: 0.0, b: 1.0, a: 1.0))!
        #expect(flat.points()?.0 == 3.0 && flat.points()?.1 == 1.0)
        #expect(flat.placement == .element)
        let decoded = decodePng(flat.pngData())!
        #expect(Array(decoded.rgba[0..<4]) == [255, 0, 0, 255])
        #expect(Array(decoded.rgba[4..<8]) == [0, 0, 255, 255])
        let half = Array(decoded.rgba[8..<12])
        #expect(half[3] == 255)
        #expect(half[0] == half[1] && half[0] > 150 && half[2] == 255)
    }

    @Test func pictureIsItemsImageElseSnapshotOverBacking() {
        let snap = DragImage.rgba(1, 1, [0, 0, 0, 0])!
        let own = DragImage.rgba(1, 1, [1, 2, 3, 255])!
        #expect(dragPicture(DragItem.new(), snap) == snap)
        #expect(dragPicture(DragItem.new().image(own), snap) == own)
        #expect(dragPicture(DragItem.new(), nil) == nil)
        let flat = dragPicture(DragItem.new().opaque(.WHITE), snap)!
        let decoded = decodePng(flat.pngData())!
        #expect(decoded.rgba == [255, 255, 255, 255])
    }

    @Test func rgbaEncodesPngAndRejectsWrongLength() {
        let item = DragItem.new().rgba(1, 1, [255, 0, 0, 255])
        let png = item.pngData()!
        #expect(Array(png[1..<4]) == [0x50, 0x4E, 0x47])
        #expect(DragItem.new().rgba(2, 2, [0, 0, 0, 0]).pngData() == nil)
        #expect(DragImage.rgba(0, 0, []) == nil)
        let pts = DragImage.rgba(1, 1, [0, 0, 0, 0])!.size(8.0, 8.0).points()
        #expect(pts?.0 == 8.0 && pts?.1 == 8.0)
    }

    @Test func snapshotCropClampsToFrameInDevicePixels() {
        #expect(dragSnapshotCrop([10.0, 5.0, 20.0, 10.0], 2.0, (400, 300)) == [20, 10, 40, 20])
        #expect(dragSnapshotCrop([-5.0, -5.0, 10.0, 10.0], 2.0, (400, 300)) == [0, 0, 10, 10])
        #expect(dragSnapshotCrop([190.0, 0.0, 50.0, 10.0], 2.0, (400, 300)) == [380, 0, 20, 20])
        #expect(dragSnapshotCrop([500.0, 0.0, 10.0, 10.0], 2.0, (400, 300)) == nil)
    }

    @Test func readbackUnpremultipliesAndSwapsBgra() {
        var p: [UInt8] = [0, 0, 128, 128, 10, 20, 30, 255]
        dragToStraightRgba(&p, true)
        #expect(p == [255, 0, 0, 128, 30, 20, 10, 255])
    }
}
