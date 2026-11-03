// Tests ported from: crates/rune/src/shortcuts/service.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Dispatch
import Foundation
import Testing
@testable import Rune

func voidOk<E: Error>(_ result: Result<Void, E>) -> Bool {
    if case .success = result { return true }
    return false
}

func voidErr<E: Error>(_ result: Result<Void, E>) -> E? {
    if case .failure(let e) = result { return e }
    return nil
}

@Suite
struct ShortcutServiceTests {
    final class MockBackend: ShortcutBackend {
        let error: ShortcutError
        init(_ error: ShortcutError) { self.error = error }
        func register(_ id: ShortcutId, _ shortcut: Shortcut) -> Result<Void, ShortcutError> {
            _ = (id, shortcut)
            return .failure(error)
        }
        func unregister(_ id: ShortcutId) -> Result<Void, ShortcutError> {
            _ = id
            return .success(())
        }
    }

    final class AcceptBackend: ShortcutBackend {
        func register(_ id: ShortcutId, _ shortcut: Shortcut) -> Result<Void, ShortcutError> {
            _ = (id, shortcut)
            return .success(())
        }
        func unregister(_ id: ShortcutId) -> Result<Void, ShortcutError> {
            _ = id
            return .success(())
        }
    }

    @Test
    func mockBackendErrorsAreNotConfusedWithConflicts() {
        let errors: [ShortcutError] = [
            .conflict,
            .unsupported,
            .permissionDenied,
            .backend("disconnected"),
        ]
        for err in errors {
            let engine = ShortcutEngine(
                title: "mock",
                headless: false,
                wayland: false,
                sink: { _, _ in },
                native: MockBackend(err)
            )
            #expect(voidErr(engine.register(ShortcutId(1), Shortcut("ctrl+a")!)) == err)
            #expect(engine.registrations.isEmpty)
        }
        #expect(voidErr(shortcutNativeStatus(-9878, -9878)) == .conflict)
        #expect(voidErr(shortcutNativeStatus(1409, 1409)) == .conflict)
        if case .failure(.backend) = shortcutNativeStatus(5, 1409) {
            // expected
        } else {
            Issue.record("Expected backend error for status 5")
        }
    }

    @Test
    func conflictsNameTheAppThatHoldsTheChord() {
        let chord = Shortcut("ctrl+alt+shift+f17")!
        func makeNative(_ title: String) -> ShortcutEngine {
            ShortcutEngine(
                title: title,
                headless: false,
                wayland: false,
                sink: { _, _ in },
                native: AcceptBackend()
            )
        }
        do {
            var first: ShortcutEngine? = makeNative("First")
            let second = makeNative("Second")
            #expect(voidOk(first!.register(ShortcutId(UInt32.max - 1), chord)))
            #expect(voidErr(second.register(ShortcutId(UInt32.max - 2), chord)) == .conflict)
            #expect(first!.owner(chord) == "First")
            #expect(second.owner(chord) == "First")
            first = nil
            #expect(second.owner(chord) == nil)
            #expect(voidOk(second.register(ShortcutId(UInt32.max - 2), chord)))
        }

        let spec = AppSpec<Void>(title: "Owner", size: (10.0, 10.0), init: {}, view: { _, _ in el() })
        let app = App.new(spec)
        let handle = app.handle()
        let ownerChord = Shortcut("ctrl+alt+o")!
        #expect(handle.shortcutOwner(ownerChord) == nil)
        var guardObj: ShortcutGuard? = ShortcutGuard.attach(handle, wake: {}, headless: true, wayland: false)
        _ = guardObj
        if case .failure(let err) = handle.registerShortcut(ownerChord, { _, _ in }) {
            Issue.record("Unexpected error: \(err)")
        }
        #expect(handle.registerShortcut(ownerChord, { _, _ in }) == .failure(.conflict))
        #expect(handle.shortcutOwner(ownerChord) == "Owner")
        #expect(handle.shortcutOwner(Shortcut("super+space")!) == nil)
        guardObj = nil
    }

    @Test
    func headlessHandlersShareStateAndUnregisterCancelsQueuedActivation() {
        let spec = AppSpec<UInt32>(title: "shortcuts", size: (100.0, 100.0), init: { 0 }, view: { _, _ in el() })
        let app = App.new(spec).globalShortcut("cmd+shift+space") { s, tx in
            s += 1
            tx.instant()
        }
        let handle = app.handle()
        var guardObj: ShortcutGuard? = ShortcutGuard.attach(handle, wake: {}, headless: true, wayland: false)
        let shortcut = Shortcut("cmd+shift+space")!
        #expect(voidOk(handle.shortcutHub.fire(shortcut)))
        var state: UInt32 = 0
        var tx = Tx()
        _ = handle.drainUpdates(into: &state, tx: &tx)
        #expect(state == 1)
        #expect(handle.registerShortcut(shortcut, { _, _ in }) == .failure(.conflict))

        guard case .success(let id) = handle.registerShortcut(Shortcut("ctrl+a")!, { s, _ in s += 10 }) else {
            Issue.record("Expected ctrl+a registration")
            return
        }
        #expect(voidOk(handle.shortcutHub.fire(Shortcut("ctrl+a")!)))
        #expect(voidOk(handle.unregisterShortcut(id)))
        _ = handle.drainUpdates(into: &state, tx: &tx)
        #expect(state == 1)

        guardObj = nil
        _ = guardObj
        #expect(voidErr(handle.unregisterShortcut(id)) == .notRunning)
    }

    @Test
    func aChordWithoutAModifierIsRefusedUnlessItIsAFunctionKey() {
        let spec1 = AppSpec<Void>(title: "bare", size: (10.0, 10.0), init: {}, view: { _, _ in el() })
        let app1 = App.new(spec1).globalShortcut("space") { _, _ in }
        let handle1 = app1.handle()
        var guard1: ShortcutGuard? = ShortcutGuard.attach(handle1, wake: {}, headless: true, wayland: false)
        _ = guard1
        let errs1 = handle1.takeShortcutErrors()
        #expect(errs1.count == 1)
        if case .invalidAccelerator? = errs1.first {} else {
            Issue.record("Expected InvalidAccelerator")
        }
        for bare in ["space", "enter", "a", "shift+a", "shift+tab"] {
            if case .failure(.invalidAccelerator) = handle1.registerShortcut(Shortcut(bare)!, { _, _ in }) {
                // expected
            } else {
                Issue.record("Expected \(bare) to require modifier")
            }
        }
        for allowed in ["f5", "f24", "shift+f1", "ctrl+space", "alt+a", "super+enter"] {
            if case .failure(let err) = handle1.registerShortcut(Shortcut(allowed)!, { _, _ in }) {
                Issue.record("Expected \(allowed) to succeed, got \(err)")
            }
        }
        guard1 = nil

        let spec2 = AppSpec<Void>(title: "bare", size: (10.0, 10.0), init: {}, view: { _, _ in el() })
        let app2 = App.new(spec2)
            .globalShortcut("space") { _, _ in }
            .allowUnmodifiedShortcuts()
        let handle2 = app2.handle()
        var guard2: ShortcutGuard? = ShortcutGuard.attach(handle2, wake: {}, headless: true, wayland: false)
        _ = guard2
        #expect(handle2.takeShortcutErrors().isEmpty)
        if case .failure(let err) = handle2.registerShortcut(Shortcut("shift+a")!, { _, _ in }) {
            Issue.record("Expected shift+a to succeed with allowUnmodifiedShortcuts, got \(err)")
        }
        guard2 = nil
    }

    @Test
    func backgroundRegistrationWakesAndReturnsTheBackendResult() {
        let spec = AppSpec<Void>(title: "shortcuts", size: (10.0, 10.0), init: {}, view: { _, _ in el() })
        let app = App.new(spec)
        let woke = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        let handle = app.handle()
        var guardObj: ShortcutGuard? = ShortcutGuard.attach(handle, wake: { woke.signal() }, headless: true, wayland: false)
        final class ResultBox: @unchecked Sendable { var res: Result<ShortcutId, ShortcutError>? = nil }
        let box = ResultBox()
        Thread.detachNewThread {
            box.res = handle.registerShortcut(Shortcut("ctrl+space")!) { _, _ in }
            done.signal()
        }
        #expect(woke.wait(timeout: .now() + 2.0) == .success)
        guardObj?.drain()
        #expect(done.wait(timeout: .now() + 2.0) == .success)
        if case .success? = box.res {} else {
            Issue.record("Expected background registration to succeed")
        }
        guardObj = nil
    }

    @Test
    func activationTokensAreScopedToTheHandlerAndShutdownBreaksHandleCycles() {
        weak var weakHandle: AppHandle<Bool>? = nil
        do {
            let spec = AppSpec<Bool>(title: "shortcuts", size: (10.0, 10.0), init: { false }, view: { _, _ in el() })
            var app: App<Bool>? = App.new(spec)
            let handle = app!.handle()
            weakHandle = handle
            var guardObj: ShortcutGuard? = ShortcutGuard.attach(handle, wake: {}, headless: true, wayland: false)
            let captured = app!.handle()
            guard case .success(let id) = app!.handle().registerShortcut(Shortcut("ctrl+space")!, { state, tx in
                #expect(tx.activationToken() == "compositor-token")
                captured.activate(tx.activationToken()!)
                state = true
            }) else {
                Issue.record("Expected shortcut registration")
                return
            }
            _ = handle.shortcutHub.control.invoke { engine in
                engine.sink(id, "compositor-token")
                return .success(())
            }
            var state = false
            var tx = Tx()
            _ = handle.drainUpdates(into: &state, tx: &tx)
            #expect(state)
            #expect(tx.activationToken() == nil)
            #expect(handle.takeWindowRequest() == .open("compositor-token"))
            app = nil
            guardObj = nil
            _ = guardObj
        }
        #expect(weakHandle == nil)
    }
}
