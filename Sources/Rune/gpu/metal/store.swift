// Ported from: crates/rune/src/gpu/metal/store.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Copy-on-Write buffer storage ring (`Store`), mirroring `crates/rune/src/gpu/metal/store.rs`.
//!
//! A `MetalBuffer` holds one active `MetalRawBuffer` plus up to `SPARES = 2` spare allocations.
//! Writes while no recorded or in-flight GPU work references the active allocation mutate it in
//! place. Writes while recorded or in-flight GPU work still reads the active allocation swap in an
//! idle spare (retiring old spares once `completed >= retiredAt`), copy forward only the byte spans
//! outside the write (`missed`), and record the write in a bounded `LOG = 8` span ring so partial
//! writes copy only what changed since that spare last saw the buffer.

#if canImport(Metal)
import Metal
#endif
#if !os(WASI)
import Foundation
#endif

public let METAL_STORE_SPARES: Int = 2
public let METAL_STORE_LOG: Int = 8

private let storeSwapsLock = LiveLock()
// PORT NOTE: Guarded by `storeSwapsLock`, mirroring `static SWAPS: AtomicU64` in `store.rs`.
nonisolated(unsafe) private var globalStoreSwaps: UInt64 = 0

public func metalStoreTotalSwaps() -> UInt64 {
    storeSwapsLock.withLock { globalStoreSwaps }
}

/// Half-open byte span `[start, end)` within a buffer.
public struct StoreSpan: Sendable, Equatable {
    public var start: Int
    public var end: Int

    public init(_ start: Int, _ end: Int) {
        self.start = start
        self.end = end
    }
}

/// Computes the uncovered sub-spans of `[0, totalLength)` after subtracting `written` `[wStart, wEnd)`
/// from `dirty` `[dStart, dEnd)` (or `[0, totalLength)` when `dirty == nil`).
public func storeMissedSpans(totalLength: Int, dirty: StoreSpan?, written: StoreSpan) -> [StoreSpan] {
    let base = dirty ?? StoreSpan(0, totalLength)
    let a = max(0, min(base.start, totalLength))
    let b = max(a, min(base.end, totalLength))
    if a >= b { return [] }
    let w0 = max(a, min(written.start, b))
    let w1 = max(w0, min(written.end, b))
    var out: [StoreSpan] = []
    if a < w0 {
        out.append(StoreSpan(a, w0))
    }
    if w1 < b {
        out.append(StoreSpan(w1, b))
    }
    return out
}

/// One underlying buffer allocation (wrapping an `MTLBuffer` on Apple platforms and a host byte
/// slice on non-Apple platforms).
// PORT NOTE: Synchronized by the owning `MetalBufferStore` lock; `MTLBuffer` contents are CPU-shared (`storageModeShared`) and only mutated while idle or freshly swapped.
public final class MetalRawBuffer: @unchecked Sendable {
    public let length: Int
    #if canImport(Metal)
    public let mtlBuffer: (any MTLBuffer)?
    #endif
    private var hostBytes: [UInt8]
    /// Number of unsubmitted passes/encoders currently holding this raw allocation.
    var recordedUses: Int = 0
    /// Highest submission index reading from this raw allocation (`0` means never submitted).
    var lastSubmitted: UInt64 = 0
    /// Generation in the `Store`'s write log that this allocation already reflects.
    var generation: UInt64 = 0

    #if canImport(Metal)
    public init(device: (any MTLDevice)?, length: Int, label: String? = nil) {
        let allocLen = max(length, 1)
        self.length = length
        if let device, let buf = device.makeBuffer(length: allocLen, options: .storageModeShared) {
            if let label { buf.label = label }
            memset(buf.contents(), 0, allocLen)
            self.mtlBuffer = buf
            self.hostBytes = []
        } else {
            self.mtlBuffer = nil
            self.hostBytes = [UInt8](repeating: 0, count: length)
        }
    }
    #else
    public init(length: Int, label: String? = nil) {
        _ = label
        self.length = length
        self.hostBytes = [UInt8](repeating: 0, count: length)
    }
    #endif

    public func write(_ offset: Int, _ bytes: UnsafeRawBufferPointer) {
        guard bytes.count > 0, let src = bytes.baseAddress else { return }
        precondition(offset >= 0 && offset + bytes.count <= length, "MetalRawBuffer write out of bounds")
        #if canImport(Metal)
        if let buf = mtlBuffer {
            buf.contents().advanced(by: offset).copyMemory(from: src, byteCount: bytes.count)
            return
        }
        #endif
        hostBytes.withUnsafeMutableBytes { dst in
            if let dstBase = dst.baseAddress {
                dstBase.advanced(by: offset).copyMemory(from: src, byteCount: bytes.count)
            }
        }
    }

    public func copySpan(_ span: StoreSpan, from other: MetalRawBuffer) {
        let count = span.end - span.start
        guard count > 0 else { return }
        #if canImport(Metal)
        if let dstBuf = mtlBuffer, let srcBuf = other.mtlBuffer {
            dstBuf.contents().advanced(by: span.start).copyMemory(
                from: srcBuf.contents().advanced(by: span.start),
                byteCount: count
            )
            return
        }
        #endif
        let slice = other.readSlice(span.start..<span.end)
        slice.withUnsafeBytes { raw in
            write(span.start, raw)
        }
    }

    public func readSlice(_ range: Range<Int>) -> [UInt8] {
        let clampedStart = max(0, min(range.lowerBound, length))
        let clampedEnd = max(clampedStart, min(range.upperBound, length))
        guard clampedStart < clampedEnd else { return [] }
        #if canImport(Metal)
        if let buf = mtlBuffer {
            let ptr = buf.contents().advanced(by: clampedStart).assumingMemoryBound(to: UInt8.self)
            return Array(UnsafeBufferPointer(start: ptr, count: clampedEnd - clampedStart))
        }
        #endif
        return Array(hostBytes[clampedStart..<clampedEnd])
    }
}

/// Copy-on-Write storage manager for a single logical buffer.
// PORT NOTE: Synchronized via `lock` (`LiveLock`), mirroring `Mutex<Inner>` in `crates/rune/src/gpu/metal/store.rs`.
public final class MetalBufferStore: @unchecked Sendable {
    private let lock = LiveLock()
    public let length: Int
    private let label: String?
    #if canImport(Metal)
    private let mtlDevice: (any MTLDevice)?
    #endif
    private let onAllocate: (@Sendable () -> Void)?
    private let onFree: (@Sendable () -> Void)?

    private var current: MetalRawBuffer
    private var spares: [MetalRawBuffer] = []
    private var log: [StoreSpan] = Array(repeating: StoreSpan(0, 0), count: METAL_STORE_LOG)
    private var writeGen: UInt64 = 0
    private var swapCount: UInt64 = 0
    private var copiedBytes: UInt64 = 0

    #if canImport(Metal)
    public init(
        device: (any MTLDevice)?,
        length: Int,
        label: String? = nil,
        onAllocate: (@Sendable () -> Void)? = nil,
        onFree: (@Sendable () -> Void)? = nil
    ) {
        self.mtlDevice = device
        self.length = length
        self.label = label
        self.onAllocate = onAllocate
        self.onFree = onFree
        self.current = MetalRawBuffer(device: device, length: length, label: label)
        onAllocate?()
    }
    #else
    public init(
        length: Int,
        label: String? = nil,
        onAllocate: (@Sendable () -> Void)? = nil,
        onFree: (@Sendable () -> Void)? = nil
    ) {
        self.length = length
        self.label = label
        self.onAllocate = onAllocate
        self.onFree = onFree
        self.current = MetalRawBuffer(length: length, label: label)
        onAllocate?()
    }
    #endif

    deinit {
        if let onFree {
            let total = 1 + spares.count
            for _ in 0..<total {
                onFree()
            }
        }
    }

    public var activeRaw: MetalRawBuffer {
        lock.withLock { current }
    }

    /// `(spareCount, swapCount)` for diagnostics and unit tests.
    public func swaps() -> (Int, UInt64) {
        lock.withLock { (spares.count, swapCount) }
    }

    /// Total bytes copied forward across spare swaps.
    public func copied() -> UInt64 {
        lock.withLock { copiedBytes }
    }

    /// Retains the current backing for a recorded command/pass. Must be paired with `releaseRecorded` or `markSubmitted`.
    public func retainForRecording() -> MetalRawBuffer {
        lock.withLock {
            current.recordedUses += 1
            return current
        }
    }

    public func releaseRecorded(_ raw: MetalRawBuffer, submittedAt: UInt64?) {
        lock.withLock {
            raw.recordedUses = max(0, raw.recordedUses - 1)
            if let index = submittedAt, index > raw.lastSubmitted {
                raw.lastSubmitted = index
            }
        }
    }

    /// Writes `bytes` in place if nothing recorded or in-flight reads `current`, or swaps in a spare
    /// if busy (`write_in_place` / `Direct` path). Returns `true` when satisfied without staging.
    public func writeInPlace(offset: Int, bytes: UnsafeRawBufferPointer, completedSubmission: UInt64) -> Bool {
        guard bytes.count > 0 else { return true }
        return lock.withLock {
            let busy = current.recordedUses > 0 || current.lastSubmitted > completedSubmission
            if !busy {
                current.write(offset, bytes)
                recordWriteLocked(StoreSpan(offset, offset + bytes.count))
                return true
            }
            guard let next = acquireSpareLocked(completedSubmission: completedSubmission) else {
                return false
            }
            swapToSpareLocked(next, written: StoreSpan(offset, offset + bytes.count), bytes: bytes)
            return true
        }
    }

    /// `Queue.writeBuffer` path:
    /// - If `current` has NO recorded unsubmitted encoders AND no in-flight GPU submissions (`!recorded && !inFlight`), writes in place (`true`).
    /// - If `current` has NO recorded unsubmitted encoders (`current.recordedUses == 0`) so only already-submitted work reads it, swaps in a spare (`true`) so no staging command buffer is needed, while encoders recorded BEFORE `writeBuffer` (where `recordedUses > 0`) take the `false` branch so a staged copy lands ahead of the next submit!
    public func writeQueue(offset: Int, bytes: UnsafeRawBufferPointer, completedSubmission: UInt64) -> Bool {
        guard bytes.count > 0 else { return true }
        return lock.withLock {
            if current.recordedUses > 0 {
                // An encoder recorded before this `queue.write_buffer` references `current`:
                // return false so the queue stages a copy ahead of the next submit, ensuring that
                // early encoder sees the new bytes just like wgpu guarantees.
                return false
            }
            let inFlight = current.lastSubmitted > completedSubmission
            if !inFlight {
                current.write(offset, bytes)
                recordWriteLocked(StoreSpan(offset, offset + bytes.count))
                return true
            }
            guard let next = acquireSpareLocked(completedSubmission: completedSubmission) else {
                return false
            }
            swapToSpareLocked(next, written: StoreSpan(offset, offset + bytes.count), bytes: bytes)
            return true
        }
    }

    /// Marks a GPU write (e.g. copy destination or storage buffer write) covering `span`.
    public func gpuWrite(_ span: StoreSpan) {
        lock.withLock {
            recordWriteLocked(span)
        }
    }

    public func readBytes(_ range: Range<Int>) -> [UInt8] {
        lock.withLock { current.readSlice(range) }
    }

    // MARK: - Locked Helpers

    private func recordWriteLocked(_ span: StoreSpan) {
        let slot = Int(writeGen % UInt64(METAL_STORE_LOG))
        log[slot] = span
        writeGen &+= 1
        current.generation = writeGen
    }

    private func acquireSpareLocked(completedSubmission: UInt64) -> MetalRawBuffer? {
        if let idx = spares.firstIndex(where: { $0.recordedUses == 0 && $0.lastSubmitted <= completedSubmission }) {
            return spares.remove(at: idx)
        }
        if spares.count < METAL_STORE_SPARES {
            let fresh: MetalRawBuffer
            #if canImport(Metal)
            fresh = MetalRawBuffer(device: mtlDevice, length: length, label: label)
            #else
            fresh = MetalRawBuffer(length: length, label: label)
            #endif
            fresh.generation = 0
            onAllocate?()
            return fresh
        }
        return nil
    }

    private func swapToSpareLocked(_ next: MetalRawBuffer, written: StoreSpan, bytes: UnsafeRawBufferPointer) {
        let old = current
        // Determine dirty region between `next.generation` and `old.generation`.
        let delta = old.generation >= next.generation ? (old.generation - next.generation) : UInt64.max
        let dirty: StoreSpan?
        if next.generation == 0 || delta > UInt64(METAL_STORE_LOG) {
            dirty = StoreSpan(0, length)
        } else if delta == 0 {
            dirty = StoreSpan(0, 0)
        } else {
            var minStart = length
            var maxEnd = 0
            for g in next.generation..<old.generation {
                let s = log[Int(g % UInt64(METAL_STORE_LOG))]
                if s.start < s.end {
                    minStart = min(minStart, s.start)
                    maxEnd = max(maxEnd, s.end)
                }
            }
            dirty = minStart < maxEnd ? StoreSpan(minStart, maxEnd) : StoreSpan(0, 0)
        }

        let missed = storeMissedSpans(totalLength: length, dirty: dirty, written: written)
        for span in missed {
            next.copySpan(span, from: old)
            copiedBytes &+= UInt64(span.end - span.start)
        }
        next.write(written.start, bytes)

        if spares.count < METAL_STORE_SPARES {
            spares.append(old)
        } else {
            onFree?()
        }
        current = next
        swapCount &+= 1
        storeSwapsLock.withLock { globalStoreSwaps &+= 1 }
        recordWriteLocked(written)
    }
}
