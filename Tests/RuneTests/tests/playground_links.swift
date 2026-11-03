// Tests ported from: crates/rune/tests/playground_links.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private struct PgLinksReal {
    init() {}
}

private struct PgLinksUpload {
    var bytes: UInt32 = 0
}

private func pgLinksUploadView(_ u: PgLinksUpload, _: Cx<PgLinksUpload>) -> El {
    text("\(u.bytes) bytes").key("upload")
}

private final class PgLinksCounter: @unchecked Sendable {
    var count: Int = 0
}

private func pgLinksRuntime(_ counter: PgLinksCounter = PgLinksCounter()) -> Runtime<PgLinksReal> {
    let pg = Playground<PgLinksReal>.new()
        .story(
            Story.new("Timeline/Send", { PgLinksUpload() }, pgLinksUploadView)
                .variant("Small") { u in u.bytes = 10 }
                .variant("Large") { u in u.bytes = 1_000_000 }
        )
        .story(Story.new("Lists/Many devices", { PgLinksUpload() }, pgLinksUploadView))
    let spec = AppSpec.new("links", (800.0, 500.0), PgLinksReal.init) { _, _ in
        counter.count += 1
        return text("the app").key("app")
    }
    return App.new(spec).playground(pg).headlessRuntime((800.0, 500.0), Env.new(false, 1.0))
}

private func pgLinksBytes(_ rt: Runtime<PgLinksReal>) -> UInt32? {
    rt.playgroundState(PgLinksUpload.self)?.bytes
}

@Suite("PlaygroundLinksIntegrationTests")
struct PlaygroundLinksIntegrationTests {
    @Test func aSlugIsThePathLowercasedWithDashes() {
        #expect(playgroundSlug("Timeline/Send") == "timeline-send")
        #expect(playgroundSlug("Lists/Many devices") == "lists-many-devices")
        #expect(playgroundSlug("  Toasts / Sync -- toast!  ") == "toasts-sync-toast")
        #expect(playgroundSlug("Café/Crème brûlée") == "café-crème-brûlée")
        #expect(playgroundSlug("Motion/Fade 2") == "motion-fade-2")
    }

    @Test func everyLookupTakesASlug() {
        let rt = pgLinksRuntime()
        rt.openPlayground("lists-many-devices", nil)
        #expect(pgLinksBytes(rt) == 0)
        rt.openPlayground("timeline-send", "Large")
        #expect(pgLinksBytes(rt) == 1_000_000)
    }

    @Test func aLinkBeforeTheFirstFrameOpensStraightOntoTheStory() {
        let counter = PgLinksCounter()
        let rt = pgLinksRuntime(counter)
        rt.update { _, tx in tx.openPlaygroundAt("timeline-send", "Large") }
        _ = rt.frame(0.0)
        let shown = rt.playgroundElement("upload")?.text
        #expect(shown == "1000000 bytes")
        #expect(counter.count == 0)
    }

    @Test func fromAHandlerItMovesAnOpenPlaygroundToTheStory() {
        let rt = pgLinksRuntime()
        rt.openPlayground("Lists/Many devices", nil)
        rt.update { _, tx in tx.openPlaygroundAt("Send", "2") }
        _ = rt.frame(0.0)
        #expect(pgLinksBytes(rt) == 1_000_000)
    }

    @Test func anUnknownStoryOpensTheListInsteadOfStoppingTheApp() {
        let rt = pgLinksRuntime()
        rt.update { _, tx in tx.openPlaygroundAt("timeline-nope", nil) }
        _ = rt.frame(0.0)
        let hasList = rt.hostFind("playground-list") != nil
        #expect(hasList)
        #expect(pgLinksBytes(rt) == 10)
    }

    @Test func anUnknownVariantOpensTheStoryAsItWouldWithoutOne() {
        let rt = pgLinksRuntime()
        rt.update { _, tx in tx.openPlaygroundAt("Timeline/Send", "Huge") }
        _ = rt.frame(0.0)
        #expect(pgLinksBytes(rt) == 10)
    }
}
