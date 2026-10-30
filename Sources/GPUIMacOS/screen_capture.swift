// Ported from: crates/gpui_macos/src/screen_capture.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(macOS)
import AppKit
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import GPUI
import ScreenCaptureKit

/// Metadata describing a capturable screen display.
public struct SourceMetadata: Sendable, Equatable {
    public var id: UInt64
    public var label: SharedString?
    public var isMain: Bool?
    public var resolution: Size<DevicePixels>

    public init(
        id: UInt64,
        label: SharedString? = nil,
        isMain: Bool? = nil,
        resolution: Size<DevicePixels>
    ) {
        self.id = id
        self.label = label
        self.isMain = isMain
        self.resolution = resolution
    }
}

/// A captured display frame delivered by `MacScreenCaptureStream`.
// PORT NOTE: CMSampleBuffer is an immutable CoreMedia sample container safe to pass to frame consumers.
public struct ScreenCaptureFrame: @unchecked Sendable {
    public let sampleBuffer: CMSampleBuffer

    public init(sampleBuffer: CMSampleBuffer) {
        self.sampleBuffer = sampleBuffer
    }
}

private struct ScreenMeta: Sendable {
    var label: SharedString
    var isMain: Bool
}

private final class StreamDelegate: NSObject, SCStreamDelegate, Sendable {
    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        _ = stream
        _ = error
    }
}

// PORT NOTE: Forwards ScreenCaptureKit sample buffers on ScreenCaptureKit's sample queue to a Sendable callback.
private final class StreamOutputHandler: NSObject, SCStreamOutput, @unchecked Sendable {
    let frameCallback: @Sendable (ScreenCaptureFrame) -> Void

    init(frameCallback: @escaping @Sendable (ScreenCaptureFrame) -> Void) {
        self.frameCallback = frameCallback
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        _ = stream
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer) else {
            return
        }
        frameCallback(ScreenCaptureFrame(sampleBuffer: sampleBuffer))
    }
}

/// Active `SCStream` session capturing frames from a `MacScreenCaptureSource`.
// PORT NOTE: Wraps SCStream and its output handler; teardown stops capture cleanly on deinit.
public final class MacScreenCaptureStream: @unchecked Sendable {
    private let scStream: SCStream
    private let scDelegate: StreamDelegate
    private let scStreamOutput: StreamOutputHandler
    private let meta: SourceMetadata

    fileprivate init(
        scStream: SCStream,
        scDelegate: StreamDelegate,
        scStreamOutput: StreamOutputHandler,
        meta: SourceMetadata
    ) {
        self.scStream = scStream
        self.scDelegate = scDelegate
        self.scStreamOutput = scStreamOutput
        self.meta = meta
    }

    public func metadata() throws -> SourceMetadata {
        meta
    }

    deinit {
        try? scStream.removeStreamOutput(scStreamOutput, type: .screen)
        scStream.stopCapture { _ in }
    }
}

/// ScreenCaptureKit-backed `ScreenCaptureSource` representing a macOS display.
// PORT NOTE: Wraps immutable SCDisplay descriptor returned by SCShareableContent.
public final class MacScreenCaptureSource: ScreenCaptureSource, @unchecked Sendable {
    private let scDisplay: SCDisplay
    private let meta: ScreenMeta?

    fileprivate init(scDisplay: SCDisplay, meta: ScreenMeta?) {
        self.scDisplay = scDisplay
        self.meta = meta
    }

    public var id: String {
        String(scDisplay.displayID)
    }

    public var title: String {
        meta?.label.asString ?? "Display \(scDisplay.displayID)"
    }

    public func metadata() throws -> SourceMetadata {
        let displayId = scDisplay.displayID
        let width: Int32
        let height: Int32
        if let mode = CGDisplayCopyDisplayMode(displayId) {
            width = Int32(mode.pixelWidth)
            height = Int32(mode.pixelHeight)
        } else {
            width = Int32(scDisplay.width)
            height = Int32(scDisplay.height)
        }

        return SourceMetadata(
            id: UInt64(displayId),
            label: meta?.label,
            isMain: meta?.isMain,
            resolution: size(DevicePixels(width), DevicePixels(height))
        )
    }

    public func stream(
        foregroundExecutor: ForegroundExecutor?,
        frameCallback: @escaping @Sendable (ScreenCaptureFrame) -> Void
    ) async throws -> MacScreenCaptureStream {
        _ = foregroundExecutor
        let meta = try metadata()
        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.scalesToFit = true
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.width = Int(meta.resolution.width.value)
        configuration.height = Int(meta.resolution.height.value)

        let delegate = StreamDelegate()
        let output = StreamOutputHandler(frameCallback: frameCallback)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: delegate)
        let queue = DispatchQueue(label: "dev.gpua.screen-capture.\(meta.id)", qos: .userInteractive)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()

        return MacScreenCaptureStream(
            scStream: stream,
            scDelegate: delegate,
            scStreamOutput: output,
            meta: meta
        )
    }
}

private func screenIdToHumanLabel() -> [CGDirectDisplayID: ScreenMeta] {
    let buildOnMain: () -> [CGDirectDisplayID: ScreenMeta] = {
        var map: [CGDirectDisplayID: ScreenMeta] = [:]
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        for (index, screen) in NSScreen.screens.enumerated() {
            guard let number = screen.deviceDescription[key] as? NSNumber else {
                continue
            }
            let displayId = CGDirectDisplayID(number.uint32Value)
            map[displayId] = ScreenMeta(
                label: SharedString(screen.localizedName),
                isMain: index == 0
            )
        }
        return map
    }

    if Thread.isMainThread {
        return buildOnMain()
    } else {
        return DispatchQueue.main.sync(execute: buildOnMain)
    }
}

/// Enumerates all capturable displays via `ScreenCaptureKit`.
func getSources() async throws -> [any ScreenCaptureSource] {
    let labels = screenIdToHumanLabel()
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    return content.displays.map { display in
        MacScreenCaptureSource(
            scDisplay: display,
            meta: labels[display.displayID]
        )
    }
}
#endif
