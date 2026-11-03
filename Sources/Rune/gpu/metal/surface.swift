// Ported from: crates/rune/src/gpu/metal/surface.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `CAMetalLayer` presentation surface (`MetalSurface`) and acquired drawable (`MetalOutput`).

#if canImport(Metal)
import Metal
import QuartzCore
#endif
#if os(macOS)
import AppKit
#endif
import CWebGPU

public enum MetalSurfaceStatus: Sendable, Equatable {
    case good
    case suboptimal
    case timeout
    case occluded
    case outdated
    case lost
}

/// Acquired drawable for a single presented frame.
// PORT NOTE: Wraps a single-frame `CAMetalDrawable` and its `MetalTexture`.
public final class MetalOutput: @unchecked Sendable {
    public let texture: MetalTexture?
    public let status: MetalSurfaceStatus
    #if canImport(Metal)
    public let drawable: (any CAMetalDrawable)?

    public init(texture: MetalTexture?, drawable: (any CAMetalDrawable)?, status: MetalSurfaceStatus) {
        self.texture = texture
        self.drawable = drawable
        self.status = status
    }
    #else
    public init(texture: MetalTexture?, status: MetalSurfaceStatus) {
        self.texture = texture
        self.status = status
    }
    #endif
}

/// Presentation surface backed by a `CAMetalLayer` on Apple platforms.
// PORT NOTE: Synchronizes configuration via `lock` (`LiveLock`); UIKit/AppKit `CAMetalLayer` properties are updated on configure/acquire.
public final class MetalSurface: @unchecked Sendable {
    private let lock = LiveLock()
    private var configuredFormat: WGPUTextureFormat = WGPUTextureFormat_BGRA8UnormSrgb
    private var configuredWidth: UInt32 = 0
    private var configuredHeight: UInt32 = 0
    private weak var sharedRef: MetalShared?
    #if canImport(Metal)
    public let layer: CAMetalLayer?
    #endif
    #if os(macOS)
    private weak var hostingWindow: NSWindow?
    #endif

    #if canImport(Metal)
    public init(layer: CAMetalLayer? = nil, window: AnyObject? = nil) {
        self.layer = layer
        #if os(macOS)
        self.hostingWindow = window as? NSWindow
        #else
        _ = window
        #endif
    }
    #else
    public init(window: AnyObject? = nil) {
        _ = window
    }
    #endif

    public var supportedFormats: [WGPUTextureFormat] {
        [
            WGPUTextureFormat_BGRA8UnormSrgb,
            WGPUTextureFormat_BGRA8Unorm,
            WGPUTextureFormat_RGBA16Float,
            WGPUTextureFormat_RGB10A2Unorm,
        ]
    }

    public func configure(
        device: MetalDevice,
        format: WGPUTextureFormat,
        width: UInt32,
        height: UInt32,
        alphaOpaque: Bool = true,
        displaySync: Bool = true
    ) {
        lock.withLock {
            self.sharedRef = device.shared
            self.configuredFormat = format
            self.configuredWidth = width
            self.configuredHeight = height
            #if canImport(Metal)
            if let layer {
                layer.device = device.shared.mtlDevice
                layer.pixelFormat = metalPixelFormat(for: format)
                layer.drawableSize = CGSize(width: Double(max(1, width)), height: Double(max(1, height)))
                layer.isOpaque = alphaOpaque
                layer.framebufferOnly = true
                layer.presentsWithTransaction = false
                layer.maximumDrawableCount = 3
                #if os(macOS)
                layer.displaySyncEnabled = displaySync
                #else
                _ = displaySync
                #endif
            }
            #else
            _ = (alphaOpaque, displaySync)
            #endif
        }
    }

    public func getCurrentTexture() -> MetalOutput {
        let (shared, format): (MetalShared?, WGPUTextureFormat) = lock.withLock {
            (sharedRef, configuredFormat)
        }
        #if os(macOS)
        if let win = hostingWindow, Thread.isMainThread {
            let visible = MainActor.assumeIsolated { win.occlusionState.contains(.visible) }
            if !visible {
                #if canImport(Metal)
                return MetalOutput(texture: nil, drawable: nil, status: .occluded)
                #else
                return MetalOutput(texture: nil, status: .occluded)
                #endif
            }
        }
        #endif
        #if canImport(Metal)
        guard let shared, let layer else {
            return MetalOutput(texture: nil, drawable: nil, status: .lost)
        }
        shared.pace()
        guard let drawable = layer.nextDrawable() else {
            return MetalOutput(texture: nil, drawable: nil, status: .timeout)
        }
        let tex = MetalTexture(rawTexture: drawable.texture, format: format, shared: shared, owner: drawable)
        return MetalOutput(texture: tex, drawable: drawable, status: .good)
        #else
        _ = (shared, format)
        return MetalOutput(texture: nil, status: .lost)
        #endif
    }
}
