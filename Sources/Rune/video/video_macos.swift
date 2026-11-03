// Ported from: crates/rune/src/video/macos.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

//! AVFoundation: AVPlayer + AVPlayerItemVideoOutput for windows, AVAssetImageGenerator for
//! posters and headless frames, and a bare AVPlayer for audio.

/// Paused players that keep a native player (and its decoder) for a quick resume. Older paused
/// players are released; a video's last frame stays on screen and resuming recreates it.
private let PARKED_PLAYERS: Int = 4
/// Posters never need more than this many pixels per side; headless frames keep full size.
private let POSTER_MAX: Double = 1920.0
/// A seek that never lands stops requesting redraws (or ticks) after this long.
private let SEEK_PATIENCE_SECS: Double = 2.0
/// A player item that never becomes ready fails after this long.
private let LOAD_PATIENCE_SECS: Double = 30.0
/// How often playing audio checks for its end, loops and loading.
private let AUDIO_TICK_SECS: TimeInterval = 0.050
/// An audio seek has landed once the player reports a time this close to the target.
private let AUDIO_SEEK_SLOP: Double = 0.25

// PORT NOTE: Transfers an AVFoundation object across thread/task boundaries under explicit caller synchronization.
private struct AVSendableBox<T>: @unchecked Sendable {
    let value: T
}

// PORT NOTE: Synchronized poster slot shared between `VideoShared` and its background poster worker thread.
final class VideoPosters: @unchecked Sendable {
    let lock = LiveLock()
    var want: Double? = nil
    var busy: Bool = false
    /// A video poster and its clip's facts, or (no frame) an audio clip's facts.
    var done: Result<(ByteFrame?, VideoMeta), SurfaceError>? = nil
}

struct VideoPlayerObjects {
    let asset: AVAsset
    let player: AVPlayer
    let item: AVPlayerItem
    /// `nil` for audio.
    let output: AVPlayerItemVideoOutput?
}

// PORT NOTE: Created, reconciled, and paused on the main thread; `deinit` dispatches pause/release to the main queue if dropped off-main.
final class VideoNativePlayer: @unchecked Sendable {
    var objects: VideoPlayerObjects?
    var rate: Float = 0.0
    var muted: Bool = false
    var ready: Bool = false
    let created: RuneInstant = .now()
    var seeking: (RuneInstant, Double)? = nil
    var orient: SurfaceOrient = .UP
    var shown: Double? = nil
    var hold: Double? = nil

    init(_ objects: VideoPlayerObjects) {
        self.objects = objects
    }

    deinit {
        guard let objects = self.objects else { return }
        self.objects = nil
        if Thread.isMainThread {
            objects.player.pause()
        } else {
            let boxed = AVSendableBox(value: objects)
            DispatchQueue.main.async {
                boxed.value.player.pause()
            }
        }
    }
}

// PORT NOTE: Guarded by `VideoShared.nativeLock` (`VideoTryLock`), matching `unsafe impl Send for Native` in `video/macos.rs`.
final class VideoBackendNative: @unchecked Sendable {
    /// Headless decodes reuse one generator.
    var generator: AVAssetImageGenerator? = nil
    var player: VideoNativePlayer? = nil
    let posters = VideoPosters()
    var posterStarted: Bool = false
    var posterDue: Bool = false

    init() {}
}

private let parkedLock = LiveLock()
// PORT NOTE: Guarded by `parkedLock`, matching `static PARKED: Mutex<Vec<Weak<Shared>>>` in `video/macos.rs`.
nonisolated(unsafe) private var parkedList: [WeakVideoShared] = []

private let audioListLock = LiveLock()
// PORT NOTE: Guarded by `audioListLock`, matching `static AUDIO: Mutex<Vec<Weak<Shared>>>` in `video/macos.rs`.
nonisolated(unsafe) private var audioList: [WeakVideoShared] = []

private let tickerStateLock = LiveLock()
// PORT NOTE: Guarded by `tickerStateLock`, matching `AUDIO_BUSY` and `TICKING` atomics in `video/macos.rs`.
nonisolated(unsafe) private var audioBusy: Bool = false
// PORT NOTE: Guarded by `tickerStateLock`, matching `TICKING` atomic in `video/macos.rs`.
nonisolated(unsafe) private var audioTicking: Bool = false

private func onMain(_ work: @escaping @Sendable () -> Void) {
    DispatchQueue.main.async(execute: work)
}

/// The source's lowercase extension, if any.
func videoMacosExtension(_ source: MediaSource) -> String? {
    let name: String
    switch source {
    case .file(let path):
        let trimmed = path.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        guard !trimmed.isEmpty else { return nil }
        let last = (trimmed as NSString).lastPathComponent
        if last.isEmpty || last == "/" || last == "." || last == ".." {
            return nil
        }
        name = last
    case .url(let url):
        let withoutQuery = url.split(whereSeparator: { $0 == "?" || $0 == "#" }).first.map(String.init) ?? ""
        let pathPart: String
        if let schemeRange = withoutQuery.range(of: "://") {
            let rest = withoutQuery[schemeRange.upperBound...]
            if let slashIdx = rest.firstIndex(of: "/") {
                pathPart = String(rest[rest.index(after: slashIdx)...])
            } else {
                pathPart = ""
            }
        } else {
            pathPart = withoutQuery
        }
        if let lastSlash = pathPart.lastIndex(of: "/") {
            name = String(pathPart[pathPart.index(after: lastSlash)...])
        } else {
            name = pathPart
        }
    }
    guard let dot = name.lastIndex(of: ".") else { return nil }
    let ext = String(name[name.index(after: dot)...]).lowercased()
    return ext.isEmpty ? nil : ext
}

/// AVFoundation has no Ogg, WebM or Matroska demuxer; fail at once rather than wait on a load
/// that can only fail.
private func unsupportedFormat(_ source: MediaSource, _ kind: VideoKind) -> String? {
    guard let ext = videoMacosExtension(source) else { return nil }
    switch ext {
    case "ogg", "oga", "ogv", "opus", "spx", "webm", "mkv", "mka":
        return ".\(ext) isn't supported on macOS (AVFoundation can't read it); use mp3, m4a, wav, mp4 or mov"
    default:
        return nil
    }
}

func videoBackendCreated(_ shared: VideoShared) {
    if let err = unsupportedFormat(shared.source, shared.kind) {
        shared.ctlLock.withLock {
            shared.ctl.fail(err)
        }
        return
    }
    if shared.kind == .audio {
        audioListLock.withLock {
            audioList.removeAll { $0.value == nil }
            audioList.append(WeakVideoShared(value: shared))
        }
        if videoPlaybackEnabled() {
            loadAudio(shared)
        }
    }
}

/// The window loop is starting: load audio clips made before it.
func videoBackendEnable() {
    let clips: [VideoShared] = audioListLock.withLock {
        audioList.removeAll { $0.value == nil }
        return audioList.compactMap { $0.value }
    }
    for clip in clips {
        loadAudio(clip)
        onMain {
            videoBackendDrive(clip)
        }
    }
}

private func loadAudio(_ shared: VideoShared) {
    shared.nativeLock.withLock {
        let alreadyOpened = shared.ctlLock.withLock { shared.ctl.opened() }
        if !shared.native.posterStarted && !alreadyOpened {
            requestPoster(shared, shared.native, 0.0)
        }
    }
}

private func resolveURL(_ source: MediaSource) -> Result<URL, SurfaceError> {
    switch source {
    case .file(let path):
        if !FileManager.default.fileExists(atPath: path) {
            return .failure(SurfaceError("no such file: \(path)"))
        }
        let absURL = URL(fileURLWithPath: path).standardizedFileURL
        return .success(absURL)
    case .url(let raw):
        guard let u = URL(string: raw), u.scheme != nil else {
            return .failure(SurfaceError("invalid URL: \(raw)"))
        }
        return .success(u)
    }
}

private func makeAsset(_ source: MediaSource, _ headers: [(String, String)]) -> Result<AVURLAsset, SurfaceError> {
    switch resolveURL(source) {
    case .failure(let err):
        return .failure(err)
    case .success(let u):
        if headers.isEmpty {
            return .success(AVURLAsset(url: u))
        }
        var fields: [String: String] = [:]
        for (name, value) in headers {
            fields[name] = value
        }
        let options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": fields]
        return .success(AVURLAsset(url: u, options: options))
    }
}

private func cmSeconds(_ t: CMTime) -> Double {
    let s = CMTimeGetSeconds(t)
    return s.isFinite ? s : 0.0
}

private func cmFromSeconds(_ seconds: Double) -> CMTime {
    CMTimeMakeWithSeconds(seconds, preferredTimescale: 600_000)
}

private func cmZero() -> CMTime {
    CMTime(value: 0, timescale: 1)
}

/// Blocks until the asset's tracks and duration load (a network fetch for URLs).
private func loadMeta(_ asset: AVURLAsset, _ kind: VideoKind) -> Result<VideoMeta, SurfaceError> {
    let boxedAsset = AVSendableBox(value: asset)
    let sema = DispatchSemaphore(value: 0)
    // PORT NOTE: Single-assignment result written before `sema.signal()` and read after `sema.wait()`.
    final class BoxResult: @unchecked Sendable {
        var value: Result<VideoMeta, SurfaceError> = .failure(SurfaceError("asset load cancelled"))
    }
    let out = BoxResult()
    Task.detached {
        let a = boxedAsset.value
        do {
            if kind == .audio {
                let tracks = try await a.loadTracks(withMediaType: .audio)
                guard !tracks.isEmpty else {
                    out.value = .failure(SurfaceError("no playable audio track (unreachable, or a format AVFoundation can't read)"))
                    sema.signal()
                    return
                }
                let dur = try await a.load(.duration)
                out.value = .success(VideoMeta(duration: cmSeconds(dur), size: nil, frame: 1.0 / 30.0))
                sema.signal()
                return
            } else {
                let tracks = try await a.loadTracks(withMediaType: .video)
                guard let track = tracks.first else {
                    out.value = .failure(SurfaceError("no playable video track"))
                    sema.signal()
                    return
                }
                let (size, t, minDur, nominal, dur) = try await (
                    track.load(.naturalSize),
                    track.load(.preferredTransform),
                    track.load(.minFrameDuration),
                    track.load(.nominalFrameRate),
                    a.load(.duration)
                )
                let w = abs(Double(size.width) * Double(t.a) + Double(size.height) * Double(t.c)).rounded()
                let h = abs(Double(size.width) * Double(t.b) + Double(size.height) * Double(t.d)).rounded()
                let minS = cmSeconds(minDur)
                let nomD = Double(nominal)
                let frame = minS > 0.0 ? minS : (nomD > 0.0 ? 1.0 / nomD : 1.0 / 30.0)
                if w < 1.0 || h < 1.0 {
                    out.value = .failure(SurfaceError("video track has no size"))
                } else {
                    out.value = .success(VideoMeta(duration: cmSeconds(dur), size: (UInt32(w), UInt32(h)), frame: frame))
                }
                sema.signal()
            }
        } catch {
            if kind == .audio {
                out.value = .failure(SurfaceError("no playable audio track: \(error.localizedDescription)"))
            } else {
                out.value = .failure(SurfaceError("no playable video track: \(error.localizedDescription)"))
            }
            sema.signal()
        }
    }
    sema.wait()
    return out.value
}

private func loadOrient(_ asset: AVAsset) -> SurfaceOrient {
    let boxedAsset = AVSendableBox(value: asset)
    let sema = DispatchSemaphore(value: 0)
    // PORT NOTE: Single-assignment orientation written before `sema.signal()` and read after `sema.wait()`.
    final class BoxOrient: @unchecked Sendable {
        var value: SurfaceOrient = .UP
    }
    let out = BoxOrient()
    Task.detached {
        if let tracks = try? await boxedAsset.value.loadTracks(withMediaType: .video),
           let track = tracks.first,
           let t = try? await track.load(.preferredTransform) {
            out.value = SurfaceOrient.fromTransform(Double(t.a), Double(t.b), Double(t.c), Double(t.d))
        }
        sema.signal()
    }
    sema.wait()
    return out.value
}

private func makeGenerator(_ asset: AVURLAsset, max maxDim: Double?) -> AVAssetImageGenerator {
    let g = AVAssetImageGenerator(asset: asset)
    g.appliesPreferredTrackTransform = true
    g.requestedTimeToleranceBefore = cmZero()
    g.requestedTimeToleranceAfter = cmZero()
    if let m = maxDim {
        g.maximumSize = CGSize(width: m, height: m)
    }
    return g
}

/// Draws a decoded image into sRGB BGRA bytes (opaque, so premultiplied equals straight).
private func cgImageToBGRA(_ image: CGImage) -> Result<ByteFrame, SurfaceError> {
    let w = image.width
    let h = image.height
    if w == 0 || h == 0 {
        return .failure(SurfaceError("decoded an empty frame"))
    }
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
    let ok: Bool = bytes.withUnsafeMutableBytes { rawBuf in
        guard let base = rawBuf.baseAddress,
              let ctx = CGContext(
                  data: base,
                  width: w,
                  height: h,
                  bitsPerComponent: 8,
                  bytesPerRow: w * 4,
                  space: space,
                  bitmapInfo: bitmapInfo
              )
        else {
            return false
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }
    guard ok else {
        return .failure(SurfaceError("CGBitmapContextCreate failed"))
    }
    return .success(ByteFrame(
        width: UInt32(w),
        height: UInt32(h),
        format: .bgra,
        color: ColorInfo(matrix: .bt709, transfer: .srgb),
        planes: [bytes, []]
    ))
}

private func generateImage(_ generator: AVAssetImageGenerator, _ at: Double) -> Result<ByteFrame, SurfaceError> {
    let boxedGen = AVSendableBox(value: generator)
    let sema = DispatchSemaphore(value: 0)
    // PORT NOTE: Single-assignment CGImage result written before `sema.signal()` and read after `sema.wait()`.
    final class BoxImage: @unchecked Sendable {
        var value: Result<CGImage, SurfaceError> = .failure(SurfaceError("image generation cancelled"))
    }
    let out = BoxImage()
    let targetTime = cmFromSeconds(at)
    Task.detached {
        do {
            let (cgImg, _) = try await boxedGen.value.image(at: targetTime)
            out.value = .success(cgImg)
        } catch {
            out.value = .failure(SurfaceError(error.localizedDescription))
        }
        sema.signal()
    }
    sema.wait()
    switch out.value {
    case .failure(let err):
        return .failure(err)
    case .success(let cgImg):
        return cgImageToBGRA(cgImg)
    }
}

private func openAssetAndMeta(
    _ source: MediaSource,
    _ headers: [(String, String)],
    _ kind: VideoKind
) -> Result<(AVURLAsset, VideoMeta), SurfaceError> {
    switch makeAsset(source, headers) {
    case .failure(let err):
        return .failure(err)
    case .success(let asset):
        switch loadMeta(asset, kind) {
        case .failure(let err):
            return .failure(err)
        case .success(let meta):
            return .success((asset, meta))
        }
    }
}

func videoBackendProbe(
    _ native: inout VideoBackendNative,
    _ source: MediaSource,
    _ headers: [(String, String)],
    _ kind: VideoKind
) -> Result<VideoMeta, SurfaceError> {
    switch openAssetAndMeta(source, headers, kind) {
    case .failure(let err):
        return .failure(err)
    case .success(let (asset, meta)):
        if kind == .video {
            native.generator = makeGenerator(asset, max: nil)
        }
        return .success(meta)
    }
}

func videoBackendDecode(
    _ native: inout VideoBackendNative,
    _ source: MediaSource,
    _ headers: [(String, String)],
    _ at: Double
) -> Result<ByteFrame, SurfaceError> {
    if native.generator == nil {
        switch makeAsset(source, headers) {
        case .failure(let err):
            return .failure(err)
        case .success(let asset):
            native.generator = makeGenerator(asset, max: nil)
        }
    }
    guard let gen = native.generator else {
        return .failure(SurfaceError("missing AVAssetImageGenerator"))
    }
    return generateImage(gen, at)
}

/// A clip's frame at `at` upright (as posters and headless runs show it), and as its buffer
/// stores it (as the player hands it out) with how that turns upright.
func videoTestFrames(_ source: MediaSource, _ at: Double) -> Result<(ByteFrame, ByteFrame, SurfaceOrient), SurfaceError> {
    switch makeAsset(source, []) {
    case .failure(let err):
        return .failure(err)
    case .success(let asset):
        let uprightGen = makeGenerator(asset, max: nil)
        let rawGen = makeGenerator(asset, max: nil)
        rawGen.appliesPreferredTrackTransform = false
        switch generateImage(uprightGen, at) {
        case .failure(let err):
            return .failure(err)
        case .success(let upright):
            switch generateImage(rawGen, at) {
            case .failure(let err):
                return .failure(err)
            case .success(let raw):
                return .success((upright, raw, loadOrient(asset)))
            }
        }
    }
}

/// Whether a poster decode has landed, and with a picture.
func videoMacosTestPoster(_ shared: VideoShared) -> Bool? {
    shared.nativeLock.withLock {
        shared.native.posters.lock.withLock {
            guard let done = shared.native.posters.done else { return nil }
            if case .success(let (frame, _)) = done {
                return frame != nil
            }
            return false
        }
    }
}

func videoBackendPreload(_ shared: VideoShared) {
    shared.nativeLock.withLock {
        let state = shared.ctlLock.withLock { (shared.ctl.failed != nil, shared.ctl.time) }
        if shared.kind == .audio || shared.native.player != nil || shared.native.posterStarted || state.0 {
            return
        }
        shared.native.posterDue = true
        requestPoster(shared, shared.native, state.1)
    }
}

private func requestPoster(_ shared: VideoShared, _ native: VideoBackendNative, _ at: Double) {
    native.posterStarted = true
    let shouldSpawn: Bool = native.posters.lock.withLock {
        native.posters.want = at
        if native.posters.busy {
            return false
        }
        native.posters.busy = true
        return true
    }
    guard shouldSpawn else { return }

    let posters = native.posters
    let weakClip = WeakVideoShared(value: shared)
    let source = shared.source
    let headers = shared.headers
    let kind = shared.kind

    let thread = Thread {
        var opened: (AVAssetImageGenerator?, VideoMeta)? = nil
        while true {
            let nextAt: Double? = posters.lock.withLock {
                let w = posters.want
                posters.want = nil
                if w == nil {
                    posters.busy = false
                }
                return w
            }
            guard let targetAt = nextAt else { return }
            guard weakClip.value != nil else { return }

            let result: Result<(ByteFrame?, VideoMeta), SurfaceError> = autoreleasepool {
                if opened == nil {
                    switch openAssetAndMeta(source, headers, kind) {
                    case .failure(let err):
                        return .failure(err)
                    case .success(let (asset, meta)):
                        let gen = (kind == .video) ? makeGenerator(asset, max: POSTER_MAX) : nil
                        opened = (gen, meta)
                    }
                }
                guard let (gen, meta) = opened else {
                    return .failure(SurfaceError("poster open failed"))
                }
                if let g = gen {
                    switch generateImage(g, meta.frameTime(meta.frameIndex(targetAt))) {
                    case .failure(let err):
                        return .failure(err)
                    case .success(let frame):
                        return .success((frame, meta))
                    }
                } else {
                    return .success((nil, meta))
                }
            }

            posters.lock.withLock {
                posters.done = result
            }
            guard let clip = weakClip.value else { return }
            switch kind {
            case .video:
                clip.wakeWindows()
            case .audio:
                onMain {
                    videoBackendDrive(clip)
                }
            }
        }
    }
    thread.name = "rune-media-poster"
    thread.start()
}

private func createPlayerObjects(
    _ source: MediaSource,
    _ headers: [(String, String)],
    _ kind: VideoKind
) -> Result<VideoPlayerObjects, SurfaceError> {
    switch makeAsset(source, headers) {
    case .failure(let err):
        return .failure(err)
    case .success(let asset):
        let item = AVPlayerItem(asset: asset)
        let output: AVPlayerItemVideoOutput?
        if kind == .video {
            let vout = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: String](),
                kCVPixelBufferMetalCompatibilityKey as String: NSNumber(value: true),
            ])
            vout.suppressesPlayerRendering = true
            item.add(vout)
            output = vout
        } else {
            output = nil
        }
        let player = AVPlayer(playerItem: item)
        return .success(VideoPlayerObjects(asset: asset, player: player, item: item, output: output))
    }
}

private func hostSeconds(_ at: RuneInstant) -> Double {
    let now = RuneInstant.now()
    let host = Double(CVGetCurrentHostTime()) / CVGetHostClockFrequency()
    if at >= now {
        let d = at.durationSince(now)
        return host + Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18
    } else {
        let d = now.durationSince(at)
        return host - (Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18)
    }
}

private func durationSeconds(_ d: Duration) -> Double {
    Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18
}

private func reconcile(_ p: VideoNativePlayer, _ c: inout VideoControl, _ now: RuneInstant) {
    guard let o = p.objects else { return }
    if p.muted != c.muted {
        o.player.isMuted = c.muted
        p.muted = c.muted
    }
    if p.ready, let t = c.seek {
        c.seek = nil
        o.player.seek(to: cmFromSeconds(t), toleranceBefore: cmZero(), toleranceAfter: cmZero())
        let sameFrame: Bool
        if !c.playing, let m = c.meta, let shown = p.shown {
            sameFrame = (m.frameIndex(shown) == m.frameIndex(t))
        } else {
            sameFrame = false
        }
        if sameFrame {
            p.hold = t
        } else {
            p.seeking = (now, t)
            p.hold = nil
        }
    }
    if p.ready {
        let rate: Float = c.playing ? c.rate : 0.0
        if p.rate != rate {
            if rate > 0.0 {
                o.player.rate = rate
            } else {
                o.player.pause()
            }
            p.rate = rate
        }
    }
}

func videoBackendApply(_ shared: VideoShared) {
    if !videoPlaybackEnabled() || shared.ctlLock.withLock({ shared.ctl.failed != nil }) {
        return
    }
    if !Thread.isMainThread {
        let weakClip = WeakVideoShared(value: shared)
        onMain {
            if let clip = weakClip.value {
                videoBackendApply(clip)
            }
        }
        return
    }
    if shared.kind == .audio {
        videoBackendDrive(shared)
        return
    }
    let playing: Bool? = shared.nativeLock.tryWithLock {
        guard let p = shared.native.player else { return nil }
        return shared.ctlLock.withLock {
            reconcile(p, &shared.ctl, .now())
            return shared.ctl.playing
        }
    } ?? nil
    if playing == true {
        unparkPlayer(shared)
    }
}

func videoBackendLiveTime(_ shared: VideoShared) -> Double? {
    if shared.kind != .audio || !Thread.isMainThread {
        return nil
    }
    guard let timeOpt = shared.nativeLock.tryWithLock({ () -> Double? in
        guard let p = shared.native.player,
              p.ready && p.rate > 0.0 && p.seeking == nil,
              let o = p.objects
        else { return nil }
        return cmSeconds(o.player.currentTime())
    }), let time = timeOpt else {
        return nil
    }
    return shared.ctlLock.withLock {
        guard shared.ctl.playing && !shared.ctl.ended else { return nil }
        if let d = shared.ctl.duration {
            return min(max(time, 0.0), d)
        }
        return time
    }
}

private func takePoster(_ native: VideoBackendNative, _ c: inout VideoControl, _ surface: NativeSurface?) {
    let doneOpt: Result<(ByteFrame?, VideoMeta), SurfaceError>? = native.posters.lock.withLock {
        let d = native.posters.done
        native.posters.done = nil
        return d
    }
    guard let done = doneOpt else { return }
    switch done {
    case .success(let (bytesOpt, meta)):
        if !c.opened() {
            c.open(.success(meta))
        }
        if let bytes = bytesOpt, let surface, native.player == nil, native.posterDue {
            let id = c.nextFrameId()
            if case .failure(let e) = surface.pushBytes(bytes, id) {
                c.fail(e.message)
            }
        }
    case .failure(let e):
        c.fail(e.message)
    }
}

private func checkItem(_ native: VideoBackendNative, _ c: inout VideoControl, _ now: RuneInstant) -> Bool {
    guard let p = native.player, let o = p.objects else { return false }
    let status = o.item.status
    let failure: String?
    if status == .failed {
        failure = o.item.error?.localizedDescription ?? "playback failed"
    } else if status != .readyToPlay && durationSeconds(now.durationSince(p.created)) > LOAD_PATIENCE_SECS {
        failure = "timed out loading after \(Int(LOAD_PATIENCE_SECS)) s"
    } else {
        failure = nil
    }
    if let err = failure {
        c.fail(err)
        native.player = nil
        return false
    }
    if status == .readyToPlay && !p.ready {
        p.ready = true
        if o.output != nil {
            p.orient = loadOrient(o.asset)
        }
        if !c.opened() {
            let sz = o.item.presentationSize
            let dur = cmSeconds(o.item.duration)
            let size: (UInt32, UInt32)? = (sz.width >= 1.0 && sz.height >= 1.0)
                ? (UInt32(sz.width.rounded()), UInt32(sz.height.rounded()))
                : nil
            c.open(.success(VideoMeta(duration: dur, size: size, frame: 1.0 / 30.0)))
        }
    }
    return true
}

private func ensurePlayer(_ shared: VideoShared, _ native: VideoBackendNative, _ c: inout VideoControl) -> Bool {
    if native.player != nil {
        return true
    }
    if shared.kind == .audio && !c.opened() {
        if !native.posterStarted {
            requestPoster(shared, native, 0.0)
        }
        return false
    }
    switch createPlayerObjects(shared.source, shared.headers, shared.kind) {
    case .success(let objects):
        if c.time > 0.0 && c.seek == nil {
            c.seek = c.time
        }
        native.player = VideoNativePlayer(objects)
        native.posterStarted = true
        native.posterDue = false
        return true
    case .failure(let err):
        c.fail(err.message)
        return false
    }
}

private func follow(_ p: VideoNativePlayer, _ c: inout VideoControl, _ now: RuneInstant, _ frameTime: Double?) {
    guard let o = p.objects else { return }
    let current = cmSeconds(o.player.currentTime())
    if frameTime == nil, let (_, to) = p.seeking, abs(current - to) < AUDIO_SEEK_SLOP {
        p.seeking = nil
    }
    if c.playing || (p.hold != nil && abs(current - p.hold!) < 1e-3) {
        p.hold = nil
    }
    let seeking = (p.seeking != nil) || (p.hold != nil)
    let stopped = p.rate > 0.0 && o.player.rate == 0.0
    let atEnd = !seeking && ((c.duration != nil && current >= c.duration! - 1e-3) || stopped)
    let pos: Double
    if seeking {
        pos = c.time
    } else if c.playing && !atEnd {
        pos = max(frameTime ?? current, 0.0)
    } else {
        pos = current
    }
    if c.observe(pos, atEnd: atEnd) {
        o.player.seek(to: cmZero(), toleranceBefore: cmZero(), toleranceAfter: cmZero())
        o.player.rate = c.rate
        p.rate = c.rate
        p.seeking = (now, 0.0)
        c.generation &+= 1
    } else if !c.playing {
        p.rate = 0.0
    }
}

func videoBackendPull(_ shared: VideoShared, _ surface: NativeSurface, _ target: RuneInstant) -> Bool {
    let now = RuneInstant.now()
    enum Outcome {
        case done(Bool)
        case finish(active: Bool, park: Bool)
    }
    var needUnparkFresh = false
    let outcome: Outcome = shared.nativeLock.withLock {
        let native = shared.native
        return shared.ctlLock.withLock {
            takePoster(native, &shared.ctl, surface)
            if shared.ctl.failed != nil {
                native.player = nil
                return .done(false)
            }
            guard Thread.isMainThread else { return .done(false) }
            if native.player == nil && !shared.ctl.playing {
                let want: Double?
                if let s = shared.ctl.seek {
                    shared.ctl.seek = nil
                    want = s
                } else if !native.posterStarted {
                    want = shared.ctl.time
                } else {
                    want = nil
                }
                if let at = want {
                    native.posterDue = true
                    requestPoster(shared, native, at)
                }
                return .done(false)
            }
            let fresh = (native.player == nil)
            if !ensurePlayer(shared, native, &shared.ctl) {
                return .done(false)
            }
            if fresh {
                needUnparkFresh = true
            }
            if !checkItem(native, &shared.ctl, now) {
                return .done(false)
            }
            guard let p = native.player else { return .done(false) }
            reconcile(p, &shared.ctl, now)
            if p.ready, let o = p.objects, let output = o.output {
                let itemTime = output.itemTime(forHostTime: hostSeconds(target))
                var shown = itemTime
                if output.hasNewPixelBuffer(forItemTime: itemTime),
                   let cvBuf = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: &shown) {
                    let id = shared.ctl.nextFrameId()
                    let orient = p.orient
                    let pushed = surface.pushOriented(PixelBuffer(cvBuf), id, orient)
                    if case .failure(let e) = pushed {
                        shared.ctl.fail(e.message)
                        native.player = nil
                        return .done(false)
                    }
                    p.shown = cmSeconds(shown)
                    p.seeking = nil
                }
                follow(p, &shared.ctl, now, cmSeconds(itemTime))
            }
            if let (since, _) = p.seeking, durationSeconds(now.durationSince(since)) > SEEK_PATIENCE_SECS {
                p.seeking = nil
            }
            let active = shared.ctl.playing || p.seeking != nil || !p.ready
            let shouldPark = p.ready && !active
            return .finish(active: active, park: shouldPark)
        }
    }
    if needUnparkFresh {
        unparkPlayer(shared)
    }
    switch outcome {
    case .done(let active):
        return active
    case .finish(let active, let shouldPark):
        if shouldPark {
            parkPlayer(shared)
        } else {
            unparkPlayer(shared)
        }
        return active
    }
}

func videoBackendDrive(_ shared: VideoShared) {
    if stepAudio(shared) {
        tickerStateLock.withLock {
            audioBusy = true
        }
        startTicking()
    }
    shared.settle(windows: true)
}

private func stepAudio(_ shared: VideoShared) -> Bool {
    guard Thread.isMainThread else { return false }
    let now = RuneInstant.now()
    enum StepOutcome {
        case done(Bool)
        case finish(active: Bool, park: Bool)
    }
    var needUnparkFresh = false
    guard let outcome: StepOutcome = shared.nativeLock.tryWithLock({
        let native = shared.native
        return shared.ctlLock.withLock {
            takePoster(native, &shared.ctl, nil)
            if shared.ctl.failed != nil {
                native.player = nil
                return .done(false)
            }
            if native.player == nil && !shared.ctl.playing {
                return .done(false)
            }
            let fresh = (native.player == nil)
            if !ensurePlayer(shared, native, &shared.ctl) {
                return .done(false)
            }
            if fresh {
                needUnparkFresh = true
            }
            if !checkItem(native, &shared.ctl, now) {
                return .done(false)
            }
            guard let p = native.player else { return .done(false) }
            reconcile(p, &shared.ctl, now)
            if !p.ready {
                return .done(true)
            }
            follow(p, &shared.ctl, now, nil)
            if let (since, _) = p.seeking, durationSeconds(now.durationSince(since)) > SEEK_PATIENCE_SECS {
                p.seeking = nil
            }
            let active = shared.ctl.playing || p.seeking != nil || !p.ready
            let shouldPark = p.ready && !active
            return .finish(active: active, park: shouldPark)
        }
    }) else {
        // Already being driven further up this stack (a waker that edits the clip).
        return true
    }

    if needUnparkFresh {
        unparkPlayer(shared)
    }
    switch outcome {
    case .done(let active):
        return active
    case .finish(let active, let shouldPark):
        if shouldPark {
            parkPlayer(shared)
        } else {
            unparkPlayer(shared)
        }
        return active
    }
}

private func tickAudio() {
    let clips: [VideoShared] = audioListLock.withLock {
        audioList.removeAll { $0.value == nil }
        return audioList.compactMap { $0.value }
    }
    var busy = false
    for clip in clips {
        if stepAudio(clip) {
            busy = true
        }
        clip.settle(windows: true)
    }
    tickerStateLock.withLock {
        audioBusy = busy
    }
}

private func startTicking() {
    let shouldStart: Bool = tickerStateLock.withLock {
        if audioTicking { return false }
        audioTicking = true
        return true
    }
    guard shouldStart else { return }
    let thread = Thread {
        while true {
            Thread.sleep(forTimeInterval: AUDIO_TICK_SECS)
            let keepGoing: Bool = tickerStateLock.withLock {
                if !audioBusy {
                    audioTicking = false
                    return false
                }
                return true
            }
            if !keepGoing {
                return
            }
            onMain {
                tickAudio()
            }
        }
    }
    thread.name = "rune-audio-tick"
    thread.start()
}

private func unparkPlayer(_ shared: VideoShared) {
    parkedLock.withLock {
        parkedList.removeAll { $0.value == nil || $0.value === shared }
    }
}

private func parkPlayer(_ shared: VideoShared) {
    for clip in videoMacosParkedWith(shared) {
        let removed: VideoNativePlayer? = clip.nativeLock.withLock {
            let p = clip.native.player
            clip.native.player = nil
            if clip.kind == .video && p?.shown == nil {
                clip.native.posterStarted = false
            }
            return p
        }
        _ = removed
    }
}

/// Parks `shared` and returns the clips to release: the oldest past `PARKED_PLAYERS`. A clip
/// that plays again (before its next pull unparks it) leaves the list and is never released.
func videoMacosParkedWith(_ shared: VideoShared) -> [VideoShared] {
    let isPlaying = { (clip: VideoShared) -> Bool in
        // A clip being edited on another thread right now counts as playing.
        clip.ctlLock.tryWithLock { clip.ctl.playing } ?? true
    }
    return parkedLock.withLock {
        parkedList.removeAll { w in
            guard let clip = w.value else { return true }
            return !(clip === shared || !isPlaying(clip))
        }
        if !parkedList.contains(where: { $0.value === shared }) {
            parkedList.append(WeakVideoShared(value: shared))
        }
        let excess = max(parkedList.count - PARKED_PLAYERS, 0)
        if excess == 0 {
            return []
        }
        let drained = Array(parkedList.prefix(excess))
        parkedList.removeFirst(excess)
        return drained.compactMap { $0.value }
    }
}
#endif
