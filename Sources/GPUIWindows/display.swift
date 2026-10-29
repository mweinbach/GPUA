// Ported from: crates/gpui_windows/src/display.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Windows)
import Foundation
import GPUI
import GPUICollections
import GPUIUtil
import ZedUtil
#if canImport(CWinSys)
import CWinSys
#endif

// PORT NOTE: WindowsDisplay represents a Windows HMONITOR display with logical and physical bounds and scale factor.
public final class WindowsDisplay: PlatformDisplay, @unchecked Sendable {
    public let handle: WinHandle?
    public let displayId: DisplayId
    public let scaleFactor: Float
    private let _bounds: Bounds<Pixels>
    private let _visibleBounds: Bounds<Pixels>
    private let _physicalBounds: Bounds<DevicePixels>
    private let _uuid: UUID

    public init(
        displayId: DisplayId,
        scaleFactor: Float,
        bounds: Bounds<Pixels>,
        visibleBounds: Bounds<Pixels>,
        physicalBounds: Bounds<DevicePixels>,
        uuid: UUID,
        handle: WinHandle? = nil
    ) {
        self.displayId = displayId
        self.scaleFactor = scaleFactor
        self._bounds = bounds
        self._visibleBounds = visibleBounds
        self._physicalBounds = physicalBounds
        self._uuid = uuid
        self.handle = handle
    }

    public convenience init?(handle: WinHandle?, displayId: DisplayId) {
        guard let handle = handle else { return nil }
        var info = CWinMonitorInfo()
        guard cwin_win32_get_monitor_info(handle, &info) == 0 else { return nil }

        let scale = Float(info.dpi_x) / 96.0
        let pWidth = DevicePixels(info.monitor_right - info.monitor_left)
        let pHeight = DevicePixels(info.monitor_bottom - info.monitor_top)
        let physicalSize = Size(width: pWidth, height: pHeight)
        let physicalOrigin = Point(
            x: DevicePixels(info.monitor_left),
            y: DevicePixels(info.monitor_top)
        )
        let physBounds = Bounds(origin: physicalOrigin, size: physicalSize)

        let logicalOrigin = logicalPoint(
            x: Float(info.monitor_left),
            y: Float(info.monitor_top),
            scaleFactor: scale
        )
        let logicalSize = physicalSize.toPixels(scale)
        let logBounds = Bounds(origin: logicalOrigin, size: logicalSize)

        let workWidth = Float(info.work_right - info.work_left) / scale
        let workHeight = Float(info.work_bottom - info.work_top) / scale
        let visOrigin = logicalPoint(
            x: Float(info.work_left),
            y: Float(info.work_top),
            scaleFactor: scale
        )
        let visBounds = Bounds(
            origin: visOrigin,
            size: Size(width: px(workWidth), height: px(workHeight))
        )

        let nameStr = withUnsafePointer(to: info.device_name) { ptr in
            ptr.withMemoryRebound(to: UInt16.self, capacity: 32) { u16Ptr in
                fromWideString(u16Ptr)
            }
        }
        let deterministicUUID = WindowsDisplay.generateUUID(from: nameStr)

        self.init(
            displayId: displayId,
            scaleFactor: scale,
            bounds: logBounds,
            visibleBounds: visBounds,
            physicalBounds: physBounds,
            uuid: deterministicUUID,
            handle: handle
        )
    }

    public convenience init?(displayId: DisplayId) {
        let displays = WindowsDisplay.availableMonitors()
        let idx = Int(displayId.rawValue)
        guard idx >= 0 && idx < displays.count else { return nil }
        self.init(handle: displays[idx], displayId: displayId)
    }

    // MARK: - PlatformDisplay Conformance

    public func id() -> DisplayId {
        displayId
    }

    public func visibleBounds() -> Bounds<Pixels> {
        self._visibleBounds
    }

    public func bounds() -> Bounds<Pixels> {
        self._bounds
    }

    public func physicalBounds() -> Bounds<DevicePixels> {
        self._physicalBounds
    }

    public func uuid() throws -> UUID {
        self._uuid
    }

    // MARK: - Query & Enumeration

    public func checkGivenBounds(_ bounds: Bounds<Pixels>) -> Bool {
        let center = bounds.center()
        let cx = Int32(center.x.value * scaleFactor)
        let cy = Int32(center.y.value * scaleFactor)
        let monitor = cwin_win32_monitor_from_point(cx, cy, 0)
        guard let monitor = monitor else { return false }
        return monitor == self.handle
    }

    public static func primaryMonitor() -> WindowsDisplay? {
        let hmon = cwin_win32_primary_monitor()
        guard let hmon = hmon else { return nil }
        return WindowsDisplay(handle: hmon, displayId: DisplayId(0))
    }

    public static func availableMonitors() -> [WinHandle] {
        var monitors = [CWinMonitorInfo](repeating: CWinMonitorInfo(), count: 16)
        var count: UInt32 = 0
        let status = monitors.withUnsafeMutableBufferPointer { buf in
            cwin_win32_get_monitors(buf.baseAddress, UInt32(buf.count), &count)
        }
        guard status == 0 && count > 0 else {
            if let primary = cwin_win32_primary_monitor() {
                return [primary]
            }
            return []
        }
        return (0..<Int(count)).compactMap { idx in
            monitors[idx].handle
        }
    }

    public static func displays() -> [any PlatformDisplay] {
        let monitors = availableMonitors()
        if monitors.isEmpty {
            // Fallback default display for headless environments
            return [
                WindowsDisplay(
                    displayId: DisplayId(0),
                    scaleFactor: 1.0,
                    bounds: Bounds(origin: .zero, size: Size(width: px(1920), height: px(1080))),
                    visibleBounds: Bounds(origin: .zero, size: Size(width: px(1920), height: px(1080))),
                    physicalBounds: Bounds(origin: .zero, size: Size(width: DevicePixels(1920), height: DevicePixels(1080))),
                    uuid: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
                )
            ]
        }
        return monitors.enumerated().compactMap { idx, handle in
            WindowsDisplay(handle: handle, displayId: DisplayId(UInt32(idx)))
        }
    }

    private static func generateUUID(from deviceName: String) -> UUID {
        var data = Data(deviceName.utf8)
        while data.count < 16 {
            data.append(0)
        }
        let b = [UInt8](data.prefix(16))
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}

#endif
