// Swift-only: Native Swift UIApplicationDelegate entry point for Hosts/iOS replacing Objective-C main.m per ADR-0011

import Foundation
import GPUI
import GPUIPlatform
import UIKit

@_silgen_name("gpui_ios_run_demo")
private func gpuiIosRunDemoBridge(_ name: UnsafePointer<CChar>?)

@_silgen_name("gpui_ios_handle_open_url")
private func gpuiIosHandleOpenUrlBridge(_ url: UnsafePointer<CChar>?)

@main
final class GPUIAppDelegate: UIResponder, UIApplicationDelegate {
    private static let lastDemoDefaultsKey = "GPUI_IOS_LAST_DEMO"

    private static let knownDemos: Set<String> = [
        // Upstream main.m launcher demo names
        "hello_world",
        "touch",
        "text",
        "lifecycle",
        "combined",
        "scroll",
        "text_input",
        "vertical_scroll",
        "horizontal_scroll",
        "pinch",
        "rotation",
        "controls",
        "safe_area",
        "layout_showcase",
        "file_picker",
        "clipboard",
        "file_drop",
        // Built-in app_bridge demo catalog names
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

    private var didLaunchDemo = false

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        _ = application
        launchSelectedDemoIfNeeded()

        if let launchUrl = launchOptions?[.url] as? URL {
            forwardOpenUrl(launchUrl)
        }
        return true
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        _ = app
        _ = options
        forwardOpenUrl(url)
        return true
    }

    private func launchSelectedDemoIfNeeded() {
        guard !didLaunchDemo else { return }
        didLaunchDemo = true

        let processInfo = ProcessInfo.processInfo
        let args = processInfo.arguments
        let env = processInfo.environment
        let defaults = UserDefaults.standard

        var selectedDemo = env["GPUI_IOS_DEMO"] ?? ""

        if selectedDemo.isEmpty, args.count > 1 {
            for candidate in args.dropFirst().reversed() where Self.knownDemos.contains(candidate) {
                selectedDemo = candidate
                break
            }
        }

        if selectedDemo.isEmpty,
           let savedDemo = defaults.string(forKey: Self.lastDemoDefaultsKey),
           !savedDemo.isEmpty
        {
            selectedDemo = savedDemo
        }

        if selectedDemo.isEmpty {
            selectedDemo = "hello_world"
        }

        defaults.set(selectedDemo, forKey: Self.lastDemoDefaultsKey)
        NSLog("[GPUI-iOS] launch args=%@ selected_demo=%@", args.description, selectedDemo)

        selectedDemo.withCString { cStr in
            gpuiIosRunDemoBridge(cStr)
        }
    }

    private func forwardOpenUrl(_ url: URL) {
        url.absoluteString.withCString { cStr in
            gpuiIosHandleOpenUrlBridge(cStr)
        }
    }
}
