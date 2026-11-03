// Ported from: crates/rune/src/tooling/record.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Headless frame output: staging readback ring, unpadding, ffmpeg video piping, and PNG writing.

#if !os(WASI)
import Foundation
#endif

/// Readbacks in flight: rendering frame `n + 1` and `n + 2` overlaps mapping frame `n`.
let TOOLING_READBACK_DEPTH: Int = 3

/// Rows of `width` RGBA pixels from a buffer whose rows are `paddedRow` bytes apart.
func toolingUnpad(_ data: [UInt8], _ width: UInt32, _ height: UInt32, _ paddedRow: UInt32) -> [UInt8] {
    let row = Int(width) * 4
    let stride = Int(paddedRow)
    var out: [UInt8] = []
    out.reserveCapacity(row * Int(height))
    for y in 0..<Int(height) {
        let start = y * stride
        let end = min(start + row, data.count)
        if start < end {
            out.append(contentsOf: data[start..<end])
        }
    }
    return out
}

/// Pipelined staging buffer ring for offscreen readback (`crates/rune/src/tooling/record.rs`).
final class ToolingReadback<T> {
    private struct Slot {
        var buffer: [UInt8]
        var ready: Bool = false
    }

    private var slots: [Slot]
    private var nextIndex: Int = 0
    /// Copied frames, oldest first: `(slot, tag, mapped)`.
    private var pending: [(Int, T, Bool)] = []
    let width: UInt32
    let height: UInt32
    let paddedRow: UInt32

    init(width: UInt32, height: UInt32, depth: Int = TOOLING_READBACK_DEPTH) {
        let rawRow = width * 4
        let padded = (rawRow + 255) & ~255
        self.width = width
        self.height = height
        self.paddedRow = padded
        let cap = Int(padded) * Int(height)
        self.slots = (0..<max(depth, 1)).map { _ in
            Slot(buffer: [UInt8](repeating: 0, count: cap), ready: false)
        }
    }

    /// Frames that must finish before the next `copy` has a free buffer.
    func makeRoom() -> [(T, [UInt8])] {
        var done: [(T, [UInt8])] = []
        if pending.count >= slots.count, let popped = pop(wait: true) {
            done.append(popped)
        }
        return done
    }

    /// Copies `rgba` (`width * height * 4`) into the next free padded staging slot.
    func copy(_ rgba: [UInt8], _ tag: T) {
        precondition(pending.count < slots.count, "ToolingReadback.makeRoom first")
        let slot = nextIndex
        nextIndex = (nextIndex + 1) % slots.count
        let rowBytes = Int(width) * 4
        let stride = Int(paddedRow)
        for y in 0..<Int(height) {
            let src = y * rowBytes
            let dst = y * stride
            if src + rowBytes <= rgba.count {
                slots[slot].buffer.replaceSubrange(dst..<(dst + rowBytes), with: rgba[src..<(src + rowBytes)])
            }
        }
        slots[slot].ready = false
        pending.append((slot, tag, false))
    }

    /// Marks every copied buffer whose commands were submitted as mapping-started.
    func submitted() {
        for idx in pending.indices where !pending[idx].2 {
            let slot = pending[idx].0
            slots[slot].ready = true
            pending[idx].2 = true
        }
    }

    /// Finished frames in submission order, without waiting.
    func ready() -> [(T, [UInt8])] {
        var done: [(T, [UInt8])] = []
        while let frame = pop(wait: false) {
            done.append(frame)
        }
        return done
    }

    /// Waits for every frame in flight.
    func finish() -> [(T, [UInt8])] {
        var done: [(T, [UInt8])] = []
        while let frame = pop(wait: true) {
            done.append(frame)
        }
        return done
    }

    private func pop(wait: Bool) -> (T, [UInt8])? {
        guard let head = pending.first else { return nil }
        let (slot, tag, mapped) = head
        precondition(mapped, "ToolingReadback.submitted after submitting the copy")
        if !slots[slot].ready && !wait {
            return nil
        }
        pending.removeFirst()
        let pixels = toolingUnpad(slots[slot].buffer, width, height, paddedRow)
        slots[slot].ready = false
        return (tag, pixels)
    }
}

// MARK: - Video Container & FFmpeg Args

/// The container and codec `--video` picks from the file extension.
enum ToolingVideoContainer: Sendable, Equatable {
    case mp4
    case mov
    case webm

    static func of(_ path: String) -> Result<ToolingVideoContainer, ToolingCliError> {
        let filename = path.split(separator: "/").last.map(String.init) ?? path
        let ext: String
        if let dot = filename.lastIndex(of: "."), dot != filename.startIndex {
            ext = String(filename[filename.index(after: dot)...]).lowercased()
        } else if filename.hasPrefix("."), let dot = filename.dropFirst().lastIndex(of: ".") {
            ext = String(filename[filename.index(after: dot)...]).lowercased()
        } else if let dot = filename.lastIndex(of: ".") {
            ext = String(filename[filename.index(after: dot)...]).lowercased()
        } else {
            ext = ""
        }
        switch ext {
        case "mp4": return .success(.mp4)
        case "mov": return .success(.mov)
        case "webm": return .success(.webm)
        default:
            return .failure(ToolingCliError("--video \(path): use a .mp4, .mov or .webm file"))
        }
    }

    var codecArgs: [String] {
        let even = "pad=ceil(iw/2)*2:ceil(ih/2)*2,scale=out_color_matrix=bt709:out_range=tv,format=yuv420p"
        let tags = ["-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709"]
        switch self {
        case .mp4:
            return ["-c:v", "libx264", "-preset", "medium", "-crf", "18", "-vf", even]
                + tags + ["-movflags", "+faststart"]
        case .mov:
            return ["-c:v", "prores_ks", "-profile:v", "4444", "-pix_fmt", "yuva444p10le",
                    "-vf", "scale=out_color_matrix=bt709:out_range=tv", "-vendor", "apl0"] + tags
        case .webm:
            return ["-c:v", "libvpx-vp9", "-crf", "30", "-b:v", "0", "-row-mt", "1",
                    "-deadline", "good", "-cpu-used", "4", "-vf", even] + tags
        }
    }
}

/// The `ffmpeg` arguments for raw RGBA frames on stdin.
func toolingFfmpegArgs(_ path: String, _ size: (UInt32, UInt32), _ fps: Double) -> Result<[String], ToolingCliError> {
    switch ToolingVideoContainer.of(path) {
    case .failure(let err):
        return .failure(err)
    case .success(let container):
        let fpsStr: String
        if let exact = Int64(exactly: fps) {
            fpsStr = "\(exact)"
        } else {
            fpsStr = "\(fps)"
        }
        var args = [
            "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
            "-f", "rawvideo", "-pix_fmt", "rgba",
            "-s", "\(size.0)x\(size.1)", "-r", fpsStr, "-i", "-",
        ]
        args.append(contentsOf: container.codecArgs)
        let isRelative = !path.hasPrefix("/") && !(path.count >= 2 && Array(path)[1] == ":")
        let output = (isRelative && path.hasPrefix("-")) ? "./\(path)" : path
        args.append(output)
        return .success(args)
    }
}

func toolingWritePng(_ path: String, _ width: UInt32, _ height: UInt32, _ rgba: [UInt8]) throws {
    guard let pngBytes = encodePng(width, height, rgba) else {
        throw ToolingCliError("\(path): invalid RGBA buffer size \(rgba.count) for \(width)x\(height)")
    }
    #if os(WASI)
    throw ToolingCliError("\(path): filesystem write unavailable on WASI")
    #else
    let url = URL(fileURLWithPath: path)
    let dir = url.deletingLastPathComponent()
    if !dir.path.isEmpty {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    try Data(pngBytes).write(to: url)
    #endif
}

// MARK: - Frame & Video Writer (`ToolingWriter`)

#if !os(WASI) && !os(Android)
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// PORT NOTE: Synchronized via `LiveLock` for streaming raw RGBA frames to an encoder child process on a background thread.
private final class VideoEncoderSession: @unchecked Sendable {
    private let lock = LiveLock()
    private var queue: [[UInt8]] = []
    private var closed: Bool = false
    private var workerDone: Bool = false
    private var earlyPipeError: String? = nil
    private var finalResult: Result<Void, ToolingCliError>? = nil
    private let process: Process
    private let pipe: Pipe
    let outputPath: String

    init(process: Process, pipe: Pipe, outputPath: String) {
        self.process = process
        self.pipe = pipe
        self.outputPath = outputPath
        startWorker()
    }

    private func startWorker() {
        #if canImport(Darwin) || canImport(Glibc)
        signal(SIGPIPE, SIG_IGN)
        #endif
        let handle = pipe.fileHandleForWriting
        let t = Thread { [weak self] in
            guard let self else { return }
            var writeErr: (any Error)? = nil
            while true {
                let nextFrame: [UInt8]? = self.lock.withLock {
                    if !self.queue.isEmpty {
                        return self.queue.removeFirst()
                    }
                    return nil
                }
                if let frame = nextFrame {
                    do {
                        try handle.write(contentsOf: Data(frame))
                    } catch {
                        writeErr = error
                        break
                    }
                } else {
                    let shouldStop = self.lock.withLock { self.closed && self.queue.isEmpty }
                    if shouldStop { break }
                    Thread.sleep(forTimeInterval: 0.001)
                }
            }
            try? handle.close()
            self.process.waitUntilExit()
            let code = self.process.terminationStatus
            let res: Result<Void, ToolingCliError>
            if code == 0 && writeErr == nil {
                res = .success(())
            } else if let writeErr {
                res = .failure(ToolingCliError("ffmpeg stopped reading frames (\(writeErr); exit status: \(code)); see its message above"))
            } else {
                res = .failure(ToolingCliError("ffmpeg failed writing \(self.outputPath) (exit status: \(code))"))
            }
            self.lock.withLock {
                if case .failure(let err) = res {
                    self.earlyPipeError = err.message
                }
                self.finalResult = res
                self.workerDone = true
            }
        }
        t.name = "rune-video"
        t.start()
    }

    func send(_ frame: [UInt8]) -> Result<Void, ToolingCliError> {
        // Wait if queue has `TOOLING_READBACK_DEPTH` frames so early process exit is detected promptly
        while true {
            let state: (Bool, String?, Bool) = lock.withLock {
                if workerDone {
                    return (true, earlyPipeError ?? "video writer disconnected", false)
                }
                if queue.count < TOOLING_READBACK_DEPTH {
                    queue.append(frame)
                    return (false, nil, true)
                }
                return (false, nil, false)
            }
            if state.0 {
                return .failure(ToolingCliError(state.1 ?? "video writer disconnected"))
            }
            if state.2 {
                return .success(())
            }
            Thread.sleep(forTimeInterval: 0.002)
        }
    }

    func finish() -> Result<String, ToolingCliError> {
        lock.withLock { closed = true }
        while true {
            let done: Result<Void, ToolingCliError>? = lock.withLock {
                workerDone ? (finalResult ?? .success(())) : nil
            }
            if let done {
                return done.map { outputPath }
            }
            Thread.sleep(forTimeInterval: 0.002)
        }
    }

    deinit {
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }
}
#endif

/// Streams finished headless frames to `ffmpeg` and/or PNG files.
final class ToolingWriter {
    let size: (UInt32, UInt32)
    #if !os(WASI) && !os(Android)
    private var videoSession: VideoEncoderSession? = nil
    #endif
    private var pngError: ToolingCliError? = nil

    init(_ size: (UInt32, UInt32)) {
        self.size = size
    }

    var hasVideo: Bool {
        #if !os(WASI) && !os(Android)
        return videoSession != nil
        #else
        return false
        #endif
    }

    func video(_ path: String, _ fps: Double) -> Result<Void, ToolingCliError> {
        switch toolingFfmpegArgs(path, size, fps) {
        case .failure(let err):
            return .failure(err)
        case .success(let args):
            #if os(WASI) || os(Android)
            _ = args
            return .failure(ToolingCliError("--video needs ffmpeg on PATH"))
            #else
            let url = URL(fileURLWithPath: path)
            let dir = url.deletingLastPathComponent()
            if !dir.path.isEmpty {
                do {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                } catch {
                    return .failure(ToolingCliError("\(dir.path): \(error)"))
                }
            }
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = ["ffmpeg"] + args
            let pipe = Pipe()
            proc.standardInput = pipe
            proc.standardOutput = FileHandle.nullDevice
            // Probe PATH for `ffmpeg` first so missing `ffmpeg` reports the exact install hint
            if !Self.commandExistsOnPath("ffmpeg") {
                return .failure(ToolingCliError("--video needs ffmpeg on PATH (macOS: brew install ffmpeg; Debian/Ubuntu: apt install ffmpeg)"))
            }
            do {
                try proc.run()
            } catch {
                return .failure(ToolingCliError("--video needs ffmpeg on PATH (macOS: brew install ffmpeg; Debian/Ubuntu: apt install ffmpeg)"))
            }
            videoSession = VideoEncoderSession(process: proc, pipe: pipe, outputPath: path)
            return .success(())
            #endif
        }
    }

    #if !os(WASI) && !os(Android)
    private static func commandExistsOnPath(_ name: String) -> Bool {
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        for dir in envPath.split(separator: ":") {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return true
            }
        }
        return false
    }

    /// Test hook mirroring `Writer::encode(child, path)` in `crates/rune/src/tooling/record.rs`.
    func encodeShellForTest(_ command: String, _ path: String) -> Result<Void, ToolingCliError> {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", command]
        let pipe = Pipe()
        proc.standardInput = pipe
        do {
            try proc.run()
        } catch {
            return .failure(ToolingCliError("sh: \(error)"))
        }
        videoSession = VideoEncoderSession(process: proc, pipe: pipe, outputPath: path)
        return .success(())
    }
    #endif

    func frame(_ pixels: [UInt8]) -> Result<Void, ToolingCliError> {
        #if !os(WASI) && !os(Android)
        if let session = videoSession {
            let res = session.send(pixels)
            if case .failure = res {
                _ = finish()
            }
            return res
        }
        #endif
        return .success(())
    }

    func png(_ path: String, _ pixels: [UInt8]) -> Result<Void, ToolingCliError> {
        do {
            try toolingWritePng(path, size.0, size.1, pixels)
            return .success(())
        } catch let err as ToolingCliError {
            pngError = err
            return .failure(err)
        } catch {
            let err = ToolingCliError("\(path): \(error)")
            pngError = err
            return .failure(err)
        }
    }

    func finish() -> Result<String?, ToolingCliError> {
        var videoOut: Result<String?, ToolingCliError> = .success(nil)
        #if !os(WASI) && !os(Android)
        if let session = videoSession {
            videoSession = nil
            videoOut = session.finish().map { Optional($0) }
        }
        #endif
        if let err = pngError {
            pngError = nil
            return .failure(err)
        }
        return videoOut
    }
}
