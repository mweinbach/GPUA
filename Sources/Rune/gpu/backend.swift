// Ported from: crates/rune/src/gpu/backend.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Which GPU backend the process runs on (`RUNE_GPU_BACKEND` or `App.gpuBackend`).
//!
//! `GpuBackend.metal` is Rune's native Metal backend (`gpu/metal`, macOS and iOS) and is the
//! default there; `GpuBackend.wgpu` is wgpu's backend (Vulkan, DX12, WebGPU, or wgpu-hal's
//! Metal when chosen on Apple). The choice is process-wide because `Gpu.instance()` is: an app
//! that calls `App.gpuBackend` sets it before any `Gpu` is built, and `RUNE_GPU_BACKEND` sets
//! it when nothing did.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(Musl)
import Musl
#elseif os(Windows)
import ucrt
#elseif os(WASI)
import WASILibc
#endif

/// Which GPU backend an app's windows and headless renderers run on.
public enum GpuBackend: Sendable, Equatable, Hashable, CustomStringConvertible {
    /// wgpu's backend: Vulkan on Linux and Android, DX12 on Windows, WebGPU in the browser, or
    /// wgpu-hal's Metal on macOS and iOS.
    case wgpu
    /// Rune's native Metal backend (`gpu/metal`), on macOS and iOS. Chosen elsewhere, `App.run`
    /// and `Gpu` trap with a message naming the platform.
    case metal

    public static let Wgpu: GpuBackend = .wgpu
    public static let Metal: GpuBackend = .metal

    public var description: String {
        switch self {
        case .wgpu: return "wgpu"
        case .metal: return "metal"
        }
    }
}

/// Bitflags matching `wgpu::Backends` (`VULKAN = 1 << 1`, `GL = 1 << 2`, `METAL = 1 << 3`,
/// `DX12 = 1 << 4`, `BROWSER_WEBGPU = 1 << 5`).
public struct GpuBackendMask: OptionSet, Sendable, Equatable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let vulkan = GpuBackendMask(rawValue: 1 << 1)
    public static let gl = GpuBackendMask(rawValue: 1 << 2)
    public static let metal = GpuBackendMask(rawValue: 1 << 3)
    public static let dx12 = GpuBackendMask(rawValue: 1 << 4)
    public static let browserWebGpu = GpuBackendMask(rawValue: 1 << 5)
    public static let primary: GpuBackendMask = [.vulkan, .metal, .dx12, .browserWebGpu]
    public static let all: GpuBackendMask = [.vulkan, .gl, .metal, .dx12, .browserWebGpu]
}

private let backendChoiceLock = LiveLock()
// PORT NOTE: Guarded by `backendChoiceLock`, mirroring `OnceLock<GpuBackend>` in `crates/rune/src/gpu/backend.rs`.
nonisolated(unsafe) private var chosenBackendValue: GpuBackend? = nil

func readProcessEnv(_ key: String) -> String? {
    guard let raw = getenv(key) else { return nil }
    return String(cString: raw)
}

func defaultedGpuBackend() -> GpuBackend {
    #if os(macOS) || os(iOS)
    return .metal
    #else
    return .wgpu
    #endif
}

/// Non-trapping validation helper used by tests and `resolveGpuBackend`.
public enum GpuBackendResolveError: Error, Sendable, Equatable {
    case metalUnsupportedOnPlatform
    case invalidValue(String)
}

public func tryResolveGpuBackend(_ env: String?) -> Result<GpuBackend, GpuBackendResolveError> {
    guard let raw = env else { return .success(defaultedGpuBackend()) }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return .success(defaultedGpuBackend())
    }
    switch trimmed.lowercased() {
    case "wgpu":
        return .success(.wgpu)
    case "metal":
        #if os(macOS) || os(iOS)
        return .success(.metal)
        #else
        return .failure(.metalUnsupportedOnPlatform)
        #endif
    default:
        return .failure(.invalidValue(raw))
    }
}

func resolveGpuBackend(_ env: String?) -> GpuBackend {
    switch tryResolveGpuBackend(env) {
    case .success(let b):
        return b
    case .failure(.metalUnsupportedOnPlatform):
        preconditionFailure("RUNE_GPU_BACKEND=metal is supported on macOS and iOS only")
    case .failure(.invalidValue(let s)):
        preconditionFailure("RUNE_GPU_BACKEND must be `metal` or `wgpu`, got \(String(reflecting: s))")
    }
}

/// Sets the process's backend, if nothing has read it yet. Traps if a different backend was
/// already chosen, or if `GpuBackend.metal` is chosen off macOS and iOS.
public func chooseGpuBackend(_ backend: GpuBackend) {
    #if !(os(macOS) || os(iOS))
    precondition(backend != .metal, "GpuBackend.metal is supported on macOS and iOS only")
    #endif
    let prev: GpuBackend = backendChoiceLock.withLock {
        if let existing = chosenBackendValue {
            return existing
        }
        chosenBackendValue = backend
        return backend
    }
    precondition(
        prev == backend,
        "GPU backend already set to `\(prev)` (choose it before creating a Gpu or running an App)"
    )
}

/// The backend this process runs on, latching `RUNE_GPU_BACKEND` or the platform default if
/// `chooseGpuBackend` wasn't called.
public func currentGpuBackend() -> GpuBackend {
    backendChoiceLock.withLock {
        if let existing = chosenBackendValue {
            return existing
        }
        let resolved = resolveGpuBackend(readProcessEnv("RUNE_GPU_BACKEND"))
        chosenBackendValue = resolved
        return resolved
    }
}

/// `"metal"` or `"wgpu"`, for trace headers and diagnostics.
public func gpuBackendLabel() -> String {
    currentGpuBackend().description
}

/// The `wgpu::Backends` mask to build a `wgpu::Instance` with when `backend` is chosen.
public func wgpuBackendsFor(_ backend: GpuBackend) -> GpuBackendMask {
    #if os(macOS) || os(iOS)
    switch backend {
    case .wgpu:
        return .metal
    case .metal:
        return .primary
    }
    #else
    _ = backend
    return .primary
    #endif
}

/// Adapter backend kind mirroring `wgpu::Backend`.
public enum AdapterBackendKind: String, Sendable, Equatable, Hashable {
    case noop = "noop"
    case vulkan = "vulkan"
    case metal = "metal"
    case dx12 = "dx12"
    case gl = "gl"
    case browserWebGpu = "webgpu"
}

/// Whether an adapter on `adapter` is the native backend `backend` asks for, rather than a
/// software fallback (`gl` / `noop`) that came along in `GpuBackendMask.all`.
public func backendServes(_ backend: GpuBackend, _ adapter: AdapterBackendKind) -> Bool {
    switch backend {
    case .metal:
        return adapter == .metal
    case .wgpu:
        switch adapter {
        case .vulkan, .metal, .dx12, .browserWebGpu:
            return true
        case .noop, .gl:
            return false
        }
    }
}
