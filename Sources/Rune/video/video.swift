// Ported from: crates/rune/src/video/mod.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Media playback: a cheap, cloneable `Player` (`Video`) handle for video drawn into a
//! `NativeSurface`, or for audio with no element at all.

#if !os(WASI)
import Foundation
#endif

private let playbackLock = LiveLock()
// PORT NOTE: Guarded by `playbackLock`, matching `static PLAYBACK: AtomicBool` in `video/mod.rs`.
nonisolated(unsafe) private var playbackActive: Bool = false

/// Called by the windowed shell before its event loop starts.
func enableVideoPlayback() {
    let first: Bool = playbackLock.withLock {
        if playbackActive { return false }
        playbackActive = true
        return true
    }
    if first {
        videoBackendEnable()
    }
}

func videoPlaybackEnabled() -> Bool {
    playbackLock.withLock { playbackActive }
}

struct WeakVideoShared {
    weak var value: VideoShared?
}

// PORT NOTE: Thread-local headless playback state (`clock` and weak `audio` handles) per thread.
final class HeadlessMediaState: @unchecked Sendable {
    var clock: Double? = nil
    var audio: [WeakVideoShared] = []
}

#if os(WASI)
// PORT NOTE: WASI (`wasm32-unknown-wasip1`) is single-threaded.
nonisolated(unsafe) private var wasiHeadlessMedia = HeadlessMediaState()
#endif
private let headlessThreadKey = "gpua.rune.video.headless"

private func withHeadlessMedia<R>(_ body: (HeadlessMediaState) -> R) -> R {
    #if os(WASI)
    return body(wasiHeadlessMedia)
    #else
    let dict = Thread.current.threadDictionary
    if let existing = dict[headlessThreadKey] as? HeadlessMediaState {
        return body(existing)
    }
    let created = HeadlessMediaState()
    dict[headlessThreadKey] = created
    return body(created)
    #endif
}

/// A headless runtime starts a frame at `clock`: audio clips made on this thread follow it.
func videoHeadlessFrame(_ clock: Double) {
    let clips: [VideoShared] = withHeadlessMedia { h in
        h.clock = clock
        h.audio.removeAll { $0.value == nil }
        return h.audio.compactMap { $0.value }
    }
    for clip in clips {
        clip.followClock()
    }
}

/// A new runtime on this thread starts its clock at 0, replacing an earlier runtime's.
func videoHeadlessReset() {
    withHeadlessMedia { h in
        h.clock = 0.0
    }
}

/// Current thread's headless virtual clock, if any.
func videoHeadlessClock() -> Double? {
    #if os(WASI)
    return wasiHeadlessMedia.clock
    #else
    return (Thread.current.threadDictionary[headlessThreadKey] as? HeadlessMediaState)?.clock
    #endif
}

/// Where media comes from. Strings containing `://` are URLs; anything else is a file path.
public enum MediaSource: Sendable, Equatable, Hashable {
    case file(String)
    case url(String)

    public static func File(_ path: String) -> MediaSource { .file(path) }
    public static func Url(_ url: String) -> MediaSource { .url(url) }

    public init(_ s: String) {
        if s.contains("://") {
            self = .url(s)
        } else {
            self = .file(s)
        }
    }

    public static func from(_ s: String) -> MediaSource {
        MediaSource(s)
    }

    #if !os(WASI)
    public static func from(_ url: URL) -> MediaSource {
        if url.isFileURL && !url.absoluteString.hasPrefix("file://") {
            return .file(url.path)
        }
        return .file(url.path)
    }
    #endif
}

/// A media URL with HTTP request headers, for clips behind authentication.
/// Header values never appear in `debugDescription` output or logs.
public struct MediaRequest: Sendable, CustomDebugStringConvertible {
    let url: String
    var headers: [(String, String)]

    public init(url: String, headers: [(String, String)] = []) {
        self.url = url
        self.headers = headers
    }

    public var debugDescription: String {
        let names = headers.map { "\"\($0.0)\"" }.joined(separator: ", ")
        return "MediaRequest { url: \"\(url)\", headers: [\(names)] }"
    }

    /// Adds a header sent with every request for the clip. A repeated name (case-insensitive) replaces the earlier value.
    public func header(_ name: String, _ value: String) -> MediaRequest {
        var copy = self
        copy.headers.removeAll { $0.0.caseInsensitiveCompare(name) == .orderedSame }
        copy.headers.append((name, value))
        return copy
    }

    /// An audio clip, as `Player.audio`.
    public func audio() -> Player {
        Player.create(.url(url), .audio, headers)
    }

    /// A video, muted, as `Player.url`.
    public func video() -> Player {
        Player.create(.url(url), .video, headers)
    }
}

/// Playback state. Video reports it as of the last frame that drew it; audio as of its last tick or edit.
public enum PlayerState: Sendable, Equatable, Hashable {
    case loading
    case ready
    case playing
    case ended
    case failed(String)

    public static let Loading: PlayerState = .loading
    public static let Ready: PlayerState = .ready
    public static let Playing: PlayerState = .playing
    public static let Ended: PlayerState = .ended
    public static func Failed(_ reason: String) -> PlayerState { .failed(reason) }
}

enum VideoKind: Sendable, Equatable {
    case video
    case audio
}

/// A video or audio clip. Copies share one player; dropping the last handle (and, for video,
/// every element showing it) stops and frees it. Video starts muted; audio starts unmuted.
public struct Player: Sendable, CustomDebugStringConvertible {
    let surfaceHandle: NativeSurface
    let shared: VideoShared

    init(surfaceHandle: NativeSurface, shared: VideoShared) {
        self.surfaceHandle = surfaceHandle
        self.shared = shared
    }

    public func clone() -> Player {
        self
    }

    public var debugDescription: String {
        let (st, tm) = shared.ctlLock.withLock { (shared.ctl.state(), shared.ctl.time) }
        return "Player { kind: \(shared.kind), source: \(shared.source), state: \(st), time: \(tm), .. }"
    }

    /// A video, muted.
    public init(_ source: MediaSource) {
        self = Self.create(source, .video, [])
    }

    public static func new(_ source: MediaSource) -> Player {
        Player(source)
    }

    /// A local movie file (mp4, mov; H.264 or HEVC), muted.
    public static func file(_ path: String) -> Player {
        Player(.file(path))
    }

    /// A video at an `http(s)://` or `file://` URL, muted.
    public static func url(_ url: String) -> Player {
        Player(.url(url))
    }

    /// An audio clip from a path or URL, unmuted.
    public static func audio(_ source: MediaSource) -> Player {
        create(source, .audio, [])
    }

    public static func audio(_ source: String) -> Player {
        create(MediaSource(source), .audio, [])
    }

    /// A URL to open with request headers.
    public static func request(_ url: String) -> MediaRequest {
        MediaRequest(url: url)
    }

    static func create(_ source: MediaSource, _ kind: VideoKind, _ headers: [(String, String)]) -> Player {
        var ctl = VideoControl()
        ctl.muted = (kind == .video)
        let shared = VideoShared(source: source, headers: headers, kind: kind, ctl: ctl)
        videoBackendCreated(shared)
        if kind == .audio && !videoPlaybackEnabled() {
            withHeadlessMedia { h in
                h.audio.append(WeakVideoShared(value: shared))
            }
        }
        return Player(surfaceHandle: NativeSurface.withVideo(shared), shared: shared)
    }

    public func source() -> MediaSource {
        shared.source
    }

    public func isAudio() -> Bool {
        shared.kind == .audio
    }

    public func preload() {
        if videoPlaybackEnabled() {
            videoBackendPreload(shared)
        }
    }

    /// Start or resume playback. After `PlayerState.ended` it starts from the beginning.
    public func play() {
        edit { c in
            if c.failed != nil {
                return
            }
            if c.ended {
                c.ended = false
                c.seek = 0.0
                c.time = 0.0
            }
            c.playing = true
            c.anchor = nil
        }
    }

    public func pause() {
        edit { c in
            c.playing = false
            c.anchor = nil
        }
    }

    /// Jump to `seconds` (clamped to the clip). Keeps playing if it was playing.
    public func seek(_ seconds: Double) {
        let clamped = seconds.isFinite ? max(seconds, 0.0) : 0.0
        edit { c in
            let s = c.duration.map { min(clamped, $0) } ?? clamped
            c.seek = s
            c.time = s
            c.ended = false
            c.anchor = nil
        }
    }

    /// Playback speed while playing; 1 is normal. Negative and non-finite rates are ignored.
    public func setRate(_ rate: Float) {
        if rate.isFinite && rate > 0.0 {
            edit { c in
                c.rate = rate
                c.anchor = nil
            }
        }
    }

    public func setLooping(_ looping: Bool) {
        edit { $0.looping = looping }
    }

    public func setMuted(_ muted: Bool) {
        edit { $0.muted = muted }
    }

    public func setWaker(_ waker: @escaping Waker) {
        shared.wakerLock.withLock {
            shared.wakerState = (waker, 0)
        }
        shared.settle(windows: false)
    }

    public func state() -> PlayerState {
        withRead { $0.state() }
    }

    public func isPlaying() -> Bool {
        shared.ctlLock.withLock { shared.ctl.playing }
    }

    public func time() -> Double {
        let t = withRead { $0.time }
        return videoBackendLiveTime(shared) ?? t
    }

    public func duration() -> Double? {
        withRead { $0.duration }
    }

    public func naturalSize() -> (UInt32, UInt32)? {
        shared.ctlLock.withLock { shared.ctl.size }
    }

    public func rate() -> Float {
        shared.ctlLock.withLock { shared.ctl.rate }
    }

    public func looping() -> Bool {
        shared.ctlLock.withLock { shared.ctl.looping }
    }

    public func muted() -> Bool {
        shared.ctlLock.withLock { shared.ctl.muted }
    }

    public func surface() -> NativeSurface {
        surfaceHandle
    }

    private func withRead<R>(_ body: (VideoControl) -> R) -> R {
        if shared.kind == .audio && !videoPlaybackEnabled() {
            shared.openNow()
            shared.followClock()
        }
        return shared.ctlLock.withLock { body(shared.ctl) }
    }

    private func edit(_ f: (inout VideoControl) -> Void) {
        let clock: Double? = (shared.kind == .audio && !videoPlaybackEnabled()) ? videoHeadlessClock() : nil
        if clock != nil {
            shared.openNow()
        }
        shared.ctlLock.withLock {
            if let now = clock {
                shared.ctl.advanceVirtual(now)
            }
            f(&shared.ctl)
            if let now = clock {
                shared.ctl.advanceVirtual(now)
            }
        }
        if clock != nil {
            shared.settle(windows: false)
        }
        videoBackendApply(shared)
        shared.wakeWindows()
    }
}

/// `Player`, named for the element builder it pairs with (`El.video`).
public typealias Video = Player

/// The clock a pull samples: a window's next presentation, or a headless run's virtual time.
enum VideoClock: Sendable {
    case display(RuneInstant)
    case virtual(Double)
}

/// What one pull tells the runtime.
struct VideoPulled: Sendable, Equatable {
    var active: Bool
    var generation: UInt64
}

private func rotateLeft64(_ v: UInt64, _ shift: UInt64) -> UInt64 {
    let s = shift & 63
    return s == 0 ? v : ((v << s) | (v >> (64 - s)))
}

/// Folds one drawn video's `generation` into a frame's signature, order-free.
func videoFold(_ signature: UInt64, _ generation: UInt64, _ key: Int) -> UInt64 {
    let k = rotateLeft64(UInt64(bitPattern: Int64(key)), 32)
    let mixed = rotateLeft64((generation ^ k) &* 0x9e37_79b9_7f4a_7c15, 31)
    return signature &+ mixed
}

func videoFoldUnpulled(_ signature: UInt64, _ surface: NativeSurface) -> UInt64 {
    guard let v = surface.video() else { return signature }
    let gen = v.ctlLock.withLock { v.ctl.generation }
    return videoFold(signature, gen, surface.key())
}

struct VideoSnapshot: Sendable, Equatable {
    var kind: VideoKind
    var state: PlayerState
    var time: Double
    var duration: Double?
    var size: (UInt32, UInt32)?
    var rate: Float
    var looping: Bool
    var muted: Bool

    static func == (lhs: VideoSnapshot, rhs: VideoSnapshot) -> Bool {
        let sizeEq: Bool
        switch (lhs.size, rhs.size) {
        case (nil, nil): sizeEq = true
        case (let a?, let b?): sizeEq = (a.0 == b.0 && a.1 == b.1)
        default: sizeEq = false
        }
        return lhs.kind == rhs.kind
            && lhs.state == rhs.state
            && lhs.time == rhs.time
            && lhs.duration == rhs.duration
            && sizeEq
            && lhs.rate == rhs.rate
            && lhs.looping == rhs.looping
            && lhs.muted == rhs.muted
    }
}

/// Clip facts read once when it opens.
struct VideoMeta: Sendable, Equatable {
    var duration: Double
    var size: (UInt32, UInt32)?
    var frame: Double

    static func == (lhs: VideoMeta, rhs: VideoMeta) -> Bool {
        let sizeEq: Bool
        switch (lhs.size, rhs.size) {
        case (nil, nil): sizeEq = true
        case (let a?, let b?): sizeEq = (a.0 == b.0 && a.1 == b.1)
        default: sizeEq = false
        }
        return lhs.duration == rhs.duration && sizeEq && lhs.frame == rhs.frame
    }

    func frames() -> Int64 {
        max(Int64((duration / frame).rounded()), 1)
    }

    func frameIndex(_ t: Double) -> Int64 {
        let raw = Int64((t / frame + 1e-6).rounded(.down))
        return min(max(raw, 0), frames() - 1)
    }

    /// The middle of frame `i`, so decoders never land on a neighbour's boundary.
    func frameTime(_ i: Int64) -> Double {
        min((Double(i) + 0.5) * frame, duration)
    }
}

// PORT NOTE: Non-reentrant lock supporting `tryWithLock` (matching Rust `Mutex::try_lock`) on non-WASI platforms.
final class VideoTryLock: @unchecked Sendable {
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

    @inline(__always)
    func tryWithLock<R>(_ body: () throws -> R) rethrows -> R? {
        #if !os(WASI)
        guard lock.try() else { return nil }
        defer { lock.unlock() }
        #endif
        return try body()
    }
}

struct WeakLiveWake {
    weak var value: LiveWake?
}

// PORT NOTE: Shared media controller synchronized with per-subsystem locks (`ctlLock`, `wakesLock`, `wakerLock`, `nativeLock`).
final class VideoShared: @unchecked Sendable {
    let source: MediaSource
    let headers: [(String, String)]
    let kind: VideoKind
    let ctlLock = VideoTryLock()
    var ctl: VideoControl
    private let wakesLock = LiveLock()
    private var wakes: [WeakLiveWake] = []
    let wakerLock = LiveLock()
    var wakerState: (Waker, UInt64)? = nil
    private let notifiedLock = LiveLock()
    private var notifiedGen: UInt64 = 0
    let nativeLock = VideoTryLock()
    var native = VideoBackendNative()

    init(source: MediaSource, headers: [(String, String)], kind: VideoKind, ctl: VideoControl) {
        self.source = source
        self.headers = headers
        self.kind = kind
        self.ctl = ctl
    }

    func snapshot() -> VideoSnapshot {
        ctlLock.withLock {
            VideoSnapshot(
                kind: kind,
                state: ctl.state(),
                time: ctl.time,
                duration: ctl.duration,
                size: ctl.size,
                rate: ctl.rate,
                looping: ctl.looping,
                muted: ctl.muted
            )
        }
    }

    func wakeWindows() {
        let targets: [LiveWake] = wakesLock.withLock {
            wakes.removeAll { $0.value == nil }
            return wakes.compactMap { $0.value }
        }
        for w in targets {
            w.notify()
        }
    }

    /// Tell the app's waker (and, outside a frame, the windows) that the state changed.
    func settle(windows: Bool) {
        let generation = ctlLock.withLock { ctl.generation }
        let toCall: Waker? = wakerLock.withLock {
            guard let (waker, heard) = wakerState, heard != generation else {
                return nil
            }
            wakerState = (waker, generation)
            return waker
        }
        toCall?()
        let prevNotified: UInt64 = notifiedLock.withLock {
            let old = notifiedGen
            notifiedGen = generation
            return old
        }
        if prevNotified != generation && windows {
            wakeWindows()
        }
    }

    func register(_ wake: LiveWake) {
        wakesLock.withLock {
            wakes.removeAll { $0.value == nil }
            if !wakes.contains(where: { $0.value === wake }) {
                wakes.append(WeakLiveWake(value: wake))
            }
        }
    }

    func openNow() {
        var didOpen = false
        nativeLock.withLock {
            let alreadyOpened = ctlLock.withLock { ctl.opened() }
            if !alreadyOpened {
                let meta = videoBackendProbe(&native, source, headers, kind)
                ctlLock.withLock {
                    ctl.open(meta)
                }
                didOpen = true
            }
        }
        if didOpen {
            settle(windows: false)
        }
    }

    func followClock() {
        if kind != .audio || videoPlaybackEnabled() {
            return
        }
        guard let now = videoHeadlessClock() else { return }
        if ctlLock.withLock({ ctl.playing }) {
            openNow()
        }
        ctlLock.withLock {
            ctl.advanceVirtual(now)
        }
        settle(windows: false)
    }

    func pull(_ surface: NativeSurface, _ clock: VideoClock, _ wake: LiveWake) -> VideoPulled {
        register(wake)
        if kind == .audio {
            switch clock {
            case .virtual:
                openNow()
            case .display:
                videoBackendDrive(self)
            }
            return VideoPulled(active: false, generation: ctlLock.withLock { ctl.generation })
        }

        let active: Bool
        switch clock {
        case .virtual(let now):
            active = pullVirtual(surface, now)
        case .display(let target):
            active = videoBackendPull(self, surface, target)
        }

        let pulled: VideoPulled = ctlLock.withLock {
            if ctl.failed != nil && !ctl.placeholder {
                ctl.placeholder = true
                pushVideoPlaceholder(surface)
            }
            return VideoPulled(active: active && ctl.failed == nil, generation: ctl.generation)
        }
        settle(windows: false)
        return pulled
    }

    private func pullVirtual(_ surface: NativeSurface, _ now: Double) -> Bool {
        openNow()
        return nativeLock.withLock {
            let step: (VideoMeta, Int64, Int64?)? = ctlLock.withLock {
                guard ctl.failed == nil, let meta = ctl.meta else { return nil }
                ctl.advanceVirtual(now)
                return (meta, meta.frameIndex(ctl.time), ctl.shown)
            }
            guard let (meta, frame, shown) = step else { return false }
            if shown != frame {
                let decoded = videoBackendDecode(&native, source, headers, meta.frameTime(frame))
                ctlLock.withLock {
                    ctl.shown = frame
                    let id = ctl.nextFrameId()
                    switch decoded {
                    case .success(let bytes):
                        if case .failure(let e) = surface.pushBytes(bytes, id) {
                            ctl.fail(e.message)
                        }
                    case .failure(let e):
                        ctl.fail(e.message)
                    }
                }
            }
            return ctlLock.withLock { ctl.playing }
        }
    }
}

struct VideoControl: Sendable {
    var playing: Bool = false
    var rate: Float = 1.0
    var looping: Bool = false
    var muted: Bool = true
    var seek: Double? = nil
    var time: Double = 0.0
    var duration: Double? = nil
    var size: (UInt32, UInt32)? = nil
    var meta: VideoMeta? = nil
    var ended: Bool = false
    var failed: String? = nil
    var placeholder: Bool = false
    var generation: UInt64 = 0
    var frameId: UInt64 = 0
    var anchor: (Double, Double)? = nil
    var shown: Int64? = nil

    func state() -> PlayerState {
        if let e = failed {
            return .failed(e)
        } else if meta == nil {
            return .loading
        } else if playing {
            return .playing
        } else if ended {
            return .ended
        } else {
            return .ready
        }
    }

    func opened() -> Bool {
        meta != nil || failed != nil
    }

    mutating func open(_ result: Result<VideoMeta, SurfaceError>) {
        switch result {
        case .success(let m):
            meta = m
            duration = m.duration
            size = m.size
            time = min(time, m.duration)
            seek = seek.map { min($0, m.duration) }
            generation &+= 1
        case .failure(let err):
            fail(err.message)
        }
    }

    mutating func fail(_ error: String) {
        if failed == nil {
            failed = error
            playing = false
            generation &+= 1
        }
    }

    mutating func nextFrameId() -> UInt64 {
        frameId &+= 1
        return frameId
    }

    mutating func advanceVirtual(_ now: Double) {
        guard let m = meta else { return }
        if let t = seek {
            seek = nil
            time = min(t, m.duration)
            anchor = nil
        }
        guard playing else { return }
        let startClock: Double
        let startTime: Double
        if let (clk, tm) = anchor, clk <= now {
            startClock = clk
            startTime = tm
        } else {
            let fresh = (now, time)
            anchor = fresh
            startClock = fresh.0
            startTime = fresh.1
        }
        let t = startTime + max(now - startClock, 0.0) * Double(rate)
        if t < m.duration {
            time = t
        } else if looping && m.duration > 0.0 {
            time = t.truncatingRemainder(dividingBy: m.duration)
        } else {
            time = m.duration
            playing = false
            ended = true
            anchor = nil
            generation &+= 1
        }
    }

    mutating func observe(_ pos: Double, atEnd: Bool) -> Bool {
        if let d = duration {
            time = min(max(pos, 0.0), d)
        } else {
            time = pos
        }
        if !(playing && atEnd) {
            return false
        }
        if looping {
            time = 0.0
            return true
        }
        playing = false
        ended = true
        generation &+= 1
        return false
    }
}

/// A 16:9 mid-grey frame for videos that can't play.
private func pushVideoPlaceholder(_ surface: NativeSurface) {
    let w = 32
    let h = 18
    var bgra = [UInt8]()
    bgra.reserveCapacity(w * h * 4)
    for _ in 0..<(w * h) {
        bgra.append(contentsOf: [0x46, 0x46, 0x46, 0xff])
    }
    let frame = ByteFrame(
        width: UInt32(w),
        height: UInt32(h),
        format: .bgra,
        color: ColorInfo(matrix: .bt709, transfer: .srgb),
        planes: [bgra, []]
    )
    _ = surface.pushBytes(frame, UInt64.max)
}
