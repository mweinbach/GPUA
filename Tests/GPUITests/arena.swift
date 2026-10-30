// Tests ported from: crates/gpui/src/arena.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
@testable import GPUI

@Suite("Arena Tests")
struct ArenaTests {
    @Test
    func test_arena() {
        var arena = Arena.new(1024)
        let a = arena.alloc { UInt64(1) }
        let b = arena.alloc { UInt32(2) }
        let c = arena.alloc { UInt16(3) }
        let d = arena.alloc { UInt8(4) }

        #expect(a.pointee == 1)
        #expect(b.pointee == 2)
        #expect(c.pointee == 3)
        #expect(d.pointee == 4)

        arena.clear()
        let a2 = arena.alloc { UInt64(5) }
        let b2 = arena.alloc { UInt32(6) }
        let c2 = arena.alloc { UInt16(7) }
        let d2 = arena.alloc { UInt8(8) }

        #expect(a2.pointee == 5)
        #expect(b2.pointee == 6)
        #expect(c2.pointee == 7)
        #expect(d2.pointee == 8)

        final class DropGuard {
            let onDrop: () -> Void
            init(onDrop: @escaping () -> Void) { self.onDrop = onDrop }
            deinit { onDrop() }
        }

        var dropped = false
        _ = arena.alloc {
            DropGuard {
                dropped = true
            }
        }
        arena.clear()
        #expect(dropped)
    }

    @Test
    func test_arena_grow() {
        var arena = Arena.new(8)
        _ = arena.alloc { UInt64(1) }
        _ = arena.alloc { UInt64(2) }

        #expect(arena.capacity() == 16)

        _ = arena.alloc { UInt32(3) }
        _ = arena.alloc { UInt32(4) }

        #expect(arena.capacity() == 24)
    }

    @Test
    func test_arena_alignment() {
        var arena = Arena.new(256)
        let x1 = arena.alloc { UInt8(1) }
        let x2 = arena.alloc { UInt16(2) }
        let x3 = arena.alloc { UInt32(3) }
        let x4 = arena.alloc { UInt64(4) }
        let x5 = arena.alloc { UInt64(5) }

        #expect(x1.pointee == 1)
        #expect(x2.pointee == 2)
        #expect(x3.pointee == 3)
        #expect(x4.pointee == 4)
        #expect(x5.pointee == 5)

        #expect(Int(bitPattern: x1.pointer) % MemoryLayout<UInt8>.alignment == 0)
        #expect(Int(bitPattern: x2.pointer) % MemoryLayout<UInt16>.alignment == 0)
        #expect(Int(bitPattern: x3.pointer) % MemoryLayout<UInt32>.alignment == 0)
        #expect(Int(bitPattern: x4.pointer) % MemoryLayout<UInt64>.alignment == 0)
        #expect(Int(bitPattern: x5.pointer) % MemoryLayout<UInt64>.alignment == 0)
    }

    @Test
    func test_arena_map() {
        struct Inner {
            var value: Int
        }
        struct Outer {
            var inner: Inner
        }

        var arena = Arena.new(256)
        let outer = arena.alloc { Outer(inner: Inner(value: 99)) }
        // Test map mapping pointer to inner member
        let mappedInner = outer.map { outerRef in
            withUnsafeMutablePointer(to: &outerRef.inner) { $0 }
        }
        #expect(mappedInner.pointee.value == 99)
    }

    @Test(.disabled("Upstream #[should_panic]: tests assertion failure on use-after-clear"))
    func test_arena_use_after_clear() {
        var arena = Arena.new(16)
        let value = arena.alloc { UInt64(1) }
        arena.clear()
        _ = value.pointee
    }
}
