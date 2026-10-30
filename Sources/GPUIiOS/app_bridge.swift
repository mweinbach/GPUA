// Ported from: crates/gpui_ios/src/app_bridge.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(iOS) || os(visionOS)
import Darwin
import Foundation
import GPUI
import GPUIMetal
import OSLog
import UIKit

// MARK: - iOS Structured Logger & Optional TCP Relay

/// Unified logger forwarding iOS bridge messages to Apple `os.Logger` and optional TCP log relay
/// (`GPUI_LOG_HOST=host:port`), matching upstream `IosLogger`.
// PORT NOTE: Synchronizes optional POSIX socket descriptor via `NSLock`.
final class IosLogger: @unchecked Sendable {
    static let shared = IosLogger()

    private let osLogger = Logger(subsystem: "dev.zed.gpui.ios", category: "gpui")
    private let lock = NSLock()
    private var tcpSocketFd: Int32 = -1

    private init() {
        if let hostSpec = ProcessInfo.processInfo.environment["GPUI_LOG_HOST"],
           !hostSpec.isEmpty
        {
            connectTcpRelay(hostSpec: hostSpec)
        }
    }

    func info(_ message: String) {
        osLogger.info("\(message, privacy: .public)")
        sendTcpLine("[INFO] \(message)\n")
    }

    func warn(_ message: String) {
        osLogger.warning("\(message, privacy: .public)")
        sendTcpLine("[WARN] \(message)\n")
    }

    func error(_ message: String) {
        osLogger.error("\(message, privacy: .public)")
        sendTcpLine("[ERROR] \(message)\n")
    }

    private func connectTcpRelay(hostSpec: String) {
        let parts = hostSpec.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let port = UInt16(parts[1]) else { return }
        let host = parts[0]

        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &res) == 0, let info = res else {
            return
        }
        defer { freeaddrinfo(res) }

        let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard fd >= 0 else { return }
        if connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 {
            lock.lock()
            tcpSocketFd = fd
            lock.unlock()
        } else {
            close(fd)
        }
    }

    private func sendTcpLine(_ line: String) {
        lock.lock()
        let fd = tcpSocketFd
        lock.unlock()
        guard fd >= 0 else { return }
        let bytes = Array(line.utf8)
        _ = bytes.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return 0 }
            return Darwin.send(fd, base, ptr.count, 0)
        }
    }
}

// MARK: - Built-in iOS Demo Catalog

/// Canonical list of GPUI iOS demos matching upstream `gpui_ios_list_demos` and `main.m`.
public let gpuiIosDemoCatalog: [String] = [
    "hello_world",
    "text",
    "text_layout",
    "text_wrapper",
    "shadow",
    "opacity",
    "gradient",
    "pattern",
    "animation",
    "focus_visible",
    "tab_stop",
    "set_menus",
    "window_positioning",
    "scrollable",
    "grid_layout",
    "flex_wrap",
    "input",
]

// MARK: - Window <-> Platform Live Loop Binder

/// Connects an `IosWindow`'s vsync, touch/gesture/keyboard, resize, appearance, and IME callbacks
/// to `App.updateWindow(handle)` so interactive iOS windows drive GPUI's 7-stage layout/paint loop.
@MainActor
public func bindIosWindowCallbacks(
    handle: AnyWindowHandle,
    iosWindow: IosWindow,
    app: App
) {
    iosWindow.onRequestFrame { [weak app] options in
        MainActor.assumeIsolated {
            guard let app else { return }
            _ = try? app.updateWindow(handle) { _, window, cx in
                if options.forceRender || window.invalidator.isDirty {
                    var appCopy = cx
                    window.draw(cx: &appCopy)
                }
            }
        }
    }

    iosWindow.onInput { [weak app, weak iosWindow] input in
        MainActor.assumeIsolated {
            guard let app else {
                return DispatchEventResult(propagate: true, defaultPrevented: false)
            }
            let result = (try? app.updateWindow(handle) { _, window, cx in
                var appCopy = cx
                let res = window.dispatchEvent(event: input, cx: &appCopy)
                if let session = iosWindow?.textInputSession {
                    session.syncFromGpui(window: &window, cx: &appCopy)
                }
                if window.invalidator.isDirty {
                    window.draw(cx: &appCopy)
                }
                return res
            }) ?? DispatchEventResult(propagate: true, defaultPrevented: false)
            return result
        }
    }

    iosWindow.onResize { [weak app] newSize, _ in
        MainActor.assumeIsolated {
            guard let app else { return }
            _ = try? app.updateWindow(handle) { _, window, cx in
                var appCopy = cx
                window.resize(newSize)
                window.draw(cx: &appCopy)
            }
        }
    }

    iosWindow.onAppearanceChanged { [weak app, weak iosWindow] in
        MainActor.assumeIsolated {
            guard let app, let iosWindow else { return }
            let updatedAppearance = iosWindow.appearance()
            _ = try? app.updateWindow(handle) { _, window, cx in
                var appCopy = cx
                window.appearanceChanged(updatedAppearance)
                window.draw(cx: &appCopy)
            }
        }
    }

    iosWindow.onActiveStatusChange { [weak app] _ in
        MainActor.assumeIsolated {
            guard let app else { return }
            _ = try? app.updateWindow(handle) { _, window, cx in
                var appCopy = cx
                window.refresh()
                window.draw(cx: &appCopy)
            }
        }
    }

    let refreshAfterTextEvent: @MainActor () -> Void = { [weak app] in
        guard let app else { return }
        _ = try? app.updateWindow(handle) { _, window, cx in
            var appCopy = cx
            window.refresh()
            window.draw(cx: &appCopy)
        }
    }

    let session = iosWindow.textInputSession
    session.onCommitTextChange = { _, _, _ in
        refreshAfterTextEvent()
    }
    session.onEmptyBackspace = {
        refreshAfterTextEvent()
    }
    session.onSubmit = {
        refreshAfterTextEvent()
    }
    session.onSelectionChange = { _ in
        refreshAfterTextEvent()
    }
}

// MARK: - Interactive Metal Demo View (`IosShowcaseView`)

// PORT NOTE: Value-type GPUI view model conforming to `Render` and `Sendable` for entity leasing.
struct IosShowcaseView: Render, Sendable {
    var activeDemo: String
    var tapCount: Int = 0
    var lastOpenedUrl: String?

    init(activeDemo: String) {
        self.activeDemo = gpuiIosDemoCatalog.contains(activeDemo) ? activeDemo : "hello_world"
    }

    mutating func render(_ window: inout Window, _ cx: inout GPUI.Context<IosShowcaseView>) -> AnyElement {
        let appearance = window.appearance()
        let isDark = (appearance == .dark || appearance == .vibrantDark)
        let bgHex: UInt32 = isDark ? 0x11151C : 0xF4F6FA
        let cardHex: UInt32 = isDark ? 0x1D2432 : 0xFFFFFF
        let accentHex: UInt32 = 0x3B82F6
        let fgHex: UInt32 = isDark ? 0xF8FAFC : 0x0F172A
        let mutedHex: UInt32 = isDark ? 0x94A3B8 : 0x475569

        let viewport = window.bounds().size
        let demoLabel = activeDemo.replacingOccurrences(of: "_", with: " ").capitalized
        let urlNote = lastOpenedUrl.map { "URL: \($0)" } ?? "Metal + CoreText + UIKit Active"

        return div()
            .flex()
            .flexCol()
            .sizeFull()
            .bg(Hsla(rgba: rgb(bgHex)))
            .justifyCenter()
            .itemsCenter()
            .gap4()
            .p6()
            .child(
                div()
                    .flex()
                    .flexCol()
                    .gap3()
                    .p5()
                    .roundedLg()
                    .bg(Hsla(rgba: rgb(cardHex)))
                    .border1()
                    .borderColor(Hsla(rgba: rgb(accentHex)))
                    .shadowLg()
                    .itemsCenter()
                    .child(
                        div()
                            .textXl()
                            .textColor(Hsla(rgba: rgb(fgHex)))
                            .child("GPUA iOS — \(demoLabel)")
                    )
                    .child(
                        div()
                            .textSm()
                            .textColor(Hsla(rgba: rgb(mutedHex)))
                            .child("Viewport \(Int(viewport.width.value))×\(Int(viewport.height.value)) pt • Taps: \(tapCount)")
                    )
                    .child(
                        div()
                            .textSm()
                            .textColor(Hsla(rgba: rgb(accentHex)))
                            .child(urlNote)
                    )
                    .child(
                        div()
                            .flex()
                            .gap2()
                            .child(div().size8().roundedMd().bg(GPUI.red()))
                            .child(div().size8().roundedMd().bg(GPUI.green()))
                            .child(div().size8().roundedMd().bg(GPUI.blue()))
                            .child(div().size8().roundedMd().bg(GPUI.yellow()))
                    )
            )
            .intoAnyElement()
    }
}

// MARK: - Retained iOS Application Runtime

@MainActor
private final class IosDemoRuntime {
    static var current: IosDemoRuntime?

    let platform: IosPlatform
    let application: Application
    var windowHandle: WindowHandle<IosShowcaseView>?

    init(demoName: String) {
        let platform = IosPlatform.new()
        let application = Application.withPlatform(platform)
        self.platform = platform
        self.application = application

        application.onOpenUrls { [weak self] urls in
            guard let firstUrl = urls.first else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let handle = self.windowHandle else { return }
                    let app = self.application.app
                    _ = try? app.updateWindow(handle.anyHandle) { view, window, cx in
                        if case .success(let entity) = view.downcast() as Result<Entity<IosShowcaseView>, AnyView> {
                            entity.update(cx) { model, _ in
                                model.lastOpenedUrl = firstUrl
                            }
                        }
                        var appCopy = cx
                        window.refresh()
                        window.draw(cx: &appCopy)
                    }
                }
            }
        }

        application.run { [weak self] cx in
            guard let self else { return }
            do {
                let handle = try cx.openWindow(WindowOptions()) { _, app in
                    app.new { _ in
                        IosShowcaseView(activeDemo: demoName)
                    }
                }
                self.windowHandle = handle

                if let iosWin = platform.iosWindow(for: handle.anyHandle) {
                    bindIosWindowCallbacks(
                        handle: handle.anyHandle,
                        iosWindow: iosWin,
                        app: cx
                    )
                    // Draw initial frame immediately so first visible frame is populated.
                    _ = try? cx.updateWindow(handle.anyHandle) { _, window, app in
                        var appCopy = app
                        window.draw(cx: &appCopy)
                    }
                }
            } catch {
                IosLogger.shared.error("Failed to open iOS demo window: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - C ABI Entry Points (`app_bridge.rs`)

/// Launches the GPUI iOS application showcasing the named demo (defaulting to `"hello_world"`
/// when `demoNamePtr` is null or empty), matching upstream C ABI `gpui_ios_run_demo`.
@_cdecl("gpui_ios_run_demo")
public func gpuiIosRunDemo(_ demoNamePtr: UnsafePointer<CChar>?) {
    let requestedName: String
    if let demoNamePtr {
        let decoded = String(cString: demoNamePtr).trimmingCharacters(in: .whitespacesAndNewlines)
        requestedName = decoded.isEmpty ? "hello_world" : decoded
    } else {
        requestedName = "hello_world"
    }

    IosLogger.shared.info("Launching GPUI iOS demo: \(requestedName)")

    let launchBlock: @MainActor () -> Void = {
        UserDefaults.standard.set(requestedName, forKey: "GPUI_IOS_LAST_DEMO")
        IosDemoRuntime.current = IosDemoRuntime(demoName: requestedName)
    }

    if Thread.isMainThread {
        MainActor.assumeIsolated(launchBlock)
    } else {
        DispatchQueue.main.async {
            MainActor.assumeIsolated(launchBlock)
        }
    }
}

/// Returns a newly heap-allocated, newline-separated UTF-8 C string listing all built-in iOS
/// demos (caller frees via `gpui_ios_free_string`), matching upstream `gpui_ios_list_demos`.
@_cdecl("gpui_ios_list_demos")
public func gpuiIosListDemos() -> UnsafeMutablePointer<CChar>? {
    let joined = gpuiIosDemoCatalog.joined(separator: "\n")
    return strdup(joined)
}

/// Frees a C string previously returned by `gpui_ios_list_demos`, matching upstream
/// `gpui_ios_free_string`.
@_cdecl("gpui_ios_free_string")
public func gpuiIosFreeString(_ ptr: UnsafeMutablePointer<CChar>?) {
    guard let ptr else { return }
    free(ptr)
}
#endif
