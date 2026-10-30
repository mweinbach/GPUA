// Swift-only: Android display metrics, density scale factor, and safe-area inset reconciliation per ADR-0012

import Foundation
import GPUI

/// Snapshot of Android `DisplayMetrics`, refresh rate, and `WindowInsets` in physical device pixels.
public struct AndroidDisplayMetrics: Sendable, Equatable {
    public var widthPixels: Int32
    public var heightPixels: Int32
    public var density: Float
    public var densityDpi: Int32
    public var scaledDensity: Float
    public var xdpi: Float
    public var ydpi: Float
    public var refreshRateHz: Float
    public var safeAreaInsetsPx: EdgeInsets<Int32>

    public init(
        widthPixels: Int32 = 1080,
        heightPixels: Int32 = 2400,
        density: Float = 2.75,
        densityDpi: Int32 = 440,
        scaledDensity: Float? = nil,
        xdpi: Float? = nil,
        ydpi: Float? = nil,
        refreshRateHz: Float = 60.0,
        safeAreaInsetsPx: EdgeInsets<Int32> = EdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    ) {
        self.widthPixels = max(1, widthPixels)
        self.heightPixels = max(1, heightPixels)
        let sanitizedDensity = (density.isFinite && density > 0.0) ? density : 1.0
        self.density = sanitizedDensity
        self.densityDpi = densityDpi > 0 ? densityDpi : Int32((sanitizedDensity * 160.0).rounded())
        self.scaledDensity = scaledDensity ?? sanitizedDensity
        let defaultDpi = Float(self.densityDpi)
        self.xdpi = xdpi ?? defaultDpi
        self.ydpi = ydpi ?? defaultDpi
        self.refreshRateHz = (refreshRateHz.isFinite && refreshRateHz > 0.0) ? refreshRateHz : 60.0
        self.safeAreaInsetsPx = EdgeInsets(
            top: max(0, safeAreaInsetsPx.top),
            left: max(0, safeAreaInsetsPx.left),
            bottom: max(0, safeAreaInsetsPx.bottom),
            right: max(0, safeAreaInsetsPx.right)
        )
    }

    /// Validated logical-to-physical scale factor (`density`).
    public var scaleFactor: Float {
        (density.isFinite && density > 0.0) ? density : 1.0
    }

    /// Physical pixel dimensions of the display.
    public var physicalSize: Size<DevicePixels> {
        Size(width: DevicePixels(widthPixels), height: DevicePixels(heightPixels))
    }

    /// Full logical bounds in density-independent GPUI `Pixels` (`dp`).
    public var logicalSize: Size<Pixels> {
        let scale = scaleFactor
        return Size(
            width: px(Float(widthPixels) / scale),
            height: px(Float(heightPixels) / scale)
        )
    }

    /// Full logical bounds starting at `.zero`.
    public var logicalBounds: Bounds<Pixels> {
        Bounds(origin: .zero, size: logicalSize)
    }

    /// Safe-area insets (status bar, navigation bar, display cutout, IME) converted to logical `Pixels`.
    public var safeAreaInsetsLogical: EdgeInsets<Pixels> {
        let scale = scaleFactor
        return EdgeInsets(
            top: px(Float(max(0, safeAreaInsetsPx.top)) / scale),
            left: px(Float(max(0, safeAreaInsetsPx.left)) / scale),
            bottom: px(Float(max(0, safeAreaInsetsPx.bottom)) / scale),
            right: px(Float(max(0, safeAreaInsetsPx.right)) / scale)
        )
    }

    /// Usable logical bounds after subtracting system bar / display cutout / IME safe-area insets.
    public var visibleBounds: Bounds<Pixels> {
        let full = logicalSize
        let insets = safeAreaInsetsLogical
        let originX = min(insets.left.value, full.width.value)
        let originY = min(insets.top.value, full.height.value)
        let usableWidth = max(0.0, full.width.value - originX - insets.right.value)
        let usableHeight = max(0.0, full.height.value - originY - insets.bottom.value)
        return Bounds(
            origin: Point(x: px(originX), y: px(originY)),
            size: Size(width: px(usableWidth), height: px(usableHeight))
        )
    }

    /// Nominal frame interval in seconds derived from `refreshRateHz`.
    public var vsyncInterval: TimeInterval {
        1.0 / Double(max(1.0, refreshRateHz))
    }
}

/// Android implementation of GPUI's `PlatformDisplay`.
// PORT NOTE: Synchronized via NSLock so display metrics/insets updates from JNI are thread-safe.
public final class AndroidDisplay: PlatformDisplay, @unchecked Sendable {
    private let lock = NSLock()
    private let displayId: DisplayId
    private var metrics: AndroidDisplayMetrics

    public init(
        id: DisplayId = DisplayId(0),
        metrics: AndroidDisplayMetrics = AndroidDisplayMetrics()
    ) {
        self.displayId = id
        self.metrics = metrics
    }

    public func id() -> DisplayId {
        displayId
    }

    public func visibleBounds() -> Bounds<Pixels> {
        lock.lock()
        defer { lock.unlock() }
        return metrics.visibleBounds
    }

    public func bounds() -> Bounds<Pixels> {
        lock.lock()
        defer { lock.unlock() }
        return metrics.logicalBounds
    }

    public func physicalSize() -> Size<DevicePixels> {
        lock.lock()
        defer { lock.unlock() }
        return metrics.physicalSize
    }

    public func scaleFactor() -> Float {
        lock.lock()
        defer { lock.unlock() }
        return metrics.scaleFactor
    }

    public func refreshRateHz() -> Float {
        lock.lock()
        defer { lock.unlock() }
        return metrics.refreshRateHz
    }

    public func safeAreaInsets() -> EdgeInsets<Pixels> {
        lock.lock()
        defer { lock.unlock() }
        return metrics.safeAreaInsetsLogical
    }

    public func currentMetrics() -> AndroidDisplayMetrics {
        lock.lock()
        defer { lock.unlock() }
        return metrics
    }

    public func updateMetrics(_ newMetrics: AndroidDisplayMetrics) {
        lock.lock()
        self.metrics = newMetrics
        lock.unlock()
    }

    public func updateSize(
        widthPx: Int32,
        heightPx: Int32,
        density: Float? = nil,
        densityDpi: Int32? = nil,
        refreshRateHz: Float? = nil
    ) {
        lock.lock()
        var updated = metrics
        if widthPx > 0 {
            updated.widthPixels = widthPx
        }
        if heightPx > 0 {
            updated.heightPixels = heightPx
        }
        if let density = density, density.isFinite && density > 0.0 {
            updated.density = density
            if densityDpi == nil {
                updated.densityDpi = Int32((density * 160.0).rounded())
            }
        }
        if let densityDpi = densityDpi, densityDpi > 0 {
            updated.densityDpi = densityDpi
        }
        if let refreshRateHz = refreshRateHz, refreshRateHz.isFinite && refreshRateHz > 0.0 {
            updated.refreshRateHz = refreshRateHz
        }
        self.metrics = updated
        lock.unlock()
    }

    public func updateSafeAreaInsets(topPx: Int32, leftPx: Int32, bottomPx: Int32, rightPx: Int32) {
        lock.lock()
        metrics.safeAreaInsetsPx = EdgeInsets(
            top: max(0, topPx),
            left: max(0, leftPx),
            bottom: max(0, bottomPx),
            right: max(0, rightPx)
        )
        lock.unlock()
    }
}
