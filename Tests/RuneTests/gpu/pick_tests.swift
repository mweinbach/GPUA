// Ported from: crates/rune/src/gpu/pick_tests.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("GPU Adapter Pick Tests")
struct GpuPickTests {
    private func card(
        _ name: String,
        _ ty: AdapterDeviceType,
        vendor: UInt32 = 0,
        device: UInt32 = 0,
        pci: String = ""
    ) -> AdapterCandidate {
        AdapterCandidate(
            name: name,
            vendor: vendor,
            device: device,
            deviceType: ty,
            backend: .vulkan,
            pciBusId: pci
        )
    }

    @Test("discrete wins over integrated and llvmpipe when nothing else says")
    func discreteWinsOverIntegratedAndLlvmpipe() {
        let adapters = [
            card("llvmpipe (LLVM 19.1.7, 256 bits)", .cpu),
            card("AMD Radeon Graphics (RADV GFX1103_R1)", .integratedGpu, vendor: 0x1002, device: 0x15bf, pci: "0000:65:00.0"),
            card("NVIDIA GeForce RTX 4070", .discreteGpu, vendor: 0x10de, device: 0x2786, pci: "0000:01:00.0"),
        ]
        let picked = pickAdapter(adapters, explicit: nil, compositorDev: nil)
        #expect(picked == AdapterPick(index: 2, reason: .discreteOverIntegrated))
    }

    @Test("llvmpipe is used only when no hardware adapter survived")
    func llvmpipeUsedOnlyWhenNoHardwareAdapterSurvived() {
        let onlyCpu = [card("llvmpipe (LLVM 19.1.7, 256 bits)", .cpu)]
        #expect(pickAdapter(onlyCpu, explicit: nil, compositorDev: nil) == AdapterPick(index: 0, reason: .softwareFallback))

        let oneHw = [
            card("llvmpipe", .cpu),
            card("Apple M3 Max", .integratedGpu),
        ]
        #expect(pickAdapter(oneHw, explicit: nil, compositorDev: nil) == AdapterPick(index: 1, reason: .onlyHardware))
    }

    @Test("wayland compositor device beats the discrete card")
    func waylandCompositorDeviceBeatsDiscreteCard() {
        let adapters = [
            card("NVIDIA GeForce RTX 4070", .discreteGpu, vendor: 0x10de, device: 0x2786, pci: "0000:01:00.0"),
            card("AMD Radeon 780M", .integratedGpu, vendor: 0x1002, device: 0x15bf, pci: "0000:65:00.0"),
        ]
        let byPciSlot = pickAdapter(
            adapters,
            explicit: nil,
            compositorDev: 0xe280,
            drmResolver: { _ in (pci: "0000:65:00.0", ids: nil) }
        )
        #expect(byPciSlot == AdapterPick(index: 1, reason: .waylandCompositor))

        let noPci = [
            card("NVIDIA GeForce RTX 4070", .discreteGpu, vendor: 0x10de, device: 0x2786),
            card("AMD Radeon 780M", .integratedGpu, vendor: 0x1002, device: 0x15bf),
        ]
        let byIds = pickAdapter(
            noPci,
            explicit: nil,
            compositorDev: 0xe280,
            drmResolver: { _ in (pci: nil, ids: (0x1002, 0x15bf)) }
        )
        #expect(byIds == AdapterPick(index: 1, reason: .waylandCompositor))
    }

    @Test("explicit name wins exact before substring and ignores case")
    func explicitNameWinsExactBeforeSubstringAndIgnoresCase() {
        let adapters = [
            card("AMD Radeon Pro W6800", .discreteGpu),
            card("AMD Radeon", .integratedGpu),
            card("llvmpipe", .cpu),
        ]
        #expect(pickAdapter(adapters, explicit: "amd radeon", compositorDev: nil) == AdapterPick(index: 1, reason: .explicit))
        #expect(pickAdapter(adapters, explicit: "w6800", compositorDev: nil) == AdapterPick(index: 0, reason: .explicit))
        #expect(pickAdapter(adapters, explicit: "LLVMPIPE", compositorDev: nil) == AdapterPick(index: 2, reason: .explicit))
        #expect(pickAdapter(adapters, explicit: "nonexistent", compositorDev: nil) == AdapterPick(index: 0, reason: .discreteOverIntegrated))
    }

    @Test("pci addresses match with or without a domain")
    func pciAddressesMatchWithOrWithoutDomain() {
        #expect(samePci("0000:65:00.0", "65:00.0"))
        #expect(samePci("pci:0000:01:00.0", "0000:01:00.0"))
        #expect(samePci("0001:65:00.0", "0001:65:00.0"))
        #expect(!samePci("0001:65:00.0", "65:00.0"))
        #expect(!samePci("0000:65:00.0", "0000:65:00.1"))
        #expect(!samePci("", "0000:00:00.0"))
    }

    @Test("linux dev_t splits into sysfs major and minor")
    func linuxDevTSplitsIntoSysfsMajorAndMinor() {
        // /dev/dri/renderD128 -> major 226 (0xe2), minor 128 (0x80) -> 0xe280
        #expect(devNumbers(0xe280) == (226, 128))
        // Extended minor > 255: major 226, minor 512 (0x200) -> (0x200 & 0xff) | ((0x200 & ~0xff) << 12) | (226 << 8)
        let extended: UInt64 = (UInt64(226) << 8) | (UInt64(512 & 0xff)) | (UInt64(512 & ~0xff) << 12)
        #expect(devNumbers(extended) == (226, 512))
    }
}
