// Tests ported from: crates/rune/src/platform/macos/panel_bridge.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

#if os(macOS)
import AppKit
import Foundation
import ObjectiveC.runtime

private let panelBridgeTestLock = LiveLock()
nonisolated(unsafe) private var panelBridgeTestReceived: [String] = []

private func recordBridgeMessage(_ msg: String) {
    panelBridgeTestLock.withLock {
        panelBridgeTestReceived.append(msg)
    }
}

private let testGotFrameImp: @convention(c) (AnyObject, Selector, NSRect, ObjCBool) -> Void = { _, _, rect, display in
    recordBridgeMessage("frame \(rect.origin.x) \(rect.origin.y) \(rect.size.width) \(rect.size.height) \(display.boolValue)")
}

private let testGotOriginImp: @convention(c) (AnyObject, Selector, NSPoint) -> Void = { _, _, point in
    recordBridgeMessage("origin \(point.x) \(point.y)")
}

private let testGotSizeImp: @convention(c) (AnyObject, Selector, NSSize) -> Void = { _, _, size in
    recordBridgeMessage("size \(size.width) \(size.height)")
}

private let testGotLevelImp: @convention(c) (AnyObject, Selector, Int) -> Void = { _, _, level in
    recordBridgeMessage("level \(level)")
}

private let testGotHitImp: @convention(c) (AnyObject, Selector, ObjCBool) -> Void = { _, _, ignore in
    recordBridgeMessage("ignore \(ignore.boolValue)")
}

private let testGotLiveResizeImp: @convention(c) (AnyObject, Selector) -> ObjCBool = { _, _ in
    ObjCBool(true)
}

@Suite("PanelBridgeTests", .serialized)
struct PanelBridgeTests {
    @Test("trampolines pass the arguments and the sender")
    func trampolinesPassTheArgumentsAndTheSender() throws {
        panelBridgeTestLock.withLock { panelBridgeTestReceived.removeAll() }

        let windowClass: AnyClass
        if let existing = objc_getClass("RuneBridgeTestWindow") as? AnyClass {
            windowClass = existing
        } else {
            let allocated: AnyClass = try #require(objc_allocateClassPair(NSWindow.self, "RuneBridgeTestWindow", 0))
            objc_registerClassPair(allocated)
            windowClass = allocated
        }
        #expect(macBridgeInstall(cls: windowClass, appkit: NSWindow.self, methods: macBridgeWindowForwards()))

        let panelClass: AnyClass
        if let existing = objc_getClass("RuneBridgeTestPanel") as? AnyClass {
            panelClass = existing
        } else {
            let allocated: AnyClass = try #require(objc_allocateClassPair(NSObject.self, "RuneBridgeTestPanel", 0))
            #if arch(arm64)
            let rectBoolEnc = "v@:{CGRect={CGPoint=dd}{CGSize=dd}}B"
            let boolArgEnc = "v@:B"
            let boolRetEnc = "B@:"
            #else
            let rectBoolEnc = "v@:{CGRect={CGPoint=dd}{CGSize=dd}}c"
            let boolArgEnc = "v@:c"
            let boolRetEnc = "c@:"
            #endif
            _ = rectBoolEnc.withCString { class_addMethod(allocated, NSSelectorFromString("setFrame:display:"), unsafeBitCast(testGotFrameImp, to: IMP.self), $0) }
            _ = "v@:{CGPoint=dd}".withCString { class_addMethod(allocated, NSSelectorFromString("setFrameOrigin:"), unsafeBitCast(testGotOriginImp, to: IMP.self), $0) }
            _ = "v@:{CGSize=dd}".withCString { class_addMethod(allocated, NSSelectorFromString("setContentSize:"), unsafeBitCast(testGotSizeImp, to: IMP.self), $0) }
            _ = "v@:q".withCString { class_addMethod(allocated, NSSelectorFromString("setLevel:"), unsafeBitCast(testGotLevelImp, to: IMP.self), $0) }
            _ = boolArgEnc.withCString { class_addMethod(allocated, NSSelectorFromString("setIgnoresMouseEvents:"), unsafeBitCast(testGotHitImp, to: IMP.self), $0) }
            _ = boolRetEnc.withCString { class_addMethod(allocated, NSSelectorFromString("inLiveResize"), unsafeBitCast(testGotLiveResizeImp, to: IMP.self), $0) }
            objc_registerClassPair(allocated)
            panelClass = allocated
        }

        // Allocate without initializing NSWindow so no window server connection is required.
        let windowObj = try #require(class_createInstance(windowClass, 0)) as AnyObject
        let panelObj = try #require(class_createInstance(panelClass, 0)) as AnyObject
        let viewObj = NSObject() as AnyObject

        let windowAddr = UInt(bitPattern: Unmanaged.passUnretained(windowObj).toOpaque())
        let panelAddr = UInt(bitPattern: Unmanaged.passUnretained(panelObj).toOpaque())
        let viewAddr = UInt(bitPattern: Unmanaged.passUnretained(viewObj).toOpaque())

        macBridgeInsertForTests(window: windowAddr, view: viewAddr, panel: panelAddr, ordinary: true)
        defer { macBridgeRemoveForTests(window: windowAddr) }

        let contentSel = NSSelectorFromString("contentView")
        let contentMethod = try #require(class_getInstanceMethod(windowClass, contentSel))
        typealias ContentFn = @convention(c) (AnyObject, Selector) -> UnsafeMutableRawPointer?
        let contentRes = unsafeBitCast(method_getImplementation(contentMethod), to: ContentFn.self)(windowObj, contentSel)
        #expect(contentRes == UnsafeMutableRawPointer(bitPattern: viewAddr))

        // NSInvocation calls the method from CoreFoundation, as AppKit would.
        if let invClass = objc_getClass("NSInvocation") as? AnyClass {
            let sigSel = NSSelectorFromString("methodSignatureForSelector:")
            if let sigM = class_getInstanceMethod(windowClass, sigSel),
               let invCreateM = class_getClassMethod(invClass, NSSelectorFromString("invocationWithMethodSignature:"))
            {
                typealias SigFn = @convention(c) (AnyObject, Selector, Selector) -> AnyObject?
                typealias InvCreateFn = @convention(c) (AnyClass, Selector, AnyObject) -> AnyObject?
                if let sig = unsafeBitCast(method_getImplementation(sigM), to: SigFn.self)(windowObj, sigSel, contentSel),
                   let inv = unsafeBitCast(method_getImplementation(invCreateM), to: InvCreateFn.self)(
                       invClass,
                       NSSelectorFromString("invocationWithMethodSignature:"),
                       sig
                   )
                {
                    let setSel = NSSelectorFromString("setSelector:")
                    let invokeSel = NSSelectorFromString("invokeWithTarget:")
                    let getRetSel = NSSelectorFromString("getReturnValue:")
                    if let setM = class_getInstanceMethod(invClass, setSel),
                       let invokeM = class_getInstanceMethod(invClass, invokeSel),
                       let getRetM = class_getInstanceMethod(invClass, getRetSel)
                    {
                        typealias SetSelFn = @convention(c) (AnyObject, Selector, Selector) -> Void
                        typealias InvokeFn = @convention(c) (AnyObject, Selector, AnyObject) -> Void
                        typealias GetRetFn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Void
                        unsafeBitCast(method_getImplementation(setM), to: SetSelFn.self)(inv, setSel, contentSel)
                        unsafeBitCast(method_getImplementation(invokeM), to: InvokeFn.self)(inv, invokeSel, windowObj)
                        var foreign: UnsafeMutableRawPointer? = UnsafeMutableRawPointer(bitPattern: viewAddr)
                        withUnsafeMutablePointer(to: &foreign) { ptr in
                            unsafeBitCast(method_getImplementation(getRetM), to: GetRetFn.self)(inv, getRetSel, ptr)
                        }
                        #expect(foreign == nil)
                    }
                }
            }
        }

        let liveSel = NSSelectorFromString("inLiveResize")
        let liveM = try #require(class_getInstanceMethod(windowClass, liveSel))
        typealias LiveFn = @convention(c) (AnyObject, Selector) -> ObjCBool
        let live = unsafeBitCast(method_getImplementation(liveM), to: LiveFn.self)(windowObj, liveSel)
        #expect(live.boolValue)

        let setFrameSel = NSSelectorFromString("setFrame:display:")
        let setFrameM = try #require(class_getInstanceMethod(windowClass, setFrameSel))
        typealias SetFrameFn = @convention(c) (AnyObject, Selector, NSRect, ObjCBool) -> Void
        unsafeBitCast(method_getImplementation(setFrameM), to: SetFrameFn.self)(
            windowObj,
            setFrameSel,
            NSRect(x: 1.5, y: 2.5, width: 300.0, height: 200.0),
            ObjCBool(true)
        )

        let setOriginSel = NSSelectorFromString("setFrameOrigin:")
        let setOriginM = try #require(class_getInstanceMethod(windowClass, setOriginSel))
        typealias SetOriginFn = @convention(c) (AnyObject, Selector, NSPoint) -> Void
        unsafeBitCast(method_getImplementation(setOriginM), to: SetOriginFn.self)(
            windowObj,
            setOriginSel,
            NSPoint(x: 7.0, y: 8.0)
        )

        let setSizeSel = NSSelectorFromString("setContentSize:")
        let setSizeM = try #require(class_getInstanceMethod(windowClass, setSizeSel))
        typealias SetSizeFn = @convention(c) (AnyObject, Selector, NSSize) -> Void
        unsafeBitCast(method_getImplementation(setSizeM), to: SetSizeFn.self)(
            windowObj,
            setSizeSel,
            NSSize(width: 40.0, height: 50.0)
        )

        let setLevelSel = NSSelectorFromString("setLevel:")
        let setLevelM = try #require(class_getInstanceMethod(windowClass, setLevelSel))
        typealias SetLevelFn = @convention(c) (AnyObject, Selector, Int) -> Void
        unsafeBitCast(method_getImplementation(setLevelM), to: SetLevelFn.self)(
            windowObj,
            setLevelSel,
            3
        )

        let setHitSel = NSSelectorFromString("setIgnoresMouseEvents:")
        let setHitM = try #require(class_getInstanceMethod(windowClass, setHitSel))
        typealias SetHitFn = @convention(c) (AnyObject, Selector, ObjCBool) -> Void
        unsafeBitCast(method_getImplementation(setHitM), to: SetHitFn.self)(
            windowObj,
            setHitSel,
            ObjCBool(true)
        )

        let received = panelBridgeTestLock.withLock { panelBridgeTestReceived }
        #expect(
            received == [
                "frame 1.5 2.5 300.0 200.0 true",
                "origin 7.0 8.0",
                "size 40.0 50.0",
                "level 3",
                "ignore true",
            ]
        )
    }
}
#endif
