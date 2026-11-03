// Tests ported from: crates/rune/src/open_url/incoming_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import Foundation
#endif
import Testing
@testable import Rune

@Suite
struct OpenUrlIncomingTests {
    final class FakeGlue: OpenUrlGlue {
        var elsewhere: Bool = false
        var refuse: Bool = false
        var installs: Int = 0
        var removes: Int = 0

        init(elsewhere: Bool = false, refuse: Bool = false) {
            self.elsewhere = elsewhere
            self.refuse = refuse
        }

        func handledElsewhere() -> Bool { elsewhere }
        func install() -> Bool {
            installs += 1
            return !refuse
        }
        func remove() {
            removes += 1
        }
    }

    private func makeApp() -> App<[String]> {
        let spec = AppSpec<[String]>(
            title: "links",
            size: (100.0, 100.0),
            init: { [] },
            view: { _, _ in el() }
        )
        return App.new(spec).onOpenUrl { links, url, _ in links.append(url) }
    }

    private func makePlainApp() -> App<[String]> {
        let spec = AppSpec<[String]>(
            title: "plain",
            size: (100.0, 100.0),
            init: { [] },
            view: { _, _ in el() }
        )
        return App.new(spec)
    }

    private func makeRuntime() -> Runtime<[String]> {
        Runtime<[String]>([], { _, _ in el() }, (100.0, 100.0), Env())
    }

    private func deliver(_ app: App<[String]>, _ rt: Runtime<[String]>) -> Int {
        let updates = app.handle().takeUpdates()
        for f in updates {
            _ = rt.hostUpdateIf(f)
        }
        return updates.count
    }

    @Test
    func withoutAHookNothingListensAndTheLaunchHandlerGoes() {
        let inbox = OpenUrlInbox()
        let glue = FakeGlue()
        inbox.prepare(glue)
        inbox.receive("app://kept")
        #expect(inbox.listen(makePlainApp(), glue) == nil)
        inbox.settle(glue)
        #expect(glue.installs == 1 && glue.removes == 1)
        let late = makeApp()
        inbox.receive("app://dropped")
        let listening = inbox.listen(late, glue)
        #expect(listening != nil)
        #expect(late.handle().takeUpdates().isEmpty)
        _ = listening
    }

    @Test
    func linksBeforeTheFirstWindowArriveOnceInOrderAsItStarts() {
        let inbox = OpenUrlInbox()
        let glue = FakeGlue()
        let app = makeApp()
        inbox.prepare(glue)
        inbox.receive("app://one")
        inbox.receive("app://two?x=1")
        let listening = inbox.listen(app, glue)
        #expect(listening != nil)
        inbox.settle(glue)
        let rt = makeRuntime()
        #expect(rt.state.isEmpty)
        #expect(deliver(app, rt) == 2)
        #expect(rt.state == ["app://one", "app://two?x=1"])
        #expect(rt.hostNeedsCommit())
        #expect(deliver(app, rt) == 0)
        #expect(glue.installs == 1 && glue.removes == 0)
        _ = listening
    }

    @Test
    func aLaterWindowWithTheHookGetsTheLaunchLink() {
        let inbox = OpenUrlInbox()
        let glue = FakeGlue()
        let first = makePlainApp()
        let second = makeApp()
        inbox.prepare(glue)
        inbox.receive("app://launch")
        #expect(inbox.listen(first, glue) == nil)
        let listening = inbox.listen(second, glue)
        #expect(listening != nil)
        inbox.settle(glue)
        #expect(second.handle().takeUpdates().count == 1)
        #expect(glue.removes == 0)
        _ = listening
    }

    @Test
    func linksWhileRunningWakeTheLoopAndArrive() {
        let inbox = OpenUrlInbox()
        let glue = FakeGlue()
        let app = makeApp()
        let listening = inbox.listen(app, glue)
        #expect(listening != nil)
        final class Counter: @unchecked Sendable { var value = 0 }
        let wakes = Counter()
        app.handle().connect { wakes.value += 1 }
        let before = wakes.value
        inbox.receive("app://later")
        #expect(wakes.value == before + 1)
        let rt = makeRuntime()
        #expect(deliver(app, rt) == 1)
        #expect(rt.state == ["app://later"])
        _ = listening
    }

    @Test
    func whenTheListeningWindowGoesTheNextOneTakesOver() {
        let inbox = OpenUrlInbox()
        let glue = FakeGlue()
        let first = makeApp()
        let second = makeApp()
        var listening: OpenUrlListening? = inbox.listen(first, glue)
        let secondListening = inbox.listen(second, glue)
        #expect(listening != nil && secondListening != nil)
        inbox.receive("app://a")
        listening = nil
        inbox.receive("app://b")
        #expect(first.handle().takeUpdates().count == 1)
        #expect(second.handle().takeUpdates().count == 1)
        #expect(glue.installs == 1)
        _ = secondListening
    }

    @Test
    func anAppsOwnHandlerStaysUnlessAWindowHasTheHook() {
        let inbox = OpenUrlInbox()
        let glue = FakeGlue(elsewhere: true)
        inbox.prepare(glue)
        inbox.receive("app://theirs")
        inbox.settle(glue)
        #expect(glue.installs == 0 && glue.removes == 0)
        let app = makeApp()
        let listening = inbox.listen(app, glue)
        #expect(listening != nil)
        #expect(glue.installs == 1)
        #expect(app.handle().takeUpdates().isEmpty)
        _ = listening
    }

    @Test
    func aHandlerThatCantInstallListensToNothing() {
        let inbox = OpenUrlInbox()
        let app = makeApp()
        #expect(inbox.listen(app, FakeGlue(refuse: true)) == nil)
        inbox.receive("app://dropped")
        #expect(app.handle().takeUpdates().isEmpty)
        let listening = inbox.listen(app, FakeGlue())
        #expect(listening != nil)
        _ = listening
    }

    #if os(macOS)
    @Test
    func theUrlIsTheEventsDirectObject() {
        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: 0x4755_524C,
            eventID: 0x4755_524C,
            targetDescriptor: nil,
            returnID: -1,
            transactionID: 0
        )
        #expect(macAppleEventUrlOf(event) == nil)
        let param = NSAppleEventDescriptor(string: "myapp://open?id=1")
        event.setParam(param, forKeyword: 0x2D2D_2D2D)
        #expect(macAppleEventUrlOf(event) == "myapp://open?id=1")
    }
    #endif
}
