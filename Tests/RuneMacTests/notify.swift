// Tests ported from: crates/rune-mac/src/notify.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import Foundation
import ObjectiveC
import Testing
@testable import RuneMac

@Test
func notification_builder_preserves_fields_and_equality() {
    let a = notify.Notification.new("build-1", "Build finished")
        .body("All targets passed")
        .info("workspace", "GPUA")
        .info("target", "RuneMac")
    let b = notify.Notification.new("build-1", "Build finished")
        .body("All targets passed")
        .info("workspace", "GPUA")
        .info("target", "RuneMac")
    #expect(a == b)
    #expect(a.id == "build-1")
    #expect(a.title == "Build finished")
    #expect(a.bodyText == "All targets passed")
    #expect(a.userInfo.count == 2)
}

@Test
func delegate_will_present_returns_list_and_banner_options() {
    let cls: AnyClass = RuneMacNotificationDelegate.registeredClass
    let delegate = RuneMacNotificationDelegate()
    let selector = NSSelectorFromString("userNotificationCenter:willPresentNotification:withCompletionHandler:")
    guard let imp = class_getMethodImplementation(cls, selector) else {
        Issue.record("Missing userNotificationCenter:willPresentNotification:withCompletionHandler: implementation")
        return
    }
    var receivedOptions: UInt = 0
    let completionBlock: @convention(block) (UInt) -> Void = { opts in
        receivedOptions = opts
    }
    typealias WillPresentIMP = @convention(c) (
        AnyObject,
        Selector,
        AnyObject?,
        AnyObject,
        @convention(block) (UInt) -> Void
    ) -> Void
    let fn = unsafeBitCast(imp, to: WillPresentIMP.self)
    fn(delegate, selector, nil, NSObject(), completionBlock)
    #expect(receivedOptions == ((1 << 3) | (1 << 4)))
}
#endif
