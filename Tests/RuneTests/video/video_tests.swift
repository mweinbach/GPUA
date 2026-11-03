// Tests ported from: crates/rune/src/video/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Testing
@testable import Rune
#if canImport(Darwin)
import Darwin
#endif

private func sampleMeta() -> VideoMeta {
    VideoMeta(duration: 1.0, size: (64, 36), frame: 0.25)
}

#if os(macOS)
private final class RefusedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count: Int = 0
    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
    func load() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

/// Local HTTP 206 byte-range server requiring `Authorization: Bearer let-me-in`.
private func serveWithAuth(_ body: [UInt8], _ contentType: String) -> (String, RefusedCounter) {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    precondition(fd >= 0, "socket() failed")
    var yes: Int32 = 1
    _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = 0
    addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let bindRes = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    precondition(bindRes == 0, "bind() failed")
    precondition(listen(fd, 16) == 0, "listen() failed")

    var bound = sockaddr_in()
    var boundLen = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &bound) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            getsockname(fd, sa, &boundLen)
        }
    }
    let port = UInt16(bigEndian: bound.sin_port)
    let url = "http://127.0.0.1:\(port)/media/clip"
    let refused = RefusedCounter()

    let serverThread = Thread {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 { return }
            var noSigPipe: Int32 = 1
            _ = setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            let workerBody = body
            let workerRefused = refused
            let workerThread = Thread {
                defer { close(client) }
                var pending = [UInt8]()
                var scratch = [UInt8](repeating: 0, count: 4096)

                func readLine() -> String? {
                    while true {
                        if let nl = pending.firstIndex(of: 0x0a) {
                            let lineBytes = Array(pending[0...nl])
                            pending.removeFirst(nl + 1)
                            return String(decoding: lineBytes, as: UTF8.self)
                        }
                        let n = scratch.withUnsafeMutableBytes { buf in
                            recv(client, buf.baseAddress, buf.count, 0)
                        }
                        if n <= 0 {
                            if pending.isEmpty { return nil }
                            let rest = pending
                            pending.removeAll()
                            return String(decoding: rest, as: UTF8.self)
                        }
                        pending.append(contentsOf: scratch[0..<n])
                    }
                }

                func writeAll(_ bytes: [UInt8]) -> Bool {
                    var offset = 0
                    while offset < bytes.count {
                        let sent = bytes.withUnsafeBytes { raw in
                            send(client, raw.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
                        }
                        if sent <= 0 { return false }
                        offset += sent
                    }
                    return true
                }

                while true {
                    guard let reqLine = readLine(), !reqLine.isEmpty else { return }
                    let isHead = reqLine.uppercased().hasPrefix("HEAD ")
                    var authorized = false
                    var rangeHeader: String? = nil
                    while true {
                        guard let rawHdr = readLine() else { return }
                        let hdr = rawHdr.trimmingCharacters(in: .whitespacesAndNewlines)
                        if hdr.isEmpty { break }
                        if let colon = hdr.firstIndex(of: ":") {
                            let name = hdr[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                            let value = hdr[hdr.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                            if name == "authorization" {
                                authorized = (value == "Bearer let-me-in")
                            } else if name == "range", value.hasPrefix("bytes=") {
                                rangeHeader = String(value.dropFirst("bytes=".count))
                            }
                        }
                    }

                    if !authorized {
                        workerRefused.increment()
                        if !writeAll(Array("HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\n\r\n".utf8)) {
                            return
                        }
                        continue
                    }

                    let totalLen = workerBody.count
                    var start = 0
                    var end = max(totalLen - 1, 0)
                    if let r = rangeHeader, let dash = r.firstIndex(of: "-") {
                        if let a = Int(r[..<dash]) {
                            start = min(max(a, 0), max(totalLen - 1, 0))
                            let bStr = String(r[r.index(after: dash)...])
                            if let b = Int(bStr) {
                                end = min(max(b, start), max(totalLen - 1, 0))
                            }
                        }
                    }
                    let sliceLen = totalLen == 0 ? 0 : (end + 1 - start)
                    let respHead =
                        "HTTP/1.1 206 Partial Content\r\n" +
                        "Content-Type: \(contentType)\r\n" +
                        "Accept-Ranges: bytes\r\n" +
                        "Content-Range: bytes \(start)-\(end)/\(totalLen)\r\n" +
                        "Content-Length: \(sliceLen)\r\n\r\n"
                    if !writeAll(Array(respHead.utf8)) { return }
                    if !isHead && sliceLen > 0 {
                        if !writeAll(Array(workerBody[start...end])) { return }
                    }
                }
            }
            workerThread.start()
        }
    }
    serverThread.start()
    return (url, refused)
}

private func renderSurface(_ gpu: Gpu, _ pipe: SurfaceRenderer, _ surface: NativeSurface) -> [UInt8] {
    let draw = SurfaceDraw(
        surface: surface,
        fit: .fit,
        beforeInstance: 0,
        rect: [0.0, 0.0, 64.0, 36.0]
    )
    pipe.prepare(gpu.metalDevice, gpu.metalQueue, [draw], (64, 36))
    let target = Offscreen(gpu.metalDevice, 64, 36)
    let encoder = gpu.metalDevice.createCommandEncoder()
    let pass = encoder.beginRenderPass(
        colorAttachments: [MetalColorAttachment(view: target.view, load: .clear(r: 0, g: 0, b: 0, a: 0))]
    )
    if !pipe.isEmpty() {
        pipe.draw(pass, 0)
    }
    pass.end()
    target.copy(encoder)
    pipe.submit(gpu.metalQueue, encoder)
    return target.read(gpu.metalDevice)
}

private func centreRGB(_ p: [UInt8]) -> [UInt8] {
    let i = (18 * 64 + 32) * 4
    return [p[i], p[i + 1], p[i + 2]]
}

private func expectNearRGB(_ got: [UInt8], _ want: [UInt8], _ what: String) {
    for c in 0..<3 {
        #expect(abs(Int(got[c]) - Int(want[c])) <= 24, "\(what): got \(got), want ~\(want)")
    }
}
#endif

@Suite("Video and Audio Player Tests", .serialized)
struct VideoPlayerTests {
    @Test("new videos are muted, paused and loading")
    func newVideosAreMutedPausedAndLoading() {
        let v = Video.file("missing.mp4")
        #expect(v.muted())
        #expect(!v.looping())
        #expect(!v.isPlaying())
        #expect(v.rate() == 1.0)
        #expect(v.time() == 0.0)
        #expect(v.duration() == nil)
        #expect(v.naturalSize() == nil)
        #expect(!v.isAudio())
        #if os(macOS)
        #expect(v.state() == .loading)
        #endif
        #expect(v.source() == .file("missing.mp4"))
    }

    @Test("sources tell URLs from paths")
    func sourcesTellUrlsFromPaths() {
        #expect(MediaSource.from("https://example.com/a.mp3") == .url("https://example.com/a.mp3"))
        #expect(MediaSource.from("file:///tmp/a.wav") == .url("file:///tmp/a.wav"))
        #expect(MediaSource.from("sounds/a.m4a") == .file("sounds/a.m4a"))
        #expect(MediaSource.from(URL(fileURLWithPath: "a.mp3")).isFilePathEnding(with: "a.mp3"))
    }

    @Test("audio starts unmuted with no size")
    func audioStartsUnmutedWithNoSize() {
        let a = Player.audio("missing.m4a")
        #expect(a.isAudio())
        #expect(!a.muted(), "audio is audible by default")
        #expect(a.naturalSize() == nil)
    }

    @Test("webm video fails at once")
    func webmVideoFailsAtOnce() {
        let a = Player.url("https://example.com/clips/tap.webm?v=2")
        guard case .failed(let message) = a.state() else {
            Issue.record("expected failed state, got \(a.state())")
            return
        }
        #if os(macOS)
        #expect(message.contains(".webm isn't supported on macOS"), "\(message)")
        #else
        #expect(message == "video playback isn't supported on this platform yet")
        #endif
        a.play()
        #expect(!a.isPlaying(), "a failed clip doesn't play")
    }

    @Test("the waker hears each state change once")
    func theWakerHearsEachStateChangeOnce() {
        let a = Player.audio("missing.m4a")
        let lock = NSLock()
        nonisolated(unsafe) var calls = 0
        a.setWaker {
            lock.lock()
            calls += 1
            lock.unlock()
        }
        a.shared.settle(windows: false)
        #expect(calls == 0, "nothing changed yet")
        a.shared.ctlLock.withLock {
            a.shared.ctl.open(.success(VideoMeta(duration: 2.0, size: nil, frame: 1.0 / 30.0)))
        }
        a.shared.settle(windows: false)
        a.shared.settle(windows: false)
        #expect(calls == 1)
        a.shared.ctlLock.withLock {
            a.shared.ctl.fail("gone")
        }
        a.shared.settle(windows: false)
        #expect(calls == 2)
    }

    @Test("a waker set after a failure hears it once")
    func aWakerSetAfterAFailureHearsItOnce() {
        let a = Player.url("tap.ogv")
        if case .failed = a.shared.snapshot().state {
            // expected
        } else {
            Issue.record("expected failed state")
        }
        let lock = NSLock()
        nonisolated(unsafe) var calls = 0
        a.setWaker {
            lock.lock()
            calls += 1
            lock.unlock()
        }
        a.shared.settle(windows: true)
        a.play()
        #expect(calls == 1)
    }

    @Test("a seek before the clip opens is clamped when it does")
    func aSeekBeforeTheClipOpensIsClampedWhenItDoes() {
        let v = Video.file("missing.mp4")
        v.seek(30.0)
        #expect(v.shared.ctlLock.withLock { v.shared.ctl.seek } == 30.0, "no duration yet")
        v.shared.ctlLock.withLock {
            v.shared.ctl.open(.success(sampleMeta()))
        }
        let (sk, tm) = v.shared.ctlLock.withLock { (v.shared.ctl.seek, v.shared.ctl.time) }
        #expect(sk == 1.0 && tm == 1.0)
    }

    @Test("handle edits are shared and validated")
    func handleEditsAreSharedAndValidated() {
        let v = Video.url("https://example.com/clip.mp4")
        let other = v.clone()
        other.setRate(2.0)
        other.setRate(-1.0)
        other.setRate(.nan)
        other.setLooping(true)
        other.setMuted(false)
        other.seek(-3.0)
        #expect(v.rate() == 2.0)
        #expect(v.looping())
        #expect(!v.muted())
        #expect(v.time() == 0.0)
        v.play()
        #if os(macOS)
        #expect(other.isPlaying())
        #expect(v.state() == .loading)
        #endif
    }

    @Test("state follows open, play, end and failure")
    func stateFollowsOpenPlayEndAndFailure() {
        var c = VideoControl()
        c.open(.success(sampleMeta()))
        #expect(c.state() == .ready)
        #expect(c.duration == 1.0)
        #expect(c.size?.0 == 64 && c.size?.1 == 36)
        c.playing = true
        #expect(c.state() == .playing)
        c.advanceVirtual(10.0)
        c.advanceVirtual(10.5)
        #expect(c.time == 0.5)
        let generation = c.generation
        c.advanceVirtual(11.25)
        #expect(c.time == 1.0 && !c.playing && c.ended)
        #expect(c.state() == .ended)
        #expect(c.generation > generation, "ending re-runs views")
        c.fail("boom")
        c.fail("second")
        #expect(c.state() == .failed("boom"))
    }

    @Test("virtual time loops, rates and seeks")
    func virtualTimeLoopsRatesAndSeeks() {
        var c = VideoControl()
        c.open(.success(sampleMeta()))
        c.playing = true
        c.looping = true
        c.rate = 2.0
        c.advanceVirtual(0.0)
        c.advanceVirtual(0.6)
        #expect(abs(c.time - 0.2) < 1e-9, "1.2 s wraps to 0.2: \(c.time)")
        #expect(c.playing)
        c.seek = 0.75
        c.anchor = nil
        c.advanceVirtual(5.0)
        #expect(c.time == 0.75)
        c.advanceVirtual(5.1)
        #expect(abs(c.time - 0.95) < 1e-9)
        c.playing = false
        c.advanceVirtual(9.0)
        #expect(abs(c.time - 0.95) < 1e-9)
    }

    @Test("playing after the end restarts from zero")
    func playingAfterTheEndRestartsFromZero() {
        let v = Video.file("missing.mp4")
        v.shared.ctlLock.withLock {
            v.shared.ctl.open(.success(sampleMeta()))
            v.shared.ctl.time = 1.0
            v.shared.ctl.ended = true
        }
        #expect(v.state() == .ended)
        v.play()
        let (sk, pl, en) = v.shared.ctlLock.withLock { (v.shared.ctl.seek, v.shared.ctl.playing, v.shared.ctl.ended) }
        #expect(sk == 0.0)
        #expect(pl && !en)
    }

    @Test("display positions loop or end")
    func displayPositionsLoopOrEnd() {
        var c = VideoControl()
        c.open(.success(sampleMeta()))
        c.playing = true
        let r0 = c.observe(0.4, atEnd: false)
        #expect(!r0)
        #expect(c.time == 0.4)
        c.looping = true
        let r1 = c.observe(1.0, atEnd: true)
        #expect(r1, "looping restarts the player")
        #expect(c.time == 0.0 && c.playing)
        c.looping = false
        let r2 = c.observe(1.2, atEnd: true)
        #expect(!r2)
        #expect(c.time == 1.0 && !c.playing && c.state() == .ended)
    }

    @Test("frames snap to whole frames inside the clip")
    func framesSnapToWholeFramesInsideTheClip() {
        let m = sampleMeta()
        #expect(m.frames() == 4)
        #expect(m.frameIndex(0.0) == 0)
        #expect(m.frameIndex(0.2499) == 0)
        #expect(m.frameIndex(0.25) == 1)
        #expect(m.frameIndex(1.0) == 3, "the end shows the last frame")
        #expect(m.frameIndex(-1.0) == 0)
        #expect(m.frameTime(1) == 0.375)
        #expect(m.frameTime(3) == 0.875)
    }

    @Test("the last handle or element frees the player")
    func theLastHandleOrElementFreesThePlayer() {
        weak var weakShared: VideoShared? = nil
        var inTree: NativeSurface? = nil
        do {
            let v = Video.file("missing.mp4")
            weakShared = v.shared
            inTree = v.surface().clone()
        }
        #expect(weakShared != nil)
        inTree = nil
        _ = inTree
        #expect(weakShared == nil)
    }

    @Test("failures draw a placeholder and stop drawing")
    func failuresDrawAPlaceholderAndStopDrawing() {
        let v = Video.file("/nonexistent/clip.mp4")
        let wake = LiveWake {}
        let p0 = v.surface().pullVideo(.virtual(0.0), wake)!
        #expect(!p0.active)
        guard case .failed(let message) = v.state() else {
            Issue.record("expected failed state, got \(v.state())")
            return
        }
        #if os(macOS)
        #expect(message.contains("no such file"), "\(message)")
        #else
        #expect(message == "video playback isn't supported on this platform yet")
        #endif
        let frame = v.surface().latest()
        #expect(frame != nil, "placeholder frame")
        #expect(frame?.size == [32, 18] && frame?.format == .bgra)
        let p1 = v.surface().pullVideo(.virtual(0.1), wake)!
        #expect(!p1.active, "a failed video requests no frames")
        #expect(p1.generation == p0.generation)
    }

    @Test("requests carry headers without printing their values")
    func requestsCarryHeadersWithoutPrintingTheirValues() {
        let request = Player.request("https://example.com/media/a.m4a")
            .header("Authorization", "Bearer secret-token")
            .header("authorization", "Bearer newer-token")
            .header("X-Board", "1")
        let printed = String(reflecting: request)
        #expect(printed.contains("Authorization") || printed.contains("authorization"), "\(printed)")
        #expect(!printed.contains("token"), "header values never print: \(printed)")
        let a = request.audio()
        #expect(a.isAudio())
        #expect(a.source() == .url("https://example.com/media/a.m4a"))
        #expect(a.shared.headers.count == 2)
        #expect(a.shared.headers[0].0 == "authorization" && a.shared.headers[0].1 == "Bearer newer-token")
        #expect(a.shared.headers[1].0 == "X-Board" && a.shared.headers[1].1 == "1")
        #expect(!String(reflecting: a).contains("token"))
        let v = Player.request("https://example.com/media/a.mp4").header("Authorization", "Bearer t").video()
        #expect(!v.isAudio() && v.muted())
    }

    #if os(macOS)
    @Test("headless audio opens on read and holds time")
    func headlessAudioOpensOnReadAndHoldsTime() {
        videoHeadlessReset()
        let m4aPath = VideoTestFixtures.writeFixture(name: "silence.m4a", base64: VideoTestFixtures.silenceM4ABase64)
        let wavPath = VideoTestFixtures.writeSilenceWav()
        let videoPath = VideoTestFixtures.writeFixture(name: "rgbw.mp4", base64: VideoTestFixtures.rgbwMP4Base64)

        let a = Player.audio(.file(m4aPath))
        a.setMuted(true)
        #expect(a.state() == .ready)
        let d = a.duration()!
        #expect(abs(d - 1.0) < 0.1, "\(d)")
        #expect(a.naturalSize() == nil)
        a.play()
        #expect(a.state() == .playing)
        #expect(a.time() == 0.0)
        a.seek(0.4)
        #expect(a.time() == 0.4)

        let wav = Player.audio(.file(wavPath))
        #expect(abs((wav.duration() ?? 0.0) - 0.5) < 0.01)

        let videoOnly = Player.audio(.file(videoPath))
        if case .failed(let e) = videoOnly.state() {
            #expect(e.contains("no playable audio track"))
        } else {
            Issue.record("expected video-only MP4 opened as audio to fail")
        }
    }

    @Test("headless playback decodes the frame at virtual time")
    func headlessPlaybackDecodesTheFrameAtVirtualTime() {
        let gpu = Gpu.headless()
        let pipe = SurfaceRenderer(gpu.metalDevice, OFFSCREEN_FORMAT)
        let videoPath = VideoTestFixtures.writeFixture(name: "rgbw.mp4", base64: VideoTestFixtures.rgbwMP4Base64)
        let v = Video.file(videoPath)
        let wake = LiveWake {}

        var clock = 0.0
        func step(_ dt: Double) -> Bool {
            clock += dt
            return v.surface().pullVideo(.virtual(clock), wake)?.active ?? false
        }

        _ = step(0.0)
        #expect(v.state() == .ready)
        #expect(v.naturalSize()?.0 == 64 && v.naturalSize()?.1 == 36)
        #expect(abs((v.duration() ?? 0.0) - 1.0) < 1e-3)
        let first = renderSurface(gpu, pipe, v.surface())
        expectNearRGB(centreRGB(first), [255, 0, 0], "first frame")
        _ = step(0.0)
        #expect(!step(0.5), "a paused video requests no frames")
        #expect(renderSurface(gpu, pipe, v.surface()) == first, "deterministic")

        v.play()
        #expect(step(0.0), "playing keeps frames coming")
        #expect(step(0.3))
        #expect(v.state() == .playing)
        #expect(abs(v.time() - 0.3) < 1e-9)
        expectNearRGB(centreRGB(renderSurface(gpu, pipe, v.surface())), [0, 255, 0], "0.3 s")

        _ = step(0.3)
        expectNearRGB(centreRGB(renderSurface(gpu, pipe, v.surface())), [0, 0, 255], "0.6 s")

        _ = step(0.3)
        expectNearRGB(centreRGB(renderSurface(gpu, pipe, v.surface())), [255, 255, 255], "0.9 s")

        _ = step(0.3)
        #expect(v.state() == .ended)
        #expect(v.time() == 1.0)
        expectNearRGB(centreRGB(renderSurface(gpu, pipe, v.surface())), [255, 255, 255], "the end holds the last frame")
        _ = step(0.0)
        #expect(!step(0.1), "an ended video requests no frames")

        v.seek(0.3)
        _ = step(0.0)
        expectNearRGB(centreRGB(renderSurface(gpu, pipe, v.surface())), [0, 255, 0], "seek while paused")

        v.setLooping(true)
        v.setRate(2.0)
        v.play()
        _ = step(0.0)
        _ = step(0.5)
        #expect(abs(v.time() - 0.3) < 1e-9, "0.3 + 2 x 0.5 wraps to 0.3: \(v.time())")
        expectNearRGB(centreRGB(renderSurface(gpu, pipe, v.surface())), [0, 255, 0], "looped")
    }

    @Test("headless audio opens with request headers")
    func headlessAudioOpensWithRequestHeaders() {
        let wavPath = VideoTestFixtures.writeSilenceWav()
        let wavBytes = Array((try? Data(contentsOf: URL(fileURLWithPath: wavPath))) ?? Data())
        let (url, refused) = serveWithAuth(wavBytes, "audio/wav")

        let a = Player.request("\(url).wav").header("Authorization", "Bearer let-me-in").audio()
        #expect(a.state() == .ready)
        #expect(abs((a.duration() ?? 0.0) - 0.5) < 0.01)
        #expect(refused.load() == 0, "every request carried the header")

        let without = Player.audio("\(url)-2.wav")
        if case .failed = without.state() {
            // expected
        } else {
            Issue.record("expected request without Authorization header to fail: \(without.state())")
        }
        #expect(refused.load() > 0)
    }

    @Test("headless audio time follows the virtual clock")
    func headlessAudioTimeFollowsTheVirtualClock() {
        let wavPath = VideoTestFixtures.writeSilenceWav()
        let a = Player.audio(.file(wavPath))
        let lock = NSLock()
        nonisolated(unsafe) var ends = 0
        let clip = a.clone()
        a.setWaker {
            if clip.shared.ctlLock.withLock({ clip.shared.ctl.ended }) {
                lock.lock()
                ends += 1
                lock.unlock()
            }
        }

        videoHeadlessReset()
        var clock = 0.0
        func advance(_ dt: Double) {
            clock += dt
            videoHeadlessFrame(clock)
        }

        a.play()
        advance(0.0)
        advance(0.1)
        #expect(abs(a.time() - 0.1) < 1e-6)
        #expect(a.state() == .playing)

        a.pause()
        advance(0.2)
        #expect(abs(a.time() - 0.1) < 1e-6)

        a.setRate(2.0)
        a.play()
        advance(0.05)
        #expect(abs(a.time() - 0.2) < 1e-6)

        a.seek(0.05)
        #expect(abs(a.time() - 0.05) < 1e-6)
        advance(0.1)
        #expect(abs(a.time() - 0.25) < 1e-6)
        #expect(ends == 0)

        advance(0.5)
        #expect(a.state() == .ended)
        #expect(abs(a.time() - 0.5) < 1e-6)
        #expect(ends == 1, "the waker hears the end once")

        a.setLooping(true)
        a.setRate(1.0)
        a.play()
        advance(0.6)
        #expect(abs(a.time() - 0.1) < 1e-6)
        #expect(a.isPlaying())
    }

    @Test("a new runtime starts the headless clock again")
    func aNewRuntimeStartsTheHeadlessClockAgain() {
        videoHeadlessReset()
        videoHeadlessFrame(5.0)
        let wavPath = VideoTestFixtures.writeSilenceWav()
        let a = Player.audio(.file(wavPath))
        videoHeadlessReset()
        a.play()
        videoHeadlessFrame(0.1)
        #expect(abs(a.time() - 0.1) < 1e-6)
    }

    @Test("preload decodes the first frame before anything draws it")
    func preloadDecodesTheFirstFrameBeforeAnythingDrawsIt() {
        let videoPath = VideoTestFixtures.writeFixture(name: "rgbw.mp4", base64: VideoTestFixtures.rgbwMP4Base64)
        let v = Video.file(videoPath)
        #expect(videoMacosTestPoster(v.shared) == nil)
        videoBackendPreload(v.shared)
        let deadline = Date().addingTimeInterval(10.0)
        while videoMacosTestPoster(v.shared) == nil && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.005)
        }
        #expect(videoMacosTestPoster(v.shared) == true, "the first frame decoded off the main thread")
        v.preload()

        let wavPath = VideoTestFixtures.writeSilenceWav()
        let audio = Player.audio(.file(wavPath))
        videoBackendPreload(audio.shared)
        #expect(videoMacosTestPoster(audio.shared) == nil, "audio has no poster to warm")
    }
    #endif
}

private extension MediaSource {
    func isFilePathEnding(with suffix: String) -> Bool {
        if case .file(let p) = self {
            return p.hasSuffix(suffix)
        }
        return false
    }
}
