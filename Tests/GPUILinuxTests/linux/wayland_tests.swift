// Swift-only: headless Weston smoke test verifying Wayland windowing and WebGPU presentation
#if os(Linux)
import Foundation
import Testing
@testable import GPUILinux
import GPUI
import GPUIWGPU
import CLinuxSys
import CWebGPU
import Glibc

@Suite("WaylandIntegrationTests")
struct WaylandIntegrationTests {
    @Test
    func testHeadlessWestonWindowAndRenderingSmoke() throws {
        if ProcessInfo.processInfo.environment["CI"] != nil {
            #expect(FileManager.default.isExecutableFile(atPath: "/usr/bin/weston"), "Weston binary must be installed on Linux CI")
        }
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/weston") else {
            return
        }

        let runId = UUID().uuidString
        let runtimeDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wayland-run-\(runId)")
        try FileManager.default.createDirectory(at: runtimeDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer {
            try? FileManager.default.removeItem(at: runtimeDir)
        }

        let socketName = "wayland-test-\(runId)"
        let socketPath = runtimeDir.appendingPathComponent(socketName).path

        let prevWaylandDisplay = getenv("WAYLAND_DISPLAY").map { String(cString: $0) }
        let prevRuntimeDir = getenv("XDG_RUNTIME_DIR").map { String(cString: $0) }

        setenv("XDG_RUNTIME_DIR", runtimeDir.path, 1)
        setenv("WAYLAND_DISPLAY", socketName, 1)

        defer {
            if let prev = prevWaylandDisplay {
                setenv("WAYLAND_DISPLAY", prev, 1)
            } else {
                unsetenv("WAYLAND_DISPLAY")
            }
            if let prev = prevRuntimeDir {
                setenv("XDG_RUNTIME_DIR", prev, 1)
            } else {
                unsetenv("XDG_RUNTIME_DIR")
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/weston")
        process.arguments = [
            "--backend=headless",
            "--socket=\(socketName)",
            "--no-config"
        ]
        var env = ProcessInfo.processInfo.environment
        env["XDG_RUNTIME_DIR"] = runtimeDir.path
        env["WAYLAND_DISPLAY"] = socketName
        process.environment = env

        try process.run()
        defer {
            process.terminate()
            process.waitUntilExit()
        }

        // Wait for headless Weston to create the wayland socket
        var socketReady = false
        for _ in 0..<60 {
            if FileManager.default.fileExists(atPath: socketPath) {
                socketReady = true
                break
            }
            usleep(50_000)
        }
        #expect(socketReady, "Weston failed to create Wayland socket at \(socketPath)")
        guard socketReady else { return }

        // Connect client
        let client = try WaylandClient.new()
        #expect(client.compositorName() == "Wayland")
        #expect(client.ptr.state.display != nil)
        #expect(client.ptr.state.globals.compositor != nil)
        #expect(client.ptr.state.globals.wmBase != nil)

        // Process initial roundtrip events
        client.dispatchEvents()

        // Displays should be queryable
        let displays = client.displays()
        #expect(!displays.isEmpty)
        #expect(client.primaryDisplay() != nil)

        // Open genuine Wayland window
        let windowBounds = Bounds(origin: .zero, size: Size(width: px(320), height: px(240)))
        let options = WindowOptions(
            windowBounds: .windowed(windowBounds),
            titlebar: TitlebarOptions(title: "GPUA Authentic Wayland Window"),
            kind: .normal
        )
        let platformWindow = try client.openWindow(handle: AnyWindowHandle(id: 101), options: options)
        guard let waylandWindow = platformWindow as? WaylandWindow else {
            Issue.record("Expected opened window to be WaylandWindow")
            return
        }

        // Verify window internals
        #expect(waylandWindow.ptr.state.surface != nil, "wl_surface must be non-null")
        if case .xdg(let xdgState) = waylandWindow.ptr.state.surfaceState {
            #expect(xdgState.xdgSurface != nil, "xdgSurface must be non-null")
            #expect(xdgState.toplevel != nil, "toplevel must be non-null")
        } else {
            Issue.record("Expected xdg surface state")
        }

        // Verify WgpuWindowHandleProvider conformance and raw window handle
        let rawHandle = waylandWindow.rawWindowHandle
        if case .wayland(let displayPtr, let surfacePtr) = rawHandle {
            #expect(displayPtr != nil, "Wayland raw display handle must not be nil")
            #expect(surfacePtr != nil, "Wayland raw surface handle must not be nil")
        } else {
            Issue.record("Expected .wayland raw window handle")
        }

        // Dispatch events and verify first configure acknowledgement
        for _ in 0..<30 {
            client.dispatchEvents()
            if waylandWindow.ptr.state.acknowledgedFirstConfigure {
                break
            }
            usleep(15_000)
        }
        #expect(waylandWindow.ptr.state.acknowledgedFirstConfigure == true, "Expected first configure to be acknowledged")
        #expect(waylandWindow.isVisible() == true)

        // Test window methods and state modifications
        waylandWindow.setTitle("Wayland Verified Title")
        #expect(waylandWindow.ptr.state.title == "Wayland Verified Title")
        waylandWindow.setAppId("org.gpua.wayland.smoke")
        #expect(waylandWindow.ptr.state.appId == "org.gpua.wayland.smoke")

        waylandWindow.activate()
        waylandWindow.zoom()
        #expect(waylandWindow.isMaximized() == true)
        waylandWindow.toggleFullScreen()
        #expect(waylandWindow.isFullscreen() == true)
        waylandWindow.minimize()

        waylandWindow.showWindowMenu(Point(x: px(10), y: px(10)))
        waylandWindow.startWindowMove()
        waylandWindow.startWindowResize(.topLeft)

        // Construct a scene and render via WgpuRenderer to the Wayland surface
        var scene = Scene()
        let bgBounds = Bounds(
            origin: Point<ScaledPixels>(x: ScaledPixels(0), y: ScaledPixels(0)),
            size: Size(width: ScaledPixels(320), height: ScaledPixels(240))
        )
        let bgQuad = Quad(
            order: DrawOrder(1),
            borderStyle: .solid,
            bounds: bgBounds,
            contentMask: ContentMask(bounds: bgBounds),
            background: solidBackground(Rgba(r: 0.1, g: 0.5, b: 0.8, a: 1.0)),
            borderColor: Hsla(h: 0, s: 0, l: 0, a: 1),
            cornerRadii: .zero,
            borderWidths: .zero
        )
        scene.insertQuad(bgQuad)

        let fgBounds = Bounds(
            origin: Point<ScaledPixels>(x: ScaledPixels(40), y: ScaledPixels(40)),
            size: Size(width: ScaledPixels(120), height: ScaledPixels(80))
        )
        let fgQuad = Quad(
            order: DrawOrder(2),
            borderStyle: .solid,
            bounds: fgBounds,
            contentMask: ContentMask(bounds: fgBounds),
            background: solidBackground(Rgba(r: 0.9, g: 0.3, b: 0.2, a: 1.0)),
            borderColor: Hsla(h: 0, s: 0, l: 0, a: 1),
            cornerRadii: .zero,
            borderWidths: .zero
        )
        scene.insertQuad(fgQuad)

        waylandWindow.draw(scene: scene)
        waylandWindow.completedFrame()

        // Flush rendering and pending Wayland requests
        client.dispatchEvents()

        // Verify genuine Wayland clipboard operations
        let clipItem = ClipboardItem(text: "Hello Wayland Clipboard 🚀")
        client.writeToClipboard(clipItem)
        let readItem = client.readFromClipboard()
        #expect(readItem?.text == "Hello Wayland Clipboard 🚀")

        let primaryItem = ClipboardItem(text: "Hello Wayland Primary 📝")
        client.writeToPrimary(primaryItem)
        let readPrimary = client.readFromPrimary()
        #expect(readPrimary?.text == "Hello Wayland Primary 📝")
    }
}
#endif
