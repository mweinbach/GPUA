// Ported from: crates/gpui_web/src/window_environment.rs
// Upstream commit: 650aab59d54f
// Port status: ported

// Failure modes:
// - Device-pixel ratio changes without a resize observer update.
// - Rebinding the DPR media query during its own callback drops the active closure.
// - Zero-sized canvases must still notify GPUI that the window disappeared.
// - Repeated identical observations must not emit redundant resize work.

import Foundation

struct CanvasMetrics: Sendable, Equatable {
    var physicalWidth: UInt32
    var physicalHeight: UInt32
    var logicalWidth: Float
    var logicalHeight: Float
    var scaleFactor: Float

    init(
        physicalWidth: UInt32,
        physicalHeight: UInt32,
        logicalWidth: Float,
        logicalHeight: Float,
        scaleFactor: Float
    ) {
        self.physicalWidth = physicalWidth
        self.physicalHeight = physicalHeight
        self.logicalWidth = logicalWidth
        self.logicalHeight = logicalHeight
        self.scaleFactor = scaleFactor
    }
}

struct EnvironmentUpdate: Sendable, Equatable {
    var mediaQuery: String?
    var resize: ResizeUpdate?

    init(mediaQuery: String?, resize: ResizeUpdate?) {
        self.mediaQuery = mediaQuery
        self.resize = resize
    }
}

enum ResizeUpdate: Sendable, Equatable {
    case hidden(scaleFactor: Float)
    case visible(
        logicalWidth: Float,
        logicalHeight: Float,
        physicalWidth: UInt32,
        physicalHeight: UInt32,
        scaleFactor: Float
    )
}

struct WindowEnvironmentState: Sendable {
    private var currentMediaQueryValue: String?
    private var pendingMetrics: CanvasMetrics?
    private var lastEmittedPhysicalSize: (UInt32, UInt32)?
    private var lastEmittedScaleFactor: Float?
    private var dprDirty: Bool

    init(_ initialDpr: Double) {
        self.currentMediaQueryValue = mediaQueryForDpr(initialDpr)
        self.pendingMetrics = nil
        self.lastEmittedPhysicalSize = nil
        self.lastEmittedScaleFactor = nil
        self.dprDirty = false
    }

    static func new(_ initialDpr: Double) -> WindowEnvironmentState {
        WindowEnvironmentState(initialDpr)
    }

    func currentMediaQuery() -> String? {
        currentMediaQueryValue
    }

    mutating func queueResize(_ metrics: CanvasMetrics) {
        pendingMetrics = metrics
    }

    mutating func queueDprChange() {
        dprDirty = true
    }

    func needsMeasurement() -> Bool {
        dprDirty
    }

    mutating func reconcile(
        _ currentDpr: Double,
        _ measuredMetrics: CanvasMetrics?,
        _ maxTextureDimension: UInt32
    ) -> EnvironmentUpdate {
        let nextMediaQuery = mediaQueryForDpr(currentDpr)
        let mediaQuery: String?
        if currentMediaQueryValue != nextMediaQuery {
            currentMediaQueryValue = nextMediaQuery
            mediaQuery = nextMediaQuery
        } else {
            mediaQuery = nil
        }

        if dprDirty, let metrics = measuredMetrics {
            pendingMetrics = metrics
        }

        dprDirty = false

        var resize: ResizeUpdate? = nil
        if let metrics = pendingMetrics {
            pendingMetrics = nil

            let scaleChanged: Bool
            if let lastScale = lastEmittedScaleFactor {
                scaleChanged = !approximatelyEqual(lastScale, metrics.scaleFactor)
            } else {
                scaleChanged = true
            }

            let sizeChanged: Bool
            if let lastSize = lastEmittedPhysicalSize {
                sizeChanged = lastSize.0 != metrics.physicalWidth || lastSize.1 != metrics.physicalHeight
            } else {
                sizeChanged = true
            }

            if scaleChanged || sizeChanged {
                lastEmittedScaleFactor = metrics.scaleFactor
                lastEmittedPhysicalSize = (metrics.physicalWidth, metrics.physicalHeight)

                if metrics.physicalWidth == 0 || metrics.physicalHeight == 0 {
                    resize = .hidden(scaleFactor: metrics.scaleFactor)
                } else {
                    resize = .visible(
                        logicalWidth: metrics.logicalWidth,
                        logicalHeight: metrics.logicalHeight,
                        physicalWidth: min(metrics.physicalWidth, maxTextureDimension),
                        physicalHeight: min(metrics.physicalHeight, maxTextureDimension),
                        scaleFactor: metrics.scaleFactor
                    )
                }
            }
        }

        return EnvironmentUpdate(
            mediaQuery: mediaQuery,
            resize: resize
        )
    }
}

private func mediaQueryForDpr(_ dpr: Double) -> String {
    let formatted = formatDprValue(dpr)
    return "(resolution: \(formatted)dppx), (-webkit-device-pixel-ratio: \(formatted))"
}

private func formatDprValue(_ dpr: Double) -> String {
    if dpr.isFinite && dpr.rounded(.towardZero) == dpr && abs(dpr) < Double(Int64.max) {
        return String(Int64(dpr))
    }
    return String(dpr)
}

private func approximatelyEqual(_ left: Float, _ right: Float) -> Bool {
    abs(left - right) < 0.0001
}
