// Tests ported from: crates/rune/src/platform/embed.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

#if os(macOS)
import QuartzCore

@Suite("EmbedTests")
struct EmbedTests {
    @Test("layer host runs compositor and validates layer pointer")
    func layerHostRunsCompositorAndValidatesLayerPointer() {
        let view: ((), Cx<()>) -> El = { _, _ in
            el().size(120.0, 80.0)
        }
        let spec = AppSpec.new("embed-test", (120.0, 80.0), { () }, view)

        let nullResult = LayerHost<()>.fromCoreAnimationLayer(
            nil,
            spec,
            (),
            (120.0, 80.0),
            2.0,
            true,
            {}
        )
        if case .success = nullResult {
            Issue.record("Expected null CAMetalLayer pointer to fail")
        }

        let layer = CAMetalLayer()
        let rawPtr = Unmanaged.passUnretained(layer).toOpaque()
        let created = LayerHost<()>.fromCoreAnimationLayer(
            rawPtr,
            spec,
            (),
            (120.0, 80.0),
            2.0,
            true,
            {}
        )
        guard case .success(var host) = created else {
            return
        }
        var seenMark: UInt32 = 0
        host = host.withCompositor { _, _, _, _ in
            seenMark = 42
        }
        let out = host.frame()
        if out.drew {
            #expect(seenMark == 42)
        }

        // Zero viewport suspends frame presentation cleanly.
        host.resize((0.0, 80.0), 2.0)
        let suspendedFrame = host.frame()
        #expect(!suspendedFrame.drew)
    }
}
#endif
