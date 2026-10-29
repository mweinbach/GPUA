// Swift-only: unit tests for WindowsDisplay coordinate math, scale factor, and bounds

#if os(Windows)
import Foundation
import Testing
import GPUI
@testable import GPUIWindows

@Suite("WindowsDisplayTests")
struct WindowsDisplayTests {
    @Test
    func testLogicalPointConversion() {
        let pt = logicalPoint(x: 3840.0, y: 2160.0, scaleFactor: 2.0)
        #expect(pt.x.value == 1920.0)
        #expect(pt.y.value == 1080.0)

        let ptIdentity = logicalPoint(x: 1920.0, y: 1080.0, scaleFactor: 1.0)
        #expect(ptIdentity.x.value == 1920.0)
        #expect(ptIdentity.y.value == 1080.0)
    }

    @Test
    func testHiLoWordCalculations() {
        let value: UInt32 = 0x12345678
        #expect(value.hiword() == 0x1234)
        #expect(value.loword() == 0x5678)

        let intVal: Int = 0x12345678
        #expect(intVal.hiword() == 0x1234)
        #expect(intVal.loword() == 0x5678)
    }

    @Test
    func testWideStringConversions() {
        let testStr = "GPUA Windows Direct3D 11 测试"
        let wide = toWideString(testStr)
        #expect(wide.last == 0)

        wide.withUnsafeBufferPointer { buf in
            let reconstructed = fromWideString(buf.baseAddress)
            #expect(reconstructed == testStr)
        }

        let fromBuf = fromWideBuffer(wide)
        #expect(fromBuf == testStr)
    }

    @Test
    func testWindowsDisplayManualCreation() {
        let display = WindowsDisplay(
            displayId: DisplayId(1),
            scaleFactor: 1.5,
            bounds: Bounds(origin: .zero, size: Size(width: px(1280), height: px(720))),
            visibleBounds: Bounds(origin: .zero, size: Size(width: px(1280), height: px(680))),
            physicalBounds: Bounds(origin: .zero, size: Size(width: DevicePixels(1920), height: DevicePixels(1080))),
            uuid: UUID()
        )

        #expect(display.id() == DisplayId(1))
        #expect(display.scaleFactor == 1.5)
        #expect(display.bounds().size.width.value == 1280.0)
        #expect(display.visibleBounds().size.height.value == 680.0)
        #expect(display.physicalBounds().size.width.value == 1920)
    }
}

#endif
