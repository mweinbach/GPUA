// Ported from: crates/rune/src/render/upload.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Per-frame uploads: instances, globals, glyph and image atlas rows, and GPU spring nodes.
//!
//! Writes go through the renderer's `MetalStaging`, so a steady frame allocates no buffers. They
//! are recorded into the frame's encoder where the renderer first uses it (`flushUploads`), or
//! submitted ahead of a draw into a caller's pass (`drawRange*`) and of `Renderer.submit`.

import CWebGPU
import RuneStaging

/// Byte size of one `Instance` (`8 × vec4 = 128` bytes).
public let INSTANCE_BYTE_SIZE: Int = 128

/// Packs one `Instance` into 32 little-endian `UInt32` words matching `#[repr(C)] Instance`.
@inline(__always)
func instanceWords(_ i: Instance) -> [UInt32] {
    [
        i.rect[0].bitPattern, i.rect[1].bitPattern, i.rect[2].bitPattern, i.rect[3].bitPattern,
        i.radii[0].bitPattern, i.radii[1].bitPattern, i.radii[2].bitPattern, i.radii[3].bitPattern,
        i.fill[0].bitPattern, i.fill[1].bitPattern, i.fill[2].bitPattern, i.fill[3].bitPattern,
        i.border[0].bitPattern, i.border[1].bitPattern, i.border[2].bitPattern, i.border[3].bitPattern,
        i.params[0].bitPattern, i.params[1].bitPattern, i.params[2].bitPattern, i.params[3].bitPattern,
        i.uv[0].bitPattern, i.uv[1].bitPattern, i.uv[2].bitPattern, i.uv[3].bitPattern,
        i.clip[0].bitPattern, i.clip[1].bitPattern, i.clip[2].bitPattern, i.clip[3].bitPattern,
        i.fade[0], i.fade[1], i.fade[2], i.fade[3],
    ]
}

func instanceBytes(_ i: Instance) -> [UInt8] {
    var words = instanceWords(i).map { $0.littleEndian }
    return words.withUnsafeMutableBufferPointer { buf in
        Array(UnsafeRawBufferPointer(buf))
    }
}

func instancesSliceBytes(_ slice: ArraySlice<Instance>) -> [UInt8] {
    if slice.isEmpty { return [] }
    var words = [UInt32]()
    words.reserveCapacity(slice.count * 32)
    for inst in slice {
        words.append(contentsOf: instanceWords(inst).map { $0.littleEndian })
    }
    return words.withUnsafeBufferPointer { buf in
        Array(UnsafeRawBufferPointer(buf))
    }
}

func floatsBytes(_ values: [Float]) -> [UInt8] {
    var words = values.map { $0.bitPattern.littleEndian }
    return words.withUnsafeMutableBufferPointer { buf in
        Array(UnsafeRawBufferPointer(buf))
    }
}

// MARK: - MetalStaging

private enum StagedCopy {
    case buffer(
        chunk: MetalBuffer,
        srcOffset: UInt64,
        dst: MetalBuffer,
        dstOffset: UInt64,
        size: UInt64
    )
    case texture(
        chunk: MetalBuffer,
        srcOffset: UInt64,
        bytesPerRow: UInt32,
        rows: UInt32,
        dst: MetalTexture,
        y0: UInt32
    )
}

/// Native Metal staging uploader implementing `rune_staging::Staging` semantics over `MetalBuffer` chunks.
// PORT NOTE: Synchronized with `LiveLock` so completion/drop callbacks can return chunks from any thread.
final class MetalStaging: @unchecked Sendable {
    private let device: MetalDevice
    private let queue: MetalQueue
    private let allowDirect: Bool
    private let lock = LiveLock()

    private var freeChunks: [MetalBuffer] = []
    private var freeBytes: UInt64 = 0
    private var activeChunk: MetalBuffer? = nil
    private var activeOffset: UInt64 = 0
    private var sealedInCycle: [MetalBuffer] = []
    private var pendingBytes: UInt64 = 0
    private var unrecordedCopies: [StagedCopy] = []
    private var recordedInCycle: Bool = false
    private var hookInstalledForCycle: Bool = false
    private var statsValue = RuneStaging.Stats()
    private var lostCount: UInt64 = 0

    init(device: MetalDevice, queue: MetalQueue, allowDirect: Bool = true) {
        self.device = device
        self.queue = queue
        self.allowDirect = allowDirect
    }

    func stats() -> RuneStaging.Stats {
        lock.withLock { statsValue }
    }

    func lost() -> UInt64 {
        lock.withLock { lostCount }
    }

    func busy() -> Bool {
        lock.withLock {
            !unrecordedCopies.isEmpty || recordedInCycle || !sealedInCycle.isEmpty || activeChunk != nil
        }
    }

    private func allocLocked(size: UInt64, align: UInt64) -> (MetalBuffer, UInt64) {
        if let chunk = activeChunk {
            let aligned = RuneStaging.alignUp(activeOffset, to: align)
            if aligned + size <= UInt64(chunk.size) {
                activeOffset = aligned + size
                return (chunk, aligned)
            }
            sealedInCycle.append(chunk)
            activeChunk = nil
            activeOffset = 0
        }

        let needed = max(RuneStaging.chunkSize, RuneStaging.nextPowerOfTwo(size))
        if let idx = freeChunks.firstIndex(where: { UInt64($0.size) >= needed }) {
            let reused = freeChunks.remove(at: idx)
            freeBytes -= UInt64(reused.size)
            activeChunk = reused
            activeOffset = size
            return (reused, 0)
        }

        let created = device.createBuffer(label: "staging chunk", size: Int(needed))
        statsValue.chunks &+= 1
        activeChunk = created
        activeOffset = size
        return (created, 0)
    }

    private func recycleChunks(_ chunks: [MetalBuffer]) {
        guard !chunks.isEmpty else { return }
        lock.withLock {
            for ch in chunks {
                let sz = UInt64(ch.size)
                if sz <= RuneStaging.keepChunkMax
                    && freeChunks.count < RuneStaging.keepChunks
                    && freeBytes + sz <= RuneStaging.keepBytes {
                    freeChunks.append(ch)
                    freeBytes += sz
                }
            }
        }
    }

    private func markLostAndRecycle(_ chunks: [MetalBuffer]) {
        lock.withLock {
            lostCount &+= 1
            for ch in chunks {
                let sz = UInt64(ch.size)
                if sz <= RuneStaging.keepChunkMax
                    && freeChunks.count < RuneStaging.keepChunks
                    && freeBytes + sz <= RuneStaging.keepBytes {
                    freeChunks.append(ch)
                    freeBytes += sz
                }
            }
        }
    }

    func writeBuffer(_ buffer: MetalBuffer, _ offset: UInt64, _ data: [UInt8]) {
        guard !data.isEmpty else { return }
        let alignedLen = RuneStaging.alignUp(UInt64(data.count), to: RuneStaging.copyBufferAlignment)

        if allowDirect && Int(offset) + data.count <= buffer.size {
            if buffer.writeInPlace(offset: offset, data: data) {
                lock.withLock {
                    statsValue.writes &+= 1
                    statsValue.bytes &+= UInt64(data.count)
                    statsValue.direct &+= 1
                }
                return
            }
        }

        let shouldAutoSubmit = lock.withLock {
            pendingBytes + alignedLen > RuneStaging.maxPending && !recordedInCycle
        }
        if shouldAutoSubmit {
            submit()
        }

        lock.withLock {
            let (chunk, chunkOff) = allocLocked(size: alignedLen, align: RuneStaging.copyBufferAlignment)
            var padded = data
            if padded.count < Int(alignedLen) {
                padded.append(contentsOf: repeatElement(0, count: Int(alignedLen) - padded.count))
            }
            _ = chunk.writeInPlace(offset: chunkOff, data: padded)
            unrecordedCopies.append(
                .buffer(
                    chunk: chunk,
                    srcOffset: chunkOff,
                    dst: buffer,
                    dstOffset: offset,
                    size: alignedLen
                )
            )
            pendingBytes &+= alignedLen
            statsValue.writes &+= 1
            statsValue.bytes &+= UInt64(data.count)
        }
    }

    func writeTextureRows(_ texture: MetalTexture, _ y0: UInt32, _ data: [UInt8]) {
        guard !data.isEmpty else { return }
        let bpp = UInt32(metalFormatBytesPerPixel(texture.format))
        let rowBytes = texture.width * bpp
        guard rowBytes > 0 else { return }
        let rows = UInt32(data.count) / rowBytes
        guard rows > 0 else { return }

        let paddedRow = UInt32(RuneStaging.alignUp(UInt64(rowBytes), to: RuneStaging.rowAlign))
        let stagedLen = UInt64(paddedRow) * UInt64(rows)

        let shouldAutoSubmit = lock.withLock {
            pendingBytes + stagedLen > RuneStaging.maxPending && !recordedInCycle
        }
        if shouldAutoSubmit {
            submit()
        }

        lock.withLock {
            let (chunk, chunkOff) = allocLocked(size: stagedLen, align: RuneStaging.rowAlign)
            if paddedRow == rowBytes {
                _ = chunk.writeInPlace(offset: chunkOff, data: data)
            } else {
                var staged = [UInt8](repeating: 0, count: Int(stagedLen))
                for r in 0..<Int(rows) {
                    let srcStart = r * Int(rowBytes)
                    let dstStart = r * Int(paddedRow)
                    staged.replaceSubrange(
                        dstStart..<(dstStart + Int(rowBytes)),
                        with: data[srcStart..<(srcStart + Int(rowBytes))]
                    )
                }
                _ = chunk.writeInPlace(offset: chunkOff, data: staged)
            }
            unrecordedCopies.append(
                .texture(
                    chunk: chunk,
                    srcOffset: chunkOff,
                    bytesPerRow: paddedRow,
                    rows: rows,
                    dst: texture,
                    y0: y0
                )
            )
            pendingBytes &+= stagedLen
            statsValue.writes &+= 1
            statsValue.bytes &+= stagedLen
        }
    }

    private static func emitCopies(_ copies: [StagedCopy], into encoder: MetalCommandEncoder) {
        for op in copies {
            switch op {
            case .buffer(let chunk, let srcOffset, let dst, let dstOffset, let size):
                encoder.copyBufferToBuffer(
                    source: chunk,
                    sourceOffset: srcOffset,
                    destination: dst,
                    destinationOffset: dstOffset,
                    size: size
                )
            case .texture(let chunk, let srcOffset, let bytesPerRow, let rows, let dst, let y0):
                encoder.copyBufferToTexture(
                    source: chunk,
                    sourceOffset: srcOffset,
                    bytesPerRow: bytesPerRow,
                    rowsPerImage: rows,
                    destination: dst,
                    mipLevel: 0,
                    originX: 0,
                    originY: y0,
                    arrayLayer: 0,
                    width: dst.width,
                    height: rows
                )
            }
        }
    }

    /// Emits unrecorded copies into `encoder` in command order without sealing the open chunk yet.
    func record(_ encoder: MetalCommandEncoder) {
        let (ops, installDropHook): ([StagedCopy], Bool) = lock.withLock {
            guard !unrecordedCopies.isEmpty else { return ([], false) }
            let taken = unrecordedCopies
            unrecordedCopies.removeAll(keepingCapacity: true)
            recordedInCycle = true
            let needHook = !hookInstalledForCycle
            hookInstalledForCycle = true
            return (taken, needHook)
        }
        guard !ops.isEmpty else { return }
        Self.emitCopies(ops, into: encoder)
        if installDropHook {
            encoder.onDropUnsubmitted { [weak self] in
                guard let self else { return }
                let orphaned: [MetalBuffer] = self.lock.withLock {
                    guard self.recordedInCycle else { return [] }
                    var all = self.sealedInCycle
                    self.sealedInCycle.removeAll()
                    if let act = self.activeChunk {
                        all.append(act)
                        self.activeChunk = nil
                    }
                    self.activeOffset = 0
                    self.pendingBytes = 0
                    self.unrecordedCopies.removeAll()
                    self.recordedInCycle = false
                    self.hookInstalledForCycle = false
                    return all
                }
                if !orphaned.isEmpty {
                    self.markLostAndRecycle(orphaned)
                }
            }
        }
    }

    /// Records any remaining copies into `encoder` and seals the current chunk cycle for GPU recycle.
    func flush(_ encoder: MetalCommandEncoder) {
        let (ops, chunksToReturn): ([StagedCopy], [MetalBuffer]) = lock.withLock {
            if unrecordedCopies.isEmpty && !recordedInCycle && sealedInCycle.isEmpty && activeChunk == nil {
                return ([], [])
            }
            let ops = unrecordedCopies
            unrecordedCopies.removeAll(keepingCapacity: true)
            var chunks = sealedInCycle
            sealedInCycle.removeAll()
            if let act = activeChunk {
                chunks.append(act)
                activeChunk = nil
            }
            activeOffset = 0
            pendingBytes = 0
            let hadWork = !ops.isEmpty || recordedInCycle
            let alreadyHooked = hookInstalledForCycle
            recordedInCycle = false
            hookInstalledForCycle = false
            if hadWork {
                statsValue.flushes &+= 1
            }
            _ = alreadyHooked
            return (ops, chunks)
        }
        if !ops.isEmpty {
            Self.emitCopies(ops, into: encoder)
        }
        if !chunksToReturn.isEmpty {
            encoder.onSubmittedWorkDone { [weak self] in
                self?.recycleChunks(chunksToReturn)
            }
            encoder.onDropUnsubmitted { [weak self] in
                self?.markLostAndRecycle(chunksToReturn)
            }
        }
    }

    /// Submits any pending copies in a standalone staging command buffer.
    func submit() {
        let (ops, chunksToReturn): ([StagedCopy], [MetalBuffer]) = lock.withLock {
            if unrecordedCopies.isEmpty && sealedInCycle.isEmpty && activeChunk == nil {
                return ([], [])
            }
            let ops = unrecordedCopies
            unrecordedCopies.removeAll(keepingCapacity: true)
            var chunks = sealedInCycle
            sealedInCycle.removeAll()
            if let act = activeChunk {
                chunks.append(act)
                activeChunk = nil
            }
            activeOffset = 0
            pendingBytes = 0
            recordedInCycle = false
            hookInstalledForCycle = false
            if !ops.isEmpty {
                statsValue.submits &+= 1
            }
            return (ops, chunks)
        }
        guard !ops.isEmpty else {
            recycleChunks(chunksToReturn)
            return
        }
        let enc = device.createCommandEncoder(label: "rune-staging")
        Self.emitCopies(ops, into: enc)
        if !chunksToReturn.isEmpty {
            enc.onSubmittedWorkDone { [weak self] in
                self?.recycleChunks(chunksToReturn)
            }
        }
        _ = queue.submit([enc.finish()])
    }
}

// MARK: - Uploads

final class Uploads {
    var stagingInstance: MetalStaging? = nil
    var frameWrites: MetalStaging? = nil
    var instances: [Instance] = []
    var batched: Bool = false
    var hasLayers: Bool = false
    private let viewportLock = LiveLock()
    private var viewportPacked: UInt64 = .max
    var srgb: Bool? = nil
    var lost: (UInt64, UInt64) = (0, 0)
    var globalsWrites: UInt64 = 0
    var batchRuns: UInt64 = 0

    func swapViewport(_ next: UInt64) -> UInt64 {
        viewportLock.withLock {
            let prev = viewportPacked
            viewportPacked = next
            return prev
        }
    }

    func storeViewport(_ next: UInt64) {
        viewportLock.withLock {
            viewportPacked = next
        }
    }

    func forgetInstances() {
        instances.removeAll(keepingCapacity: true)
        batched = false
    }

    func staging(_ device: MetalDevice, _ queue: MetalQueue) -> MetalStaging {
        if let s = stagingInstance {
            return s
        }
        let created = MetalStaging(device: device, queue: queue, allowDirect: true)
        stagingInstance = created
        return created
    }

    func stats() -> RuneStaging.Stats {
        stagingInstance?.stats() ?? RuneStaging.Stats()
    }

    func frameWriteStats() -> RuneStaging.Stats {
        frameWrites?.stats() ?? RuneStaging.Stats()
    }
}

private let BATCHED_KINDS: UInt32 =
    (1 << UInt32(KIND_GLYPH))
    | (1 << UInt32(KIND_IMAGE))
    | (1 << UInt32(KIND_LAYER))
    | (1 << UInt32(KIND_EFFECT))
    | (1 << UInt32(KIND_BACKDROP_BLUR))

let INSTANCE_DIFF_BLOCK: Int = 64

/// Fast word-wise equality check across two equal-length `Instance` slices.
func sameInstances(_ a: ArraySlice<Instance>, _ b: ArraySlice<Instance>) -> Bool {
    guard a.count == b.count else { return false }
    var acc: UInt32 = 0
    var ia = a.makeIterator()
    var ib = b.makeIterator()
    while let xa = ia.next(), let xb = ib.next() {
        let wa = instanceWords(xa)
        let wb = instanceWords(xb)
        for j in 0..<32 {
            acc |= wa[j] ^ wb[j]
        }
        if acc != 0 {
            return false
        }
    }
    return acc == 0
}

@inline(__always)
private func packViewport(_ vp: (UInt32, UInt32)) -> UInt64 {
    (UInt64(vp.0) << 32) | UInt64(vp.1)
}

@inline(__always)
private func sameParams(_ a: Instance, _ b: Instance) -> Bool {
    a.params[0].bitPattern == b.params[0].bitPattern
        && a.params[1].bitPattern == b.params[1].bitPattern
        && a.params[2].bitPattern == b.params[2].bitPattern
        && a.params[3].bitPattern == b.params[3].bitPattern
}

extension Renderer {
    /// Records pending uploads into `encoder`, ahead of the renderer's commands in it.
    func flushUploads(_ encoder: MetalCommandEncoder) {
        uploads.stagingInstance?.flush(encoder)
    }

    /// Submits pending uploads ahead of commands already recorded.
    func submitUploads() {
        uploads.stagingInstance?.submit()
    }

    /// Readies the frame's `encoder` for submission: submits pending uploads ahead of it, and
    /// seals the compositor's writes recorded into it.
    public func beforeSubmit(_ encoder: MetalCommandEncoder) {
        submitUploads()
        uploads.frameWrites?.flush(encoder)
    }

    /// `Queue.writeBuffer` through staging chunks, recorded into `encoder` in command order.
    public func writeBuffer(
        _ device: MetalDevice,
        _ queue: MetalQueue,
        _ encoder: MetalCommandEncoder,
        _ buffer: MetalBuffer,
        _ offset: UInt64,
        _ data: [UInt8]
    ) {
        let st: MetalStaging
        if let existing = uploads.frameWrites {
            st = existing
        } else {
            let created = MetalStaging(device: device, queue: queue, allowDirect: false)
            uploads.frameWrites = created
            st = created
        }
        st.writeBuffer(buffer, offset, data)
        st.record(encoder)
    }

    private static func writeRows(
        _ staging: MetalStaging,
        _ texture: MetalTexture,
        _ data: [UInt8],
        _ rows: (UInt32, UInt32)
    ) {
        let (y0, y1) = rows
        guard y1 > y0 else { return }
        let row = Int(texture.width) * metalFormatBytesPerPixel(texture.format)
        let start = Int(y0) * row
        let end = min(Int(y1) * row, data.count)
        guard end > start else { return }
        staging.writeTextureRows(texture, y0, Array(data[start..<end]))
    }

    /// Uploads changed rows of the runtime's image atlas (`El.pixels`), creating its texture on first use.
    public func uploadImages(_ device: MetalDevice, _ queue: MetalQueue, _ imageAtlas: inout ImageAtlas) {
        if imageAtlas.pages.isEmpty && images.isEmpty {
            refreshLayerBindings(device)
            return
        }
        let st = uploads.staging(device, queue)
        let currentLost = st.lost()
        if currentLost != uploads.lost.1 {
            uploads.lost.1 = currentLost
            for idx in imageAtlas.pages.indices {
                imageAtlas.pages[idx].dirty = (0, imageAtlas.pages[idx].height)
            }
        }
        var changed = images.count != imageAtlas.pages.count
        if images.count < imageAtlas.pages.count {
            images.append(contentsOf: repeatElement(nil, count: imageAtlas.pages.count - images.count))
        } else if images.count > imageAtlas.pages.count {
            images.removeSubrange(imageAtlas.pages.count..<images.count)
        }

        for index in imageAtlas.pages.indices {
            if imageAtlas.pages[index].data.isEmpty {
                if images[index] != nil { changed = true }
                images[index] = nil
                continue
            }
            let pageW = imageAtlas.pages[index].width
            let pageH = imageAtlas.pages[index].height
            let needsAlloc = images[index].map { $0.0.width != pageW || $0.0.height != pageH } ?? true
            if needsAlloc {
                let texture = Self.makeImageTexture(device, pageW, pageH)
                let bind = Self.makeBindGroup(device, bindLayout, globals, atlas, texture, nil)
                images[index] = (texture, bind)
                changed = true
                imageAtlas.pages[index].dirty = (0, pageH)
            }
            guard let rows = imageAtlas.pages[index].dirty else { continue }
            imageAtlas.pages[index].dirty = nil
            Self.writeRows(st, images[index]!.0, imageAtlas.pages[index].data, rows)
        }
        if changed {
            imagesChanged()
        }
        refreshLayerBindings(device)
    }

    /// Uploads several instance lists back to back and returns each list's instance range for `drawRange`.
    public func prepareLists(
        _ device: MetalDevice,
        _ queue: MetalQueue,
        _ glyphAtlas: inout Atlas,
        _ lists: [[Instance]],
        _ viewport: (UInt32, UInt32)
    ) -> [Range<UInt32>] {
        let total = lists.reduce(0) { $0 + $1.count }
        var all = [Instance]()
        all.reserveCapacity(total)
        var ranges = [Range<UInt32>]()
        ranges.reserveCapacity(lists.count)
        for list in lists {
            let a = UInt32(all.count)
            all.append(contentsOf: list)
            ranges.append(a..<UInt32(all.count))
        }
        prepare(device, queue, &glyphAtlas, all, viewport)
        return ranges
    }

    static func makeInstanceBuffer(_ device: MetalDevice, _ capacity: Int) -> MetalBuffer {
        device.createBuffer(label: "instances", size: max(capacity, 1) * INSTANCE_BYTE_SIZE)
    }

    /// Uploads instances, globals, and any dirty glyph atlas rows.
    public func prepare(
        _ device: MetalDevice,
        _ queue: MetalQueue,
        _ glyphAtlas: inout Atlas,
        _ instances: [Instance],
        _ viewport: (UInt32, UInt32)
    ) {
        if springsState != nil {
            precondition(instances.count == springInstances, "GPU springs instance count mismatch")
        }
        let st = uploads.staging(device, queue)
        let currentLost = st.lost()
        if currentLost != uploads.lost.0 {
            uploads.lost.0 = currentLost
            resendUploads(&glyphAtlas)
        }
        if let rows = glyphAtlas.dirty {
            glyphAtlas.dirty = nil
            Self.writeRows(st, atlas, glyphAtlas.data, rows)
        }
        var atlasChanged = atlasPages.count > glyphAtlas.pages.count
        if atlasPages.count > glyphAtlas.pages.count {
            atlasPages.removeSubrange(glyphAtlas.pages.count..<atlasPages.count)
        }
        for index in glyphAtlas.pages.indices {
            if index >= atlasPages.count {
                let texture = Self.makeTexture(device, "glyph atlas", WGPUTextureFormat_R8Unorm, ATLAS_SIZE, ATLAS_SIZE)
                let bind = Self.makeBindGroup(device, bindLayout, globals, texture, texture, nil)
                atlasPages.append((texture, bind))
                atlasChanged = true
            }
            if let rows = glyphAtlas.pages[index].dirty {
                glyphAtlas.pages[index].dirty = nil
                Self.writeRows(st, atlasPages[index].0, glyphAtlas.pages[index].data, rows)
            }
        }
        if atlasChanged {
            imagesChanged()
        }

        if instances.count > capacity {
            capacity = Int(RuneStaging.nextPowerOfTwo(UInt64(max(instances.count, 1))))
            instancesBuffer = Self.makeInstanceBuffer(device, capacity)
            uploads.forgetInstances()
        }
        writeInstances(st, instances)

        let packedVp = packViewport(viewport)
        if uploads.swapViewport(packedVp) != packedVp {
            st.writeBuffer(globals, 0, floatsBytes([Float(viewport.0), Float(viewport.1)]))
            uploads.globalsWrites &+= 1
        }
        if uploads.srgb != srgbBlendEnabled {
            uploads.srgb = srgbBlendEnabled
            let flags: [Float] = [srgbBlendEnabled ? 1.0 : 0.0, 0.0, 0.0, 0.0]
            st.writeBuffer(globals, 16, floatsBytes(flags))
            uploads.globalsWrites &+= 1
        }

        count = UInt32(instances.count)
        if !uploads.batched {
            batch(instances)
        } else {
            for idx in effects.indices {
                let at = Int(effects[idx].0)
                if at < instances.count {
                    effects[idx].1 = instances[at]
                }
            }
        }

        let hasLayers = uploads.hasLayers
        prepareLayers(device, queue, hasLayers ? instances : [], viewport)
        syncResidentCaches(&glyphAtlas.residentCaches)

        if effects.contains(where: { $0.1.params[0] != 0.0 || $0.1.params[1] == KIND_BACKDROP_BLUR }) {
            ensureBackdrop(device, format, viewport)
            for (extraFmt, _) in extra {
                ensureBackdrop(device, extraFmt, viewport)
            }
            if layers.targets.contains(where: { $0 != nil }) {
                ensureBackdrop(device, LAYER_FORMAT, viewport)
            }
        }
        prepareBackdropBlur(device, queue, viewport)
    }

    public func prepareSurfaces(
        _ device: MetalDevice,
        _ queue: MetalQueue,
        _ draws: [SurfaceDraw],
        _ viewport: (UInt32, UInt32)
    ) {
        #if !os(WASI)
        if !draws.isEmpty && surfaces == nil {
            let sr = SurfaceRenderer(device, format)
            sr.setSrgbBlend(srgbBlendEnabled)
            for (extraFmt, _) in extra {
                sr.addFormat(device, extraFmt)
            }
            surfaces = sr
        }
        if let sr = surfaces {
            sr.setSrgbBlend(srgbBlendEnabled)
            if layers.additive != nil {
                sr.addPlusLighter(device, LAYER_FORMAT)
            }
            sr.prepare(device, queue, draws, viewport)
        }
        if layerStats().targets > 0 {
            positionLayerSurfaces(queue)
        }
        #else
        _ = (device, queue, draws, viewport)
        #endif
    }

    /// One uniform write per presentation-only frame; use the display's target time.
    public func presentAt(_ queue: MetalQueue, _ viewport: (UInt32, UInt32), _ time: Double) {
        let t = springs.splitTime(time)
        let data = floatsBytes([Float(viewport.0), Float(viewport.1), t[0], t[1]])
        uploads.storeViewport(packViewport(viewport))
        if let st = uploads.stagingInstance {
            st.writeBuffer(globals, 0, data)
        } else {
            queue.writeBuffer(globals, offset: 0, data: data)
        }
    }

    /// A retarget touches one node record; caller computes inherited position/velocity on CPU.
    public func writeSpringNode(_ queue: MetalQueue, _ id: Int, _ node: springs.Node) {
        guard var props = springsState else {
            fatalError("renderer has no GPU springs")
        }
        props.writeNode(id, node)
        springsState = props
        guard let nodesBuf = props.nodesBuffer else { return }
        let offset = UInt64(id * springs.Node.byteSize)
        let bytes = node.toBytes()
        if let st = uploads.stagingInstance {
            st.writeBuffer(nodesBuf, offset, bytes)
        } else {
            queue.writeBuffer(nodesBuf, offset: offset, data: bytes)
        }
    }

    private func batch(_ instances: [Instance]) {
        imageBatches.removeAll(keepingCapacity: true)
        var start: UInt32 = 0
        var bind = BatchBind.image(0)
        var hasLayers = false
        effects.removeAll(keepingCapacity: true)

        for (i, instance) in instances.enumerated() {
            let kind = instance.params[1]
            if kind >= 0.0 && kind < 16.0 && (BATCHED_KINDS & (1 << UInt32(kind))) == 0 {
                continue
            }
            if kind == KIND_LAYER {
                hasLayers = true
            }
            if kind == KIND_EFFECT || kind == KIND_BACKDROP_BLUR {
                effects.append((UInt32(i), instance))
            }
            let nextBind: BatchBind?
            if kind == KIND_IMAGE {
                nextBind = .image(Int(instance.params[0]))
            } else if kind == KIND_GLYPH {
                let g = Int(instance.params[2])
                if g == 0 {
                    switch bind {
                    case .image:
                        nextBind = nil
                    case .glyph:
                        nextBind = .image(0)
                    }
                } else {
                    nextBind = .glyph(g - 1)
                }
            } else {
                nextBind = nil
            }
            if let next = nextBind, next != bind {
                if start < UInt32(i) {
                    imageBatches.append((start..<UInt32(i), bind))
                }
                start = UInt32(i)
                bind = next
            }
        }
        if start < UInt32(instances.count) {
            imageBatches.append((start..<UInt32(instances.count), bind))
        }
        uploads.hasLayers = hasLayers
        uploads.batched = true
        uploads.batchRuns &+= 1
    }

    private func writeInstances(_ staging: MetalStaging, _ instances: [Instance]) {
        let shared = min(instances.count, uploads.instances.count)
        var rebatch = instances.count != uploads.instances.count
        if uploads.instances.count < instances.count {
            uploads.instances.append(contentsOf: repeatElement(Instance.zeroed(), count: instances.count - uploads.instances.count))
        } else if uploads.instances.count > instances.count {
            uploads.instances.removeSubrange(instances.count..<uploads.instances.count)
        }

        var open: Range<Int>? = nil
        var start = 0
        while start < shared {
            let end = min(start + INSTANCE_DIFF_BLOCK, shared)
            func differs(_ idx: Int) -> Bool {
                !sameInstances(instances[idx...idx], uploads.instances[idx...idx])
            }
            let first: Int
            if differs(start) {
                first = start
            } else if sameInstances(instances[start..<end], uploads.instances[start..<end]) {
                start += INSTANCE_DIFF_BLOCK
                continue
            } else {
                first = ((start + 1)..<end).first(where: differs) ?? start
            }
            var last = end
            for k in stride(from: end - 1, through: first, by: -1) {
                if differs(k) {
                    last = k + 1
                    break
                }
            }
            if Self.joinSpan(instancesBuffer, &uploads.instances, staging, instances, &open, first..<last) {
                rebatch = true
            }
            start += INSTANCE_DIFF_BLOCK
        }
        if instances.count > shared {
            if Self.joinSpan(instancesBuffer, &uploads.instances, staging, instances, &open, shared..<instances.count) {
                rebatch = true
            }
        }
        if let span = open {
            if Self.writeSpan(instancesBuffer, &uploads.instances, staging, instances, span) {
                rebatch = true
            }
        }
        if rebatch {
            uploads.batched = false
        }
    }

    private static func joinSpan(
        _ buffer: MetalBuffer,
        _ held: inout [Instance],
        _ staging: MetalStaging,
        _ instances: [Instance],
        _ open: inout Range<Int>?,
        _ span: Range<Int>
    ) -> Bool {
        if let o = open, span.lowerBound <= o.upperBound + INSTANCE_DIFF_BLOCK {
            open = o.lowerBound..<span.upperBound
            return false
        }
        let previous = open
        open = span
        if let prev = previous {
            return writeSpan(buffer, &held, staging, instances, prev)
        }
        return false
    }

    private static func writeSpan(
        _ buffer: MetalBuffer,
        _ held: inout [Instance],
        _ staging: MetalStaging,
        _ instances: [Instance],
        _ span: Range<Int>
    ) -> Bool {
        var rebatch = false
        for idx in span {
            if !sameParams(held[idx], instances[idx]) {
                rebatch = true
            }
            held[idx] = instances[idx]
        }
        let offset = UInt64(span.lowerBound * INSTANCE_BYTE_SIZE)
        staging.writeBuffer(buffer, offset, instancesSliceBytes(instances[span]))
        return rebatch
    }

    private func resendUploads(_ glyphAtlas: inout Atlas) {
        uploads.forgetInstances()
        uploads.storeViewport(.max)
        uploads.srgb = nil
        glyphAtlas.dirty = (0, ATLAS_SIZE)
        for idx in glyphAtlas.pages.indices {
            glyphAtlas.pages[idx].dirty = (0, ATLAS_SIZE)
        }
        layers.forgetBlurUniforms()
    }
}
