// Tests ported from: crates/rune-ref/tests/alloc.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneRef

@Suite("RuneRef Steady Frame Allocation Tests")
struct RuneRefAllocTests {
    // PORT NOTE: Swift lacks a process-wide `GlobalAlloc` override hook in user test code; we verify that `Frame.render` mutates `rgba` and `owners` buffers strictly in-place without reallocating or changing buffer base addresses across 30 steady-state frames.
    @Test("steady reference frames reuse existing buffers without reallocation")
    func steadyReferenceFramesAllocateNothing() {
        let scene = generate.seeded(24, 8)
        var frame = Frame.new(64, 64, true)
        frame.render(scene)

        let initialRgbaPtr = frame.rgba.withUnsafeBufferPointer { $0.baseAddress }
        let initialRgbaCap = frame.rgba.capacity
        let initialOwnersPtr = frame.owners?.withUnsafeBufferPointer { $0.baseAddress }
        let initialOwnersCap = frame.owners?.capacity

        for _ in 0..<30 {
            frame.render(scene)
        }

        let afterRgbaPtr = frame.rgba.withUnsafeBufferPointer { $0.baseAddress }
        let afterOwnersPtr = frame.owners?.withUnsafeBufferPointer { $0.baseAddress }
        #expect(afterRgbaPtr == initialRgbaPtr)
        #expect(frame.rgba.capacity == initialRgbaCap)
        #expect(afterOwnersPtr == initialOwnersPtr)
        #expect(frame.owners?.capacity == initialOwnersCap)
    }
}
