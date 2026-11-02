// Tests ported from: crates/rune-mac/src/notify_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import Foundation
import ObjectiveC
import Testing
@testable import RuneMac

@objc(RuneMacFakeResponse)
private final class RuneMacFakeResponse: NSObject {
    @objc var notification: AnyObject { self }
    @objc var request: AnyObject { self }
    @objc var content: AnyObject { self }
    @objc var identifier: String { "n-7" }
    @objc var userInfo: NSDictionary {
        [
            "session": "ses_7",
            "server": "http://127.0.0.1:4096",
        ]
    }
}

private final class ClickCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [RuneMac.Click] = []
    private var doneFlag = false

    func append(_ click: RuneMac.Click) {
        lock.lock()
        items.append(click)
        lock.unlock()
    }

    func markDone() {
        lock.lock()
        doneFlag = true
        lock.unlock()
    }

    var clicks: [RuneMac.Click] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }

    var isDone: Bool {
        lock.lock()
        defer { lock.unlock() }
        return doneFlag
    }
}

@Test
func a_bare_test_binary_cannot_post() {
    // Not a .app bundle, so it never reaches UNUserNotificationCenter (which would throw).
    #expect(!notify.available())
    #expect(!notify.post(notify.Notification.new("n-1", "Response ready").body("Fix the build")))
    notify.remove(["n-1"])
}

@Test
func click_reads_user_info() {
    let click = notify.Click(id: "n-1", info: [("session", "ses_1")])
    #expect(click.get("session") == "ses_1")
    #expect(click.get("server") == nil)
}

/// The delegate's click method, called the way UNUserNotificationCenter calls it, with a stand-in
/// response that answers `notification`, `request`, `content`, `identifier` and `userInfo`.
@Test
func a_click_reaches_the_handler_and_completes() {
    let collector = ClickCollector()
    ClickHandlerRegistry.shared.set { click in
        collector.append(click)
    }
    defer {
        ClickHandlerRegistry.shared.set(nil)
    }

    let completionBlock: @convention(block) () -> Void = {
        collector.markDone()
    }

    autoreleasepool {
        let response = RuneMacFakeResponse()
        let cls: AnyClass = RuneMacNotificationDelegate.registeredClass
        let delegate = RuneMacNotificationDelegate()
        let selector = NSSelectorFromString("userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:")
        guard let imp = class_getMethodImplementation(cls, selector) else {
            Issue.record("Missing userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler: implementation")
            return
        }
        typealias DidReceiveIMP = @convention(c) (
            AnyObject,
            Selector,
            AnyObject?,
            AnyObject,
            @convention(block) () -> Void
        ) -> Void
        let fn = unsafeBitCast(imp, to: DidReceiveIMP.self)
        fn(delegate, selector, nil, response, completionBlock)
    }

    let got = collector.clicks
    #expect(got.count == 1)
    if let first = got.first {
        #expect(first.id == "n-7")
        #expect(first.get("session") == "ses_7")
        #expect(first.get("server") == "http://127.0.0.1:4096")
        #expect(first.info.count == 2)
    }
    #expect(collector.isDone, "the completion handler runs")
}
#endif
