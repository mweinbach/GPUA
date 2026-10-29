// Tests ported from: crates/gpui/src/subscription.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
@testable import GPUI

@Suite("Subscription Tests")
struct SubscriptionTests {

    struct TestGlobal: Global, Sendable, Equatable {}

    @Test("test_unsubscribe_during_callback_with_insert")
    @MainActor
    func test_unsubscribe_during_callback_with_insert() {
        let app = App()
        app.setGlobal(TestGlobal())

        var observerACount = 0
        var observerBCount = 0

        var subA: Subscription? = nil
        var subB: Subscription? = nil

        subA = app.update { cx in
            cx.observeGlobal(TestGlobal.self) { cx in
                observerACount += 1
                subA = nil
                cx.observeGlobal(TestGlobal.self) { _ in true }.detach()
                return true
            }
        }

        subB = app.update { cx in
            cx.observeGlobal(TestGlobal.self) { _ in
                observerBCount += 1
                subB = nil
                return true
            }
        }

        _ = subA
        _ = subB
        app.update { cx in cx.setGlobal(TestGlobal()) }
        #expect(observerACount == 1)
        #expect(observerBCount == 1)

        app.update { cx in cx.setGlobal(TestGlobal()) }
        #expect(observerACount == 1)
        #expect(observerBCount == 1)
    }

    @Test("test_callback_dropped_by_earlier_callback_does_not_fire")
    @MainActor
    func test_callback_dropped_by_earlier_callback_does_not_fire() {
        let app = App()
        app.setGlobal(TestGlobal())

        var observerBCount = 0
        var subB: Subscription? = nil

        app.update { cx in
            cx.observeGlobal(TestGlobal.self) { _ in
                subB = nil
                return true
            }.detach()
        }

        subB = app.update { cx in
            cx.observeGlobal(TestGlobal.self) { _ in
                observerBCount += 1
                return true
            }
        }

        _ = subB
        app.update { cx in cx.setGlobal(TestGlobal()) }
        #expect(observerBCount == 0, "B should not fire - A dropped its subscription")
    }

    @Test("test_self_drop_during_callback")
    @MainActor
    func test_self_drop_during_callback() {
        let app = App()
        app.setGlobal(TestGlobal())

        var count = 0
        var sub: Subscription? = nil

        sub = app.update { cx in
            cx.observeGlobal(TestGlobal.self) { _ in
                count += 1
                sub = nil
                return true
            }
        }

        _ = sub
        app.update { cx in cx.setGlobal(TestGlobal()) }
        #expect(count == 1)

        app.update { cx in cx.setGlobal(TestGlobal()) }
        #expect(count == 1, "should not fire after self-drop")
    }

    @Test("test_subscription_drop")
    @MainActor
    func test_subscription_drop() {
        let app = App()
        app.setGlobal(TestGlobal())

        var count = 0

        var subscription: Subscription? = app.update { cx in
            cx.observeGlobal(TestGlobal.self) { _ in
                count += 1
                return true
            }
        }

        subscription = nil
        _ = subscription

        app.update { cx in cx.setGlobal(TestGlobal()) }
        #expect(count == 0, "should not fire after drop")
    }

    @Test("test_subscriber_set_inert_insert")
    func test_subscriber_set_inert_insert() {
        let set = SubscriberSet<Int, () -> Void>()
        var count = 0

        var sub: Subscription?
        let activate: () -> Void
        (sub, activate) = set.insert(1) {
            count += 1
        }

        // Before activation, retain should not invoke the callback
        set.retain(1) { callback in
            callback()
            return true
        }
        #expect(count == 0)

        // After activation, retain should invoke the callback
        activate()
        set.retain(1) { callback in
            callback()
            return true
        }
        #expect(count == 1)

        // Drop subscription
        _ = sub
        sub = nil

        set.retain(1) { callback in
            callback()
            return true
        }
        #expect(count == 1)
    }
}
