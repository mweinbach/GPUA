// Ported from: crates/rune/src/native_menu/standard_macos.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import AppKit
import Foundation
import ObjectiveC.runtime

enum MenuUnhandledAction: Sendable {
    case close
    case minimize
    case menu(@Sendable () -> Void)
}

@MainActor private var standardMenusInstalled: Bool = false
@MainActor private var standardMenusChecked: Bool = false
@MainActor private var hookedViewClasses: Set<ObjectIdentifier> = []
// PORT NOTE: Accessed exclusively on the AppKit main thread during synchronous key/menu action dispatch.
nonisolated(unsafe) private var unhandledMenuSlot: (Character?, MenuUnhandledAction)? = nil

/// At a window's start: the standard items, when the app asked (`App.standardMenus`) or the
/// menu bar is still winit's default for a regular app as the first window starts. Once per
/// process.
@MainActor
func installStandardMenus(_ optIn: Bool) {
    if standardMenusInstalled { return }
    let app = NSApplication.shared
    let wasChecked = standardMenusChecked
    standardMenusChecked = true
    let isDefault = !wasChecked && isWinitDefaultMenu(app)
    if !optIn && !isDefault { return }
    standardMenusInstalled = true
    addStandardMenus(app)
    hookStandardMenuViewClass()
}

/// The window host, for a key press it maps to `key`: what to do if no handler takes it, when
/// a menu item is handing Rune that very key.
func takeMenuUnhandled(_ key: KeyEvent) -> MenuUnhandledAction? {
    guard let (expectedChar, thenAction) = unhandledMenuSlot else { return nil }
    unhandledMenuSlot = nil
    if let c = expectedChar {
        guard key.key == .command(c) && !key.mods.alt && !key.mods.ctrl else {
            return nil
        }
    }
    return thenAction
}

/// An app's `keysFirst` item picked by its key equivalent while a Rune window's view has the
/// keyboard: the key goes to that view, so the window's handlers see it first, and `run`
/// happens only if none takes it.
@MainActor
func deferMenuKey(_ run: @escaping @Sendable () -> Void) -> Bool {
    let app = NSApplication.shared
    guard let event = app.currentEvent, event.type == .keyDown else { return false }
    guard let window = app.keyWindow, !(window is NSPanel) else { return false }
    guard let view = window.firstResponder as? NSView, isRuneWindowView(view) else { return false }
    unhandledMenuSlot = (nil, .menu(run))
    commitViewComposition(view)
    view.keyDown(with: event)
    if unhandledMenuSlot != nil {
        unhandledMenuSlot = nil
        run()
    }
    return true
}

/// After each window creation: adopt the content view's class for standard menu selectors.
@MainActor
func adoptStandardMenuView(_ viewClass: AnyClass? = nil) {
    hookStandardMenuViewClass(viewClass)
}

@MainActor
private func isRuneWindowView(_ view: NSView) -> Bool {
    let className = NSStringFromClass(type(of: view))
    return className.contains("Rune") || className.contains("WinitView")
}

@MainActor
private func hookStandardMenuViewClass(_ explicitClass: AnyClass? = nil) {
    guard standardMenusInstalled else { return }
    var classesToHook: [AnyClass] = []
    if let cls = explicitClass {
        classesToHook.append(cls)
    }
    if let winitCls = NSClassFromString("WinitView") {
        classesToHook.append(winitCls)
    }
    for cls in classesToHook {
        let id = ObjectIdentifier(cls)
        if hookedViewClasses.contains(id) { continue }
        for item in STANDARD_MENU_ITEMS {
            let sel = Selector((item.action))
            let imp = unsafeBitCast(standardMenuActionImp, to: IMP.self)
            _ = class_addMethod(cls, sel, imp, "v@:@")
        }
        hookedViewClasses.insert(id)
    }
}

private let standardMenuActionImp: @convention(c) (AnyObject, Selector, AnyObject?) -> Void = { receiver, selector, _ in
    let actionName = NSStringFromSelector(selector)
    guard let item = standardMenuByAction(actionName),
          let view = receiver as? NSView
    else { return }
    MainActor.assumeIsolated {
        performStandardMenuAction(view, item)
    }
}

@MainActor
private func performStandardMenuAction(_ view: NSView, _ item: StandardMenuItem) {
    let window = view.window
    let (buttonKind, thenAction): (NSWindow.ButtonType?, MenuUnhandledAction?) = {
        switch item.role {
        case .close: return (.closeButton, .close)
        case .minimize: return (.miniaturizeButton, .minimize)
        default: return (nil, nil)
        }
    }()
    let isPanel = window is NSPanel
    let hasEnabledButton: Bool = {
        guard !isPanel, let w = window, let kind = buttonKind, let btn = w.standardWindowButton(kind) else {
            return false
        }
        return btn.isEnabled
    }()
    let current = NSApplication.shared.currentEvent.flatMap { $0.type == .keyDown ? $0 : nil }
    let route = standardMenuRoute(item, hasEnabledButton, current.map(extractKeyDown))
    if route.thenButton, let thenAction {
        unhandledMenuSlot = (item.key, thenAction)
    } else {
        unhandledMenuSlot = nil
    }
    commitViewComposition(view)
    if route.current, let event = current {
        view.keyDown(with: event)
    } else {
        synthesizeStandardPress(view, item, window)
    }
    unhandledMenuSlot = nil
}

@MainActor
private func commitViewComposition(_ view: NSView) {
    if let textClient = view as? any NSTextInputClient, textClient.hasMarkedText() {
        view.inputContext?.discardMarkedText()
        textClient.unmarkText()
    }
}

@MainActor
private func extractKeyDown(_ event: NSEvent) -> StandardKeyDown {
    let flags = event.modifierFlags
    return StandardKeyDown(
        chars: event.charactersIgnoringModifiers ?? "",
        cmd: flags.contains(.command),
        shift: flags.contains(.shift),
        alt: flags.contains(.option),
        ctrl: flags.contains(.control)
    )
}

@MainActor
private func synthesizeStandardPress(_ view: NSView, _ item: StandardMenuItem, _ window: NSWindow?) {
    let windowNumber = window?.windowNumber ?? 0
    let chars = item.shift ? String(item.key).uppercased() : String(item.key)
    let uptime = ProcessInfo.processInfo.systemUptime
    var flags: NSEvent.ModifierFlags = [.command]
    if item.shift {
        flags.insert(.shift)
    }
    if let down = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: flags,
        timestamp: uptime,
        windowNumber: windowNumber,
        context: nil,
        characters: chars,
        charactersIgnoringModifiers: chars,
        isARepeat: false,
        keyCode: item.keyCode
    ) {
        view.keyDown(with: down)
    }
    if let up = NSEvent.keyEvent(
        with: .keyUp,
        location: .zero,
        modifierFlags: NSEvent.modifierFlags,
        timestamp: uptime,
        windowNumber: windowNumber,
        context: nil,
        characters: chars,
        charactersIgnoringModifiers: chars,
        isARepeat: false,
        keyCode: item.keyCode
    ) {
        view.keyUp(with: up)
    }
}
#endif
