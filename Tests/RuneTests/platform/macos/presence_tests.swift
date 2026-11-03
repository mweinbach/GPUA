// Tests ported from: crates/rune/src/platform/macos/presence_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("MacOverlayPresenceTests")
struct MacOverlayPresenceTests {
    @Test("a prewarmed panel is not excluded until it shows")
    func prewarmedPanelIsNotExcludedUntilItShows() {
        var p = MacOverlayPresence.new(true)
        #expect(p.requested() && !p.excluded())
        let g = p.show()
        #expect(p.excluded())
        #expect(p.fadeDone(g, false) == true)
        #expect(p.excluded())
    }

    @Test("a hide without a fade drops the exclusion at once")
    func hideWithoutAFadeDropsTheExclusionAtOnce() {
        var p = MacOverlayPresence.new(true)
        p.show()
        p.hide(false)
        #expect(!p.excluded() && p.requested())
    }

    @Test("a fading hide keeps the exclusion until its fade finishes")
    func fadingHideKeepsTheExclusionUntilItsFadeFinishes() {
        var p = MacOverlayPresence.new(true)
        p.show()
        let g = p.hide(true)
        #expect(p.excluded())
        #expect(p.fadeDone(g, true) == true)
        #expect(!p.excluded())
    }

    @Test("a show during a fade out wins")
    func showDuringAFadeOutWins() {
        var p = MacOverlayPresence.new(true)
        p.show()
        let out = p.hide(true)
        let back = p.show()
        #expect(p.fadeDone(out, true) == false)
        #expect(p.excluded())
        #expect(p.fadeDone(back, false) == true)
        #expect(p.excluded())
    }

    @Test("a show fade completing after a hide changes nothing")
    func showFadeCompletingAfterAHideChangesNothing() {
        var p = MacOverlayPresence.new(true)
        let shown = p.show()
        p.hide(false)
        #expect(p.fadeDone(shown, false) == false)
        #expect(!p.excluded())
    }

    @Test("a toggle while hidden waits for the next show")
    func toggleWhileHiddenWaitsForTheNextShow() {
        var p = MacOverlayPresence.new(false)
        p.request(true)
        #expect(p.requested() && !p.excluded())
        p.show()
        #expect(p.excluded())
        p.request(false)
        #expect(!p.excluded())
        p.hide(false)
        p.request(true)
        p.request(false)
        p.show()
        #expect(!p.excluded())
    }

    @Test("excluded iff shown and requested across every sequence")
    func excludedIffShownAndRequestedAcrossEverySequence() {
        enum Step {
            case show
            case hide
            case hideFading
            case finishFade
            case request(Bool)
        }
        let steps: [Step] = [.show, .hide, .hideFading, .finishFade, .request(true), .request(false)]
        var seq = [0, 0, 0, 0, 0]
        while true {
            for start in [false, true] {
                var p = MacOverlayPresence.new(start)
                var shown = false
                var requested = start
                var pending: (UInt64, Bool)? = nil
                for idx in seq {
                    switch steps[idx] {
                    case .show:
                        pending = (p.show(), false)
                        shown = true
                    case .hide:
                        p.hide(false)
                        pending = nil
                        shown = false
                    case .hideFading:
                        pending = (p.hide(true), true)
                    case .finishFade:
                        if let (g, hiding) = pending {
                            pending = nil
                            #expect(p.fadeDone(g, hiding) == true)
                            if hiding {
                                shown = false
                            }
                        }
                    case .request(let on):
                        p.request(on)
                        requested = on
                    }
                    #expect(p.excluded() == (shown && requested))
                    #expect(p.requested() == requested)
                }
            }
            guard let pos = seq.lastIndex(where: { $0 + 1 < steps.count }) else { break }
            seq[pos] += 1
            for k in (pos + 1)..<seq.count {
                seq[k] = 0
            }
        }
    }
}
