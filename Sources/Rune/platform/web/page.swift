// Ported from: crates/rune/src/platform/web/page.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! What a web app holds of the page while it runs, and gives back when it ends: the event loop,
//! a canvas the page passed in, the body's style and the document title. An app started while the
//! running one is quitting starts once it has gone, so a route can unmount Rune and mount it again
//! in the same tick.

typealias WebQuitting = @Sendable () -> Bool
typealias WebStart = @Sendable () -> Result<Void, WebPlatformError>

private struct WebPage {
    /// The running app's "a quit is on its way".
    var live: WebQuitting? = nil
    /// The app to start once the running one has gone.
    var next: (WebQuitting, WebStart)? = nil
    var router: (@Sendable (String) -> Bool)? = nil
}

private let webPageLock = LiveLock()
// PORT NOTE: Access to `webPageGlobal` is serialized via `webPageLock` (matching Rust `thread_local! PAGE`).
nonisolated(unsafe) private var webPageGlobal = WebPage()

let webPageBusyMessage = "a Rune app is already running on this page; call its AppHandle::quit before starting another"

/// Starts an app now if the page is free, or once the running app (asked to quit) has gone.
/// `quitting` reports whether the new app was itself asked to quit before it started.
func webPageStart(_ quitting: @escaping WebQuitting, _ start: @escaping WebStart) -> Result<Void, WebPlatformError> {
    let outcome: Result<WebStart?, WebPlatformError> = webPageLock.withLock {
        let ahead = (webPageGlobal.next?.0 ?? webPageGlobal.live).map { $0() }
        switch ahead {
        case nil:
            return .success(start)
        case true?:
            webPageGlobal.next = (quitting, start)
            return .success(nil)
        case false?:
            return .failure(WebPlatformError(webPageBusyMessage))
        }
    }
    switch outcome {
    case .failure(let err):
        return .failure(err)
    case .success(let now):
        if let now {
            return now()
        }
        return .success(())
    }
}

/// The event loop for `quitting`'s app started.
func webPageOccupy(_ quitting: @escaping WebQuitting, _ router: (@Sendable (String) -> Bool)?) {
    webPageLock.withLock {
        webPageGlobal.live = quitting
        webPageGlobal.router = router
    }
}

/// The running app's event loop is ending. A queued app starts after this turn.
func webPageVacate() {
    let next: (WebQuitting, WebStart)? = webPageLock.withLock {
        webPageGlobal.live = nil
        webPageGlobal.router = nil
        let queued = webPageGlobal.next
        webPageGlobal.next = nil
        return queued
    }
    if let (_, start) = next {
        if case .failure(let err) = start() {
            webReportError(err.message, embedded: false)
        }
    }
}

/// The running app's `App.sameTabRouter`, which routed `href` when it returns true.
func webPageRoute(_ href: String) -> Bool {
    let router = webPageLock.withLock { webPageGlobal.router }
    return router?(href) ?? false
}

func webPageResetForTest() {
    webPageLock.withLock {
        webPageGlobal = WebPage()
    }
}

/// The attributes Rune sets on a borrowed canvas.
let webCanvasAttributes: [String] = ["tabindex", "alt", "width", "height"]

/// What Rune changed on the page, to put back when the app ends.
struct WebBorrowed: Sendable, Equatable {
    var canvasCss: String? = nil
    var canvasAttributes: [(String, String?)] = []
    var bodyCss: String? = nil
    var title: String? = nil

    init() {}

    mutating func rememberCanvas(css: String, attributes: [(String, String?)]) {
        self.canvasCss = css
        self.canvasAttributes = attributes
    }

    mutating func rememberViewport(bodyCss: String?, title: String) {
        self.bodyCss = bodyCss
        self.title = title
    }

    func giveBack() {
        if let title {
            webPlatformSetDocumentTitle(title)
        }
    }

    static func == (lhs: WebBorrowed, rhs: WebBorrowed) -> Bool {
        guard lhs.canvasCss == rhs.canvasCss,
              lhs.bodyCss == rhs.bodyCss,
              lhs.title == rhs.title,
              lhs.canvasAttributes.count == rhs.canvasAttributes.count
        else {
            return false
        }
        for (a, b) in zip(lhs.canvasAttributes, rhs.canvasAttributes) {
            if a.0 != b.0 || a.1 != b.1 { return false }
        }
        return true
    }
}
