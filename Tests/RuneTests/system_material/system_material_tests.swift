// Tests ported from: crates/rune/src/system_material/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import RuneMotion
#if os(macOS)
import AppKit
import QuartzCore
#endif
@testable import Rune

@Suite("SystemMaterialTests")
struct SystemMaterialTests {
    @Test("native_frames_are_points_from_the_top_left")
    func nativeFramesArePointsFromTheTopLeft() {
        let draw = MaterialDraw(
            id: NodeId(1),
            material: .glass,
            rect: [20.0, 40.0, 200.0, 100.0],
            radius: 24.0,
            continuous: false,
            opacity: 1.0
        )
        let (pts2, rad2) = draw.points(2.0)
        #expect(pts2 == [10.0, 20.0, 100.0, 50.0] && rad2 == 12.0)
        let (pts1, rad1) = draw.points(1.0)
        #expect(pts1 == [20.0, 40.0, 200.0, 100.0] && rad1 == 24.0)
    }

    @Test("one_radius_is_the_largest_corner_within_half_the_shorter_side")
    func oneRadiusIsLargestCornerWithinHalfShorterSide() {
        #expect(system_material.clampRadius([8.0, 6.0, 4.0, 0.0], 100.0, 40.0) == 8.0)
        #expect(system_material.clampRadius([8.0, 30.0, 4.0, 0.0], 100.0, 40.0) == 20.0)
        #expect(system_material.clampRadius([500.0, 500.0, 500.0, 500.0], 30.0, 90.0) == 15.0)
        #expect(system_material.clampRadius([-4.0, -4.0, -4.0, -4.0], 30.0, 90.0) == 0.0)
        #expect(system_material.clampRadius([12.0, 12.0, 12.0, 12.0], 0.0, 90.0) == 0.0)
    }

    @Test("fallback_keeps_a_fill_and_tints_without_one")
    func fallbackKeepsFillAndTintsWithoutOne() {
        let red = Color(1.0, 0.0, 0.0, 0.5)
        #expect(system_material.fallbackFill(red, true) == red)
        let clearRed = Color(1.0, 0.0, 0.0, 0.0)
        let dark = system_material.fallbackFill(clearRed, true)
        let light = system_material.fallbackFill(clearRed, false)
        #expect(dark.a > 0.9 && light.a > 0.9)
        #expect(dark.r < 0.3 && light.r > 0.9)
    }

    @Test("mode_reads_the_environment_value")
    func modeReadsEnvironmentValue() {
        #expect(system_material.Mode.parse(nil) == .synced)
        #expect(system_material.Mode.parse("legacy") == .legacy)
        #expect(system_material.Mode.parse(" unsynced ") == .unsynced)
        #expect(system_material.Mode.parse("off") == .off)
        #expect(system_material.Mode.parse("0") == .off)
        #expect(system_material.Mode.parse("anything") == .synced)
    }

    @Test("views_follow_their_element_across_insertions_and_unmounts")
    func viewsFollowTheirElementAcrossInsertionsAndUnmounts() {
        let (a, b, c) = (NodeId(1), NodeId(2), NodeId(3))
        // A popover inserted before the glass leaves the glass on its view and gets a new one.
        #expect(system_material.assign([(.glass, a)], [(.popover, b), (.glass, a)]) == [nil, 0])
        // Unmounting the first of two leaves the second on its own view.
        #expect(system_material.assign([(.glass, a), (.glass, b)], [(.glass, b)]) == [1])
        // A new element reuses a spare view of its material, or one freed this frame, never another material's.
        #expect(system_material.assign([(.glass, nil), (.popover, nil)], [(.popover, c)]) == [1])
        #expect(system_material.assign([(.glass, a)], [(.glass, c)]) == [0])
        #expect(system_material.assign([(.glass, a)], [(.popover, a)]) == [nil])
        // An element's own view wins over an earlier draw that could also take it.
        #expect(system_material.assign([(.glass, a), (.glass, b)], [(.glass, c), (.glass, a)]) == [1, 0])
    }

    @Test("a_window_move_never_turns_off_transactions_materials_need")
    func windowMoveNeverTurnsOffTransactionsMaterialsNeed() {
        var flag = PresentFlag()
        #expect(flag.materials(true) == true)
        #expect(flag.moving(true) == nil)
        #expect(flag.moving(false) == nil)
        #expect(flag.materials(false) == false)
        #expect(flag.moving(true) == true)
        #expect(flag.materials(true) == nil)
        #expect(flag.materials(false) == nil)
        #expect(flag.moving(false) == false)
        #expect(flag.moving(false) == nil)
    }

    @Test("a_live_resize_keeps_transactions_on_until_it_ends")
    func liveResizeKeepsTransactionsOnUntilItEnds() {
        var flag = PresentFlag()
        #expect(flag.live(true) == true)
        #expect(flag.moving(false) == nil)
        #expect(flag.materials(false) == nil)
        #expect(flag.live(true) == nil)
        #expect(flag.live(false) == false)
        #expect(flag.materials(true) == true)
        #expect(flag.live(true) == nil)
        #expect(flag.live(false) == nil)
    }

    #if os(macOS)
    @Test("live_resize_end_notification_turns_off_transactions_unless_materials_or_move_need_them")
    func liveResizeEndNotificationTurnsOffTransactions() {
        let window = NSObject()
        let layer = CAMetalLayer()
        let flag = PresentFlagCell()
        let token = watchLiveEnd(window: window, layer: layer, flag: flag)
        defer { unwatchLiveEnd(token) }

        func postEnd() {
            NotificationCenter.default.post(
                name: NSNotification.Name("NSWindowDidEndLiveResizeNotification"),
                object: window
            )
        }

        #expect(flag.update({ $0.live(true) }) == true)
        layer.presentsWithTransaction = true
        #expect(layer.presentsWithTransaction)
        postEnd()
        #expect(!layer.presentsWithTransaction, "NSWindowDidEndLiveResizeNotification turns off transactions when idle")

        // When materials also need transactions, ending live resize keeps the layer synced until materials stop.
        #expect(flag.update({ $0.materials(true) }) == true)
        #expect(flag.update({ $0.live(true) }) == nil)
        layer.presentsWithTransaction = true
        postEnd()
        #expect(layer.presentsWithTransaction, "materials keep transactions on after live resize ends")
        #expect(flag.update({ $0.materials(false) }) == false)
    }

    @MainActor
    @Test("RuneMaterialHost is flipped and transparent to hit testing")
    func runeMaterialHostIsFlippedAndHitTestTransparent() {
        let host = RuneMaterialHost(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        #expect(host.isFlipped)
        #expect(host.hitTest(NSPoint(x: 50, y: 50)) == nil)
    }
    #endif
}
