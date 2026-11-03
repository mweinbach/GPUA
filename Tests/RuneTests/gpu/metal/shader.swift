// Tests ported from: crates/rune/src/gpu/metal/shader.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("MetalShaderUnitTests")
struct MetalShaderUnitTests {
    @Test("builtin table is sorted and binary-searchable")
    func builtinTableLookup() {
        #expect(METAL_BUILTIN_SOURCES.count == 28)
        #expect(METAL_BUILTIN_FUNCTIONS.count == 60)
        for h in METAL_BUILTIN_SOURCES {
            #expect(metalBuiltinKnown(h))
        }
        #expect(!metalBuiltinKnown("00000000000000000000000000000000"))
        for row in METAL_BUILTIN_FUNCTIONS {
            let found = metalBuiltinLookupRow(row.key)
            #expect(found?.functionName == row.functionName)
        }
    }

    @Test("passthrough metallib validation rejects non-MTLB bytes cleanly")
    func passthroughValidation() {
        let (device, _) = metalGpu()
        let bad = device.createShaderModulePassthrough(metallib: [1, 2, 3, 4], entryPoints: ["vs"])
        #expect(!metalModuleReady(bad))
    }
}
