// Tests ported from: crates/rune/src/native_surface/macos.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune
#if os(macOS)
import CoreVideo
import IOSurface
#endif

@Suite("NativeSurface macOS CoreVideo and IOSurface Tests")
struct NativeSurfaceMacosTests {
    #if os(macOS)
    @Test("PixelBuffer rejects null pointers and validates IOSurface attachments")
    func pixelBufferValidationAndIOSurfaceWrap() {
        if case .success = PixelBuffer.fromRaw(nil) {
            Issue.record("expected null CVPixelBuffer to fail")
        }
        if case .success = PixelBuffer.fromIOSurface(nil, .default()) {
            Issue.record("expected null IOSurface to fail")
        }

        let frame = syntheticSurfaceFrame(64, 36, 0)
        guard case .success(let pb) = PixelBuffer.fromBytes(frame) else {
            Issue.record("expected PixelBuffer.fromBytes to succeed")
            return
        }
        guard let ioSurface = CVPixelBufferGetIOSurface(pb.cvBuffer) else {
            Issue.record("expected IOSurface-backed CVPixelBuffer")
            return
        }
        let rawIO = ioSurface.toOpaque()
        let color = ColorInfo(matrix: .bt601, transfer: .srgb)
        guard case .success(let wrapped) = PixelBuffer.fromIOSurface(rawIO, color),
              case .success(let (size, fmt, gotColor)) = wrapped.info()
        else {
            Issue.record("expected PixelBuffer.fromIOSurface to succeed")
            return
        }
        #expect(size == [64, 36])
        #expect(fmt == .nv12Video)
        #expect(gotColor == color)
    }
    #else
    @Test("Non-macOS stub compiles cleanly")
    func nonMacosStub() {
        #expect(Bool(true))
    }
    #endif
}
