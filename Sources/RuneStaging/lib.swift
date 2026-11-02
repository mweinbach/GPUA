// Ported from: crates/rune-staging/src/lib.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Per-frame GPU uploads through reused staging memory.
//!
//! On native backends every `Queue::write_buffer` and `Queue::write_texture` allocates a fresh
//! staging buffer and frees it once the GPU has copied out of it. `Staging` writes into mapped
//! chunks instead and records the copies itself: into an encoder at `flush`, or in a submission
//! of its own at `submit`. A chunk comes back for reuse once the GPU is done with it, so a steady
//! animating frame allocates no buffers.

import CWebGPU
#if !os(WASI)
import Foundation
#endif

// MARK: - Constants & Alignment Helpers

/// The size of a new chunk; a larger write gets a chunk sized to its next power of two.
public let chunkSize: UInt64 = 128 * 1024

/// Returned chunks kept for reuse, by count and in bytes; larger chunks are freed on return.
public let keepChunks: Int = 8
public let keepBytes: UInt64 = 4 << 20
public let keepChunkMax: UInt64 = 1 << 20

/// Staged bytes past which a write first submits what is pending, so a caller that never
/// flushes can't grow the chunks without bound.
public let maxPending: UInt64 = 16 << 20

/// WebGPU buffer-to-buffer copy alignment (`wgpu::COPY_BUFFER_ALIGNMENT`).
public let copyBufferAlignment: UInt64 = 4

/// WebGPU buffer map offset alignment (`wgpu::MAP_ALIGNMENT`).
public let mapAlignment: UInt64 = 8

/// Staged texture rows start at this alignment, and `bytes_per_row` is a multiple of it (`wgpu::COPY_BYTES_PER_ROW_ALIGNMENT`).
public let rowAlign: UInt64 = 256

/// Rounds `value` up to the next multiple of `alignment` (`u64::next_multiple_of`).
@inline(__always)
public func alignUp(_ value: UInt64, to alignment: UInt64) -> UInt64 {
    guard alignment > 1 else { return value }
    if (alignment & (alignment - 1)) == 0 {
        let mask = alignment - 1
        return (value + mask) & ~mask
    }
    let remainder = value % alignment
    return remainder == 0 ? value : value + (alignment - remainder)
}

/// Smallest power of two greater than or equal to `value` (`u64::next_power_of_two`).
@inline(__always)
public func nextPowerOfTwo(_ value: UInt64) -> UInt64 {
    if value <= 1 { return 1 }
    let shift = 64 - (value - 1).leadingZeroBitCount
    return shift >= 64 ? (1 << 63) : (1 << shift)
}

/// Bytes per texel block for uncompressed color `WGPUTextureFormat` values (`TextureFormat::block_copy_size(None)`).
public func textureFormatBlockCopySize(_ format: WGPUTextureFormat) -> UInt32? {
    switch format {
    case WGPUTextureFormat_R8Unorm,
         WGPUTextureFormat_R8Snorm,
         WGPUTextureFormat_R8Uint,
         WGPUTextureFormat_R8Sint:
        return 1
    case WGPUTextureFormat_R16Uint,
         WGPUTextureFormat_R16Sint,
         WGPUTextureFormat_R16Float,
         WGPUTextureFormat_RG8Unorm,
         WGPUTextureFormat_RG8Snorm,
         WGPUTextureFormat_RG8Uint,
         WGPUTextureFormat_RG8Sint:
        return 2
    case WGPUTextureFormat_R32Float,
         WGPUTextureFormat_R32Uint,
         WGPUTextureFormat_R32Sint,
         WGPUTextureFormat_RG16Uint,
         WGPUTextureFormat_RG16Sint,
         WGPUTextureFormat_RG16Float,
         WGPUTextureFormat_RGBA8Unorm,
         WGPUTextureFormat_RGBA8UnormSrgb,
         WGPUTextureFormat_RGBA8Snorm,
         WGPUTextureFormat_RGBA8Uint,
         WGPUTextureFormat_RGBA8Sint,
         WGPUTextureFormat_BGRA8Unorm,
         WGPUTextureFormat_BGRA8UnormSrgb,
         WGPUTextureFormat_RGB10A2Uint,
         WGPUTextureFormat_RGB10A2Unorm,
         WGPUTextureFormat_RG11B10Ufloat,
         WGPUTextureFormat_RGB9E5Ufloat:
        return 4
    case WGPUTextureFormat_RG32Float,
         WGPUTextureFormat_RG32Uint,
         WGPUTextureFormat_RG32Sint,
         WGPUTextureFormat_RGBA16Uint,
         WGPUTextureFormat_RGBA16Sint,
         WGPUTextureFormat_RGBA16Float:
        return 8
    case WGPUTextureFormat_RGBA32Float,
         WGPUTextureFormat_RGBA32Uint,
         WGPUTextureFormat_RGBA32Sint:
        return 16
    default:
        return nil
    }
}

// MARK: - Synchronization

// PORT NOTE: StagingLock uses NSLock on multi-threaded targets and is a no-op on single-threaded WASI where Foundation omits NSLock.
private final class StagingLock: @unchecked Sendable {
    #if !os(WASI)
    private let lock = NSLock()
    #endif

    @inline(__always)
    func withLock<R>(_ body: () throws -> R) rethrows -> R {
        #if !os(WASI)
        lock.lock()
        defer { lock.unlock() }
        #endif
        return try body()
    }
}

// MARK: - Direct Writer

/// Writes `data` to `buffer` at `offset` in place, for the commands recorded after it, or
/// returns false to have it staged. Commands recorded before it keep reading what they would
/// have, so the write lands no later than a flush would land it.
public typealias Direct = @Sendable (WGPUBuffer, UInt64, [UInt8]) -> Bool

// PORT NOTE: DirectRegistry replaces Rust's `OnceLock<Direct>` with lock-guarded write-once semantics across threads.
private final class DirectRegistry: @unchecked Sendable {
    static let shared = DirectRegistry()
    private let lock = StagingLock()
    private var writer: Direct?

    func set(_ direct: @escaping Direct) {
        lock.withLock {
            if writer == nil {
                writer = direct
            }
        }
    }

    func get() -> Direct? {
        lock.withLock { writer }
    }
}

/// Registers the process's `Direct` writer. The first one stays.
public func setDirect(_ direct: @escaping Direct) {
    DirectRegistry.shared.set(direct)
}

// MARK: - Stats

/// Counters, for tests and benchmarks.
public struct Stats: Equatable, Hashable, Sendable {
    /// Chunks created, each one buffer allocation.
    public var chunks: UInt64
    /// Writes staged.
    public var writes: UInt64
    /// Bytes staged, row padding included.
    public var bytes: UInt64
    /// Pending writes recorded into a caller's encoder.
    public var flushes: UInt64
    /// Pending writes submitted on their own.
    public var submits: UInt64
    /// Writes made in place by the `Direct` writer, counted in `writes` and `bytes` too.
    public var direct: UInt64

    public init(
        chunks: UInt64 = 0,
        writes: UInt64 = 0,
        bytes: UInt64 = 0,
        flushes: UInt64 = 0,
        submits: UInt64 = 0,
        direct: UInt64 = 0
    ) {
        self.chunks = chunks
        self.writes = writes
        self.bytes = bytes
        self.flushes = flushes
        self.submits = submits
        self.direct = direct
    }
}

// MARK: - Texture Metadata

/// Describes a `CWebGPU` texture's dimensions and format for row-aligned staging uploads.
// PORT NOTE: CWebGPU `WGPUTexture` is an opaque C handle without portable width/format getters on Android/WASI shims; `StagingTexture` carries or registers that metadata explicitly.
public struct StagingTexture: Equatable, Hashable, @unchecked Sendable {
    public var handle: WGPUTexture
    public var width: UInt32
    public var height: UInt32
    public var format: WGPUTextureFormat

    public init(
        _ handle: WGPUTexture,
        width: UInt32,
        height: UInt32 = 1,
        format: WGPUTextureFormat = WGPUTextureFormat_RGBA8Unorm
    ) {
        self.handle = handle
        self.width = width
        self.height = height
        self.format = format
    }
}

private struct TextureMetadata: Sendable {
    var width: UInt32
    var height: UInt32
    var bytesPerPixel: UInt32
}

// MARK: - Pure-Swift Suballocation Pool

/// A suballocated aligned byte range within a staging chunk.
public struct StagingSlice: Equatable, Hashable, Sendable {
    public var chunkId: UInt64
    public var chunkSize: UInt64
    public var offset: UInt64
    public var size: UInt64

    public init(chunkId: UInt64, chunkSize: UInt64, offset: UInt64, size: UInt64) {
        self.chunkId = chunkId
        self.chunkSize = chunkSize
        self.offset = offset
        self.size = size
    }
}

/// Pure-Swift staging chunk suballocation pool implementing upstream's exact chunk sizing,
/// alignment, active reuse, and bounded free-list retention (`keepChunks`, `keepBytes`, `keepChunkMax`).
public struct StagingPool: Sendable {
    public struct ChunkDescriptor: Equatable, Sendable {
        public var id: UInt64
        public var size: UInt64
        public var used: UInt64
        public var storage: [UInt8]

        public init(id: UInt64, size: UInt64, used: UInt64 = 0) {
            self.id = id
            self.size = size
            self.used = used
            self.storage = [UInt8](repeating: 0, count: Int(size))
        }
    }

    public private(set) var active: [ChunkDescriptor] = []
    public private(set) var free: [ChunkDescriptor] = []
    public private(set) var totalChunksCreated: UInt64 = 0
    private var nextId: UInt64 = 1

    public init() {}

    /// Reserves `size` bytes (rounded up to `copyBufferAlignment`) aligned to `align` and writes `data` into the slice.
    public mutating func stage(_ data: UnsafeRawBufferPointer, size rawSize: UInt64? = nil, align: UInt64 = mapAlignment) -> StagingSlice {
        let requested = rawSize ?? UInt64(data.count)
        let alignedSize = alignUp(requested, to: copyBufferAlignment)
        let index: Int
        if let found = active.firstIndex(where: { alignUp($0.used, to: align) + alignedSize <= $0.size }) {
            index = found
        } else {
            let chunk: ChunkDescriptor
            if let freeIdx = free.firstIndex(where: { $0.size >= alignedSize }) {
                var reused = free.remove(at: freeIdx)
                reused.used = 0
                chunk = reused
            } else {
                let allocSize = max(chunkSize, nextPowerOfTwo(alignedSize))
                let id = nextId
                nextId &+= 1
                totalChunksCreated += 1
                chunk = ChunkDescriptor(id: id, size: allocSize, used: 0)
            }
            active.append(chunk)
            index = active.count - 1
        }

        let at = alignUp(active[index].used, to: align)
        active[index].used = at + alignedSize
        if data.count > 0, let srcBase = data.baseAddress {
            let copyCount = min(data.count, Int(alignedSize))
            active[index].storage.withUnsafeMutableBytes { dstBuf in
                if let dstBase = dstBuf.baseAddress {
                    dstBase.advanced(by: Int(at)).copyMemory(from: srcBase, byteCount: copyCount)
                }
            }
        }
        return StagingSlice(
            chunkId: active[index].id,
            chunkSize: active[index].size,
            offset: at,
            size: alignedSize
        )
    }

    /// Seals and drains all active chunks so they can be recycled once GPU work completes.
    public mutating func drainActive() -> [ChunkDescriptor] {
        let drained = active
        active.removeAll(keepingCapacity: true)
        return drained
    }

    /// Returns a completed chunk to the free list if within `keepChunkMax`, `keepChunks`, and `keepBytes`.
    public mutating func recycle(_ chunk: ChunkDescriptor) {
        var returned = chunk
        returned.used = 0
        let keptBytes = free.reduce(UInt64(0)) { $0 + $1.size }
        if returned.size <= keepChunkMax && free.count < keepChunks && keptBytes + returned.size <= keepBytes {
            free.append(returned)
        }
    }

    public var freeBytes: UInt64 {
        free.reduce(0) { $0 + $1.size }
    }
}

// MARK: - Recorded Copy Commands & Pure-Swift / RAII Encoder

/// Destination of a staged upload copy command.
public enum StagedCopyDestination: Equatable, Hashable, Sendable {
    case buffer(handleBits: UInt, offset: UInt64)
    case textureRows(handleBits: UInt, width: UInt32, bytesPerPixel: UInt32, y: UInt32, rows: UInt32, bytesPerRow: UInt32)
}

/// Recorded copy operation emitted during `record`, `flush`, or `submit`.
public struct StagedCopyCommand: Equatable, Sendable {
    public var data: [UInt8]
    public var size: UInt64
    public var destination: StagedCopyDestination

    public init(data: [UInt8], size: UInt64, destination: StagedCopyDestination) {
        self.data = data
        self.size = size
        self.destination = destination
    }
}

/// Command encoder wrapper that pairs optional live `WGPUCommandEncoder` recording with RAII drop
/// tracking (`Return` in upstream): if dropped without calling `submit()`, every sealed staging
/// chunk recorded into it increments `Staging.lost()`.
// PORT NOTE: StagingCommandEncoder mirrors Rust's `Return` Drop guard on unsubmitted encoders while optionally forwarding copies to a live WGPUCommandEncoder.
public final class StagingCommandEncoder: @unchecked Sendable {
    private let lock = StagingLock()
    public let rawEncoder: WGPUCommandEncoder?
    private var recordedCopies: [StagedCopyCommand] = []
    private var returnHandlers: [@Sendable (Bool) -> Void] = []
    private var wasSubmitted = false

    public init(rawEncoder: WGPUCommandEncoder? = nil) {
        self.rawEncoder = rawEncoder
    }

    public var copies: [StagedCopyCommand] {
        lock.withLock { recordedCopies }
    }

    func appendCopy(_ command: StagedCopyCommand) {
        lock.withLock {
            recordedCopies.append(command)
        }
    }

    func addReturnHandler(_ handler: @escaping @Sendable (Bool) -> Void) {
        lock.withLock {
            returnHandlers.append(handler)
        }
    }

    /// Marks the encoder as submitted, applying tracked copies and returning sealed chunks for reuse.
    public func submit() {
        let handlers: [@Sendable (Bool) -> Void] = lock.withLock {
            guard !wasSubmitted else { return [] }
            wasSubmitted = true
            let h = returnHandlers
            returnHandlers.removeAll()
            return h
        }
        for h in handlers {
            h(true)
        }
    }

    deinit {
        if !wasSubmitted {
            for h in returnHandlers {
                h(false)
            }
        }
    }
}

// MARK: - Internal Chunk & Pending Structures

// PORT NOTE: Chunk wraps either a live mapped WGPUBuffer (on Linux/Android) or a pure-Swift byte buffer, accessed exclusively under StagingCore's lock or WGPU map callbacks.
private final class Chunk: @unchecked Sendable {
    let id: UInt64
    let size: UInt64
    let wgpuBuffer: WGPUBuffer?
    var used: UInt64 = 0
    /// Cached pointer from `wgpuBufferGetMappedRange` on first write; cleared before `wgpuBufferUnmap`.
    var mappedRange: UnsafeMutableRawPointer?
    /// Host mirror bytes used when running without a live native `WGPUBuffer` (macOS/iOS/Windows/headless).
    var hostBytes: [UInt8]

    init(id: UInt64, size: UInt64, wgpuBuffer: WGPUBuffer?) {
        self.id = id
        self.size = size
        self.wgpuBuffer = wgpuBuffer
        self.mappedRange = nil
        if wgpuBuffer == nil {
            self.hostBytes = [UInt8](repeating: 0, count: Int(size))
        } else {
            self.hostBytes = []
        }
    }

    func writeBytes(at offset: UInt64, from src: UnsafeRawBufferPointer, count: Int) {
        guard count > 0, let srcBase = src.baseAddress else { return }
        #if os(Linux) || os(Android)
        if let buf = wgpuBuffer {
            let ptr: UnsafeMutableRawPointer
            if let existing = mappedRange {
                ptr = existing
            } else {
                guard let mapped = wgpuBufferGetMappedRange(buf, 0, Int(size)) else {
                    preconditionFailure("a mapped staging chunk")
                }
                mappedRange = mapped
                ptr = mapped
            }
            ptr.advanced(by: Int(offset)).copyMemory(from: srcBase, byteCount: count)
            return
        }
        #endif
        hostBytes.withUnsafeMutableBytes { dstBuf in
            if let dstBase = dstBuf.baseAddress {
                dstBase.advanced(by: Int(offset)).copyMemory(from: srcBase, byteCount: count)
            }
        }
    }

    func writeRowPadded(at offset: UInt64, rows: UnsafeRawBufferPointer, rowBytes: Int, paddedRowBytes: Int, rowCount: Int) {
        guard rowCount > 0, rowBytes > 0, let srcBase = rows.baseAddress else { return }
        #if os(Linux) || os(Android)
        if let buf = wgpuBuffer {
            let ptr: UnsafeMutableRawPointer
            if let existing = mappedRange {
                ptr = existing
            } else {
                guard let mapped = wgpuBufferGetMappedRange(buf, 0, Int(size)) else {
                    preconditionFailure("a mapped staging chunk")
                }
                mappedRange = mapped
                ptr = mapped
            }
            if paddedRowBytes == rowBytes {
                ptr.advanced(by: Int(offset)).copyMemory(from: srcBase, byteCount: paddedRowBytes * rowCount)
            } else {
                for r in 0..<rowCount {
                    let dstRow = ptr.advanced(by: Int(offset) + r * paddedRowBytes)
                    let srcRow = srcBase.advanced(by: r * rowBytes)
                    dstRow.copyMemory(from: srcRow, byteCount: rowBytes)
                }
            }
            return
        }
        #endif
        hostBytes.withUnsafeMutableBytes { dstBuf in
            guard let dstBase = dstBuf.baseAddress else { return }
            if paddedRowBytes == rowBytes {
                dstBase.advanced(by: Int(offset)).copyMemory(from: srcBase, byteCount: paddedRowBytes * rowCount)
            } else {
                for r in 0..<rowCount {
                    let dstRow = dstBase.advanced(by: Int(offset) + r * paddedRowBytes)
                    let srcRow = srcBase.advanced(by: r * rowBytes)
                    dstRow.copyMemory(from: srcRow, byteCount: rowBytes)
                }
            }
        }
    }

    func sliceBytes(offset: UInt64, size sliceSize: UInt64) -> [UInt8] {
        guard !hostBytes.isEmpty else { return [] }
        let start = Int(offset)
        let end = min(hostBytes.count, start + Int(sliceSize))
        guard start < end else { return [] }
        return Array(hostBytes[start..<end])
    }

    func unmap() {
        mappedRange = nil
        #if os(Linux) || os(Android)
        if let buf = wgpuBuffer {
            wgpuBufferUnmap(buf)
        }
        #endif
    }

    deinit {
        #if os(Linux) || os(Android)
        if let buf = wgpuBuffer {
            wgpuBufferDestroy(buf)
            wgpuBufferRelease(buf)
        }
        #endif
    }
}

// PORT NOTE: Dst stores CWebGPU buffer/texture handles protected by StagingCore's lock.
private enum Dst: @unchecked Sendable {
    case buffer(WGPUBuffer, UInt64, rawLength: Int)
    case rows(texture: WGPUTexture, width: UInt32, bytesPerPixel: UInt32, y: UInt32, rows: UInt32, bytesPerRow: UInt32)
}

private struct Pending: Sendable {
    var src: Chunk
    var offset: UInt64
    var size: UInt64
    var dst: Dst
}

// MARK: - StagingCore

// PORT NOTE: StagingCore mirrors Rust's `Arc<Mutex<Inner>>` + atomic `lost` and `busy` flags behind `StagingLock`.
private final class StagingCore: @unchecked Sendable {
    let stateLock = StagingLock()
    let flagLock = StagingLock()

    let device: WGPUDevice?
    let queue: WGPUQueue?
    let instanceDirect: Direct?

    private var isBusyFlag: Bool = false
    private var lostCountValue: UInt64 = 0

    private var active: [Chunk] = []
    private var free: [Chunk] = []
    private var returned: [Chunk] = []
    /// Chunks unmapped during `flush(WGPUCommandEncoder)` awaiting `recall()` after queue submission.
    private var flushedAwaitingRecall: [Chunk] = []
    private var pending: [Pending] = []
    private var pendingBytes: UInt64 = 0
    private var currentStats = Stats()
    private var nextChunkId: UInt64 = 1

    private var textureRegistry: [UInt: TextureMetadata] = [:]
    private var trackedBuffers: [UInt: [UInt8]] = [:]
    private var trackedTextures: [UInt: [UInt32: [UInt8]]] = [:]

    init(device: WGPUDevice?, queue: WGPUQueue?, direct: Direct?) {
        self.device = device
        self.queue = queue
        self.instanceDirect = direct
    }

    var busy: Bool {
        get { flagLock.withLock { isBusyFlag } }
        set { flagLock.withLock { isBusyFlag = newValue } }
    }

    var lost: UInt64 {
        flagLock.withLock { lostCountValue }
    }

    func addLost(_ delta: UInt64 = 1) {
        guard delta > 0 else { return }
        flagLock.withLock {
            lostCountValue &+= delta
        }
    }

    private var hasLiveNativeWgpu: Bool {
        #if os(Linux) || os(Android)
        guard let dev = device else { return false }
        return dev != OpaquePointer(bitPattern: 1)
        #else
        return false
        #endif
    }

    private var hasLiveWasmQueue: Bool {
        #if os(WASI)
        guard let q = queue else { return false }
        return q != OpaquePointer(bitPattern: 1)
        #else
        return false
        #endif
    }

    func registerTexture(_ texture: WGPUTexture, width: UInt32, height: UInt32, bytesPerPixel: UInt32) {
        let key = UInt(bitPattern: texture)
        stateLock.withLock {
            textureRegistry[key] = TextureMetadata(width: width, height: height, bytesPerPixel: bytesPerPixel)
        }
    }

    func unregisterTexture(_ texture: WGPUTexture) {
        let key = UInt(bitPattern: texture)
        stateLock.withLock {
            _ = textureRegistry.removeValue(forKey: key)
        }
    }

    func lookupTexture(_ texture: WGPUTexture) -> TextureMetadata? {
        let key = UInt(bitPattern: texture)
        return stateLock.withLock { textureRegistry[key] }
    }

    func writeBuffer(_ buffer: WGPUBuffer, offset: UInt64, bytes: UnsafeRawBufferPointer) {
        guard bytes.count > 0 else { return }

        if let directFn = instanceDirect ?? DirectRegistry.shared.get() {
            let arrayCopy = Array(bytes)
            if directFn(buffer, offset, arrayCopy) {
                stateLock.withLock {
                    currentStats.direct += 1
                    currentStats.writes += 1
                    currentStats.bytes += UInt64(arrayCopy.count)
                    applyTrackedBufferWrite(handleBits: UInt(bitPattern: buffer), offset: offset, data: arrayCopy)
                }
                return
            }
        }

        stateLock.withLock {
            #if os(WASI)
            if hasLiveWasmQueue, let q = queue, let baseAddress = bytes.baseAddress {
                wgpuQueueWriteBuffer(q, buffer, offset, baseAddress, bytes.count)
                return
            }
            #endif

            let rawSize = UInt64(bytes.count)
            let alignedSize = alignUp(rawSize, to: copyBufferAlignment)
            let (chunk, at) = stageLocked(size: rawSize, align: mapAlignment) { chunk, startOffset in
                chunk.writeBytes(at: startOffset, from: bytes, count: bytes.count)
            }
            pending.append(
                Pending(
                    src: chunk,
                    offset: at,
                    size: alignedSize,
                    dst: .buffer(buffer, offset, rawLength: bytes.count)
                )
            )
        }
    }

    func writeTextureRows(
        _ texture: WGPUTexture,
        width: UInt32,
        bytesPerPixel: UInt32,
        y: UInt32,
        rows: UnsafeRawBufferPointer
    ) {
        let row = width &* bytesPerPixel
        guard row > 0 else { return }
        let count = UInt32(rows.count / Int(row))
        guard count > 0 else { return }

        stateLock.withLock {
            #if os(WASI)
            if hasLiveWasmQueue, let q = queue, let baseAddress = rows.baseAddress {
                var dest = WGPUTexelCopyTextureInfo()
                dest.texture = texture
                dest.mipLevel = 0
                dest.origin = WGPUOrigin3D(x: 0, y: y, z: 0)
                dest.aspect = WGPUTextureAspect_All

                var layout = WGPUTexelCopyBufferLayout()
                layout.offset = 0
                layout.bytesPerRow = row
                layout.rowsPerImage = WGPU_COPY_STRIDE_UNDEFINED

                var extent = WGPUExtent3D(width: width, height: count, depthOrArrayLayers: 1)
                wgpuQueueWriteTexture(q, &dest, baseAddress, Int(row * count), &layout, &extent)
                return
            }
            #endif

            let padded = alignUp(UInt64(row), to: rowAlign)
            let totalSize = padded * UInt64(count)
            let (chunk, at) = stageLocked(size: totalSize, align: rowAlign) { chunk, startOffset in
                chunk.writeRowPadded(
                    at: startOffset,
                    rows: rows,
                    rowBytes: Int(row),
                    paddedRowBytes: Int(padded),
                    rowCount: Int(count)
                )
            }
            pending.append(
                Pending(
                    src: chunk,
                    offset: at,
                    size: totalSize,
                    dst: .rows(
                        texture: texture,
                        width: width,
                        bytesPerPixel: bytesPerPixel,
                        y: y,
                        rows: count,
                        bytesPerRow: UInt32(padded)
                    )
                )
            )
        }
    }

    func flush(rawEncoder: WGPUCommandEncoder) {
        guard busy else { return }
        stateLock.withLock {
            if pending.isEmpty && active.isEmpty { return }
            encodeRawLocked(encoder: rawEncoder)
            currentStats.flushes += 1
        }
    }

    func flush(stagingEncoder: StagingCommandEncoder) {
        guard busy else { return }
        stateLock.withLock {
            if pending.isEmpty && active.isEmpty { return }
            encodeManagedLocked(encoder: stagingEncoder)
            currentStats.flushes += 1
        }
    }

    func record(rawEncoder: WGPUCommandEncoder) {
        guard busy else { return }
        stateLock.withLock {
            if pending.isEmpty { return }
            copyToRawLocked(encoder: rawEncoder, applyHostTracking: true)
            currentStats.flushes += 1
        }
    }

    func record(stagingEncoder: StagingCommandEncoder) {
        guard busy else { return }
        stateLock.withLock {
            if pending.isEmpty { return }
            let commands = copyToManagedLocked(encoder: stagingEncoder)
            stagingEncoder.addReturnHandler { [weak self] submitted in
                guard submitted, let self else { return }
                self.stateLock.withLock {
                    for cmd in commands {
                        self.applyTrackedCommandLocked(cmd)
                    }
                }
            }
            currentStats.flushes += 1
        }
    }

    func submit() {
        guard busy else { return }
        stateLock.withLock {
            submitLocked()
        }
    }

    func recall() {
        stateLock.withLock {
            recallFlushedLocked()
        }
    }

    func isPending() -> Bool {
        stateLock.withLock { !pending.isEmpty }
    }

    func stats() -> Stats {
        stateLock.withLock { currentStats }
    }

    func readTrackedBuffer(_ buffer: WGPUBuffer, offset: UInt64, size: Int?) -> [UInt8] {
        let key = UInt(bitPattern: buffer)
        return stateLock.withLock {
            guard let storage = trackedBuffers[key] else { return [] }
            let start = Int(offset)
            guard start < storage.count else { return [] }
            let end = size.map { min(storage.count, start + $0) } ?? storage.count
            guard start < end else { return [] }
            return Array(storage[start..<end])
        }
    }

    func readTrackedTextureRow(_ texture: WGPUTexture, y: UInt32) -> [UInt8]? {
        let key = UInt(bitPattern: texture)
        return stateLock.withLock {
            trackedTextures[key]?[y]
        }
    }

    // MARK: - Locked Internals

    private func stageLocked(
        size rawSize: UInt64,
        align: UInt64,
        fill: (Chunk, UInt64) -> Void
    ) -> (Chunk, UInt64) {
        let size = alignUp(rawSize, to: copyBufferAlignment)
        if pendingBytes + size > maxPending {
            submitLocked()
        }

        let index: Int
        if let existing = active.firstIndex(where: { alignUp($0.used, to: align) + size <= $0.size }) {
            index = existing
        } else {
            receiveLocked()
            let chunk: Chunk
            if let freeIndex = free.firstIndex(where: { $0.size >= size }) {
                let last = free.count - 1
                free.swapAt(freeIndex, last)
                chunk = free.removeLast()
            } else {
                currentStats.chunks += 1
                let allocSize = max(chunkSize, nextPowerOfTwo(size))
                let id = nextChunkId
                nextChunkId &+= 1
                let nativeBuf = createNativeStagingBuffer(size: allocSize)
                chunk = Chunk(id: id, size: allocSize, wgpuBuffer: nativeBuf)
            }
            active.append(chunk)
            index = active.count - 1
        }

        let chunk = active[index]
        let at = alignUp(chunk.used, to: align)
        chunk.used = at + size
        fill(chunk, at)
        pendingBytes += size
        currentStats.writes += 1
        currentStats.bytes += size
        busy = true
        return (chunk, at)
    }

    private func createNativeStagingBuffer(size: UInt64) -> WGPUBuffer? {
        #if os(Linux) || os(Android)
        guard hasLiveNativeWgpu, let dev = device else { return nil }
        var desc = WGPUBufferDescriptor()
        desc.label = WGPUStringView(data: nil, length: 0)
        desc.size = size
        desc.usage = WGPUBufferUsage_MapWrite | WGPUBufferUsage_CopySrc
        desc.mappedAtCreation = 1
        return wgpuDeviceCreateBuffer(dev, &desc)
        #else
        return nil
        #endif
    }

    private func receiveLocked() {
        if !flushedAwaitingRecall.isEmpty {
            recallFlushedLocked()
        }
        #if os(Linux) || os(Android)
        if hasLiveNativeWgpu, let dev = device {
            _ = wgpuDevicePoll(dev, 0, nil)
        }
        #endif
        while let chunk = returned.popLast() {
            recycleChunkLocked(chunk)
        }
    }

    private func recycleChunkLocked(_ chunk: Chunk) {
        chunk.used = 0
        let kept = free.reduce(UInt64(0)) { $0 + $1.size }
        if chunk.size <= keepChunkMax && free.count < keepChunks && kept + chunk.size <= keepBytes {
            free.append(chunk)
        }
    }

    private func encodeRawLocked(encoder: WGPUCommandEncoder) {
        copyToRawLocked(encoder: encoder, applyHostTracking: true)
        let drained = active
        active.removeAll(keepingCapacity: true)
        for chunk in drained {
            chunk.unmap()
            if chunk.wgpuBuffer != nil {
                flushedAwaitingRecall.append(chunk)
            } else {
                returned.append(chunk)
            }
        }
        busy = false
    }

    private func encodeManagedLocked(encoder: StagingCommandEncoder) {
        let commands = copyToManagedLocked(encoder: encoder)
        let drained = active
        active.removeAll(keepingCapacity: true)
        for chunk in drained {
            chunk.unmap()
        }
        busy = false

        encoder.addReturnHandler { [weak self] submitted in
            guard let self else { return }
            if submitted {
                self.stateLock.withLock {
                    for cmd in commands {
                        self.applyTrackedCommandLocked(cmd)
                    }
                    for chunk in drained {
                        if chunk.wgpuBuffer != nil {
                            self.mapNativeChunkForReuseLocked(chunk)
                        } else {
                            self.returned.append(chunk)
                        }
                    }
                }
            } else {
                self.addLost(UInt64(drained.count))
            }
        }
    }

    private func recallFlushedLocked() {
        guard !flushedAwaitingRecall.isEmpty else { return }
        let chunks = flushedAwaitingRecall
        flushedAwaitingRecall.removeAll(keepingCapacity: true)
        for chunk in chunks {
            if chunk.wgpuBuffer != nil {
                mapNativeChunkForReuseLocked(chunk)
            } else {
                returned.append(chunk)
            }
        }
    }

    private func mapNativeChunkForReuseLocked(_ chunk: Chunk) {
        #if os(Linux) || os(Android)
        if let buf = chunk.wgpuBuffer {
            // PORT NOTE: MapReturnContext transfers ownership of `Chunk` across CWebGPU's C callback boundary and increments `lost` if dropped or aborted.
            final class MapReturnContext: @unchecked Sendable {
                var chunk: Chunk?
                weak var owner: StagingCore?
                init(chunk: Chunk, owner: StagingCore) {
                    self.chunk = chunk
                    self.owner = owner
                }
                deinit {
                    if chunk != nil {
                        owner?.addLost(1)
                    }
                }
            }
            let ctx = MapReturnContext(chunk: chunk, owner: self)
            let unmanaged = Unmanaged.passRetained(ctx)
            var cbInfo = WGPUBufferMapCallbackInfo()
            cbInfo.mode = WGPUCallbackMode_AllowProcessEvents
            cbInfo.userdata1 = unmanaged.toOpaque()
            cbInfo.callback = { status, _, u1, _ in
                guard let u1 else { return }
                let context = Unmanaged<MapReturnContext>.fromOpaque(u1).takeRetainedValue()
                if status == WGPUMapAsyncStatus_Success, let reclaimed = context.chunk {
                    context.chunk = nil
                    if let owner = context.owner {
                        owner.stateLock.withLock {
                            owner.returned.append(reclaimed)
                        }
                    }
                }
            }
            _ = wgpuBufferMapAsync(buf, WGPUMapMode_Write, 0, Int(chunk.size), cbInfo)
            return
        }
        #endif
        returned.append(chunk)
    }

    private func copyToRawLocked(encoder: WGPUCommandEncoder, applyHostTracking: Bool) {
        let items = pending
        pending.removeAll(keepingCapacity: true)
        pendingBytes = 0

        let liveEncoder: Bool = {
            #if os(Linux) || os(Android)
            return hasLiveNativeWgpu && encoder != OpaquePointer(bitPattern: 1)
            #else
            return false
            #endif
        }()

        for p in items {
            switch p.dst {
            case let .buffer(dstBuffer, dstOffset, rawLength):
                #if os(Linux) || os(Android)
                if liveEncoder, let srcBuf = p.src.wgpuBuffer, dstBuffer != OpaquePointer(bitPattern: 1) {
                    wgpuCommandEncoderCopyBufferToBuffer(encoder, srcBuf, p.offset, dstBuffer, dstOffset, p.size)
                }
                #endif
                if applyHostTracking && p.src.wgpuBuffer == nil {
                    let bytes = p.src.sliceBytes(offset: p.offset, size: UInt64(rawLength))
                    applyTrackedBufferWrite(handleBits: UInt(bitPattern: dstBuffer), offset: dstOffset, data: bytes)
                }

            case let .rows(texture, width, bytesPerPixel, y, rows, bytesPerRow):
                #if os(Linux) || os(Android)
                if liveEncoder, let srcBuf = p.src.wgpuBuffer, texture != OpaquePointer(bitPattern: 1) {
                    var srcCopy = WGPUTexelCopyBufferInfo()
                    srcCopy.buffer = srcBuf
                    srcCopy.layout = WGPUTexelCopyBufferLayout(
                        offset: p.offset,
                        bytesPerRow: bytesPerRow,
                        rowsPerImage: WGPU_COPY_STRIDE_UNDEFINED
                    )

                    var dstCopy = WGPUTexelCopyTextureInfo()
                    dstCopy.texture = texture
                    dstCopy.mipLevel = 0
                    dstCopy.origin = WGPUOrigin3D(x: 0, y: y, z: 0)
                    dstCopy.aspect = WGPUTextureAspect_All

                    var extent = WGPUExtent3D(width: width, height: rows, depthOrArrayLayers: 1)
                    wgpuCommandEncoderCopyBufferToTexture(encoder, &srcCopy, &dstCopy, &extent)
                }
                #endif
                if applyHostTracking && p.src.wgpuBuffer == nil {
                    let data = p.src.sliceBytes(offset: p.offset, size: p.size)
                    applyTrackedTextureRowsWrite(
                        handleBits: UInt(bitPattern: texture),
                        width: width,
                        bytesPerPixel: bytesPerPixel,
                        y: y,
                        rows: rows,
                        bytesPerRow: bytesPerRow,
                        paddedData: data
                    )
                }
            }
        }
    }

    private func copyToManagedLocked(encoder: StagingCommandEncoder) -> [StagedCopyCommand] {
        if let raw = encoder.rawEncoder {
            let snapshot = buildCommandsFromPendingLocked()
            copyToRawLocked(encoder: raw, applyHostTracking: false)
            for cmd in snapshot {
                encoder.appendCopy(cmd)
            }
            return snapshot
        }

        let snapshot = buildCommandsFromPendingLocked()
        pending.removeAll(keepingCapacity: true)
        pendingBytes = 0
        for cmd in snapshot {
            encoder.appendCopy(cmd)
        }
        return snapshot
    }

    private func buildCommandsFromPendingLocked() -> [StagedCopyCommand] {
        var commands: [StagedCopyCommand] = []
        commands.reserveCapacity(pending.count)
        for p in pending {
            switch p.dst {
            case let .buffer(dstBuffer, dstOffset, rawLength):
                let data = p.src.sliceBytes(offset: p.offset, size: UInt64(rawLength))
                commands.append(
                    StagedCopyCommand(
                        data: data,
                        size: p.size,
                        destination: .buffer(handleBits: UInt(bitPattern: dstBuffer), offset: dstOffset)
                    )
                )
            case let .rows(texture, width, bytesPerPixel, y, rows, bytesPerRow):
                let data = p.src.sliceBytes(offset: p.offset, size: p.size)
                commands.append(
                    StagedCopyCommand(
                        data: data,
                        size: p.size,
                        destination: .textureRows(
                            handleBits: UInt(bitPattern: texture),
                            width: width,
                            bytesPerPixel: bytesPerPixel,
                            y: y,
                            rows: rows,
                            bytesPerRow: bytesPerRow
                        )
                    )
                )
            }
        }
        return commands
    }

    private func submitLocked() {
        guard !pending.isEmpty else { return }

        #if os(Linux) || os(Android)
        if hasLiveNativeWgpu, let dev = device, let q = queue, q != OpaquePointer(bitPattern: 1) {
            var encDesc = WGPUCommandEncoderDescriptor()
            encDesc.label = WGPUStringView(data: nil, length: 0)
            if let encoder = wgpuDeviceCreateCommandEncoder(dev, &encDesc) {
                encodeRawLocked(encoder: encoder)
                var cmdDesc = WGPUCommandBufferDescriptor()
                cmdDesc.label = WGPUStringView(data: nil, length: 0)
                if let cmdBuffer = wgpuCommandEncoderFinish(encoder, &cmdDesc) {
                    var cmds: [WGPUCommandBuffer?] = [cmdBuffer]
                    wgpuQueueSubmit(q, 1, &cmds)
                    wgpuCommandBufferRelease(cmdBuffer)
                }
                wgpuCommandEncoderRelease(encoder)
                recallFlushedLocked()
                currentStats.submits += 1
                return
            }
        }
        #endif

        let commands = buildCommandsFromPendingLocked()
        pending.removeAll(keepingCapacity: true)
        pendingBytes = 0
        for cmd in commands {
            applyTrackedCommandLocked(cmd)
        }
        let drained = active
        active.removeAll(keepingCapacity: true)
        for chunk in drained {
            chunk.unmap()
            returned.append(chunk)
        }
        busy = false
        currentStats.submits += 1
    }

    private func applyTrackedCommandLocked(_ command: StagedCopyCommand) {
        switch command.destination {
        case let .buffer(handleBits, offset):
            applyTrackedBufferWrite(handleBits: handleBits, offset: offset, data: command.data)
        case let .textureRows(handleBits, width, bytesPerPixel, y, rows, bytesPerRow):
            applyTrackedTextureRowsWrite(
                handleBits: handleBits,
                width: width,
                bytesPerPixel: bytesPerPixel,
                y: y,
                rows: rows,
                bytesPerRow: bytesPerRow,
                paddedData: command.data
            )
        }
    }

    private func applyTrackedBufferWrite(handleBits: UInt, offset: UInt64, data: [UInt8]) {
        guard !data.isEmpty else { return }
        let start = Int(offset)
        let needed = start + data.count
        var buf = trackedBuffers[handleBits] ?? []
        if buf.count < needed {
            buf.append(contentsOf: repeatElement(0, count: needed - buf.count))
        }
        buf.replaceSubrange(start..<needed, with: data)
        trackedBuffers[handleBits] = buf
    }

    private func applyTrackedTextureRowsWrite(
        handleBits: UInt,
        width: UInt32,
        bytesPerPixel: UInt32,
        y: UInt32,
        rows: UInt32,
        bytesPerRow: UInt32,
        paddedData: [UInt8]
    ) {
        let unpaddedRowBytes = Int(width &* bytesPerPixel)
        let strideBytes = Int(bytesPerRow)
        guard unpaddedRowBytes > 0, strideBytes >= unpaddedRowBytes else { return }
        var texRows = trackedTextures[handleBits] ?? [:]
        for r in 0..<Int(rows) {
            let srcStart = r * strideBytes
            let srcEnd = srcStart + unpaddedRowBytes
            if srcEnd <= paddedData.count {
                texRows[y &+ UInt32(r)] = Array(paddedData[srcStart..<srcEnd])
            }
        }
        trackedTextures[handleBits] = texRows
    }
}

// MARK: - Staging & UploadBelt

/// Per-frame GPU upload belt Alias (`UploadBelt` == `Staging`).
public typealias UploadBelt = Staging

/// A shared handle to one set of staging chunks and the writes pending in them: the chunks,
/// the count of lost ones, and whether any are pending or mapped (so `flush` and `submit` with
/// nothing to do never lock).
public struct Staging: Sendable {
    private let core: StagingCore

    public init(_ device: WGPUDevice, _ queue: WGPUQueue, direct: Direct? = nil) {
        self.core = StagingCore(device: device, queue: queue, direct: direct)
    }

    public init(device: WGPUDevice? = nil, queue: WGPUQueue? = nil, direct: Direct? = nil) {
        self.core = StagingCore(device: device, queue: queue, direct: direct)
    }

    public static func new(_ device: WGPUDevice, _ queue: WGPUQueue) -> Staging {
        Staging(device, queue)
    }

    /// Creates a pure-Swift headless staging instance for tests or non-WebGPU backends.
    public static func headless(direct: Direct? = nil) -> Staging {
        Staging(device: nil, queue: nil, direct: direct)
    }

    public func clone() -> Staging {
        self
    }

    /// Associates width and format metadata with an opaque `WGPUTexture` handle for `writeTextureRows(_:_:_:)`.
    public func registerTexture(
        _ texture: WGPUTexture,
        width: UInt32,
        height: UInt32 = 1,
        format: WGPUTextureFormat = WGPUTextureFormat_RGBA8Unorm
    ) {
        let bpp = textureFormatBlockCopySize(format) ?? 4
        core.registerTexture(texture, width: width, height: height, bytesPerPixel: bpp)
    }

    public func unregisterTexture(_ texture: WGPUTexture) {
        core.unregisterTexture(texture)
    }

    /// Stages a write of `data` to `buffer` at `offset`. Both are multiples of 4.
    public func writeBuffer(_ buffer: WGPUBuffer, _ offset: UInt64, _ data: [UInt8]) {
        guard !data.isEmpty else { return }
        data.withUnsafeBytes { rawBuf in
            core.writeBuffer(buffer, offset: offset, bytes: rawBuf)
        }
    }

    /// Stages a write of raw `data` bytes to `buffer` at `offset`.
    public func writeBuffer(_ buffer: WGPUBuffer, _ offset: UInt64, _ data: UnsafeRawBufferPointer) {
        guard !data.isEmpty else { return }
        core.writeBuffer(buffer, offset: offset, bytes: data)
    }

    /// Stages a write of full-width rows of a registered `texture` from row `y`.
    public func writeTextureRows(_ texture: WGPUTexture, _ y: UInt32, _ rows: [UInt8]) {
        guard let meta = core.lookupTexture(texture) else {
            preconditionFailure("Texture metadata not registered; use StagingTexture or registerTexture(_:width:height:format:)")
        }
        rows.withUnsafeBytes { rawBuf in
            core.writeTextureRows(texture, width: meta.width, bytesPerPixel: meta.bytesPerPixel, y: y, rows: rawBuf)
        }
    }

    /// Stages a write of full-width rows of `texture` from row `y`. `rows` holds them tightly
    /// packed; its length is a whole number of rows.
    public func writeTextureRows(_ texture: StagingTexture, _ y: UInt32, _ rows: [UInt8]) {
        guard let bpp = textureFormatBlockCopySize(texture.format) else {
            preconditionFailure("a color format")
        }
        rows.withUnsafeBytes { rawBuf in
            core.writeTextureRows(texture.handle, width: texture.width, bytesPerPixel: bpp, y: y, rows: rawBuf)
        }
    }

    /// Stages a write of full-width rows of `texture` with explicit `width` and `format` from row `y`.
    public func writeTextureRows(
        _ texture: WGPUTexture,
        width: UInt32,
        format: WGPUTextureFormat,
        _ y: UInt32,
        _ rows: [UInt8]
    ) {
        guard let bpp = textureFormatBlockCopySize(format) else {
            preconditionFailure("a color format")
        }
        rows.withUnsafeBytes { rawBuf in
            core.writeTextureRows(texture, width: width, bytesPerPixel: bpp, y: y, rows: rawBuf)
        }
    }

    /// Stages a write of full-width rows of `texture` with explicit `width` and `bytesPerPixel` from row `y`.
    public func writeTextureRows(
        _ texture: WGPUTexture,
        width: UInt32,
        bytesPerPixel: UInt32,
        _ y: UInt32,
        _ rows: [UInt8]
    ) {
        rows.withUnsafeBytes { rawBuf in
            core.writeTextureRows(texture, width: width, bytesPerPixel: bytesPerPixel, y: y, rows: rawBuf)
        }
    }

    /// Records the pending writes into `encoder` here, ahead of what is recorded after them.
    /// `encoder` must be submitted: dropped, the writes never land (`lost` counts it).
    public func flush(_ encoder: WGPUCommandEncoder) {
        core.flush(rawEncoder: encoder)
    }

    /// Records the pending writes into a managed `StagingCommandEncoder` whose drop automatically
    /// increments `lost` if never submitted.
    public func flush(_ encoder: StagingCommandEncoder) {
        core.flush(stagingEncoder: encoder)
    }

    /// Records the pending copies into `encoder` but leaves their chunks mapped, so later writes
    /// share them: one chunk unmapped and remapped per frame instead of one per write.
    public func record(_ encoder: WGPUCommandEncoder) {
        core.record(rawEncoder: encoder)
    }

    /// Records the pending copies into a managed `StagingCommandEncoder` while keeping chunks mapped.
    public func record(_ encoder: StagingCommandEncoder) {
        core.record(stagingEncoder: encoder)
    }

    /// Submits the pending writes now, ahead of anything submitted later.
    public func submit() {
        core.submit()
    }

    /// Re-maps chunks unmapped by `flush(_ encoder: WGPUCommandEncoder)` once the caller has submitted its encoder.
    public func recall() {
        core.recall()
    }

    /// Marks `count` flushed chunks as lost when a raw `WGPUCommandEncoder` is dropped without submission.
    public func markEncoderDropped(_ count: UInt64 = 1) {
        core.addLost(count)
    }

    /// Whether writes are pending or chunks still mapped since the last `flush` or `submit`.
    public func busy() -> Bool {
        core.busy
    }

    /// Whether writes are waiting for a `flush` or `submit`.
    public func isPending() -> Bool {
        core.isPending()
    }

    /// Chunks whose writes may never have landed because their encoder was dropped unsubmitted.
    /// A caller that skips writes matching what it last wrote resends everything when it grows.
    public func lost() -> UInt64 {
        core.lost
    }

    public func stats() -> Stats {
        core.stats()
    }

    /// Reads back tracked host mirror bytes for `buffer` in headless / non-WebGPU mode.
    public func readTrackedBuffer(_ buffer: WGPUBuffer, offset: UInt64 = 0, size: Int? = nil) -> [UInt8] {
        core.readTrackedBuffer(buffer, offset: offset, size: size)
    }

    /// Reads back tracked host mirror bytes for row `y` of `texture` in headless / non-WebGPU mode.
    public func readTrackedTextureRow(_ texture: WGPUTexture, y: UInt32) -> [UInt8]? {
        core.readTrackedTextureRow(texture, y: y)
    }
}
