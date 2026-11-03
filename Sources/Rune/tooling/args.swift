// Ported from: crates/rune/src/tooling/args.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The tooling arguments: `Args` and its parser.

#if !os(WASI)
import Foundation
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(Musl)
import Musl
#elseif os(Windows)
import ucrt
#elseif os(WASI)
import WASILibc
#endif

/// Where `--keys` screencast keycaps sit (`crates/rune/src/input/keycaps.rs`).
enum ToolingKeycapCorner: String, Sendable, Equatable {
    case bottomLeft = "bottom-left"
    case bottom = "bottom"
    case bottomRight = "bottom-right"
    case topLeft = "top-left"
    case top = "top"
    case topRight = "top-right"

    static func parse(_ s: String) -> ToolingKeycapCorner? {
        ToolingKeycapCorner(rawValue: s)
    }
}

/// `--keys-theme`: dark (`true`) or light (`false`) caps, or `nil` (`auto`) matching the app's theme.
func toolingParseKeycapTheme(_ s: String) -> Bool?? {
    switch s {
    case "auto": return .some(nil)
    case "light": return .some(false)
    case "dark": return .some(true)
    default: return nil
    }
}

/// Duration specifier for `--duration`.
enum ToolingDurationLength: Sendable, Equatable {
    case seconds(Double)
    /// To the script's `end` mark, or one second after its last event.
    case auto
}

/// Retain the whole expression until the script is loaded: a mark's name can end in `-1`.
func toolingMarkTime(_ v: String) -> String? {
    guard v.hasPrefix("mark:") else { return nil }
    return String(v.dropFirst(5))
}

/// Parsed command-line tooling arguments (`crates/rune/src/tooling/args.rs`).
public struct Args: Sendable, Equatable {
    public var snap: String? = nil
    public var scene: String? = nil
    public var at: Double? = nil
    public var size: (Float, Float)? = nil
    public var scale: Float? = nil
    public var theme: String? = nil
    public var script: String? = nil
    public var frames: Int? = nil
    public var start: Double = 0.0
    public var fps: Double = 60.0
    public var out: String? = nil
    public var tree: String? = nil
    public var trace: String? = nil
    /// Trace the native window's submission clock instead of a virtual headless clock.
    public var native: Bool = false
    /// Trace every element, keyed or not (paths name the unkeyed ones).
    public var traceAll: Bool = false
    public var strip: String? = nil
    public var crops: [[Float]] = []
    public var every: Int = 1
    public var cols: Int = 10
    public var listScenes: Bool = false
    public var firstPixels: Bool = false
    public var window: String? = nil
    public var listWindows: Bool = false
    /// Draw where macOS will put the traffic lights over headless frames, and report elements
    /// that overlap them.
    public var chromeOverlay: Bool = false

    var video: String? = nil
    var duration: ToolingDurationLength? = nil
    var atMark: String? = nil
    var startMark: String? = nil
    var keys: ToolingKeycapCorner? = nil
    var keysTheme: Bool? = nil
    var pointer: Bool = false
    var desktop: String? = nil
    /// `--playground [NAME]`: `.some(nil)` when unnamed, `.some(.some(name))` when named, `nil` when absent.
    var playground: String?? = nil
    var variant: String? = nil
    var cropKey: String? = nil
    var wholeWindow: Bool = false

    public init() {}

    public static func == (lhs: Args, rhs: Args) -> Bool {
        let sameSize: Bool
        switch (lhs.size, rhs.size) {
        case (nil, nil): sameSize = true
        case (let l?, let r?): sameSize = l.0 == r.0 && l.1 == r.1
        default: sameSize = false
        }
        let samePlayground: Bool
        switch (lhs.playground, rhs.playground) {
        case (nil, nil): samePlayground = true
        case (.some(let l), .some(let r)): samePlayground = l == r
        default: samePlayground = false
        }
        return lhs.snap == rhs.snap
            && lhs.scene == rhs.scene
            && lhs.at == rhs.at
            && sameSize
            && lhs.scale == rhs.scale
            && lhs.theme == rhs.theme
            && lhs.script == rhs.script
            && lhs.frames == rhs.frames
            && lhs.start == rhs.start
            && lhs.fps == rhs.fps
            && lhs.out == rhs.out
            && lhs.tree == rhs.tree
            && lhs.trace == rhs.trace
            && lhs.native == rhs.native
            && lhs.traceAll == rhs.traceAll
            && lhs.strip == rhs.strip
            && lhs.crops == rhs.crops
            && lhs.every == rhs.every
            && lhs.cols == rhs.cols
            && lhs.listScenes == rhs.listScenes
            && lhs.firstPixels == rhs.firstPixels
            && lhs.window == rhs.window
            && lhs.listWindows == rhs.listWindows
            && lhs.chromeOverlay == rhs.chromeOverlay
            && lhs.video == rhs.video
            && lhs.duration == rhs.duration
            && lhs.atMark == rhs.atMark
            && lhs.startMark == rhs.startMark
            && lhs.keys == rhs.keys
            && lhs.keysTheme == rhs.keysTheme
            && lhs.pointer == rhs.pointer
            && lhs.desktop == rhs.desktop
            && samePlayground
            && lhs.variant == rhs.variant
            && lhs.cropKey == rhs.cropKey
            && lhs.wholeWindow == rhs.wholeWindow
    }

    public static func parse() -> Args {
        #if os(WASI)
        return parseFrom([])
        #else
        let argv = Array(CommandLine.arguments.dropFirst())
        return parseFrom(argv)
        #endif
    }

    /// Parses `argv` (without the program name); unrecognised arguments become `extraArgs()`.
    public static func parseFrom(_ argv: [String]) -> Args {
        let (args, extra) = parseSplit(argv)
        setExtraArgsOnce(extra)
        return args
    }

    /// Non-exiting variant for unit tests verifying parser error messages.
    static func tryParseSplit(_ argv: [String]) throws -> (Args, [String]) {
        var a = Args()
        a.fps = 60.0
        a.every = 1
        a.cols = 10
        var extra: [String] = []
        var i = 0

        func val() throws -> String {
            i += 1
            guard i < argv.count else {
                throw ToolingCliError("\(argv[i - 1]) needs a value")
            }
            return argv[i]
        }

        while i < argv.count {
            let arg = argv[i]
            switch arg {
            case "--hot", "--snap-on-patch", "--hot-control":
                throw ToolingCliError("live editing requires the rune/hot feature; use scripts/rune-dev")
            case "--snap":
                a.snap = try val()
            case "--scene":
                a.scene = try val()
            case "--playground":
                a.playground = .some(playgroundParseArg(argv, &i))
            case "--variant":
                a.variant = try val()
            case "--whole-window":
                a.wholeWindow = true
            case "--at":
                let v = try val()
                a.atMark = toolingMarkTime(v)
                if a.atMark == nil {
                    a.at = try toolingTryNum(v)
                }
            case "--size":
                let v = try val()
                switch toolingParseSize(v) {
                case .success(let sz): a.size = sz
                case .failure(let err): throw err
                }
            case "--scale":
                let v = try val()
                switch toolingParseScale(v) {
                case .success(let sc): a.scale = sc
                case .failure(let err): throw err
                }
            case "--theme":
                a.theme = try val()
            case "--script":
                a.script = try val()
            case "--frames":
                a.frames = max(0, Int(try toolingTryNum(try val())))
            case "--start":
                let v = try val()
                a.startMark = toolingMarkTime(v)
                if a.startMark == nil {
                    a.start = try toolingTryNum(v)
                }
            case "--fps":
                a.fps = try toolingTryNum(try val())
            case "--out":
                a.out = try val()
            case "--video":
                a.video = try val()
            case "--duration":
                let v = try val()
                if v == "auto" {
                    a.duration = .auto
                } else {
                    a.duration = .seconds(try toolingTryNum(v))
                }
            case "--keys":
                let corner = (i + 1 < argv.count) ? ToolingKeycapCorner.parse(argv[i + 1]) : nil
                if corner != nil {
                    i += 1
                }
                a.keys = corner ?? .bottomLeft
            case "--keys-theme":
                let v = try val()
                guard let parsed = toolingParseKeycapTheme(v) else {
                    throw ToolingCliError("--keys-theme is auto, light or dark")
                }
                a.keysTheme = parsed
            case "--pointer":
                a.pointer = true
            case "--desktop":
                a.desktop = try val()
            case "--tree":
                a.tree = try val()
            case "--trace":
                a.trace = try val()
            case "--native":
                a.native = true
            case "--trace-all":
                a.traceAll = true
            case "--strip":
                a.strip = try val()
            case "--crop":
                let v = try val()
                let parts = v.split(separator: ",", omittingEmptySubsequences: false).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                if parts.count == 4,
                   let r0 = Float(parts[0]), let r1 = Float(parts[1]),
                   let r2 = Float(parts[2]), let r3 = Float(parts[3]),
                   r0.isFinite, r1.isFinite, r2.isFinite, r3.isFinite
                {
                    a.crops.append([r0, r1, r2, r3])
                } else if v.contains(",") {
                    throw ToolingCliError("--crop is x,y,w,h in points, or an element's key or path")
                } else {
                    a.cropKey = v
                }
            case "--cols":
                a.cols = max(1, Int(try toolingTryNum(try val())))
            case "--every":
                a.every = max(1, Int(try toolingTryNum(try val())))
            case "--list-scenes":
                a.listScenes = true
            case "--first-pixels":
                a.firstPixels = true
            case "--window":
                a.window = try val()
            case "--list-windows":
                a.listWindows = true
            case "--chrome":
                a.chromeOverlay = true
            case "-h", "--help":
                toolingStderr("\(TOOLING_HELP)\n")
                exit(0)
            default:
                extra.append(arg)
            }
            i += 1
        }
        if a.variant != nil && a.playground == nil {
            throw ToolingCliError("--variant needs --playground")
        }
        if a.cropKey != nil && a.snap == nil {
            throw ToolingCliError("--crop KEY needs --snap")
        }
        if a.wholeWindow && (a.playground == nil || a.snap == nil) {
            throw ToolingCliError("--whole-window needs --playground and --snap")
        }
        return (a, extra)
    }

    static func parseProcess() -> Args {
        #if os(WASI)
        return parseSplit([]).0
        #else
        let argv = Array(CommandLine.arguments.dropFirst())
        return parseSplit(argv).0
        #endif
    }

    static func parseSplit(_ argv: [String]) -> (Args, [String]) {
        do {
            return try tryParseSplit(argv)
        } catch let err as ToolingCliError {
            toolingDie(err.message)
        } catch {
            toolingDie("\(error)")
        }
    }

    public func headless() -> Bool {
        snap != nil
            || tree != nil
            || (!native && (script != nil || trace != nil || frames != nil || duration != nil || out != nil))
            || video != nil
            || strip != nil
            || listScenes
            || firstPixels
            || listWindows
            || desktop != nil
    }
}

public struct ToolingCliError: Error, Sendable, Equatable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

private let headlessOnceLock = LiveLock()
// PORT NOTE: Guarded by `headlessOnceLock` so process arguments are parsed at most once for `isHeadless()`.
nonisolated(unsafe) private var cachedProcessHeadless: Bool? = nil

/// Whether this process runs headless: its arguments ask for an offscreen render, a scripted
/// run, a trace or a listing rather than a window, as `Args.headless()` decides.
public func isHeadless() -> Bool {
    headlessOnceLock.withLock {
        if let cached = cachedProcessHeadless {
            return cached
        }
        #if !os(WASI)
        // Under XCTest / swift-testing runners, avoid treating swiftpm's own flags as fatal CLI errors.
        let procName = CommandLine.arguments.first ?? ""
        if procName.contains("swiftpm-testing-helper") || procName.contains("xctest") {
            let parsed = (try? Args.tryParseSplit(Array(CommandLine.arguments.dropFirst())).0.headless()) ?? false
            cachedProcessHeadless = parsed
            return parsed
        }
        #endif
        let h = Args.parseProcess().headless()
        cachedProcessHeadless = h
        return h
    }
}

let TOOLING_HELP: String = """
usage: <app> [window]
  --snap out.png        render offscreen (no window) at --at seconds
  --scene NAME          start from a named scene (--list-scenes)
  --playground [NAME]   open App::playground at launch, at a story; headless too
  --variant N|NAME      open --playground's story on a variant (1 is the first)
                        (--snap with --playground takes only the story's stage by default;
                        --out, --video and --strip frames are the whole window)
  --whole-window        --snap with --playground takes the whole window: list, stage and side
  --crop KEY            crop --snap to the element with that key or path (with --playground,
                        one on the stage, or anywhere in the window with --whole-window)
  --at SECONDS          virtual time of the snapshot/tree (default: end of frames or script);
                        mark:NAME or mark:NAME+0.5 for a script mark's time (also --start)
  --size WxH            viewport in points      --scale N   device scale (default 2)
  --theme dark|light    system appearance
  --script FILE.json    timestamped input, replayed headless (move/down/up/tap/drag, keys,
                        {"focus":false}); a key with "repeat":true is a held key's auto-repeat;
                        {"type":"mark","name":N} marks a time;
                        {"type":"shortcut","chord":"cmd+space"} presses a chord through its
                        registered global shortcut handler, never on_key;
                        an object adds "displays" and "pointer" for place() (rune-placed, --tree)
                        menu-pick with an "id" and menu-cancel answer a pop-up menu;
                        file-dialog with a "path" and file-dialog-cancel a file dialog
  --frames N --fps 60 --start S --out DIR     dump N frames from S seconds
  --video out.mp4       stream frames into ffmpeg (.mp4 H.264, .mov ProRes 4444, .webm VP9);
                        --frames N or --duration SECONDS|auto long (default auto: to the
                        script's "end" mark, or 1 s after its last event)
  --keys [CORNER]       draw keycaps for script keys and chords on frames (bottom-left default;
                        bottom, bottom-right, top-left, top, top-right); never in --tree
  --keys-theme auto|light|dark   cap colours (default auto: match the app's background)
  --pointer             draw a ripple where the script presses
  --desktop BACKDROP.png  draw every visible window at its placed frame, with corners and
                        shadows, over the backdrop (scaled to fill). The output is --size
                        points, else the script's primary display, else the backdrop's pixels
                        at --scale; script x/y are output points, keys go to the key window;
                        --window KEY picks the window --scene and --tree describe
  --strip out.png --crop x,y,w,h --every K    tile dumped frames into one image
                        (repeat --crop to stack several regions per frame; --cols N per row)
  --tree out.json       element tree with animated values
  --trace out.jsonl     per-frame rects/opacity in motion-lint JSONL, with the tracks each frame
                        sampled (tk) and why it was animating (quality.why)
  --trace-all           trace unkeyed elements too, by path
  --native             trace native submissions; --frames N stops after N frames
  --first-pixels        report when the first GPU-complete offscreen pixels are readable
  --window KEY         select a window for headless tools (run_windows, App::window)
  --list-windows       list window keys using a deterministic virtual display
  --chrome              draw where macOS puts the traffic lights; list elements overlapping them
  other arguments are passed to the app (rune::tooling::extra_args)
"""

func toolingStderr(_ text: String) {
    #if !os(WASI)
    if let data = text.data(using: .utf8) {
        try? FileHandle.standardError.write(contentsOf: data)
    }
    #else
    fputs(text, stderr)
    #endif
}

func toolingDie(_ msg: String) -> Never {
    toolingStderr("\(msg)\n")
    exit(2)
}

func toolingTryNum(_ s: String) throws -> Double {
    let trimmed = trimAsciiWhitespace(s)
    guard let v = Double(trimmed), v.isFinite else {
        throw ToolingCliError("not a number: \(s)")
    }
    return v
}

func toolingNum(_ s: String) -> Double {
    do {
        return try toolingTryNum(s)
    } catch let err as ToolingCliError {
        toolingDie(err.message)
    } catch {
        toolingDie("not a number: \(s)")
    }
}

private func toolingPositive(_ s: String) -> Float? {
    let trimmed = trimAsciiWhitespace(s)
    guard let v = Float(trimmed), v.isFinite, v > 0.0 else { return nil }
    return v
}

/// `--size WxH`, in points.
func toolingParseSize(_ v: String) -> Result<(Float, Float), ToolingCliError> {
    if let idx = v.firstIndex(of: "x") {
        let wStr = String(v[..<idx])
        let hStr = String(v[v.index(after: idx)...])
        if let w = toolingPositive(wStr), let h = toolingPositive(hStr) {
            return .success((w, h))
        }
    }
    return .failure(ToolingCliError("--size is WxH, both above 0: \(v)"))
}

func toolingParseScale(_ v: String) -> Result<Float, ToolingCliError> {
    if let s = toolingPositive(v) {
        return .success(s)
    }
    return .failure(ToolingCliError("--scale is a number above 0: \(v)"))
}

func trimAsciiWhitespace(_ s: String) -> String {
    var start = s.startIndex
    var end = s.endIndex
    while start < end && (s[start] == " " || s[start] == "\t" || s[start] == "\n" || s[start] == "\r") {
        start = s.index(after: start)
    }
    while end > start {
        let prev = s.index(before: end)
        if s[prev] == " " || s[prev] == "\t" || s[prev] == "\n" || s[prev] == "\r" {
            end = prev
        } else {
            break
        }
    }
    return String(s[start..<end])
}

/// Optional value parser for `--playground [NAME]` (`crates/rune/src/playground.rs:arg`).
func playgroundParseArg(_ argv: [String], _ i: inout Int) -> String? {
    guard i + 1 < argv.count else { return nil }
    let next = argv[i + 1]
    if next.hasPrefix("-") {
        return nil
    }
    i += 1
    return next
}
