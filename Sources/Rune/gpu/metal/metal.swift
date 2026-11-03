// Ported from: crates/rune/src/gpu/metal/mod.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Top-level entry points for Rune's direct Metal backend (`gpu/metal/mod.rs`):
//! adapter enumeration (`MTLCopyAllDevices` on macOS, `MTLCreateSystemDefaultDevice` on iOS/tvOS),
//! power-preference selection matching `wgpu`, `metalWriteInPlace`, and `metalModuleReady`.

#if canImport(Metal)
import Metal
#endif

public enum MetalPowerPreference: Sendable, Equatable {
    case none
    case lowPower
    case highPerformance
}

public struct MetalAdapterInfo: Sendable, Equatable {
    public let name: String
    public let deviceType: AdapterDeviceType
    public let registryId: UInt64

    public init(name: String, deviceType: AdapterDeviceType, registryId: UInt64) {
        self.name = name
        self.deviceType = deviceType
        self.registryId = registryId
    }
}

#if canImport(Metal)
/// Enumerates all Metal `MTLDevice`s in `wgpu` order.
public func metalAdapterDevices() -> [any MTLDevice] {
    #if os(macOS)
    let all = MTLCopyAllDevices()
    if !all.isEmpty {
        return all
    }
    #endif
    if let def = MTLCreateSystemDefaultDevice() {
        return [def]
    }
    return []
}

/// Classifies an `MTLDevice` into `AdapterDeviceType` (`integratedGpu` vs `discreteGpu`), matching `wgpu-hal` Metal.
public func metalDeviceType(_ device: any MTLDevice) -> AdapterDeviceType {
    #if os(macOS)
    if device.hasUnifiedMemory || device.isLowPower {
        return .integratedGpu
    }
    return .discreteGpu
    #else
    _ = device
    return .integratedGpu
    #endif
}

/// Picks the preferred `MTLDevice` for `powerPreference`, matching `wgpu`'s adapter selection (`adapters_are_the_ones_wgpu_picks`).
public func metalPreferredAdapter(powerPreference: MetalPowerPreference = .none) -> (any MTLDevice)? {
    let devices = metalAdapterDevices()
    guard !devices.isEmpty else { return nil }
    switch powerPreference {
    case .highPerformance:
        if let discrete = devices.first(where: { metalDeviceType($0) == .discreteGpu }) {
            return discrete
        }
        return devices.first
    case .lowPower, .none:
        if let integrated = devices.first(where: { metalDeviceType($0) == .integratedGpu }) {
            return integrated
        }
        return devices.first
    }
}
#endif

/// Enumerates adapter info records for the Metal backend.
public func metalEnumerateAdapterInfos() -> [MetalAdapterInfo] {
    #if canImport(Metal)
    return metalAdapterDevices().map { dev in
        MetalAdapterInfo(
            name: dev.name,
            deviceType: metalDeviceType(dev),
            registryId: dev.registryID
        )
    }
    #else
    return []
    #endif
}

/// Writes `data` directly into `buffer` at `offset` (or swaps in an idle CoW spare if busy),
/// returning `true` when satisfied without staging (`write_in_place` in `gpu/metal/mod.rs`).
public func metalWriteInPlace(_ buffer: MetalBuffer, _ offset: UInt64, _ data: [UInt8]) -> Bool {
    buffer.writeInPlace(offset: offset, data: data)
}

/// Reports whether a `MetalShaderModule` compiled or loaded its passthrough `.metallib` cleanly (`module_ready`).
public func metalModuleReady(_ module: MetalShaderModule) -> Bool {
    module.isReady
}
