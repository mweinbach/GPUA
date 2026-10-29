// Tests ported from: crates/gpui_wgpu/src/wgpu_context.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux) || os(Windows) || os(Android) || os(WASI)
import Testing
@testable import GPUIWGPU

@Suite("WgpuContextTests")
struct WgpuContextTests {
    @Test
    func test_parse_device_id() throws {
        #expect(try parsePciId("0xABCD") == 0xABCD)
        #expect(try parsePciId("ABCD") == 0xABCD)
        #expect(try parsePciId("abcd") == 0xABCD)
        #expect(try parsePciId("1234") == 0x1234)

        #expect(throws: (any Error).self) {
            _ = try parsePciId("123")
        }
        #expect(throws: (any Error).self) {
            _ = try parsePciId("12345")
        }
        #expect(throws: (any Error).self) {
            _ = try parsePciId("0xZZZZ")
        }

        let lower = try parsePciId(String(format: "%04x", 0x1234))
        let upper = try parsePciId(String(format: "%04X", 0x1234))
        #expect(lower == upper)

        let lowerPrefix = try parsePciId(String(format: "%#06x", 0x1234))
        let upperPrefix = try parsePciId(String(format: "%#06X", 0x1234))
        #expect(lowerPrefix == upperPrefix)
    }

    @Test
    func test_device_lost_flag() {
        let box = DeviceLostBox(isLost: false)
        #expect(!box.isLost)
        box.isLost = true
        #expect(box.isLost)
    }

    @Test
    func test_compositor_gpu_hint() {
        let hint = CompositorGpuHint(vendorId: 0x10DE, deviceId: 0x2204)
        #expect(hint.vendorId == 0x10DE)
        #expect(hint.deviceId == 0x2204)
    }
}
#endif
