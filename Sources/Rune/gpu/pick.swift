// Ported from: crates/rune/src/gpu/pick.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Choosing one GPU adapter when a machine has more than one.
//!
//! Order of preference:
//! 1. `RUNE_GPU_ADAPTER` or `WGPU_ADAPTER_NAME`, matched case-insensitively (exact, then
//!    substring), so a user or a test can pin a card by name.
//! 2. On Wayland, the DRM device the compositor sent in `zwp_linux_dmabuf_v1.main_device`,
//!    matched by PCI address (or vendor + device id when neither side reports one).
//! 3. Any hardware GPU, discrete before integrated so a desktop with both uses the fast card
//!    on X11, Windows, and headless Linux.
//! 4. Software (`llvmpipe`, `lavapipe`, WARP) only when no hardware adapter survived.

#if !os(WASI)
import Foundation
#endif

/// Device classification mirroring `wgpu::DeviceType`.
public enum AdapterDeviceType: Sendable, Equatable, Hashable {
    case other
    case integratedGpu
    case discreteGpu
    case virtualGpu
    case cpu

    public static let Other: AdapterDeviceType = .other
    public static let IntegratedGpu: AdapterDeviceType = .integratedGpu
    public static let DiscreteGpu: AdapterDeviceType = .discreteGpu
    public static let VirtualGpu: AdapterDeviceType = .virtualGpu
    public static let Cpu: AdapterDeviceType = .cpu
}

/// Adapter metadata inspected by `pickAdapter`, mirroring `wgpu::AdapterInfo`.
public struct AdapterCandidate: Sendable, Equatable, Hashable {
    public var name: String
    public var vendor: UInt32
    public var device: UInt32
    public var deviceType: AdapterDeviceType
    public var driver: String
    public var driverInfo: String
    public var backend: AdapterBackendKind
    public var pciBusId: String

    public init(
        name: String,
        vendor: UInt32 = 0,
        device: UInt32 = 0,
        deviceType: AdapterDeviceType = .discreteGpu,
        driver: String = "",
        driverInfo: String = "",
        backend: AdapterBackendKind = .vulkan,
        pciBusId: String = ""
    ) {
        self.name = name
        self.vendor = vendor
        self.device = device
        self.deviceType = deviceType
        self.driver = driver
        self.driverInfo = driverInfo
        self.backend = backend
        self.pciBusId = pciBusId
    }
}

/// Why `pickAdapter` chose the adapter it did.
public enum AdapterPickReason: String, Sendable, Equatable, Hashable, CustomStringConvertible {
    case explicit = "RUNE_GPU_ADAPTER"
    case waylandCompositor = "wayland compositor's GPU"
    case onlyHardware = "only hardware GPU"
    case discreteOverIntegrated = "discrete over integrated"
    case firstHardware = "first hardware GPU"
    case softwareFallback = "software fallback (no hardware GPU)"

    public var description: String { rawValue }
}

/// Selected adapter index and selection reason.
public struct AdapterPick: Sendable, Equatable {
    public var index: Int
    public var reason: AdapterPickReason

    public init(index: Int, reason: AdapterPickReason) {
        self.index = index
        self.reason = reason
    }
}

/// Picks the best adapter from `candidates` using explicit name, Wayland compositor DRM `rdev`,
/// discrete-over-integrated hardware priority, and software fallback.
public func pickAdapter(
    _ candidates: [AdapterCandidate],
    explicit explicitOverride: String? = nil,
    compositorDev: UInt64? = nil,
    drmResolver: ((UInt64) -> (pci: String?, ids: (UInt32, UInt32)?))? = nil
) -> AdapterPick? {
    if candidates.isEmpty { return nil }

    let explicit = explicitOverride ?? envAdapterName()
    if let want = explicit {
        if let index = adapterByName(candidates, want) {
            return AdapterPick(index: index, reason: .explicit)
        }
    }

    if let rdev = compositorDev {
        let resolved = drmResolver?(rdev) ?? (pci: drmPciSlot(rdev), ids: drmVendorDevice(rdev))
        if let pci = resolved.pci, let index = adapterByPci(candidates, pci) {
            return AdapterPick(index: index, reason: .waylandCompositor)
        }
        if let (vendor, devId) = resolved.ids {
            if let index = candidates.firstIndex(where: {
                $0.deviceType != .cpu && $0.vendor == vendor && $0.device == devId
            }) {
                return AdapterPick(index: index, reason: .waylandCompositor)
            }
        }
    }

    let hwIndices = candidates.indices.filter { candidates[$0].deviceType != .cpu }
    if hwIndices.count == 1 {
        return AdapterPick(index: hwIndices[0], reason: .onlyHardware)
    }
    if let index = hwIndices.first(where: { candidates[$0].deviceType == .discreteGpu }) {
        let hasOtherKind = hwIndices.contains { candidates[$0].deviceType != .discreteGpu }
        let reason: AdapterPickReason = hasOtherKind ? .discreteOverIntegrated : .firstHardware
        return AdapterPick(index: index, reason: reason)
    }
    if let index = hwIndices.first {
        return AdapterPick(index: index, reason: .firstHardware)
    }
    return AdapterPick(index: 0, reason: .softwareFallback)
}

func envAdapterName() -> String? {
    for key in ["RUNE_GPU_ADAPTER", "WGPU_ADAPTER_NAME"] {
        if let val = readProcessEnv(key) {
            let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
    }
    return nil
}

/// Exact case-insensitive match first, then case-insensitive substring match.
public func adapterByName(_ candidates: [AdapterCandidate], _ want: String) -> Int? {
    let wantLower = want.lowercased()
    if let exact = candidates.firstIndex(where: { $0.name.lowercased() == wantLower }) {
        return exact
    }
    return candidates.firstIndex(where: { $0.name.lowercased().contains(wantLower) })
}

/// Matches a PCI address (`0000:65:00.0` or `65:00.0`) against `AdapterCandidate.pciBusId`.
public func adapterByPci(_ candidates: [AdapterCandidate], _ pci: String) -> Int? {
    candidates.firstIndex { $0.deviceType != .cpu && samePci($0.pciBusId, pci) }
}

/// Compares PCI `[domain:]bus:slot.func` strings numerically, defaulting an omitted domain to `0`.
public func samePci(_ a: String, _ b: String) -> Bool {
    guard let pa = pciAddress(a), let pb = pciAddress(b) else { return false }
    return pa == pb
}

/// Parses `[domain:]bus:slot.func` (also strips any `pci:` prefix) into `(domain, bus, slot, fn)`.
public func pciAddress(_ s: String) -> (UInt32, UInt8, UInt8, UInt8)? {
    var trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("pci:") {
        trimmed.removeFirst(4)
    }
    guard let dotIndex = trimmed.lastIndex(of: ".") else { return nil }
    let rest = String(trimmed[..<dotIndex])
    let fnStr = String(trimmed[trimmed.index(after: dotIndex)...])
    guard let fn = UInt8(fnStr, radix: 16) else { return nil }
    let parts = rest.split(separator: ":", omittingEmptySubsequences: false)
    switch parts.count {
    case 2:
        guard let bus = UInt8(parts[0], radix: 16),
              let slot = UInt8(parts[1], radix: 16)
        else { return nil }
        return (0, bus, slot, fn)
    case 3:
        guard let domain = UInt32(parts[0], radix: 16),
              let bus = UInt8(parts[1], radix: 16),
              let slot = UInt8(parts[2], radix: 16)
        else { return nil }
        return (domain, bus, slot, fn)
    default:
        return nil
    }
}

/// Linux `gnu_dev_major` and `gnu_dev_minor` for a 64-bit `dev_t`.
public func devNumbers(_ rdev: UInt64) -> (UInt32, UInt32) {
    let major = UInt32(((rdev >> 8) & 0xfff) | ((rdev >> 32) & ~UInt64(0xfff)))
    let minor = UInt32((rdev & 0xff) | ((rdev >> 12) & ~UInt64(0xff)))
    return (major, minor)
}

func drmPciSlot(_ rdev: UInt64) -> String? {
    #if os(Linux)
    let (major, minor) = devNumbers(rdev)
    let path = "/sys/dev/char/\(major):\(minor)/device/uevent"
    guard let uevent = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    for line in uevent.split(separator: "\n") {
        if line.hasPrefix("PCI_SLOT_NAME=") {
            return String(line.dropFirst("PCI_SLOT_NAME=".count))
        }
    }
    return nil
    #else
    _ = rdev
    return nil
    #endif
}

func drmVendorDevice(_ rdev: UInt64) -> (UInt32, UInt32)? {
    #if os(Linux)
    let (major, minor) = devNumbers(rdev)
    let base = "/sys/dev/char/\(major):\(minor)/device"
    func hex(_ file: String) -> UInt32? {
        guard let raw = try? String(contentsOfFile: "\(base)/\(file)", encoding: .utf8) else { return nil }
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("0x") || s.hasPrefix("0X") { s.removeFirst(2) }
        return UInt32(s, radix: 16)
    }
    guard let v = hex("vendor"), let d = hex("device") else { return nil }
    return (v, d)
    #else
    _ = rdev
    return nil
    #endif
}
