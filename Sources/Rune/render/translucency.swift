// Ported from: crates/rune/src/render/translucency.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Surface composite-alpha selection and low-power adapter ordering.

import CWebGPU

public enum CompositeAlphaMode: Sendable, Equatable, Hashable {
    case auto
    case opaque
    case preMultiplied
    case postMultiplied
    case inherit
}

func powerRank(_ deviceType: AdapterDeviceType) -> UInt8 {
    switch deviceType {
    case .integratedGpu: return 0
    case .discreteGpu: return 1
    case .virtualGpu: return 2
    case .other: return 3
    case .cpu: return 4
    }
}

func powerRank(_ adapterType: WGPUAdapterType) -> UInt8 {
    switch adapterType {
    case WGPUAdapterType_IntegratedGPU: return 0
    case WGPUAdapterType_DiscreteGPU: return 1
    case WGPUAdapterType_Unknown: return 3
    case WGPUAdapterType_CPU: return 4
    default: return 3
    }
}

func translucencyMode(_ modes: [CompositeAlphaMode], _ transparent: Bool) -> CompositeAlphaMode {
    if transparent {
        for want: CompositeAlphaMode in [.preMultiplied, .postMultiplied, .inherit] {
            if modes.contains(want) {
                return want
            }
        }
    }
    if modes.contains(.opaque) {
        return .opaque
    }
    return modes.first ?? .opaque
}

func translucencyServes(_ modes: [CompositeAlphaMode], _ transparent: Bool) -> Bool {
    !transparent || translucencyMode(modes, true) != .opaque
}

/// Picks the first candidate in `modes` present in `available`, falling back to `available[0]`.
func translucencyPrefer(_ available: [CompositeAlphaMode], _ modes: [CompositeAlphaMode]) -> CompositeAlphaMode {
    for mode in modes {
        if available.contains(mode) {
            return mode
        }
    }
    return available.first ?? .opaque
}
