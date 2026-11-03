// Ported from: crates/rune/src/gpu/metal/device.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `MetalShared` and `MetalDevice`: wraps an `MTLDevice`, `MTLCommandQueue`, `MTLSharedEvent`,
//! live buffer counter, and submission state (`State`).

#if canImport(Metal)
import Metal
#endif
#if !os(WASI)
import Foundation
#endif
import CWebGPU

/// Reusable retain list keeping GPU resources alive until the `MTLCommandBuffer` using them signals completion.
// PORT NOTE: Reference-counted keep list recycled under `MetalShared.lock`, mirroring `Keep = Vec<Arc<dyn Any + Send + Sync>>` in `submit.rs`.
public final class MetalKeepList: @unchecked Sendable {
    var items: [AnyObject] = []
    var rawBufferReleases: [(MetalBufferStore, MetalRawBuffer)] = []

    public init() {
        items.reserveCapacity(32)
    }

    public func keep(_ obj: AnyObject) {
        items.append(obj)
    }

    public func keepRawBuffer(store: MetalBufferStore, raw: MetalRawBuffer) {
        items.append(raw)
        rawBufferReleases.append((store, raw))
    }

    public func releaseAll(submittedAt: UInt64?) {
        for (store, raw) in rawBufferReleases {
            store.releaseRecorded(raw, submittedAt: submittedAt)
        }
        rawBufferReleases.removeAll(keepingCapacity: true)
        items.removeAll(keepingCapacity: true)
    }
}

public enum MetalPollType: Sendable {
    case poll
    case wait(submissionIndex: UInt64?, timeoutMs: UInt64?)

    public static func waitIndefinitely() -> MetalPollType {
        .wait(submissionIndex: nil, timeoutMs: nil)
    }
}

public enum MetalPollStatus: Sendable, Equatable {
    case queueEmpty
    case poll
    case waitSucceeded
}

public enum MetalPollError: Error, Sendable, Equatable {
    case wrongSubmissionIndex(UInt64, UInt64)
    case timeout
}

enum MetalPendingCallback {
    case map(@Sendable (Result<Void, any Error>) -> Void)
    case workDone(@Sendable () -> Void)
}

/// Shared state between `MetalDevice`, `MetalQueue`, encoders, and resources.
// PORT NOTE: Synchronized via `lock` (`LiveLock`) and `MTLSharedEvent` monotonic signaling, matching `Shared` in `device.rs` and `submit.rs`.
public final class MetalShared: @unchecked Sendable {
    public static let inFlightLimit = 2
    public static let maxSpareKeeps = 8

    #if canImport(Metal)
    public let mtlDevice: (any MTLDevice)?
    public let mtlQueue: (any MTLCommandQueue)?
    public let sharedEvent: (any MTLSharedEvent)?
    #endif

    let lock = LiveLock()
    private let counterLock = LiveLock()
    private var liveBufferCounter: Int = 0
    private var recordingEncodersCount: Int = 0

    // Submission state (`submit.rs` `State`)
    public internal(set) var lastSubmission: UInt64 = 0
    #if canImport(Metal)
    var heldCommandBuffer: ((any MTLCommandBuffer), UInt64)? = nil
    var pendingUploadCmdBuf: (any MTLCommandBuffer)? = nil
    var pendingUploadBlit: (any MTLBlitCommandEncoder)? = nil
    #endif
    var pendingUploadKeep: MetalKeepList? = nil
    var pendingHostUploads: [@Sendable () -> Void] = []
    var retireQueue: [(UInt64, MetalKeepList)] = []
    var callbackQueue: [(UInt64, MetalPendingCallback)] = []
    var frameValues: [UInt64] = []
    var spareKeeps: [MetalKeepList] = []

    #if canImport(Metal)
    public init(mtlDevice: (any MTLDevice)?) {
        self.mtlDevice = mtlDevice
        self.mtlQueue = mtlDevice?.makeCommandQueue()
        self.sharedEvent = mtlDevice?.makeSharedEvent()
    }
    #else
    public init() {}
    #endif

    deinit {
        #if canImport(Metal)
        let target: UInt64 = lock.withLock {
            flushHeldLocked()
            commitUploadsLocked()
            return lastSubmission
        }
        if let ev = sharedEvent, ev.signaledValue < target {
            _ = ev.wait(untilSignaledValue: target, timeoutMS: 10_000)
        }
        #endif
    }

    public var liveBuffers: Int {
        counterLock.withLock { liveBufferCounter }
    }

    func incrementLiveBuffers() {
        counterLock.withLock { liveBufferCounter += 1 }
    }

    func decrementLiveBuffers() {
        counterLock.withLock { liveBufferCounter -= 1 }
    }

    func incrementRecording() {
        counterLock.withLock { recordingEncodersCount += 1 }
    }

    func decrementRecording() {
        counterLock.withLock { recordingEncodersCount = max(0, recordingEncodersCount - 1) }
    }

    var isRecordingAny: Bool {
        counterLock.withLock { recordingEncodersCount > 0 }
    }

    public var completedSubmission: UInt64 {
        #if canImport(Metal)
        if let ev = sharedEvent {
            return ev.signaledValue
        }
        #endif
        return lock.withLock { lastSubmission }
    }

    public var spareKeepIdentifiers: [ObjectIdentifier] {
        lock.withLock { spareKeeps.map { ObjectIdentifier($0) } }
    }

    func takeKeepList() -> MetalKeepList {
        lock.withLock {
            spareKeeps.popLast() ?? MetalKeepList()
        }
    }

    func recycleKeepList(_ keep: MetalKeepList, submittedAt: UInt64?) {
        keep.releaseAll(submittedAt: submittedAt)
        lock.withLock {
            if spareKeeps.count < Self.maxSpareKeeps {
                spareKeeps.append(keep)
            }
        }
    }

    #if canImport(Metal)
    public func makeUnretainedCommandBuffer() -> (any MTLCommandBuffer)? {
        mtlQueue?.makeCommandBufferWithUnretainedReferences()
    }

    @discardableResult
    func stampLocked(_ cb: any MTLCommandBuffer, keep: MetalKeepList?) -> UInt64 {
        lastSubmission &+= 1
        let val = lastSubmission
        if let ev = sharedEvent {
            cb.encodeSignalEvent(ev, value: val)
        }
        if let keep {
            // Update submittedAt on any raw buffers immediately so `Store` knows `lastSubmitted`,
            // while holding strong object references in `retireQueue` until GPU completion!
            for (store, raw) in keep.rawBufferReleases {
                store.releaseRecorded(raw, submittedAt: val)
            }
            keep.rawBufferReleases.removeAll(keepingCapacity: true)
            retireQueue.append((val, keep))
        }
        return val
    }

    func flushHeldLocked() {
        if let (cb, _) = heldCommandBuffer {
            heldCommandBuffer = nil
            cb.commit()
        }
    }

    func commitUploadsLocked() {
        guard let cb = pendingUploadCmdBuf, let blit = pendingUploadBlit else { return }
        pendingUploadCmdBuf = nil
        pendingUploadBlit = nil
        let keep = pendingUploadKeep
        pendingUploadKeep = nil
        blit.endEncoding()
        _ = stampLocked(cb, keep: keep)
        cb.commit()
    }

    func enqueueBlitUpload(keepObjects: [AnyObject], _ encode: (any MTLBlitCommandEncoder) -> Void) {
        lock.withLock {
            if pendingUploadBlit == nil {
                guard let cb = makeUnretainedCommandBuffer(),
                      let blit = cb.makeBlitCommandEncoder()
                else { return }
                pendingUploadCmdBuf = cb
                pendingUploadBlit = blit
                pendingUploadKeep = MetalKeepList()
            }
            if let blit = pendingUploadBlit {
                encode(blit)
            }
            if let keep = pendingUploadKeep {
                for obj in keepObjects {
                    keep.keep(obj)
                }
            }
        }
    }
    #endif

    func enqueueHostUpload(_ op: @escaping @Sendable () -> Void) {
        lock.withLock {
            pendingHostUploads.append(op)
        }
    }

    func commitHostUploadsLocked() {
        guard !pendingHostUploads.isEmpty else { return }
        lastSubmission &+= 1
        let val = lastSubmission
        let ops = pendingHostUploads
        pendingHostUploads.removeAll(keepingCapacity: true)
        for op in ops { op() }
        #if canImport(Metal)
        if let ev = sharedEvent {
            if let signalCb = makeUnretainedCommandBuffer() {
                signalCb.encodeSignalEvent(ev, value: val)
                signalCb.commit()
            } else {
                ev.signaledValue = val
            }
        }
        #endif
    }

    func enqueueCallback(_ cb: MetalPendingCallback) {
        lock.withLock {
            callbackQueue.append((lastSubmission, cb))
        }
    }

    @discardableResult
    public func retire() -> UInt64 {
        let done = completedSubmission
        while true {
            let next: MetalKeepList? = lock.withLock {
                if let first = retireQueue.first, first.0 <= done {
                    return retireQueue.removeFirst().1
                }
                return nil
            }
            guard let keep = next else { break }
            recycleKeepList(keep, submittedAt: nil)
        }
        while true {
            let nextCb: MetalPendingCallback? = lock.withLock {
                if let first = callbackQueue.first, first.0 <= done {
                    return callbackQueue.removeFirst().1
                }
                return nil
            }
            guard let cb = nextCb else { break }
            switch cb {
            case .map(let f): f(.success(()))
            case .workDone(let f): f()
            }
        }
        return done
    }

    public func poll(_ mode: MetalPollType = .poll) -> Result<MetalPollStatus, MetalPollError> {
        switch mode {
        case .poll:
            let done = retire()
            let idle: Bool = lock.withLock {
                done >= lastSubmission && callbackQueue.isEmpty
            }
            return .success(idle ? .queueEmpty : .poll)

        case .wait(let submissionIndex, let timeoutMs):
            let last: UInt64 = lock.withLock {
                #if canImport(Metal)
                flushHeldLocked()
                #endif
                return lastSubmission
            }
            let target = submissionIndex ?? last
            if target > last {
                return .failure(.wrongSubmissionIndex(target, last))
            }
            #if canImport(Metal)
            if let ev = sharedEvent, ev.signaledValue < target {
                let ms = timeoutMs ?? UInt64.max
                if !ev.wait(untilSignaledValue: target, timeoutMS: ms) {
                    return .failure(.timeout)
                }
            }
            #endif
            _ = retire()
            return .success(target == last ? .queueEmpty : .waitSucceeded)
        }
    }

    public func pace() {
        let oldest: UInt64? = lock.withLock {
            guard frameValues.count >= Self.inFlightLimit else { return nil }
            return frameValues.removeFirst()
        }
        #if canImport(Metal)
        if let at = oldest, let ev = sharedEvent, ev.signaledValue < at {
            _ = ev.wait(untilSignaledValue: at, timeoutMS: 1000)
        }
        #else
        _ = oldest
        #endif
    }
}

/// Supported MSL version tuple `(major, minor)`.
public func metalMslVersion() -> (UInt8, UInt8) {
    (3, 0)
}

/// Logical device in Rune's Metal backend (`gpu/metal/device.rs`).
public final class MetalDevice: Sendable {
    public let shared: MetalShared
    public let timestampQueryEnabled: Bool
    public let maxImmediateSize: UInt32

    public init(shared: MetalShared, timestampQueryEnabled: Bool = false, maxImmediateSize: UInt32 = 0) {
        self.shared = shared
        self.timestampQueryEnabled = timestampQueryEnabled
        self.maxImmediateSize = maxImmediateSize
    }

    public var liveBufferCount: Int {
        shared.liveBuffers
    }

    public var lastSubmissionIndex: UInt64 {
        shared.lock.withLock { shared.lastSubmission }
    }

    public func createBuffer(label: String? = nil, size: Int, contents: [UInt8]? = nil) -> MetalBuffer {
        let buf = MetalBuffer(shared: shared, size: size, label: label)
        if let contents, !contents.isEmpty {
            contents.withUnsafeBytes { raw in
                _ = buf.store.writeInPlace(offset: 0, bytes: raw, completedSubmission: shared.completedSubmission)
            }
        }
        return buf
    }

    public func createTexture(
        label: String? = nil,
        format: WGPUTextureFormat,
        width: UInt32,
        height: UInt32,
        arrayLayers: UInt32 = 1,
        mipLevelCount: UInt32 = 1,
        usage: UInt32 = 0
    ) -> MetalTexture {
        MetalTexture(
            shared: shared,
            label: label,
            format: format,
            width: width,
            height: height,
            arrayLayers: arrayLayers,
            mipLevelCount: mipLevelCount,
            usage: usage
        )
    }

    public func createSampler(linear: Bool = false) -> MetalSampler {
        MetalSampler(shared: shared, linear: linear)
    }

    public func createShaderModule(label: String? = nil, wgsl: String) -> MetalShaderModule {
        MetalShaderModule(shared: shared, label: label, wgsl: wgsl)
    }

    public func createShaderModulePassthrough(
        label: String? = nil,
        metallib: [UInt8],
        entryPoints: [String]
    ) -> MetalShaderModule {
        MetalShaderModule(shared: shared, label: label, metallibBytes: metallib, entryPoints: entryPoints)
    }

    public func createBindGroupLayout(label: String? = nil, entries: [MetalBindGroupLayoutEntry]) -> MetalBindGroupLayout {
        MetalBindGroupLayout(label: label, entries: entries)
    }

    public func createPipelineLayout(
        label: String? = nil,
        bindGroupLayouts: [MetalBindGroupLayout?],
        immediateSize: UInt32 = 0
    ) -> MetalPipelineLayout {
        MetalPipelineLayout(label: label, bindGroupLayouts: bindGroupLayouts, immediateSize: immediateSize)
    }

    public func createBindGroup(
        label: String? = nil,
        layout: MetalBindGroupLayout,
        entries: [MetalBindGroupEntry]
    ) -> MetalBindGroup {
        MetalBindGroup(label: label, layout: layout, entries: entries)
    }

    public func createRenderPipeline(_ descriptor: MetalRenderPipelineDescriptor) throws -> MetalRenderPipeline {
        try MetalRenderPipeline(device: self, descriptor: descriptor)
    }

    public func createComputePipeline(_ descriptor: MetalComputePipelineDescriptor) throws -> MetalComputePipeline {
        try MetalComputePipeline(device: self, descriptor: descriptor)
    }

    public func createQuerySet(count: Int) -> MetalQuerySet {
        MetalQuerySet(shared: shared, count: count)
    }

    public func createCommandEncoder(label: String? = nil) -> MetalCommandEncoder {
        MetalCommandEncoder(shared: shared, label: label)
    }

    @discardableResult
    public func poll(_ mode: MetalPollType = .poll) -> Result<MetalPollStatus, MetalPollError> {
        shared.poll(mode)
    }
}
