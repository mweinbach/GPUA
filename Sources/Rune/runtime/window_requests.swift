// Ported from: crates/rune/src/runtime/window_requests.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Shell-facing requests queued during `Tx` dispatch (close/quit, minimize, title, URLs, clipboard, cursor, window frame).

import RuneMotion

/// Host window resize / center request queued by `Tx.resizeWindow` or `fitContentHeight`.
public struct FrameRequest: Sendable, Equatable {
    public var size: (Float, Float)? = nil
    public var animate: Bool = false
    public var spring: Spring? = nil
    public var center: Bool = false

    public init(
        size: (Float, Float)? = nil,
        animate: Bool = false,
        spring: Spring? = nil,
        center: Bool = false
    ) {
        self.size = size
        self.animate = animate
        self.spring = spring
        self.center = center
    }

    public func merge(_ newer: FrameRequest) -> FrameRequest {
        FrameRequest(
            size: newer.size ?? size,
            animate: newer.size != nil ? newer.animate : animate,
            spring: newer.size != nil ? newer.spring : spring,
            center: center || newer.center
        )
    }

    public static func == (lhs: FrameRequest, rhs: FrameRequest) -> Bool {
        guard lhs.animate == rhs.animate,
              lhs.spring == rhs.spring,
              lhs.center == rhs.center
        else { return false }
        switch (lhs.size, rhs.size) {
        case (nil, nil): return true
        case (let l?, let r?): return l.0 == r.0 && l.1 == r.1
        default: return false
        }
    }
}

public struct WindowRequests: Sendable, Equatable {
    public var shell: Shell? = nil
    public var minimize: Bool = false
    public var title: String? = nil
    public var openUrls: [(String, Bool)] = []
    public var clipboardWrite: ClipboardWrite? = nil
    public var pasteRequested: Bool = false
    public var clearSecret: Bool = false
    public var shortcutActivationToken: String? = nil

    public init() {}

    public var isEmpty: Bool {
        shell == nil && !minimize && title == nil && openUrls.isEmpty
            && clipboardWrite == nil && !pasteRequested && !clearSecret
            && shortcutActivationToken == nil
    }

    public static func == (lhs: WindowRequests, rhs: WindowRequests) -> Bool {
        guard lhs.shell == rhs.shell,
              lhs.minimize == rhs.minimize,
              lhs.title == rhs.title,
              lhs.clipboardWrite == rhs.clipboardWrite,
              lhs.pasteRequested == rhs.pasteRequested,
              lhs.clearSecret == rhs.clearSecret,
              lhs.shortcutActivationToken == rhs.shortcutActivationToken,
              lhs.openUrls.count == rhs.openUrls.count
        else { return false }
        for (a, b) in zip(lhs.openUrls, rhs.openUrls) {
            if a.0 != b.0 || a.1 != b.1 { return false }
        }
        return true
    }
}

extension Runtime {
    public func takeWindowRequests() -> WindowRequests {
        let out = pendingWindowRequests
        pendingWindowRequests = WindowRequests()
        return out
    }

    public func takeClipboardWrite() -> ClipboardWrite? {
        let out = pendingWindowRequests.clipboardWrite
        pendingWindowRequests.clipboardWrite = nil
        return out
    }

    public func takePasteRequest() -> Bool {
        let out = pendingWindowRequests.pasteRequested
        pendingWindowRequests.pasteRequested = false
        return out
    }

    public func takeShellRequest() -> Shell? {
        let out = pendingWindowRequests.shell
        pendingWindowRequests.shell = nil
        return out
    }

    public func takeMinimizeRequest() -> Bool {
        let out = pendingWindowRequests.minimize
        pendingWindowRequests.minimize = false
        return out
    }

    public func takeTitleRequest() -> String? {
        let out = pendingWindowRequests.title
        pendingWindowRequests.title = nil
        return out
    }

    public func takeOpenUrls() -> [(String, Bool)] {
        let out = pendingWindowRequests.openUrls
        pendingWindowRequests.openUrls.removeAll()
        return out
    }

    public func cursor() -> Cursor {
        currentCursor
    }

    public func takeWindowFrame() -> FrameRequest? {
        let out = windowFrame
        windowFrame = nil
        return out
    }

    public func setFitContentHeight(_ on: Bool) {
        fitHeight = on
    }

    func fitWindow(height rawHeight: Float, first: Bool, why: UInt16) {
        let s = max(env.scale, 0.001)
        let rounded = max((rawHeight * s).rounded(.up) / s, 1.0)
        if abs((fitAsked ?? viewport.1) - rounded) < 1e-4 {
            return
        }
        fitAsked = rounded
        let jump = first || pendingInstantCommit || pendingSettleCommit || (why & CommitWhy.RELAYOUT) != 0 || reducedMotion
        let sp: Spring? = (!jump) ? (pendingMotionSpring ?? tok.motion.DEFAULT) : nil
        let req = FrameRequest(size: (viewport.0, rounded), animate: !jump, spring: sp, center: false)
        windowFrame = (windowFrame ?? FrameRequest()).merge(req)
    }
}
