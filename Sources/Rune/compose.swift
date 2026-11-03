// Ported from: crates/rune/src/compose.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Compositor hook: an app takes over drawing each frame (lighting, effect layers) while Rune
//! keeps layout, animation, input, the window and the headless tooling.

import CWebGPU

/// Draws a frame in place of Rune's default.
public protocol Compositor<State>: AnyObject {
    associatedtype State

    /// Device features to request when the adapter has them (e.g. `TIMESTAMP_QUERY`).
    func features() -> UInt64

    /// Draws the frame into `f.target`. Runs after `Runtime.frame` built the instances.
    func render(_ f: inout Frame<State>)

    /// True while something the compositor draws moves on its own: the window keeps its display link running.
    func animating() -> Bool

    /// Printed after a headless run (e.g. GPU timings).
    func summary(_ device: MetalDevice) -> String?
}

extension Compositor {
    public func features() -> UInt64 { 0 }
    public func animating() -> Bool { false }
    public func summary(_ device: MetalDevice) -> String? {
        _ = device
        return nil
    }
}

/// One frame handed to a compositor.
public struct Frame<S> {
    public let device: MetalDevice
    public let queue: MetalQueue
    public let encoder: MetalCommandEncoder
    /// The window surface or the offscreen target.
    public let target: MetalView
    public let format: WGPUTextureFormat
    /// Target size in device pixels.
    public let size: (UInt32, UInt32)
    /// Real seconds since the previous frame (0 on the first).
    public let dt: Double
    /// CPU milliseconds `Runtime.frame` took this frame (handlers, view, layout, animation).
    public let updateMs: Double
    /// Runtime holding state, text atlas, image atlas, and viewport.
    public let rt: Runtime<S>
    /// Rune's own renderer.
    public let ui: Renderer
    /// Instances emitted for this frame.
    public var instances: [Instance]
    /// Window clear color in linear RGBA.
    public var clearColor: [Float]

    public init(
        device: MetalDevice,
        queue: MetalQueue,
        encoder: MetalCommandEncoder,
        target: MetalView,
        format: WGPUTextureFormat,
        size: (UInt32, UInt32),
        dt: Double,
        updateMs: Double,
        rt: Runtime<S>,
        ui: Renderer,
        instances: [Instance] = [],
        clearColor: [Float]? = nil
    ) {
        self.device = device
        self.queue = queue
        self.encoder = encoder
        self.target = target
        self.format = format
        self.size = size
        self.dt = dt
        self.updateMs = updateMs
        self.rt = rt
        self.ui = ui
        self.instances = instances
        self.clearColor = clearColor ?? (rt.transparent ? [0.0, 0.0, 0.0, 0.0] : [0.0, 0.0, 0.0, 1.0])
    }

    /// True when the frame is sRGB-blended (`App.srgbBlend`).
    public func srgbBlend() -> Bool {
        ui.srgbBlend()
    }

    /// `queue.writeBuffer` without its per-call staging buffer: `data` goes through Rune's
    /// reused staging memory and lands in `buffer` at `offset` ahead of subsequent commands.
    public func writeBuffer(_ buffer: MetalBuffer, _ offset: UInt64, _ data: [UInt8]) {
        ui.writeBuffer(device, queue, encoder, buffer, offset, data)
    }

    /// The default frame: every instance into the target, cleared to the window colour.
    public mutating func drawUi() {
        ui.prepare(device, queue, &rt.text.atlas, instances, size)
        ui.draw(encoder, target, clearColor)
    }
}

public func isGlyph(_ i: Instance) -> Bool {
    i.params[1] == KIND_GLYPH
}

/// Namespace mirroring `rune::compose::*`.
public enum compose {
    public typealias Frame<S> = Rune.Frame<S>

    public static func isGlyph(_ i: Instance) -> Bool {
        Rune.isGlyph(i)
    }
}
