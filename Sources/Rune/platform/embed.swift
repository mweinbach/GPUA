// Ported from: crates/rune/src/platform/embed.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Embedded `CAMetalLayer` host for UIKit, SwiftUI and AppKit views that own their own window
//! and event loop (e.g. a `UIViewRepresentable` driven by `CADisplayLink` on iOS).

#if canImport(QuartzCore)
import Foundation
import Metal
import QuartzCore

public struct EmbedError: Error, CustomStringConvertible, Sendable, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

private let embedPrewarmLock = LiveLock()
// PORT NOTE: Guarded by `embedPrewarmLock`, matching `STARTED: OnceLock<()>` in `embed.rs`.
nonisolated(unsafe) private var embedPrewarmStarted: Bool = false

/// Outcome of one `LayerHost.frame` pass.
public struct EmbedFrame: Sendable, Equatable {
    /// Whether a drawable was acquired and presented.
    public var drew: Bool
    /// True while springs, reveals, pending input or live bindings need another display-link tick.
    public var animating: Bool
    /// Seconds until the next scheduled timer wake (`nil` when none is pending).
    public var wakeAfterSecs: Double?
    /// CPU time spent stepping layout/motion and encoding GPU work, in microseconds.
    public var cpuUs: UInt64

    public init(
        drew: Bool = false,
        animating: Bool = false,
        wakeAfterSecs: Double? = nil,
        cpuUs: UInt64 = 0
    ) {
        self.drew = drew
        self.animating = animating
        self.wakeAfterSecs = wakeAfterSecs
        self.cpuUs = cpuUs
    }
}

/// Drives one Rune `Runtime` and `Renderer` directly onto a `CAMetalLayer`.
///
/// Pause display-link calls while the host app is backgrounded on iOS: Metal forbids drawable
/// acquisition and command-buffer submission after `didEnterBackground`.
public final class LayerHost<S> {
    private let layer: CAMetalLayer
    private let gpu: Gpu
    private let renderer: Renderer
    private var compositorRender: ((Runtime<S>, Renderer, Double, Double) -> Void)?
    private var compositorAnimating: (() -> Bool)?
    private let rt: Runtime<S>
    private var lastFrameAt: RuneInstant
    private var configWidth: UInt32
    private var configHeight: UInt32
    private var suspended: Bool

    private init(
        layer: CAMetalLayer,
        gpu: Gpu,
        renderer: Renderer,
        rt: Runtime<S>,
        configWidth: UInt32,
        configHeight: UInt32,
        suspended: Bool
    ) {
        self.layer = layer
        self.gpu = gpu
        self.renderer = renderer
        self.compositorRender = nil
        self.compositorAnimating = nil
        self.rt = rt
        self.lastFrameAt = .now()
        self.configWidth = configWidth
        self.configHeight = configHeight
        self.suspended = suspended
    }

    /// Attaches a new Rune runtime and Metal surface to `layer` (`CAMetalLayer *`), blending in
    /// sRGB space (`srgbBlend = true`, matching Apple's native text compositing).
    public static func fromCoreAnimationLayer(
        _ layerPtr: UnsafeMutableRawPointer?,
        _ spec: AppSpec<S>,
        _ state: S,
        _ viewport: (Float, Float),
        _ scale: Float,
        _ dark: Bool,
        _ wake: @escaping Waker
    ) -> Result<LayerHost<S>, EmbedError> {
        guard let layerPtr else {
            return .failure(EmbedError("null CAMetalLayer pointer"))
        }
        let anyObj = Unmanaged<AnyObject>.fromOpaque(layerPtr).takeUnretainedValue()
        guard let metalLayer = anyObj as? CAMetalLayer else {
            return .failure(EmbedError("pointer is not a CAMetalLayer"))
        }
        if metalLayer.device == nil {
            guard let device = MTLCreateSystemDefaultDevice() else {
                return .failure(EmbedError("Metal device unavailable"))
            }
            metalLayer.device = device
        }
        let clampedScale = max(scale, 1.0)
        let maxDim: UInt32 = 16384
        let pxW = min(max(UInt32((max(viewport.0, 1.0) * clampedScale).rounded()), 1), maxDim)
        let pxH = min(max(UInt32((max(viewport.1, 1.0) * clampedScale).rounded()), 1), maxDim)
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.contentsScale = CGFloat(clampedScale)
        metalLayer.drawableSize = CGSize(width: CGFloat(pxW), height: CGFloat(pxH))

        let renderer = Renderer()
        renderer.setSrgbBlend(true)

        let w = Float(pxW) / clampedScale
        let h = Float(pxH) / clampedScale
        var mutableState = state
        spec.setup?(&mutableState, wake)
        let rt = Runtime.withText(
            mutableState,
            spec.view,
            (w, h),
            Env.new(dark, clampedScale),
            TextSystem.forWindow(spec.fonts, spec.families)
        )
        rt.poll = spec.poll
        rt.onKey = spec.onKey
        rt.srgbBlend = true

        let host = LayerHost(
            layer: metalLayer,
            gpu: Gpu(),
            renderer: renderer,
            rt: rt,
            configWidth: pxW,
            configHeight: pxH,
            suspended: viewport.0 <= 0.0 || viewport.1 <= 0.0
        )
        return .success(host)
    }

    /// Attaches a custom compositor callback for shader passes.
    // PORT NOTE: Accepts closure callbacks rather than `any Compositor<S>` while `compose.swift` is owned by a sibling worker.
    public func withCompositor(
        _ render: @escaping (Runtime<S>, Renderer, Double, Double) -> Void,
        animating: @escaping () -> Bool = { false }
    ) -> LayerHost<S> {
        self.compositorRender = render
        self.compositorAnimating = animating
        return self
    }

    public func runtime() -> Runtime<S> {
        rt
    }

    public func runtimeMut() -> Runtime<S> {
        rt
    }

    /// Updates the viewport in points and display scale, reconfiguring the Metal swapchain only
    /// when its clamped device-pixel dimensions change.
    public func resize(_ viewport: (Float, Float), _ scale: Float) {
        if viewport.0 <= 0.0 || viewport.1 <= 0.0 {
            suspended = true
            return
        }
        suspended = false
        let clampedScale = max(scale, 1.0)
        let maxDim: UInt32 = 16384
        let pxW = min(max(UInt32((viewport.0 * clampedScale).rounded()), 1), maxDim)
        let pxH = min(max(UInt32((viewport.1 * clampedScale).rounded()), 1), maxDim)
        if configWidth != pxW || configHeight != pxH {
            configWidth = pxW
            configHeight = pxH
            layer.contentsScale = CGFloat(clampedScale)
            layer.drawableSize = CGSize(width: CGFloat(pxW), height: CGFloat(pxH))
        }
        rt.viewport = (Float(pxW) / clampedScale, Float(pxH) / clampedScale)
        rt.env.scale = clampedScale
    }

    /// Steps animations and layout to `RuneInstant.now()` and presents one Metal frame.
    public func frame() -> EmbedFrame {
        if suspended {
            return EmbedFrame()
        }
        let t0 = RuneInstant.now()
        let dtDur = t0.durationSince(lastFrameAt)
        lastFrameAt = t0
        let dt = Double(dtDur.components.seconds) + Double(dtDur.components.attoseconds) * 1e-18
        _ = rt.frame(max(dt, 0.0))
        let updateMs = t0.elapsedSeconds() * 1000.0
        flushMemoryClipboard(rt)

        let compAnimating = compositorAnimating?() ?? false
        guard let device = layer.device,
              let commandQueue = device.makeCommandQueue(),
              let drawable = layer.nextDrawable(),
              let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return EmbedFrame(drew: false, animating: compAnimating, wakeAfterSecs: nil, cpuUs: 0)
        }

        if let comp = compositorRender {
            comp(rt, renderer, max(dt, 0.0), updateMs)
        }

        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = drawable.texture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        passDesc.colorAttachments[0].storeAction = .store
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc) {
            encoder.endEncoding()
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()

        let elapsed = t0.elapsed()
        let cpuUs = UInt64(elapsed.components.seconds) * 1_000_000
            + UInt64(elapsed.components.attoseconds / 1_000_000_000_000)
        let keepTicking = (compositorAnimating?() ?? false)
        return EmbedFrame(
            drew: true,
            animating: keepTicking,
            wakeAfterSecs: nil,
            cpuUs: cpuUs
        )
    }
}

/// Namespace mirroring `rune::platform::embed` / `rune::embed`.
public enum embed {
    public typealias EmbedFrame = Rune.EmbedFrame
    public typealias LayerHost = Rune.LayerHost

    /// Warms the shared Metal device and compiles the default `Bgra8Unorm` uber pipeline on a
    /// background thread so the first embedded `LayerHost` opens without shader-compile latency.
    public static func prewarm() {
        let shouldStart = embedPrewarmLock.withLock { () -> Bool in
            if embedPrewarmStarted { return false }
            embedPrewarmStarted = true
            return true
        }
        guard shouldStart else { return }
        let thread = Thread {
            _ = MTLCreateSystemDefaultDevice()
            prewarmGpu()
        }
        thread.name = "rune-embed-prewarm"
        thread.start()
    }
}
#endif
