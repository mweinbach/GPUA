// Tests ported from: crates/rune/src/platform/reopen.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("ReopenTests")
struct ReopenTests {
    private func window(_ visible: Bool, _ hiddenAt: UInt64?) -> ReopenCandidate {
        ReopenCandidate(
            reopenable: true,
            visible: visible,
            minimized: false,
            hiddenAt: hiddenAt,
            main: false
        )
    }

    @Test("reopening shows the window hidden last")
    func reopeningShowsTheWindowHiddenLast() {
        var mainWin = window(false, 1)
        mainWin.main = true
        let windows = [mainWin, window(false, 3), window(false, 2)]
        #expect(!reopenHasVisible(windows))
        #expect(reopenTarget(windows) == 1)
    }

    @Test("a visible window leaves reopening alone")
    func visibleWindowLeavesReopeningAlone() {
        let windows = [window(true, nil), window(false, 5)]
        #expect(reopenHasVisible(windows))
        #expect(reopenTarget(windows) == nil)
    }

    @Test("a minimized window comes back first")
    func minimizedWindowComesBackFirst() {
        var mini = window(false, nil)
        mini.minimized = true
        let windows = [window(false, 9), mini]
        #expect(reopenTarget(windows) == 1)
    }

    @Test("without a hidden window the main window shows")
    func withoutAHiddenWindowTheMainWindowShows() {
        var mainWin = window(false, nil)
        mainWin.main = true
        let windows = [window(false, nil), mainWin]
        #expect(reopenTarget(windows) == 1)
    }

    @Test("panels and closed windows never come back or count as visible")
    func panelsAndClosedWindowsNeverComeBackOrCountAsVisible() {
        var panel = window(true, 7)
        panel.reopenable = false
        var closed = window(false, 8)
        closed.reopenable = false
        closed.main = true
        #expect(!reopenHasVisible([panel, closed]))
        #expect(reopenTarget([panel, closed]) == nil)
        #expect(reopenTarget([panel, closed, window(false, 1)]) == 2)
    }

    @Test("appkit handles a reopen unless rune brings a window back")
    func appkitHandlesAReopenUnlessRuneBringsAWindowBack() {
        #expect(reopenAppkitHandles(true, true))
        #expect(!reopenAppkitHandles(true, false))
        #expect(reopenAppkitHandles(false, false))
    }

    @Test("stamps count up")
    func stampsCountUp() {
        let a = reopenStamp()
        let b = reopenStamp()
        #expect(b > a)
    }
}
