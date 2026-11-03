// Tests ported from: crates/rune/src/platform/macos.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

#if os(macOS)
import AppKit
import CoreGraphics
import QuartzCore

@Suite("PlatformMacosTests")
struct PlatformMacosTests {
    @Test("a metal layer pins its contents to the window top left")
    func metalLayerPinsItsContentsToTheWindowTopLeft() {
        for flipped in [true, false] {
            let parent = CALayer()
            let layer = CAMetalLayer()
            parent.isGeometryFlipped = flipped
            parent.addSublayer(layer)
            macPinLayerContentsTopLeft(layer)
            #expect(layer.contentsGravity == (flipped ? .bottomLeft : .topLeft))
            #expect((layer.colorspace?.name as String?) == (CGColorSpace.sRGB as String))
        }
    }

    @Test("overlay handlerless hit releases native ownership in every input mode")
    func overlayHandlerlessHitReleasesNativeOwnershipInEveryInputMode() {
        for mode in [OverlayInput.regions, OverlayInput.none] {
            let pointer = MacOverlayPointerState(input: .regions)
            pointer.regions = [[10.0, 10.0, 30.0, 30.0]]
            pointer.recordClick(true, 20.0, 20.0)
            _ = pointer.clicks.removeFirst() // Down dispatched
            #expect(pointer.captured)
            pointer.recordClick(false, 50.0, 50.0)
            pointer.input = mode
            _ = pointer.clicks.removeFirst() // Up dispatched
            pointer.released()
            #expect(!pointer.captured)
            #expect(!pointer.hit(50.0, 50.0))
        }
    }

    @Test("a click through overlay that follows nothing never samples the pointer")
    func clickThroughOverlayThatFollowsNothingNeverSamplesThePointer() {
        let pointer = MacOverlayPointerState(input: .none)
        #expect(!pointer.wanted())
        pointer.follow = true
        #expect(pointer.wanted())
        pointer.follow = false
        pointer.captured = true
        #expect(pointer.wanted())
        pointer.captured = false
        for input in [OverlayInput.regions, OverlayInput.all] {
            pointer.input = input
            #expect(pointer.wanted())
        }
    }

    @Test("overlay lost up recovers once after grace using release position")
    func overlayLostUpRecoversOnceAfterGraceUsingReleasePosition() {
        let pointer = MacOverlayPointerState(input: .regions)
        pointer.regions.append([10.0, 10.0, 30.0, 30.0])
        pointer.recordClick(true, 20.0, 20.0)
        let now = RuneInstant.now()
        pointer.observeRelease(1, now, (40.0, 40.0))
        pointer.observeRelease(0, now, (50.0, 50.0))
        pointer.observeRelease(0, now.adding(.milliseconds(99)), (60.0, 60.0))
        #expect(pointer.captured)
        pointer.observeRelease(0, now.adding(.milliseconds(100)), (70.0, 70.0))
        #expect(!pointer.captured)
        #expect(pointer.clicks.isEmpty)
        let recovered = pointer.recoveredRelease
        pointer.recoveredRelease = nil
        #expect(recovered?.0 == 50.0 && recovered?.1 == 50.0)
        pointer.observeRelease(0, now.adding(.seconds(1)), (80.0, 80.0))
        #expect(pointer.recoveredRelease == nil)
    }

    @Test("overlay queued up and next down keep their ownership until dispatched")
    func overlayQueuedUpAndNextDownKeepTheirOwnershipUntilDispatched() {
        let pointer = MacOverlayPointerState(input: .regions)
        pointer.regions.append([10.0, 10.0, 30.0, 30.0])
        pointer.recordClick(true, 20.0, 20.0)
        pointer.recordClick(false, 100.0, 100.0)
        let now = RuneInstant.now()
        pointer.observeRelease(0, now, (100.0, 100.0))
        pointer.observeRelease(0, now.adding(.seconds(1)), (100.0, 100.0))
        #expect(pointer.captured)
        #expect(pointer.recoveredRelease == nil)
        _ = pointer.clicks.removeFirst() // Down dispatched
        _ = pointer.clicks.removeFirst() // Up dispatched
        pointer.recordClick(true, 20.0, 20.0) // next native Down queued
        pointer.released()
        #expect(pointer.captured)
        pointer.clicks.removeAll()
        pointer.released()
        #expect(!pointer.captured)
    }

    @Test("overlay undelivered click releases capture after stall")
    func overlayUndeliveredClickReleasesCaptureAfterStall() {
        let pointer = MacOverlayPointerState(input: .regions)
        pointer.regions.append([10.0, 10.0, 30.0, 30.0])
        pointer.recordClick(true, 20.0, 20.0)
        pointer.recordClick(false, 20.0, 20.0)
        let now = RuneInstant.now()
        pointer.observeRelease(0, now, (20.0, 20.0))
        pointer.observeRelease(0, now.adding(.milliseconds(1999)), (20.0, 20.0))
        #expect(pointer.captured)
        pointer.observeRelease(0, now.adding(.seconds(2)), (20.0, 20.0))
        #expect(!pointer.captured)
        #expect(pointer.clicks.isEmpty)
        #expect(!pointer.hit(50.0, 50.0))
    }

    @Test("overlay lost view releases capture where the pointer was")
    func overlayLostViewReleasesCaptureWhereThePointerWas() {
        let pointer = MacOverlayPointerState(input: .regions)
        pointer.regions.append([10.0, 10.0, 30.0, 30.0])
        pointer.last = (25.0, 15.0)
        pointer.recordClick(true, 20.0, 20.0)
        pointer.viewLost()
        #expect(!pointer.captured)
        #expect(pointer.clicks.isEmpty)
        #expect(pointer.recoveredRelease?.0 == 25.0 && pointer.recoveredRelease?.1 == 15.0)
    }

    @Test("overlay rejected down cannot poison later click and owned up survives exit")
    func overlayRejectedDownCannotPoisonLaterClickAndOwnedUpSurvivesExit() {
        let pointer = MacOverlayPointerState(input: .regions)
        pointer.regions.append([10.0, 10.0, 30.0, 30.0])
        pointer.recordClick(true, 1.0, 1.0)
        pointer.recordClick(true, 20.0, 20.0)
        pointer.recordClick(false, 100.0, 100.0)
        #expect(pointer.clicks.count == 2)
        #expect(pointer.clicks[0] == (true, 20.0, 20.0))
        #expect(pointer.clicks[1] == (false, 100.0, 100.0))
        #expect(pointer.hit(100.0, 100.0))
        pointer.captured = false
        #expect(!pointer.hit(100.0, 100.0))
    }

    @Test("overlay appkit top row belongs to secondary display")
    func overlayAppkitTopRowBelongsToSecondaryDisplay() {
        let secondary = NSRect(x: -1920.0, y: 0.0, width: 1920.0, height: 1080.0)
        #expect(macContainsAppkitRect(secondary, NSPoint(x: -100.0, y: 1080.0)))
        #expect(!macContainsAppkitRect(secondary, NSPoint(x: -100.0, y: 0.0)))
        #expect(!macContainsAppkitRect(secondary, NSPoint(x: 0.0, y: 500.0)))
        let below = NSRect(x: -1920.0, y: -1080.0, width: 1920.0, height: 1080.0)
        #expect(macContainsAppkitRect(below, NSPoint(x: -100.0, y: 0.0)))
    }
}
#endif
