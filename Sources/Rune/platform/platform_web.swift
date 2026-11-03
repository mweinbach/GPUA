// Ported from: crates/rune/src/platform/web.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Single-threaded browser shell (`web.openUrl`, `web.openUrlSameTab`, safe-area insets, and page run).

#if os(WASI)
import CWebSys
#endif

private let webInsetsLock = LiveLock()
// PORT NOTE: Guarded by `webInsetsLock` (matching Rust `thread_local! INSETS` in `platform/web.rs`).
nonisolated(unsafe) private var webSafeAreaInsets: [Float] = [0.0, 0.0, 0.0, 0.0]

func webSafeArea() -> [Float] {
    webInsetsLock.withLock { webSafeAreaInsets }
}

func webReplaceSafeArea(_ next: [Float]) -> [Float] {
    let normalized = (0..<4).map { $0 < next.count ? next[$0] : 0.0 }
    return webInsetsLock.withLock {
        let prev = webSafeAreaInsets
        webSafeAreaInsets = normalized
        return prev
    }
}

func webReportError(_ message: String, embedded: Bool) {
    _ = embedded
    webPlatformConsoleLog(0, message)
}

func webValidateApp(
    hasOverlaysOrWindows: Bool,
    isOpen: Bool,
    hasNativeHooks: Bool
) -> Result<Void, WebPlatformError> {
    if hasOverlaysOrWindows {
        return .failure(WebPlatformError("web supports one canvas; overlays and multiple windows are unsupported"))
    }
    if !isOpen || hasNativeHooks {
        return .failure(WebPlatformError("web does not support windowless apps or native window hooks"))
    }
    return .success(())
}

/// Browser link helpers (`crates/rune/src/platform/web.rs`).
public enum web {
    /// Open an HTTP(S) or mail link in a new browser tab. Call from a user input handler;
    /// browser popup policy applies. The new page receives no opener or referrer.
    public static func openUrl(_ url: String) -> Result<Void, WebPlatformError> {
        let checked: String
        do {
            checked = try checkOpenUrl(url)
        } catch {
            return .failure(WebPlatformError(error.description))
        }
        return webPlatformOpenLink(checked)
    }

    /// Open a link in this tab, as `Tx.openUrlSameTab` does: a link on the page's origin goes
    /// to the app's `App.sameTabRouter` first, and the browser loads it with `location.assign`
    /// unless the router handled it. A link without a scheme (`/notes/42`) is relative to the page.
    public static func openUrlSameTab(_ url: String) -> Result<Void, WebPlatformError> {
        let checked: String
        do {
            checked = try checkOpenUrlSameTab(url)
        } catch {
            return .failure(WebPlatformError(error.description))
        }
        switch webPlatformResolveLink(checked) {
        case .failure(let err):
            return .failure(err)
        case .success(let (href, sameOrigin)):
            if sameOrigin && webPageRoute(href) {
                return .success(())
            }
            return webPlatformAssignLink(href)
        }
    }
}
