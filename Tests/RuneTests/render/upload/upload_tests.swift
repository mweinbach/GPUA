// Tests ported from: crates/rune/src/render/upload/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import Testing
import CWebGPU
@testable import Rune

private let UPLOAD_TEST_SIZE: (UInt32, UInt32) = (64, 32)
private let UPLOAD_RED: [UInt8] = [255, 0, 0, 255]
private let UPLOAD_CLEAR: [UInt8] = [0, 0, 0, 0]

private func uploadSquare(_ x: Float, _ y: Float) -> Instance {
    Instance(
        rect: [x, y, 8.0, 8.0],
        fill: [1.0, 0.0, 0.0, 1.0],
        clip: NO_CLIP
    )
}

private func uploadScene(_ frame: Int) -> [Instance] {
    var list: [Instance] = [uploadSquare(Float(frame), 20.0)]
    for i in 0..<48 {
        var sq = uploadSquare(0.0, 0.0)
        sq.rect = [Float(i % 16) * 4.0, Float(i / 16) * 4.0, 1.0, 1.0]
        list.append(sq)
    }
    return list
}

private func uploadPixel(_ pixels: [UInt8], _ x: UInt32, _ y: UInt32) -> [UInt8] {
    let at = Int((y * UPLOAD_TEST_SIZE.0 + x) * 4)
    return Array(pixels[at..<(at + 4)])
}

@Suite("Rune Render Upload Behavioral Tests", .serialized)
struct RuneRenderUploadBehavioralTests {
    @Test("a steady animating frame creates no buffers and skips unchanged globals")
    func aSteadyAnimatingFrameCreatesNoBuffersAndSkipsUnchangedGlobals() {
        let gpu = Gpu.headless()
        let (device, queue) = (gpu.metalDevice, gpu.metalQueue)
        let renderer = Renderer(device, OFFSCREEN_FORMAT)
        var atlas = TextSystem().atlas
        let target = Offscreen(device, UPLOAD_TEST_SIZE.0, UPLOAD_TEST_SIZE.1)
        var pixels: [UInt8] = []
        for frame in 0..<24 {
            let buffersBefore = device.liveBufferCount
            let globalsBefore = renderer.uploads.globalsWrites
            let statsBefore = renderer.uploads.stats()
            renderer.prepare(device, queue, &atlas, uploadScene(frame), UPLOAD_TEST_SIZE)
            let enc = device.createCommandEncoder(label: "steady-\(frame)")
            renderer.draw(enc, target.view, [0.0, 0.0, 0.0, 0.0])
            let created = device.liveBufferCount - buffersBefore
            if frame == 23 {
                target.copy(enc)
            }
            renderer.submit(queue, enc)
            _ = device.poll(.waitIndefinitely())
            if frame < 4 { continue }
            let now = renderer.uploads.stats()
            #expect(created == 0, "frame \(frame) created buffers")
            #expect(now.chunks == statsBefore.chunks, "frame \(frame) made a staging chunk")
            #expect(renderer.uploads.globalsWrites == globalsBefore, "frame \(frame) rewrote unchanged globals")
            #expect(now.writes - statsBefore.writes == 1)
            #expect(now.bytes - statsBefore.bytes == UInt64(INSTANCE_BYTE_SIZE))
            let staged: UInt64 = (now.direct == statsBefore.direct) ? 1 : 0
            #expect(now.flushes - statsBefore.flushes == staged)
            #expect(now.submits - statsBefore.submits == 0)
        }
        pixels = target.read(device)
        #expect(uploadPixel(pixels, 27, 24) == UPLOAD_RED)
        #expect(uploadPixel(pixels, 2, 24) == UPLOAD_CLEAR)
    }

    @Test("instances are written in the spans that changed")
    func instancesAreWrittenInTheSpansThatChanged() {
        let gpu = Gpu.headless()
        let (device, queue) = (gpu.metalDevice, gpu.metalQueue)
        let renderer = Renderer(device, OFFSCREEN_FORMAT)
        var atlas = TextSystem().atlas
        let target = Offscreen(device, UPLOAD_TEST_SIZE.0, UPLOAD_TEST_SIZE.1)
        let hidden = uploadSquare(-100.0, -100.0)
        let far = 2 * INSTANCE_DIFF_BLOCK + 10
        let last = 4 * INSTANCE_DIFF_BLOCK - 3
        var instances = [Instance](repeating: hidden, count: last + 1)

        func runFrame(_ list: [Instance]) -> ((UInt64, UInt64), [UInt8]) {
            let stats = renderer.uploads.stats()
            renderer.prepare(device, queue, &atlas, list, UPLOAD_TEST_SIZE)
            let enc = device.createCommandEncoder(label: "span-frame")
            renderer.draw(enc, target.view, [0.0, 0.0, 0.0, 0.0])
            target.copy(enc)
            renderer.submit(queue, enc)
            let now = renderer.uploads.stats()
            return (
                (now.writes - stats.writes, (now.bytes - stats.bytes) / UInt64(INSTANCE_BYTE_SIZE)),
                target.read(device)
            )
        }

        _ = runFrame(instances)
        instances[3] = uploadSquare(0.0, 0.0)
        instances[far] = uploadSquare(20.0, 0.0)
        instances[last] = uploadSquare(40.0, 0.0)
        let (w1, px1) = runFrame(instances)
        #expect(w1.0 == 3 && w1.1 == 3)
        for x: UInt32 in [4, 24, 44] {
            #expect(uploadPixel(px1, x, 4) == UPLOAD_RED)
        }

        instances[far] = hidden
        instances[far + 10] = uploadSquare(20.0, 20.0)
        instances[far + 25] = uploadSquare(40.0, 20.0)
        let (w2, px2) = runFrame(instances)
        #expect(w2.0 == 1 && w2.1 == 26)
        #expect(uploadPixel(px2, 24, 4) == UPLOAD_CLEAR)
        for x: UInt32 in [24, 44] {
            #expect(uploadPixel(px2, x, 24) == UPLOAD_RED)
        }

        instances.append(contentsOf: [uploadSquare(56.0, 0.0), hidden])
        let (w3, px3) = runFrame(instances)
        #expect(w3.0 == 1 && w3.1 == 2)
        #expect(uploadPixel(px3, 60, 4) == UPLOAD_RED)

        for idx in instances.indices {
            instances[idx].rect[1] += 1.0
        }
        let (w4, _) = runFrame(instances)
        #expect(w4.0 == 1 && w4.1 == UInt64(last + 3))
    }

    @Test("uploads land before a draw into a caller's pass")
    func uploadsLandBeforeADrawIntoACallersPass() {
        let gpu = Gpu.headless()
        let (device, queue) = (gpu.metalDevice, gpu.metalQueue)
        let renderer = Renderer(device, OFFSCREEN_FORMAT)
        var atlas = TextSystem().atlas
        let target = Offscreen(device, UPLOAD_TEST_SIZE.0, UPLOAD_TEST_SIZE.1)
        for x: Float in [0.0, 30.0] {
            renderer.prepare(device, queue, &atlas, [uploadSquare(x, 4.0)], UPLOAD_TEST_SIZE)
            let enc = device.createCommandEncoder(label: "caller-pass")
            do {
                let pass = enc.beginRenderPass(
                    label: "caller",
                    colorAttachment: MetalRenderPassColorAttachment(
                        view: target.view,
                        loadOp: .clear(r: 0, g: 0, b: 0, a: 0),
                        storeOp: .store
                    )
                )
                renderer.drawRange(pass, OFFSCREEN_FORMAT, 0..<1)
                pass.end()
            }
            target.copy(enc)
            queue.submit([enc.finish()])
            let pixels = target.read(device)
            #expect(uploadPixel(pixels, UInt32(x) + 4, 8) == UPLOAD_RED)
        }
    }

    @Test("a dropped encoder makes the next frame resend everything")
    func aDroppedEncoderMakesTheNextFrameResendEverything() {
        let gpu = Gpu.headless()
        let (device, queue) = (gpu.metalDevice, gpu.metalQueue)
        let renderer = Renderer(device, OFFSCREEN_FORMAT)
        var atlas = TextSystem().atlas
        let target = Offscreen(device, UPLOAD_TEST_SIZE.0, UPLOAD_TEST_SIZE.1)
        let instances = [uploadSquare(10.0, 10.0)]
        renderer.prepare(device, queue, &atlas, instances, UPLOAD_TEST_SIZE)
        do {
            let dropped = device.createCommandEncoder(label: "dropped")
            renderer.draw(dropped, target.view, [0.0, 0.0, 0.0, 0.0])
        }
        renderer.prepare(device, queue, &atlas, instances, UPLOAD_TEST_SIZE)
        let enc = device.createCommandEncoder(label: "resubmitted")
        renderer.draw(enc, target.view, [0.0, 0.0, 0.0, 0.0])
        target.copy(enc)
        renderer.submit(queue, enc)
        #expect(uploadPixel(target.read(device), 14, 14) == UPLOAD_RED)
    }

    @Test("compositor buffer writes land in order and reuse staging")
    func compositorBufferWritesLandInOrderAndReuseStaging() {
        let gpu = Gpu.headless()
        let (device, queue) = (gpu.metalDevice, gpu.metalQueue)
        let renderer = Renderer(device, OFFSCREEN_FORMAT)
        let uniforms = device.createBuffer(label: "uniforms", size: 16)
        let readback = device.createBuffer(label: "readback", size: 32)
        func u32Bytes(_ vals: [UInt32]) -> [UInt8] {
            var le = vals.map { $0.littleEndian }
            return le.withUnsafeMutableBufferPointer { Array(UnsafeRawBufferPointer($0)) }
        }
        for frame: UInt32 in 0..<12 {
            let beforeBuffers = device.liveBufferCount
            let enc = device.createCommandEncoder(label: "comp-write-\(frame)")
            renderer.writeBuffer(device, queue, enc, uniforms, 0, u32Bytes([frame, frame, frame, frame]))
            enc.copyBufferToBuffer(source: uniforms, sourceOffset: 0, destination: readback, destinationOffset: 0, size: 16)
            renderer.writeBuffer(device, queue, enc, uniforms, 0, u32Bytes([frame + 100, frame + 100, frame + 100, frame + 100]))
            enc.copyBufferToBuffer(source: uniforms, sourceOffset: 0, destination: readback, destinationOffset: 16, size: 16)
            let created = device.liveBufferCount - beforeBuffers
            renderer.submit(queue, enc)
            readback.mapAsync { _ in }
            _ = device.poll(.waitIndefinitely())
            let raw = readback.getMappedRange()
            readback.unmap()
            var words: [UInt32] = []
            for off in stride(from: 0, to: 32, by: 4) {
                let b0 = UInt32(raw[off])
                let b1 = UInt32(raw[off + 1]) << 8
                let b2 = UInt32(raw[off + 2]) << 16
                let b3 = UInt32(raw[off + 3]) << 24
                words.append(b0 | b1 | b2 | b3)
            }
            #expect(words == [frame, frame, frame, frame, frame + 100, frame + 100, frame + 100, frame + 100])
            let stats = renderer.uploads.frameWriteStats()
            let staged: UInt64 = (stats.direct == 0) ? 1 : 0
            #expect(stats.chunks == staged)
            if frame >= 2 {
                #expect(created == 0)
            }
        }
    }

    @Test("a frame with nothing to upload never touches the staging")
    func aFrameWithNothingToUploadNeverTouchesTheStaging() {
        let gpu = Gpu.headless()
        let (device, queue) = (gpu.metalDevice, gpu.metalQueue)
        let renderer = Renderer(device, OFFSCREEN_FORMAT)
        var emptyImages = ImageAtlas()
        renderer.uploadImages(device, queue, &emptyImages)
        #expect(renderer.uploads.stagingInstance == nil)

        let uniforms = device.createBuffer(label: "u", size: 16)
        let enc = device.createCommandEncoder(label: "empty-upload")
        renderer.writeBuffer(device, queue, enc, uniforms, 0, [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0])
        let writes = renderer.uploads.frameWrites!
        #expect(writes.busy() || writes.stats().direct == 1)
        renderer.beforeSubmit(enc)
        #expect(!writes.busy())
        let flushes = writes.stats().flushes
        renderer.beforeSubmit(enc)
        #expect(writes.stats().flushes == flushes)
        queue.submit([enc.finish()])
    }

    @Test("sameInstances finds one changed bit in any word")
    func sameFindsOneChangedBitInAnyWord() {
        let a = uploadScene(0)
        #expect(sameInstances(a[...], a[...]))
        for word in 0..<(INSTANCE_BYTE_SIZE / 4) {
            var b = a
            var words = instanceWords(b[b.count - 1])
            words[word] ^= (1 << 31)
            func f(_ w: UInt32) -> Float { Float(bitPattern: w) }
            b[b.count - 1] = Instance(
                rect: [f(words[0]), f(words[1]), f(words[2]), f(words[3])],
                radii: [f(words[4]), f(words[5]), f(words[6]), f(words[7])],
                fill: [f(words[8]), f(words[9]), f(words[10]), f(words[11])],
                border: [f(words[12]), f(words[13]), f(words[14]), f(words[15])],
                params: [f(words[16]), f(words[17]), f(words[18]), f(words[19])],
                uv: [f(words[20]), f(words[21]), f(words[22]), f(words[23])],
                clip: [f(words[24]), f(words[25]), f(words[26]), f(words[27])],
                fade: [words[28], words[29], words[30], words[31]]
            )
            #expect(!sameInstances(a[...], b[...]), "missed change in word \(word)")
        }
    }

    @Test("batches break only where the bound page changes")
    func batchesBreakOnlyWhereTheBoundPageChanges() {
        let gpu = Gpu.headless()
        let (device, queue) = (gpu.metalDevice, gpu.metalQueue)
        let renderer = Renderer(device, OFFSCREEN_FORMAT)
        var atlas = TextSystem().atlas
        func withKind(_ kind: Float, _ page: Float) -> Instance {
            var sq = uploadSquare(0.0, 0.0)
            sq.params = [page, kind, 0.0, 0.0]
            return sq
        }
        func glyph(_ page: Float) -> Instance {
            var sq = uploadSquare(0.0, 0.0)
            sq.params = [0.0, KIND_GLYPH, page, 0.0]
            return sq
        }
        let instances = [
            uploadSquare(0.0, 0.0),
            withKind(KIND_IMAGE, 1.0),
            uploadSquare(0.0, 0.0),
            withKind(KIND_SHADOW, 0.0),
            glyph(2.0),
            withKind(KIND_GRADIENT, 0.0),
            glyph(0.0),
            uploadSquare(0.0, 0.0),
            withKind(KIND_IMAGE, 1.0),
        ]
        renderer.prepare(device, queue, &atlas, instances, UPLOAD_TEST_SIZE)
        struct BatchItem: Equatable {
            let range: Range<UInt32>
            let kind: String
            let page: Int
        }
        let batches: [BatchItem] = renderer.imageBatches.map { range, bind in
            switch bind {
            case .image(let p): return BatchItem(range: range, kind: "i", page: p)
            case .glyph(let p): return BatchItem(range: range, kind: "g", page: p)
            }
        }
        #expect(batches == [
            BatchItem(range: 0..<1, kind: "i", page: 0),
            BatchItem(range: 1..<4, kind: "i", page: 1),
            BatchItem(range: 4..<6, kind: "g", page: 1),
            BatchItem(range: 6..<8, kind: "i", page: 0),
            BatchItem(range: 8..<9, kind: "i", page: 1),
        ])
    }

    @Test("only a changed params or length batches again")
    func onlyAChangedParamsOrLengthBatchesAgain() {
        let gpu = Gpu.headless()
        let (device, queue) = (gpu.metalDevice, gpu.metalQueue)
        let renderer = Renderer(device, OFFSCREEN_FORMAT)
        var atlas = TextSystem().atlas
        struct PageItem: Equatable {
            let range: Range<UInt32>
            let isPage1: Bool
        }
        struct EffItem: Equatable {
            let at: UInt32
            let x: Float
        }
        func makeFrame(_ x: Float, _ page: Float, _ extra: Int) -> [Instance] {
            var img = uploadSquare(x, 8.0)
            img.params = [page, KIND_IMAGE, 0.0, 0.0]
            var eff = uploadSquare(x, 16.0)
            eff.params = [0.0, KIND_EFFECT, 0.0, 0.0]
            var list = [uploadSquare(x, 0.0), img, eff]
            for i in 0..<extra {
                list.append(uploadSquare(Float(i), 24.0))
            }
            return list
        }
        func runPrepare(_ list: [Instance]) -> (UInt64, [PageItem], [EffItem]) {
            let runs = renderer.uploads.batchRuns
            renderer.prepare(device, queue, &atlas, list, UPLOAD_TEST_SIZE)
            let pages = renderer.imageBatches.map { r, b -> PageItem in
                if case .image(1) = b { return PageItem(range: r, isPage1: true) }
                return PageItem(range: r, isPage1: false)
            }
            let effs = renderer.effects.map { EffItem(at: $0.0, x: $0.1.rect[0]) }
            return (renderer.uploads.batchRuns - runs, pages, effs)
        }

        let r1 = runPrepare(makeFrame(0.0, 1.0, 0))
        #expect(r1.0 == 1 && r1.1.count == 2 && r1.2 == [EffItem(at: 2, x: 0.0)])

        let r2 = runPrepare(makeFrame(5.0, 1.0, 0))
        #expect(r2.0 == 0 && r2.1.count == 2 && r2.2 == [EffItem(at: 2, x: 5.0)])

        let r3 = runPrepare(makeFrame(5.0, 0.0, 0))
        #expect(r3.0 == 1 && r3.1 == [PageItem(range: 0..<3, isPage1: false)] && r3.2 == [EffItem(at: 2, x: 5.0)])

        let r4 = runPrepare(makeFrame(5.0, 0.0, 2))
        #expect(r4.0 == 1)

        renderer.uploads.forgetInstances()
        let r5 = runPrepare(makeFrame(5.0, 0.0, 2))
        #expect(r5.0 == 1)

        let r6 = runPrepare([])
        #expect(r6.0 == 1 && r6.1.isEmpty && r6.2.isEmpty)
    }
}
#endif
