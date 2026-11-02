// Ported from: crates/procwatch/src/alloc.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#elseif canImport(WinSDK)
import WinSDK
#endif

// PORT NOTE: Swift does not expose a user-replaceable `#[global_allocator]` (`GlobalAlloc`) hook
// for automatic runtime-wide heap interception. We port the `GlobalAllocator` protocol, `System`
// allocator, `Counting` wrapper, RAII `alloc.Buffer`, and all global + per-thread atomic/TLS
// counters 1:1 so callers and benchmarks using `Counting` or `alloc.Buffer` observe identical
// live/peak/big-block/tag/per-thread allocation semantics across all platforms.

private struct ThreadLocalData {
    var tag: UInt8 = 0
    var threadAllocs: UInt64 = 0
    var threadBytes: UInt64 = 0
    var uninstalledOverride: Bool = false
}

#if os(WASI)
// PORT NOTE: WASI (wasm32-unknown-wasip1) is single-threaded; thread-local counters map to static storage.
nonisolated(unsafe) private var wasiThreadData = ThreadLocalData()

@inline(__always)
private func readThreadData<R>(_ body: (ThreadLocalData) -> R) -> R {
    body(wasiThreadData)
}

@inline(__always)
private func mutateThreadData<R>(_ body: (inout ThreadLocalData) -> R) -> R {
    body(&wasiThreadData)
}
#elseif os(Windows)
private let tlsIndex: DWORD = {
    let idx = TlsAlloc()
    precondition(idx != TLS_OUT_OF_INDEXES, "Procwatch: TlsAlloc failed")
    return idx
}()

@inline(__always)
private func readThreadData<R>(_ body: (ThreadLocalData) -> R) -> R {
    guard let raw = TlsGetValue(tlsIndex) else {
        return body(ThreadLocalData())
    }
    return body(raw.assumingMemoryBound(to: ThreadLocalData.self).pointee)
}

@inline(__always)
private func mutateThreadData<R>(_ body: (inout ThreadLocalData) -> R) -> R {
    let ptr: UnsafeMutablePointer<ThreadLocalData>
    if let raw = TlsGetValue(tlsIndex) {
        ptr = raw.assumingMemoryBound(to: ThreadLocalData.self)
    } else {
        ptr = UnsafeMutablePointer<ThreadLocalData>.allocate(capacity: 1)
        ptr.initialize(to: ThreadLocalData())
        _ = TlsSetValue(tlsIndex, UnsafeMutableRawPointer(ptr))
    }
    return body(&ptr.pointee)
}
#else
#if canImport(Darwin)
private func procwatchTlsDestructor(_ raw: UnsafeMutableRawPointer) {
    let ptr = raw.assumingMemoryBound(to: ThreadLocalData.self)
    ptr.deinitialize(count: 1)
    ptr.deallocate()
}
#else
private func procwatchTlsDestructor(_ raw: UnsafeMutableRawPointer?) {
    guard let raw else { return }
    let ptr = raw.assumingMemoryBound(to: ThreadLocalData.self)
    ptr.deinitialize(count: 1)
    ptr.deallocate()
}
#endif

private let tlsKey: pthread_key_t = {
    var key = pthread_key_t()
    let rc = pthread_key_create(&key, procwatchTlsDestructor)
    precondition(rc == 0, "Procwatch: pthread_key_create failed with \(rc)")
    return key
}()

@inline(__always)
private func readThreadData<R>(_ body: (ThreadLocalData) -> R) -> R {
    guard let raw = pthread_getspecific(tlsKey) else {
        return body(ThreadLocalData())
    }
    return body(raw.assumingMemoryBound(to: ThreadLocalData.self).pointee)
}

@inline(__always)
private func mutateThreadData<R>(_ body: (inout ThreadLocalData) -> R) -> R {
    let ptr: UnsafeMutablePointer<ThreadLocalData>
    if let raw = pthread_getspecific(tlsKey) {
        ptr = raw.assumingMemoryBound(to: ThreadLocalData.self)
    } else {
        ptr = UnsafeMutablePointer<ThreadLocalData>.allocate(capacity: 1)
        ptr.initialize(to: ThreadLocalData())
        _ = pthread_setspecific(tlsKey, UnsafeMutableRawPointer(ptr))
    }
    return body(&ptr.pointee)
}
#endif

// PORT NOTE: Synchronized via internal NSLock protecting global heap/tag counters across threads.
private final class AllocCounters: @unchecked Sendable {
    static let shared = AllocCounters()

    private let lock = NSLock()
    private var installed: Bool = false
    private var live: Int64 = 0
    private var peak: Int64 = 0
    private var allocs: UInt64 = 0
    private var largest: Int = 0
    private var bigLive: Int64 = 0
    private var bigBlocks: Int64 = 0
    private var tagNet: [Int64] = Array(repeating: 0, count: alloc.tags)
    private var tagNames: [String?] = Array(repeating: nil, count: alloc.tags)

    func markInstalled() {
        lock.lock()
        installed = true
        lock.unlock()
    }

    func isInstalled() -> Bool {
        if readThreadData({ $0.uninstalledOverride }) {
            return false
        }
        lock.lock()
        let v = installed
        lock.unlock()
        return v
    }

    func recordCountedAndGrew(_ size: Int, tag: Int) {
        lock.lock()
        installed = true
        allocs &+= 1
        let sizeI64 = Int64(size)
        live += sizeI64
        if live > peak {
            peak = live
        }
        if size > largest {
            largest = size
        }
        if size >= alloc.big {
            bigLive += sizeI64
            bigBlocks += 1
        }
        let idx = (tag >= 0 && tag < alloc.tags) ? tag : 0
        tagNet[idx] += sizeI64
        lock.unlock()
    }

    func recordRealloc(oldSize: Int, newSize: Int, tag: Int) {
        lock.lock()
        installed = true
        allocs &+= 1
        let oldI64 = Int64(oldSize)
        let newI64 = Int64(newSize)
        let idx = (tag >= 0 && tag < alloc.tags) ? tag : 0

        // shrank(oldSize)
        live -= oldI64
        if oldSize >= alloc.big {
            bigLive -= oldI64
            bigBlocks -= 1
        }
        tagNet[idx] -= oldI64

        // grew(newSize)
        live += newI64
        if live > peak {
            peak = live
        }
        if newSize > largest {
            largest = newSize
        }
        if newSize >= alloc.big {
            bigLive += newI64
            bigBlocks += 1
        }
        tagNet[idx] += newI64
        lock.unlock()
    }

    func recordShrank(_ size: Int, tag: Int) {
        lock.lock()
        let sizeI64 = Int64(size)
        live -= sizeI64
        if size >= alloc.big {
            bigLive -= sizeI64
            bigBlocks -= 1
        }
        let idx = (tag >= 0 && tag < alloc.tags) ? tag : 0
        tagNet[idx] -= sizeI64
        lock.unlock()
    }

    func registerTag(_ name: String) -> UInt8 {
        lock.lock()
        defer { lock.unlock() }
        for i in 1..<alloc.tags {
            if let existing = tagNames[i] {
                if existing == name {
                    return UInt8(i)
                }
            } else {
                tagNames[i] = name
                return UInt8(i)
            }
        }
        return 0
    }

    func snapshotHeap() -> alloc.Heap? {
        if readThreadData({ $0.uninstalledOverride }) {
            return nil
        }
        lock.lock()
        defer { lock.unlock() }
        guard installed else {
            return nil
        }
        var collected: [(String, Int64)] = []
        collected.reserveCapacity(alloc.tags)
        collected.append(("untagged", tagNet[0]))
        for i in 1..<alloc.tags {
            if let name = tagNames[i] {
                collected.append((name, tagNet[i]))
            }
        }
        collected.sort { $0.1 > $1.1 }
        return alloc.Heap(
            live: live,
            peak: peak,
            allocations: allocs,
            largest: largest,
            bigLive: bigLive,
            bigBlocks: bigBlocks,
            tags: collected
        )
    }
}

/// Memory layout describing requested size and power-of-two alignment.
public struct Layout: Equatable, Hashable, Sendable {
    public let size: Int
    public let align: Int

    public init?(size: Int, align: Int) {
        guard size >= 0, align > 0, (align & (align - 1)) == 0 else {
            return nil
        }
        self.size = size
        self.align = align
    }

    public static func fromSizeAlign(_ size: Int, _ align: Int) -> Layout? {
        Layout(size: size, align: align)
    }
}

/// Protocol mirroring Rust's `std::alloc::GlobalAlloc`.
public protocol GlobalAllocator: Sendable {
    func alloc(_ layout: Layout) -> UnsafeMutableRawPointer?
    func allocZeroed(_ layout: Layout) -> UnsafeMutableRawPointer?
    func dealloc(_ ptr: UnsafeMutableRawPointer, _ layout: Layout)
    func realloc(_ ptr: UnsafeMutableRawPointer, _ layout: Layout, _ newSize: Int) -> UnsafeMutableRawPointer?
}

/// System backing allocator using Swift's aligned raw memory primitives.
public struct System: GlobalAllocator, Sendable {
    public init() {}

    public func alloc(_ layout: Layout) -> UnsafeMutableRawPointer? {
        UnsafeMutableRawPointer.allocate(byteCount: max(layout.size, 1), alignment: layout.align)
    }

    public func allocZeroed(_ layout: Layout) -> UnsafeMutableRawPointer? {
        let ptr = UnsafeMutableRawPointer.allocate(byteCount: max(layout.size, 1), alignment: layout.align)
        if layout.size > 0 {
            ptr.initializeMemory(as: UInt8.self, repeating: 0, count: layout.size)
        }
        return ptr
    }

    public func dealloc(_ ptr: UnsafeMutableRawPointer, _ layout: Layout) {
        _ = layout
        ptr.deallocate()
    }

    public func realloc(_ ptr: UnsafeMutableRawPointer, _ layout: Layout, _ newSize: Int) -> UnsafeMutableRawPointer? {
        guard newSize >= 0 else { return nil }
        let next = UnsafeMutableRawPointer.allocate(byteCount: max(newSize, 1), alignment: layout.align)
        let copyBytes = min(layout.size, newSize)
        if copyBytes > 0 {
            next.copyMemory(from: ptr, byteCount: copyBytes)
        }
        ptr.deallocate()
        return next
    }
}

/// A counting global allocator namespace: live and peak heap bytes, the largest single request,
/// bytes held in big blocks, and net bytes per thread tag.
public enum alloc {
    /// A block at least this big counts as "big": a buffer worth naming in a warning.
    public static let big: Int = 64 << 20
    /// Thread tags there's room for; more fall into tag 0, "untagged".
    public static let tags: Int = 16

    /// Allocations (and reallocations) made on this thread so far; 0 unless ``Counting`` has been used.
    public static func threadAllocations() -> UInt64 {
        readThreadData { data in
            data.uninstalledOverride ? 0 : data.threadAllocs
        }
    }

    /// Bytes this thread has asked for so far: every successful alloc, allocZeroed, and realloc
    /// (a realloc counts its whole new size), frees not subtracted. Traffic, not live heap.
    /// `nil` until ``Counting`` has served a request or been installed, so a missing allocator never reads as zero.
    public static func threadAllocatedBytes() -> UInt64? {
        guard AllocCounters.shared.isInstalled() else {
            return nil
        }
        return readThreadData { $0.threadBytes }
    }

    /// Marks the counting allocator as installed in the current process.
    public static func install() {
        AllocCounters.shared.markInstalled()
    }

    /// Executes `body` on the current thread as if no counting allocator is installed.
    ///
    /// Used by `no_allocator` integration tests when SwiftPM runs multiple test suites in one process.
    public static func withUninstalledScope<R>(_ body: () throws -> R) rethrows -> R {
        let previous = mutateThreadData { data -> Bool in
            let prev = data.uninstalledOverride
            data.uninstalledOverride = true
            return prev
        }
        defer {
            mutateThreadData { data in
                data.uninstalledOverride = previous
            }
        }
        return try body()
    }

    /// Wrapping counting allocator.
    public struct Counting<A: GlobalAllocator>: GlobalAllocator, Sendable {
        public let inner: A

        public init(_ inner: A) {
            self.inner = inner
        }

        public static func new(_ inner: A) -> Counting<A> {
            Counting(inner)
        }

        public func alloc(_ layout: Layout) -> UnsafeMutableRawPointer? {
            AllocCounters.shared.markInstalled()
            guard let ptr = inner.alloc(layout) else {
                return nil
            }
            let tag = mutateThreadData { data -> Int in
                data.threadAllocs &+= 1
                data.threadBytes &+= UInt64(layout.size)
                return Int(data.tag)
            }
            AllocCounters.shared.recordCountedAndGrew(layout.size, tag: tag)
            return ptr
        }

        public func allocZeroed(_ layout: Layout) -> UnsafeMutableRawPointer? {
            AllocCounters.shared.markInstalled()
            guard let ptr = inner.allocZeroed(layout) else {
                return nil
            }
            let tag = mutateThreadData { data -> Int in
                data.threadAllocs &+= 1
                data.threadBytes &+= UInt64(layout.size)
                return Int(data.tag)
            }
            AllocCounters.shared.recordCountedAndGrew(layout.size, tag: tag)
            return ptr
        }

        public func dealloc(_ ptr: UnsafeMutableRawPointer, _ layout: Layout) {
            inner.dealloc(ptr, layout)
            let tag = readThreadData { Int($0.tag) }
            AllocCounters.shared.recordShrank(layout.size, tag: tag)
        }

        public func realloc(_ ptr: UnsafeMutableRawPointer, _ layout: Layout, _ newSize: Int) -> UnsafeMutableRawPointer? {
            guard let next = inner.realloc(ptr, layout, newSize) else {
                return nil
            }
            let tag = mutateThreadData { data -> Int in
                data.threadAllocs &+= 1
                data.threadBytes &+= UInt64(newSize)
                return Int(data.tag)
            }
            AllocCounters.shared.recordRealloc(oldSize: layout.size, newSize: newSize, tag: tag)
            return next
        }
    }

    // PORT NOTE: Buffer wraps an immutable pointer/layout allocated via Counting.system() and freed once in deinit.
    /// RAII heap buffer allocated and freed through ``Counting/system()``.
    public final class Buffer: @unchecked Sendable {
        public let count: Int
        public let pointer: UnsafeMutableRawPointer
        private let layout: Layout

        public init(repeating byte: UInt8 = 0, count: Int) {
            let validCount = max(0, count)
            let layout = Layout(size: validCount, align: 8)!
            let allocator = Counting.system()
            let ptr: UnsafeMutableRawPointer
            if byte == 0 {
                ptr = allocator.allocZeroed(layout)!
            } else {
                ptr = allocator.alloc(layout)!
                if validCount > 0 {
                    ptr.initializeMemory(as: UInt8.self, repeating: byte, count: validCount)
                }
            }
            self.count = validCount
            self.pointer = ptr
            self.layout = layout
        }

        deinit {
            Counting.system().dealloc(pointer, layout)
        }
    }

    /// Counts this thread's heap under `name` from now on (net bytes: allocated minus freed here).
    public static func tagThread(_ name: String) {
        let idx = AllocCounters.shared.registerTag(name)
        mutateThreadData { data in
            data.tag = idx
        }
    }

    /// Snapshot of counted heap statistics.
    public struct Heap: Equatable, Sendable {
        public var live: Int64
        public var peak: Int64
        public var allocations: UInt64
        public var largest: Int
        /// Bytes, and blocks, held in allocations of at least ``alloc/big``.
        public var bigLive: Int64
        public var bigBlocks: Int64
        /// Net bytes per thread tag, biggest first; `"untagged"` is everything else.
        public var tags: [(String, Int64)]

        public init(
            live: Int64 = 0,
            peak: Int64 = 0,
            allocations: UInt64 = 0,
            largest: Int = 0,
            bigLive: Int64 = 0,
            bigBlocks: Int64 = 0,
            tags: [(String, Int64)] = []
        ) {
            self.live = live
            self.peak = peak
            self.allocations = allocations
            self.largest = largest
            self.bigLive = bigLive
            self.bigBlocks = bigBlocks
            self.tags = tags
        }

        public static func == (lhs: Heap, rhs: Heap) -> Bool {
            guard lhs.live == rhs.live,
                  lhs.peak == rhs.peak,
                  lhs.allocations == rhs.allocations,
                  lhs.largest == rhs.largest,
                  lhs.bigLive == rhs.bigLive,
                  lhs.bigBlocks == rhs.bigBlocks,
                  lhs.tags.count == rhs.tags.count
            else {
                return false
            }
            for (a, b) in zip(lhs.tags, rhs.tags) where a.0 != b.0 || a.1 != b.1 {
                return false
            }
            return true
        }
    }

    /// The counters, or `nil` when ``Counting`` isn't active.
    public static func heap() -> Heap? {
        AllocCounters.shared.snapshotHeap()
    }
}

extension alloc.Counting where A == System {
    public static func system() -> alloc.Counting<System> {
        Self(System())
    }
}

public typealias Heap = alloc.Heap
