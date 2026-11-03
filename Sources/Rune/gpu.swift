// Ported from: crates/rune/src/gpu.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The GPU layer: backend choice (`backend`), adapter choice (`pick`), retained spring evaluation
//! (`springs`), and the native Metal backend (`metal`).

#if os(macOS)
import AppKit
import QuartzCore
#endif

/// Whether this process runs on Rune's native Metal backend (`gpu/metal`) rather than wgpu.
public func gpuIsNative() -> Bool {
    #if os(macOS) || os(iOS)
    return currentGpuBackend() == .metal
    #else
    return false
    #endif
}

/// Calls `f` with the `CAMetalLayer` backing `viewPtr` (`NSView` on macOS), creating or reusing
/// a `CAMetalLayer` sublayer if needed. On non-macOS platforms, yields `viewPtr` unchanged.
public func withMetalLayer<R>(_ viewPtr: UnsafeMutableRawPointer, _ f: (UnsafeMutableRawPointer) -> R) -> R {
    #if os(macOS)
    let rawAddr = Int(bitPattern: viewPtr)
    let layerAddr: Int = MainActor.assumeIsolated {
        let view = Unmanaged<NSView>.fromOpaque(UnsafeMutableRawPointer(bitPattern: rawAddr)!).takeUnretainedValue()
        view.wantsLayer = true
        if let existing = view.layer as? CAMetalLayer {
            return Int(bitPattern: Unmanaged.passUnretained(existing).toOpaque())
        }
        if let sub = view.layer?.sublayers?.compactMap({ $0 as? CAMetalLayer }).first {
            return Int(bitPattern: Unmanaged.passUnretained(sub).toOpaque())
        }
        let metalLayer = CAMetalLayer()
        metalLayer.frame = view.bounds
        metalLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        if let scale = view.window?.backingScaleFactor {
            metalLayer.contentsScale = scale
        }
        if let hostLayer = view.layer {
            hostLayer.addSublayer(metalLayer)
        } else {
            view.layer = metalLayer
        }
        return Int(bitPattern: Unmanaged.passUnretained(metalLayer).toOpaque())
    }
    return f(UnsafeMutableRawPointer(bitPattern: layerAddr)!)
    #else
    return f(viewPtr)
    #endif
}

/// Namespace mirroring `rune::gpu::*`.
public enum gpu {
    public typealias GpuBackend = Rune.GpuBackend
    public typealias springs = Rune.springs

    public static func native() -> Bool {
        gpuIsNative()
    }

    public static func withLayer<R>(_ viewPtr: UnsafeMutableRawPointer, _ f: (UnsafeMutableRawPointer) -> R) -> R {
        withMetalLayer(viewPtr, f)
    }
}
