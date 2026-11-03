// Ported from: crates/rune/src/popup_menu/macos.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import AppKit
import CoreFoundation
import Foundation

@MainActor
final class PopupTrackingMenuBox {
    let menu: NSMenu

    init(_ menu: NSMenu) {
        self.menu = menu
    }

    func cancel() {
        menu.cancelTrackingWithoutAnimation()
    }
}

@MainActor
@objc(RunePopupMenuTarget)
final class RunePopupMenuTarget: NSObject {
    let ids: [String]
    var picked: String? = nil

    init(ids: [String]) {
        self.ids = ids
        super.init()
    }

    @objc func runePopupPick(_ sender: NSMenuItem) {
        let tag = sender.tag
        if tag >= 0 && tag < ids.count {
            picked = ids[tag]
        }
    }
}

/// Opens `show` over `view` once the current handler returns.
@MainActor
func showMacPopupMenu(
    _ view: NSView,
    _ show: PopupShow,
    _ session: PopupSession,
    _ wake: Waker?
) -> Bool {
    var ids: [String] = []
    collectPopupIds(show.menu, into: &ids)
    let target = RunePopupMenuTarget(ids: ids)
    var tagCounter: Int = 0
    var positionedItem: NSMenuItem? = nil
    let menu = buildMacPopupMenu(
        show.menu,
        target: target,
        tag: &tagCounter,
        positioned: show.positioned,
        found: &positionedItem
    )
    menu.minimumWidth = CGFloat(max(0.0, show.minWidth))
    let at = NSPoint(x: CGFloat(show.at.0), y: CGFloat(show.at.1))

    runLaterOnMainRunLoop {
        MainActor.assumeIsolated {
            if session.cancelled { return }
            let picked: String?
            if view.window?.isVisible == true {
                session.tracking = PopupTrackingMenuBox(menu)
                let chose = menu.popUp(positioning: positionedItem, at: at, in: view)
                session.tracking = nil
                let chosenId = target.picked
                target.picked = nil
                _ = chose
                picked = chosenId
            } else {
                picked = nil
            }
            clearPopupMenuTargets(menu)
            if session.cancelled { return }
            session.answer = .some(picked)
            wake?()
        }
    }
    return true
}

private func collectPopupIds(_ menu: PopupMenu, into ids: inout [String]) {
    for entry in menu.entries {
        switch entry {
        case .item(let item):
            ids.append(item.itemId)
        case .submenu(_, let sub):
            collectPopupIds(sub, into: &ids)
        case .separator:
            break
        }
    }
}

@MainActor
private func buildMacPopupMenu(
    _ menu: PopupMenu,
    target: RunePopupMenuTarget,
    tag: inout Int,
    positioned: String?,
    found: inout NSMenuItem?
) -> NSMenu {
    let nsMenu = NSMenu()
    nsMenu.autoenablesItems = false
    for entry in menu.entries {
        switch entry {
        case .item(let item):
            let nsItem = NSMenuItem(
                title: item.itemTitle,
                action: #selector(RunePopupMenuTarget.runePopupPick(_:)),
                keyEquivalent: ""
            )
            nsItem.target = target
            nsItem.tag = tag
            tag += 1
            nsItem.isEnabled = item.itemEnabled
            nsItem.state = item.itemChecked ? .on : .off
            setMenuKeyEquivalent(nsItem, item.keyEquivalentValue)
            if let symbol = item.symbolName,
               let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            {
                nsItem.image = image
            }
            if positioned == item.itemId {
                found = nsItem
            }
            nsMenu.addItem(nsItem)
        case .separator:
            nsMenu.addItem(NSMenuItem.separator())
        case .submenu(let title, let sub):
            var dummyFound: NSMenuItem? = nil
            let subMenu = buildMacPopupMenu(sub, target: target, tag: &tag, positioned: nil, found: &dummyFound)
            subMenu.title = title
            let nsItem = NSMenuItem()
            nsItem.title = title
            nsItem.submenu = subMenu
            nsMenu.addItem(nsItem)
        }
    }
    return nsMenu
}

@MainActor
private func clearPopupMenuTargets(_ menu: NSMenu) {
    for i in 0..<menu.numberOfItems {
        guard let item = menu.item(at: i) else { continue }
        item.target = nil
        item.action = nil
        if let sub = item.submenu {
            clearPopupMenuTargets(sub)
        }
    }
}

private func runLaterOnMainRunLoop(_ f: @escaping () -> Void) {
    let mainLoop = CFRunLoopGetMain()
    CFRunLoopPerformBlock(mainLoop, CFRunLoopMode.defaultMode.rawValue) {
        f()
    }
    CFRunLoopWakeUp(mainLoop)
}
#endif
