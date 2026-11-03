// Tests ported from: crates/rune/src/native_menu/mod.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Testing
@testable import Rune

private func makeMenuApp() -> App<[UInt32]> {
    App.new(AppSpec(title: "menu", size: (100.0, 100.0), init: { [] }, view: { _, _ in el() }))
}

private func makeItem(_ id: String) -> MenuItem<[UInt32]> {
    MenuItem.new("Open Quick Panel", { s, _ in s.append(1) }).id(id)
}

private func drainMenuUpdates(_ app: App<[UInt32]>, _ state: inout [UInt32]) {
    var tx = Tx()
    _ = app.handle().drainUpdates(into: &state, tx: &tx)
}

@Suite("NativeMenuTests")
struct NativeMenuTests {
    @Test func titleAndIdDispatchOnTheStateThreadWithReentrantMenuUpdates() {
        let app = makeMenuApp()
            .menuItem(makeItem("quick"))
            .menuItem(MenuItem.new("Dock", { s, tx in s.append(2); tx.quit() }).dock())
        let guardObj = MenuGuard.attach(app.handle(), headless: true)
        defer { guardObj.detach() }

        let handle = app.handle()
        let sem = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            _ = fireMenuItem(handle, "Open Quick Panel")
            sem.signal()
        }
        sem.wait()

        var state: [UInt32] = []
        #expect(state.isEmpty)
        drainMenuUpdates(app, &state)
        #expect(state == [1])

        #expect(voidOk(fireMenuItem(handle, "quick")))
        drainMenuUpdates(app, &state)
        #expect(state == [1, 1])

        let h = handle
        handle.update { _, _ in
            _ = h.setMenu([makeItem("replacement").checked(true)])
        }
        drainMenuUpdates(app, &state)
        let newId = handle.menuHub.lock.withLock { handle.menuHub.state.items[0].description.id }
        #expect(newId == "replacement")
    }

    @Test func replacementDisableAndShutdownCancelStaleActions() {
        let app = makeMenuApp().menuItem(makeItem("quick"))
        let guardObj = MenuGuard.attach(app.handle(), headless: true)
        let handle = app.handle()

        #expect(voidOk(fireMenuItem(handle, "quick")))
        #expect(voidOk(handle.setMenu([makeItem("quick").enabled(false).checked(true)])))
        var state: [UInt32] = []
        drainMenuUpdates(app, &state)
        #expect(state.isEmpty)
        #expect(voidErr(fireMenuItem(handle, "quick")) == .disabled("quick"))
        let isChecked = handle.menuHub.lock.withLock { handle.menuHub.state.items[0].description.checked }
        #expect(isChecked)

        #expect(voidOk(handle.setMenu([makeItem("quick")])))
        #expect(voidOk(fireMenuItem(handle, "quick")))
        guardObj.detach()
        drainMenuUpdates(app, &state)
        #expect(state.isEmpty)
        #expect(voidErr(fireMenuItem(handle, "quick")) == .notRunning)
    }

    @Test func validationIsAtomicAndAmbiguousTitlesRequireIds() {
        let app = makeMenuApp()
            .menuItem(makeItem("first"))
            .menuItem(makeItem("second").menu("Tools"))
        let guardObj = MenuGuard.attach(app.handle(), headless: true)
        defer { guardObj.detach() }

        #expect(voidErr(fireMenuItem(app.handle(), "Open Quick Panel")) == .ambiguousTitle("Open Quick Panel"))
        #expect(voidOk(fireMenuItem(app.handle(), "first")))
        if case .invalid = voidErr(app.handle().setMenu([makeItem("duplicate"), makeItem("duplicate")])) {
            // expected
        } else {
            Issue.record("Expected MenuError.invalid for duplicate ids")
        }
        let count = app.handle().menuHub.lock.withLock { app.handle().menuHub.state.items.count }
        #expect(count == 2)
        if case .unknownItem = voidErr(fireMenuItem(app.handle(), "missing")) {
            // expected
        } else {
            Issue.record("Expected MenuError.unknownItem")
        }

        let invalid = makeMenuApp().menuItem(makeItem("same")).menuItem(makeItem("same"))
        let invalidGuard = MenuGuard.attach(invalid.handle(), headless: true)
        defer { invalidGuard.detach() }
        let errs = invalid.handle().takeMenuErrors()
        #expect(errs.count == 1)
        if case .invalid = errs.first {
            // expected
        } else {
            Issue.record("Expected deferred MenuError.invalid")
        }
        if case .unknownItem = voidErr(fireMenuItem(invalid.handle(), "same")) {
            // expected
        } else {
            Issue.record("Expected MenuError.unknownItem after invalid snapshot cleared")
        }
    }

    @Test func separatorsNeedNoIdsAndNeverFire() {
        let file: (String) -> MenuItem<[UInt32]> = { title in
            MenuItem.new(title, { s, _ in s.append(3) }).menu("File")
        }
        let app = makeMenuApp()
            .menuItem(file("New"))
            .menuItem(MenuItem.separator().menu("File"))
            .menuItem(file("Close"))
            .menuItem(MenuItem.separator().menu("File"))
            .menuItem(MenuItem.separator().dock())
        let guardObj = MenuGuard.attach(app.handle(), headless: true)
        defer { guardObj.detach() }

        #expect(app.handle().takeMenuErrors().isEmpty)
        #expect(voidErr(fireMenuItem(app.handle(), "")) == .unknownItem(""))
        #expect(voidOk(fireMenuItem(app.handle(), "Close")))
        var state: [UInt32] = []
        drainMenuUpdates(app, &state)
        #expect(state == [3])

        #expect(voidOk(app.handle().setMenu([
            file("New"),
            MenuItem.separator().menu("File"),
            MenuItem.separator().menu("File"),
        ])))
        let isSep = app.handle().menuHub.lock.withLock { app.handle().menuHub.state.items[1].description.separator }
        #expect(isSep)
        if case .invalid = voidErr(app.handle().setMenu([MenuItem.separator().menu(" ")])) {
            // expected
        } else {
            Issue.record("Expected MenuError.invalid for blank menu title")
        }
    }

    @Test func equivalentAndNonSendStateRemainBuilderCompatible() {
        final class NonSendState {}
        let _: any Sendable = AppHandle<NonSendState>()
        guard case .success(let shortcut) = Shortcut.parse("cmd+shift+k") else {
            Issue.record("Failed to parse cmd+shift+k")
            return
        }
        let item = makeItem("quick").keyEquivalent(shortcut)
        #expect(item.description.equivalent == shortcut)
        #expect(!item.description.keysFirst && item.keysFirst().description.keysFirst)
    }

    #if !os(macOS)
    @Test func unsupportedNativePlatformIsANoopButHeadlessWorks() {
        let app = makeMenuApp().menuItem(makeItem("quick"))
        let guardObj = MenuGuard.attach(app.handle(), headless: false)
        defer { guardObj.detach() }
        #expect(app.handle().takeMenuErrors() == [.unsupported])
        #expect(voidErr(app.handle().setMenu([makeItem("other")])) == .unsupported)
        let id = app.handle().menuHub.lock.withLock { app.handle().menuHub.state.items[0].description.id }
        #expect(id == "quick")
    }
    #endif
}
