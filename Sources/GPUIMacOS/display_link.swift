// Ported from: crates/gpui_macos/src/display_link.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(macOS)
import CoreGraphics
import CoreVideo
import Foundation

// PORT NOTE: Boxed DispatchSourceUserDataAdd passed through CVDisplayLink's userInfo pointer
// so high-frequency CVDisplayLink ticks coalesce safely onto DispatchQueue.main.
private final class FrameRequestRelay: @unchecked Sendable {
    let source: any DispatchSourceUserDataAdd

    init(source: any DispatchSourceUserDataAdd) {
        self.source = source
    }

    func signal() {
        source.add(data: 1)
    }
}

private func displayLinkOutputCallback(
    _ displayLink: CVDisplayLink,
    _ inNow: UnsafePointer<CVTimeStamp>,
    _ inOutputTime: UnsafePointer<CVTimeStamp>,
    _ flagsIn: CVOptionFlags,
    _ flagsOut: UnsafeMutablePointer<CVOptionFlags>,
    _ displayLinkContext: UnsafeMutableRawPointer?
) -> CVReturn {
    guard let displayLinkContext else {
        return kCVReturnSuccess
    }
    let relay = Unmanaged<FrameRequestRelay>.fromOpaque(displayLinkContext).takeUnretainedValue()
    relay.signal()
    return kCVReturnSuccess
}

/// Synchronizes window frame requests with the display refresh rate via `CVDisplayLink`
/// and coalesces ticks onto the main queue via `DispatchSourceUserDataAdd`.
// PORT NOTE: Lifecycle is controlled by MacWindowState's lock; CVDisplayLink callbacks only
// signal the thread-safe DispatchSourceUserDataAdd.
public final class DisplayLink: @unchecked Sendable {
    private var displayLink: CVDisplayLink?
    private let frameRequests: any DispatchSourceUserDataAdd
    private let relayPtr: UnsafeMutableRawPointer
    private var isRunning: Bool = false

    private init(
        displayLink: CVDisplayLink,
        frameRequests: any DispatchSourceUserDataAdd,
        relayPtr: UnsafeMutableRawPointer
    ) {
        self.displayLink = displayLink
        self.frameRequests = frameRequests
        self.relayPtr = relayPtr
    }

    public static func new(
        displayId: CGDirectDisplayID,
        callback: @escaping @Sendable () -> Void
    ) throws -> DisplayLink {
        let source = DispatchSource.makeUserDataAddSource(queue: .main)
        source.setEventHandler(handler: callback)

        let relay = FrameRequestRelay(source: source)
        let retainedRelay = Unmanaged.passRetained(relay)
        let relayRaw = retainedRelay.toOpaque()

        source.setCancelHandler {
            Unmanaged<FrameRequestRelay>.fromOpaque(relayRaw).release()
        }
        source.resume()

        var linkOut: CVDisplayLink?
        let createResult = CVDisplayLinkCreateWithActiveCGDisplays(&linkOut)
        guard createResult == kCVReturnSuccess, let link = linkOut else {
            source.cancel()
            throw NSError(
                domain: "GPUIMacOS.DisplayLink",
                code: Int(createResult),
                userInfo: [NSLocalizedDescriptionKey: "CVDisplayLinkCreateWithActiveCGDisplays failed: \(createResult)"]
            )
        }

        let setDisplayResult = CVDisplayLinkSetCurrentCGDisplay(link, displayId)
        if setDisplayResult != kCVReturnSuccess {
            source.cancel()
            throw NSError(
                domain: "GPUIMacOS.DisplayLink",
                code: Int(setDisplayResult),
                userInfo: [NSLocalizedDescriptionKey: "CVDisplayLinkSetCurrentCGDisplay failed: \(setDisplayResult)"]
            )
        }

        let callbackResult = CVDisplayLinkSetOutputCallback(link, displayLinkOutputCallback, relayRaw)
        guard callbackResult == kCVReturnSuccess else {
            source.cancel()
            throw NSError(
                domain: "GPUIMacOS.DisplayLink",
                code: Int(callbackResult),
                userInfo: [NSLocalizedDescriptionKey: "CVDisplayLinkSetOutputCallback failed: \(callbackResult)"]
            )
        }

        return DisplayLink(displayLink: link, frameRequests: source, relayPtr: relayRaw)
    }

    public func start() throws {
        guard let link = displayLink else { return }
        if CVDisplayLinkIsRunning(link) {
            isRunning = true
            return
        }
        let res = CVDisplayLinkStart(link)
        guard res == kCVReturnSuccess else {
            throw NSError(
                domain: "GPUIMacOS.DisplayLink",
                code: Int(res),
                userInfo: [NSLocalizedDescriptionKey: "CVDisplayLinkStart failed: \(res)"]
            )
        }
        isRunning = true
    }

    public func stop() throws {
        guard let link = displayLink else { return }
        if !CVDisplayLinkIsRunning(link) {
            isRunning = false
            return
        }
        let res = CVDisplayLinkStop(link)
        isRunning = false
        guard res == kCVReturnSuccess else {
            throw NSError(
                domain: "GPUIMacOS.DisplayLink",
                code: Int(res),
                userInfo: [NSLocalizedDescriptionKey: "CVDisplayLinkStop failed: \(res)"]
            )
        }
    }

    deinit {
        if let link = displayLink, CVDisplayLinkIsRunning(link) {
            _ = CVDisplayLinkStop(link)
        }
        // Retain the CVDisplayLink momentarily on main async so any in-flight CVDisplayLink
        // background thread callback finishes before release, matching upstream Drop safety.
        if let link = displayLink {
            // PORT NOTE: Retaining CVDisplayLink across async main-queue hop prevents CVDisplayLink
            // background timer thread use-after-free during teardown without leaking permanently.
            nonisolated(unsafe) let retainedLink = link
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                _ = retainedLink
            }
        }
        frameRequests.cancel()
    }
}
#endif
