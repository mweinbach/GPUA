// Tests ported from: crates/rune/src/drag_out/macos.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

#if os(macOS)
import AppKit

@Suite struct DragOutMacOSTests {
    @Test func maskOffersWhatItemAllows() {
        #expect(dragMacMask(DragItem.new()) == .copy)
        #expect(dragMacMask(DragItem.new().allowMove()) == [.copy, .move])
        #expect(dragMacMask(DragItem.new().operation(.move)) == .move)
        #expect(dragMacMask(DragItem.new().operation(.link).allow(.copy)) == [.link, .copy])
    }

    @Test func nothingIsOfferedToAppsOwnWindows() {
        let m: NSDragOperation = [.copy, .link]
        #expect(dragMacMaskIn(m, .outsideApplication) == m)
        #expect(dragMacMaskIn(m, .withinApplication).isEmpty)
    }

    @Test func modifierKeysOnlyCountWhenSeveralOperationsAreOffered() {
        #expect(dragMacSingle(dragMacMask(DragItem.new())))
        #expect(!dragMacSingle(dragMacMask(DragItem.new().allow(.link))))
        #expect(!dragMacSingle(dragMacMask(DragItem.new().allowMove())))
    }

    @Test func operationsMapToOutcomes() {
        #expect(dragMacOutcome(.copy) == .copied)
        #expect(dragMacOutcome(.move) == .moved)
        #expect(dragMacOutcome(.delete) == .moved)
        #expect(dragMacOutcome(.generic) == .moved)
        #expect(dragMacOutcome(.link) == .linked)
        #expect(dragMacOutcome([]) == .cancelled)
    }

    @Test func sessionThatNeverEndedReportsCancelledOnceOnDrop() {
        var log: [DragOutcome] = []
        do {
            _ = DragMacSessionIvars(done: { log.append($0) }, mask: .copy)
        }
        #expect(log == [.cancelled])
    }

    @Test func endedSessionDoesNotReportAgainOnDrop() {
        var log: [DragOutcome] = []
        do {
            let ivars = DragMacSessionIvars(done: { log.append($0) }, mask: .copy)
            ivars.finish(.copy)
        }
        #expect(log == [.copied])
    }
}
#endif
