// Tests ported from: crates/rune/src/native_surface/mod.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Testing
@testable import Rune

@Suite("NativeSurface Mailbox and Reference Colour Tests")
struct NativeSurfaceUnitTests {
    @Test("latest wins and releases old frames")
    func latestWinsAndReleasesOldFrames() {
        let s = NativeSurface()
        let wokeLock = NSLock()
        nonisolated(unsafe) var woke = 0
        s.setWaker {
            wokeLock.lock()
            woke += 1
            wokeLock.unlock()
        }

        let f = syntheticSurfaceFrame(64, 36, 0)
        guard case .success = s.pushBytes(f, 1) else {
            Issue.record("expected pushBytes(1) to succeed")
            return
        }
        guard case .success = s.pushBytes(f, 2) else {
            Issue.record("expected pushBytes(2) to succeed")
            return
        }
        #expect(s.latest()?.id == 2)
        #expect(s.size() == (64, 36))
        #expect(woke == 2)

        var bad = f
        bad.width = 63
        if case .success = s.pushBytes(bad, 3) {
            Issue.record("expected odd-width NV12 pushBytes to fail")
        }
        #expect(s.latest()?.id == 2)

        s.clear()
        #expect(s.size() == (0, 0))
    }

    @Test("range endpoints and neutral chroma")
    func rangeEndpointsAndNeutralChroma() {
        let c = ColorInfo(matrix: .bt709, transfer: .bt709)
        let black = nv12Reference(16, 128, 128, .nv12Video, c)
        let white = nv12Reference(235, 128, 128, .nv12Video, c)
        for v in black {
            #expect(v.magnitude < 1e-6)
        }
        for v in white {
            #expect(abs(v - 1.0) < 1e-5)
        }
        let full = nv12Reference(255, 128, 128, .nv12Full, ColorInfo(matrix: .bt601, transfer: .srgb))
        for v in full {
            #expect(abs(v - 1.0) < 1e-5)
        }
    }
}
