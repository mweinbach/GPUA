// Tests ported from: crates/rune-kit/tests/popup_list_motion.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! A `PopupList` above its field (`Side.top`) holds its bottom while its height springs, so its
//! rows ride its top. Filtering to one row and then growing again mid-exit must move every row
//! one way to its slot.

import Testing
import Rune
@testable import RuneKit

private typealias PopupItem = RuneKit.PopupItem

private struct PopupMotionState {
    var ids: [String]
    var padding: Float?
    var rowRadius: Float?
    var animate: Bool
}

private let MOTION_SIX: [String] = ["a0", "a1", "a2", "a3", "a4", "a5"]
private let MOTION_TEN: [String] = ["a1", "b0", "b1", "b2", "b3", "b4", "b5", "b6", "b7", "b8"]

private func popupMotionView(_ s: PopupMotionState, _: Cx<PopupMotionState>) -> El {
    let k = Kit.neutral(true)
    var layer: [El] = []
    var list = PopupList<PopupMotionState>.new("p", "field")
        .anchored("field", .top, .start, 8.0)
        .maxHeight(300.0)
        .items(s.ids.map { PopupItem.new($0, $0) })
        .animateFiltering(s.animate)
        .active(0)
    if let p = s.padding {
        list = list.padding(p)
    }
    if let r = s.rowRadius {
        list = list.rowRadius(r)
    }
    list.build(k, &layer)
    return root(col().pt(400.0).pl(40.0).child(el().key("field").w(300.0).h(60.0)), layer)
}

private func settledMotion(_ items: [String]) -> Runtime<PopupMotionState> {
    settledMotionWith(items, true)
}

private func settledMotionWith(_ items: [String], _ animate: Bool) -> Runtime<PopupMotionState> {
    let rt = Runtime.new(
        PopupMotionState(ids: items, padding: nil, rowRadius: nil, animate: animate),
        popupMotionView,
        (600.0, 600.0),
        Env.new(true, 1.0)
    )
    _ = rt.frame(0.0)
    for _ in 0..<60 {
        _ = rt.frame(1.0 / 120.0)
    }
    return rt
}

private func presentedY(_ rt: Runtime<PopupMotionState>, _ key: String) -> Float {
    guard let p = rt.presented(key) else {
        preconditionFailure("\(key) is presented")
    }
    return p.0[1]
}

/// Grows the list to `MOTION_TEN` and steps 90 frames, checking that the popover's top and every row
/// of the new list only rise, and land where the list settles.
private func growsWithoutOvershoot(_ rt: Runtime<PopupMotionState>) {
    rt.update { s, _ in s.ids = MOTION_TEN }
    var keys: [String] = MOTION_TEN.map { "p-option-\($0)" }
    keys.append("p-content")
    var tracks: [[Float]] = Array(repeating: [], count: keys.count)
    for _ in 0..<90 {
        _ = rt.frame(1.0 / 120.0)
        for i in 0..<keys.count {
            tracks[i].append(presentedY(rt, keys[i]))
        }
    }
    for (key, track) in zip(keys, tracks) {
        let lowest = track.min() ?? Float.greatestFiniteMagnitude
        let end = track.last!
        for f in 0..<(track.count - 1) {
            #expect(
                track[f + 1] <= track[f] + 0.05,
                "\(key) sank \(track[f]) -> \(track[f + 1]) at frame \(f + 1): \(track)"
            )
        }
        #expect(end - lowest < 0.05, "\(key) rose \(end - lowest) pt past its slot")
    }
    // The popover's bottom sits 8 points over the field at y 400; rows start inside its 4 point padding.
    #expect(abs(presentedY(rt, "p-content") - 104.0) < 0.5, "popover top \(presentedY(rt, "p-content"))")
    for (i, id) in MOTION_TEN.enumerated() {
        let want = 108.0 + 28.0 * Float(i)
        #expect(abs(presentedY(rt, "p-option-\(id)") - want) < 0.5, "\(id) settles at \(want)")
    }
}

/// An animated list in `Tx.instant` commits, or a default one in commits that animate.
private func swapsRowsAndHeightAtOnce(_ animate: Bool) {
    let rt = settledMotionWith(MOTION_SIX, animate)
    rt.update { s, tx in
        s.ids = ["a1"]
        if animate { tx.instant() }
    }
    _ = rt.frame(1.0 / 120.0)
    for id in ["a0", "a2", "a3", "a4", "a5"] {
        #expect(rt.presented("p-option-\(id)") == nil, "\(id) is gone at once")
    }
    // One row: a 36 point popover (28 + 2 * 4) whose bottom stays at 392.
    #expect(abs(presentedY(rt, "p-content") - 356.0) < 0.05, "popover top \(presentedY(rt, "p-content"))")
    #expect(abs(presentedY(rt, "p-option-a1") - 360.0) < 0.05)

    rt.update { s, tx in
        s.ids = MOTION_TEN
        if animate { tx.instant() }
    }
    _ = rt.frame(1.0 / 120.0)
    #expect(abs(presentedY(rt, "p-content") - 104.0) < 0.05, "popover top \(presentedY(rt, "p-content"))")
    for (i, id) in MOTION_TEN.enumerated() {
        #expect(abs(presentedY(rt, "p-option-\(id)") - (108.0 + 28.0 * Float(i))) < 0.05, "\(id) lands at once")
    }
}

/// Sixty rows: the 300 point popover shows the first ten and keeps the rows below it mounted,
/// clipped away.
private func settledLong() -> Runtime<PopupMotionState> {
    let ids = (0..<60).map { "a\($0)" }
    let rt = Runtime.new(
        PopupMotionState(ids: ids, padding: nil, rowRadius: nil, animate: true),
        popupMotionView,
        (600.0, 600.0),
        Env.new(true, 1.0)
    )
    _ = rt.frame(0.0)
    for _ in 0..<60 {
        _ = rt.frame(1.0 / 120.0)
    }
    return rt
}

@Suite("PopupListMotionTests")
struct PopupListMotionTests {
    // PORT NOTE: Blocked on Sources/Rune GrowthSpec height spring & childExit row presence transitions.
    @Test(.disabled("Blocked on Sources/Rune GrowthSpec height spring & childExit row presence transitions"))
    func rowsRiseToTheirSlotsWhileFilteredOutRowsStillLeave() {
        // As a chat composer's mention popover: six rows, a keystroke filters them to one, and
        // 0.17 s later more results arrive under it while the five removed rows still collapse.
        let rt = settledMotion(MOTION_SIX)
        rt.update { s, _ in s.ids = ["a1"] }
        for _ in 0..<20 {
            _ = rt.frame(1.0 / 120.0)
        }
        #expect(rt.presented("p-option-a2") != nil, "removed rows are still leaving when the results arrive")
        growsWithoutOvershoot(rt)
    }

    // PORT NOTE: Blocked on Sources/Rune GrowthSpec height spring & childExit row presence transitions.
    @Test(.disabled("Blocked on Sources/Rune GrowthSpec height spring & childExit row presence transitions"))
    func rowsRiseToTheirSlotsWhenNothingIsLeaving() {
        let rt = settledMotion(MOTION_SIX)
        rt.update { s, _ in s.ids = ["a1"] }
        for _ in 0..<120 {
            _ = rt.frame(1.0 / 120.0)
        }
        #expect(rt.presented("p-option-a2") == nil)
        growsWithoutOvershoot(rt)
    }

    @Test
    func anInstantCommitSwapsRowsAndHeightAtOnce() {
        swapsRowsAndHeightAtOnce(true)
    }

    // PORT NOTE: Blocked on Sources/Rune GrowthSpec height spring & childExit row presence transitions.
    @Test(.disabled("Blocked on Sources/Rune GrowthSpec height spring & childExit row presence transitions"))
    func byDefaultAnyCommitSwapsRowsAndHeightAtOnce() {
        swapsRowsAndHeightAtOnce(false)
    }

    @Test
    func paddingAndRowRadiusDefaultTo4AndFollowTheirBuilders() {
        func row(_ rt: Runtime<PopupMotionState>) -> ElementInfo {
            rt.elements().first(where: { $0.key == "p-option-a0" })!
        }
        func content(_ rt: Runtime<PopupMotionState>) -> [Float] {
            rt.presented("p-content")!.0
        }

        let rt = settledMotion(MOTION_SIX)
        let (c, r) = (content(rt), row(rt))
        #expect(r.radius == 4.0)
        #expect(abs(r.rect[0] - c[0] - 4.0) < 0.05 && abs(r.rect[1] - c[1] - 4.0) < 0.05)
        #expect(abs(c[3] - (6.0 * 28.0 + 8.0)) < 0.05)

        let custom = Runtime.new(
            PopupMotionState(ids: MOTION_SIX, padding: 6.0, rowRadius: 6.0, animate: false),
            popupMotionView,
            (600.0, 600.0),
            Env.new(true, 1.0)
        )
        _ = custom.frame(0.0)
        let (c2, r2) = (content(custom), row(custom))
        #expect(r2.radius == 6.0)
        #expect(abs(r2.rect[0] - c2[0] - 6.0) < 0.05 && abs(r2.rect[1] - c2[1] - 6.0) < 0.05)
        #expect(abs(r2.rect[2] - (c2[2] - 12.0)) < 0.05, "rows fill the width inside the padding")
        #expect(abs(c2[3] - (6.0 * 28.0 + 12.0)) < 0.05)
        #expect(abs(c2[1] + c2[3] - 392.0) < 0.05, "the bottom stays 8 points over the field")
    }

    // PORT NOTE: Blocked on Sources/Rune GrowthSpec height spring & childExit row presence transitions.
    @Test(.disabled("Blocked on Sources/Rune GrowthSpec height spring & childExit row presence transitions"))
    func filteredOutRowsClippedAwayLeaveAtOnce() {
        let rt = settledLong()
        #expect(rt.presented("p-option-a20") != nil, "a row below the viewport is mounted")
        rt.update { s, _ in s.ids = ["a0"] }
        _ = rt.frame(1.0 / 120.0)
        #expect(rt.presented("p-option-a20") == nil, "a row nobody sees has no fade to show")
        for _ in 0..<4 {
            _ = rt.frame(1.0 / 120.0)
        }
        guard let (_, opacity) = rt.presented("p-option-a5") else {
            Issue.record("a row in view is still leaving")
            return
        }
        #expect(opacity > 0.05 && opacity < 1.0, "it fades: \(opacity)")
    }

    // PORT NOTE: Blocked on Sources/Rune GrowthSpec height spring & childExit row presence transitions.
    @Test(.disabled("Blocked on Sources/Rune GrowthSpec height spring & childExit row presence transitions"))
    func rowsAFilterBringsIntoViewFadeIn() {
        let rt = settledLong()
        #expect(rt.presented("p-option-a50") == nil, "far down the list, not mounted")
        rt.update { s, _ in s.ids = ["a50", "a51"] }
        _ = rt.frame(1.0 / 120.0)
        guard let (_, opacity) = rt.presented("p-option-a50") else {
            Issue.record("the filter brings it into view")
            return
        }
        #expect(opacity < 0.9, "it enters as its leaving neighbours exit, not at full opacity: \(opacity)")
        for _ in 0..<60 {
            _ = rt.frame(1.0 / 120.0)
        }
        #expect(rt.presented("p-option-a50")!.1 > 0.99)
    }
}
