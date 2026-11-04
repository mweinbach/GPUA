// Ported from: crates/rune/src/image.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

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
#if canImport(ImageIO) && canImport(CoreGraphics)
import CoreGraphics
import ImageIO
#endif
#if os(macOS) && canImport(AppKit)
import AppKit
#endif

/// 32-byte content-addressed image identifier.
public typealias ImageId = [UInt8]

/// Error reported when decoding, fetching, or rasterizing an image fails.
public struct ImageError: Error, Sendable, Equatable, CustomStringConvertible, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public init(stringLiteral value: String) {
        self.message = value
    }

    public var description: String { message }
}

// PORT NOTE: Synchronized via `condition` (or `LiveLock` on WASI) so `Image` handles are `Sendable` across cache workers and UI threads.
internal final class ImageState: @unchecked Sendable {
    internal let id: ImageId
    internal let pixels: Pixels
    #if !os(WASI)
    private let condition = NSCondition()
    #else
    private let lock = LiveLock()
    #endif
    private var resolved: Result<DecodedImageMips, ImageError>? = nil

    internal init(id: ImageId) {
        self.id = id
        self.pixels = Pixels()
    }

    internal func getDecoded() -> Result<DecodedImageMips, ImageError>? {
        #if !os(WASI)
        condition.lock()
        defer { condition.unlock() }
        return resolved
        #else
        return lock.withLock { resolved }
        #endif
    }

    internal func waitDecoded() -> Result<DecodedImageMips, ImageError> {
        #if !os(WASI)
        condition.lock()
        defer { condition.unlock() }
        while resolved == nil {
            condition.wait()
        }
        return resolved!
        #else
        guard let result = lock.withLock({ resolved }) else {
            preconditionFailure("Image.wait cannot block on web; use isReady and the cache waker")
        }
        return result
        #endif
    }

    /// Marks the state resolved before notifying `pixels`, so a woken frame always sees `isReady == true` and `size()`.
    internal func finish(_ outcome: Result<DecodedImageMips, ImageError>) {
        var mipsToPublish: DecodedImageMips? = nil
        #if !os(WASI)
        condition.lock()
        if resolved == nil {
            resolved = outcome
            if case .success(let mips) = outcome {
                mipsToPublish = mips
            }
        }
        condition.broadcast()
        condition.unlock()
        #else
        lock.withLock {
            if resolved == nil {
                resolved = outcome
                if case .success(let mips) = outcome {
                    mipsToPublish = mips
                }
            }
        }
        #endif
        if let mips = mipsToPublish {
            pixels.setMips(mips)
        }
    }
}

/// A cheap shared handle to a content-addressed image. Pending images paint nothing until their worker wakes the app.
public struct Image: Sendable, CustomDebugStringConvertible {
    internal let state: ImageState

    internal init(_ state: ImageState) {
        self.state = state
    }

    /// The shared static pixel handle, ready to pass to `El.pixels` after decoding.
    public func pixels() -> Pixels {
        state.pixels
    }

    public func id() -> ImageId {
        state.id
    }

    public func size() -> [UInt32]? {
        guard case .success(let decoded)? = state.getDecoded(),
              let first = decoded.mips.first else {
            return nil
        }
        return [first.width, first.height]
    }

    public func isReady() -> Bool {
        state.getDecoded() != nil
    }

    public func error() -> ImageError? {
        guard case .failure(let err)? = state.getDecoded() else {
            return nil
        }
        return err
    }

    /// Wait for fixture assets before advancing a deterministic headless scene.
    public func wait() -> Result<[UInt32], ImageError> {
        switch state.waitDecoded() {
        case .success(let decoded):
            guard let first = decoded.mips.first else {
                return .failure(ImageError("decoded image has no mip levels"))
            }
            return .success([first.width, first.height])
        case .failure(let err):
            return .failure(err)
        }
    }

    internal func decoded() -> Result<DecodedImageMips, ImageError>? {
        state.getDecoded()
    }

    internal func finish(_ decoded: Result<DecodedImageMips, ImageError>) {
        state.finish(decoded)
    }

    internal func sharesIdentity(with other: Image) -> Bool {
        state === other.state
    }

    public var debugDescription: String {
        "Image(id: \(id()), size: \(String(describing: size())))"
    }
}

internal enum ImageInput: Sendable {
    case encoded([UInt8])
    case rgba(UInt32, UInt32, [UInt8])
    case icon(String, UInt32)
    case svg([UInt8], UInt32)
    case file(String, UInt32)
    case url(String, UInt32)
    case simulatedPanic(String)

    internal func decode() -> Result<DecodedImageMips, ImageError> {
        switch self {
        case .encoded(let bytes):
            return decodeImageBytes(bytes)
        case .rgba(let w, let h, let bytes):
            return mipChain(w, h, bytes)
        case .svg(let bytes, let px):
            return svgRgba(bytes, px).flatMap { mipChain($0.0, $0.1, $0.2) }
        case .icon(let path, let px):
            #if os(WASI)
            _ = (path, px)
            return .failure(ImageError("filesystem images are unsupported on web"))
            #else
            return appIconRgba(path, px).flatMap { mipChain($0.0, $0.1, $0.2) }
            #endif
        case .file(let path, let px):
            #if os(WASI)
            return .failure(ImageError("\(path): fetched, not decoded"))
            #else
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let bytes = [UInt8](data)
                if hasSvgExtension(path) || isSvg(bytes) {
                    return svgRgba(bytes, px).flatMap { mipChain($0.0, $0.1, $0.2) }
                }
                return decodeImageBytes(bytes)
            } catch {
                return .failure(ImageError("\(path): \(error.localizedDescription)"))
            }
            #endif
        case .url(let url, let px):
            #if os(WASI)
            _ = px
            return .failure(ImageError("\(url): fetched, not decoded"))
            #else
            switch imageFilePathFromUrl(url) {
            case .success(let resolvedPath):
                return ImageInput.file(resolvedPath, px).decode()
            case .failure(let err):
                return .failure(err)
            }
            #endif
        case .simulatedPanic(let reason):
            return .failure(ImageError("image decoder panicked: \(reason)"))
        }
    }
}

private struct WeakImageState {
    weak var value: ImageState?
}

#if !os(WASI)
private let IMAGE_DECODERS: Int = 4

private struct ImageJob: Sendable {
    var image: Image
    var input: ImageInput
}

// PORT NOTE: Bounded-thread job queue synchronized with `NSCondition`; closes cleanly when `ImageCache` deinitializes.
private final class ImageJobQueue: @unchecked Sendable {
    private let condition = NSCondition()
    private var queue: [ImageJob] = []
    private var head: Int = 0
    private var closed: Bool = false

    func send(_ job: ImageJob) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        guard !closed else { return false }
        queue.append(job)
        condition.signal()
        return true
    }

    func close() {
        condition.lock()
        closed = true
        condition.broadcast()
        condition.unlock()
    }

    func recv() -> ImageJob? {
        condition.lock()
        defer { condition.unlock() }
        while head >= queue.count && !closed {
            condition.wait()
        }
        guard head < queue.count else { return nil }
        let job = queue[head]
        head += 1
        if head >= 32 && head * 2 >= queue.count {
            queue.removeFirst(head)
            head = 0
        } else if head == queue.count {
            queue.removeAll(keepingCapacity: true)
            head = 0
        }
        return job
    }
}
#endif

/// Content-addressed image cache. Construct once during app setup; dropping all ``Image`` handles
/// releases decoded pixels, and dropping the cache stops its workers after queued requests complete.
// PORT NOTE: Entries map is synchronized via `entriesLock: LiveLock`; worker threads communicate via thread-safe `ImageJobQueue`.
public final class ImageCache: @unchecked Sendable {
    private let entriesLock = LiveLock()
    private var entries: [ImageId: WeakImageState] = [:]
    #if !os(WASI)
    private let jobs: ImageJobQueue
    #else
    private let wake: Waker
    #endif

    public static func new(_ waker: @escaping Waker) -> ImageCache {
        ImageCache(waker)
    }

    public init(_ waker: @escaping Waker) {
        #if !os(WASI)
        let jobQueue = ImageJobQueue()
        self.jobs = jobQueue
        let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let workerCount = min(IMAGE_DECODERS, cores)
        for _ in 0..<workerCount {
            let thread = Thread {
                while let job = jobQueue.recv() {
                    let decoded = job.input.decode()
                    job.image.finish(decoded)
                    waker()
                }
            }
            thread.name = "rune-images"
            thread.start()
        }
        #else
        self.wake = waker
        #endif
    }

    #if !os(WASI)
    deinit {
        jobs.close()
    }
    #endif

    /// PNG, JPEG, modern ICNS containing a PNG representation, or SVG.
    public func load(_ bytes: [UInt8]) -> Image {
        var hasher = RuneSha256()
        hasher.update(Array("rune-encoded\0".utf8))
        hasher.update(bytes)
        return request(hasher.finalize(), .encoded(bytes))
    }

    /// SVG or SVGZ bytes rasterized to fit `sizePt` points square at `scale` device pixels per point.
    public func svg(_ bytes: [UInt8], _ sizePt: Float, _ scale: Float) -> Image {
        let px = iconPixels(sizePt, scale)
        var hasher = RuneSha256()
        hasher.update(Array("rune-svg\0".utf8))
        hasher.updateUInt32LE(px)
        hasher.update(bytes)
        return request(hasher.finalize(), .svg(bytes, px))
    }

    /// Bytes with a MIME type: `image/svg+xml` rasterizes like ``svg(_:_:_:)``, anything else decodes like ``load(_:)``.
    public func loadMime(_ bytes: [UInt8], _ mime: String, _ sizePt: Float, _ scale: Float) -> Image {
        let essence = mime.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        if essence.lowercased() == "image/svg+xml" {
            return svg(bytes, sizePt, scale)
        }
        return load(bytes)
    }

    /// An image file, read and decoded on the worker.
    public func file(_ path: String, _ sizePt: Float, _ scale: Float) -> Image {
        let px = iconPixels(sizePt, scale)
        var hasher = RuneSha256()
        hasher.update(Array("rune-file\0".utf8))
        hasher.update(Array(path.utf8))
        hasher.update([0])
        hasher.updateUInt32LE(px)
        #if os(WASI)
        let input: ImageInput = .url(path, px)
        #else
        let input: ImageInput = .file(path, px)
        #endif
        return request(hasher.finalize(), input)
    }

    /// Straight-alpha sRGB RGBA8. Validation, premultiplication and mips happen off-thread.
    public func rgba(_ width: UInt32, _ height: UInt32, _ bytes: [UInt8]) -> Image {
        var hasher = RuneSha256()
        hasher.update(Array("rune-rgba8\0".utf8))
        hasher.updateUInt32LE(width)
        hasher.updateUInt32LE(height)
        hasher.update(bytes)
        return request(hasher.finalize(), .rgba(width, height, bytes))
    }

    /// The Finder / desktop icon for an app bundle or file path, rasterized at 2x `sizePt`.
    public func appIcon(_ path: String, _ sizePt: Float) -> Image {
        appIconScaled(path, sizePt, 2.0)
    }

    /// The Finder / desktop icon for `path`, rasterized at `sizePt * scale` pixels square.
    public func appIconScaled(_ path: String, _ sizePt: Float, _ scale: Float) -> Image {
        let px = iconPixels(sizePt, scale)
        var hasher = RuneSha256()
        hasher.update(Array("rune-app-icon\0".utf8))
        hasher.update(Array(path.utf8))
        hasher.update([0])
        hasher.updateUInt32LE(sizePt.bitPattern)
        hasher.updateUInt32LE(scale.bitPattern)
        return request(hasher.finalize(), .icon(path, px))
    }

    internal func request(_ id: ImageId, _ input: ImageInput) -> Image {
        let stateAndIsNew: (ImageState, Bool) = entriesLock.withLock {
            if let existing = entries[id]?.value {
                return (existing, false)
            }
            entries = entries.filter { $0.value.value != nil }
            let fresh = ImageState(id: id)
            entries[id] = WeakImageState(value: fresh)
            return (fresh, true)
        }
        let image = Image(stateAndIsNew.0)
        guard stateAndIsNew.1 else { return image }

        #if !os(WASI)
        if !jobs.send(ImageJob(image: image, input: input)) {
            image.finish(.failure(ImageError("image worker stopped")))
        }
        #else
        let decoded = input.decode()
        image.finish(decoded)
        wake()
        #endif
        return image
    }
}

internal func iconPixels(_ sizePt: Float, _ scale: Float) -> UInt32 {
    let px = (sizePt * scale).rounded(.up)
    guard px.isFinite else { return 1 }
    return UInt32(min(1024.0, max(1.0, px)))
}

internal func hasSvgExtension(_ path: String) -> Bool {
    let lower = path.lowercased()
    return lower.hasSuffix(".svg") || lower.hasSuffix(".svgz")
}

/// Gzip (SVGZ), or markup after an optional UTF-8 BOM and ASCII whitespace. No raster format starts with `<`.
internal func isSvg(_ bytes: [UInt8]) -> Bool {
    if bytes.count >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B {
        return true
    }
    var start = 0
    if bytes.count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF {
        start = 3
    }
    for i in start..<bytes.count {
        let b = bytes[i]
        if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D || b == 0x0C {
            continue
        }
        return b == UInt8(ascii: "<")
    }
    return false
}

// PORT NOTE: Upstream gates `resvg` behind an optional `svg` Cargo feature and returns this error when disabled; GPUA avoids adding external SVG dependencies without an ADR (Golden Rule 8).
internal func svgRgba(_ bytes: [UInt8], _ px: UInt32) -> Result<(UInt32, UInt32, [UInt8]), ImageError> {
    _ = (bytes, px)
    return .failure(ImageError("SVG images need rune's `svg` feature"))
}

/// Rasterize the platform icon for an app bundle or file at about `px`x`px`, as straight-alpha sRGB RGBA8.
public func appIconRgba(_ path: String, _ px: UInt32) -> Result<(UInt32, UInt32, [UInt8]), ImageError> {
    guard px >= 1 && px <= 1024 else {
        return .failure(ImageError("app icon size must be 1..=1024 pixels"))
    }
    #if os(macOS) && canImport(AppKit)
    return macosIcon(path, px)
    #elseif os(Linux)
    return linuxIcon(path, px)
    #else
    _ = path
    return .failure(ImageError("app_icon is unsupported on this platform"))
    #endif
}

#if os(macOS) && canImport(AppKit)
private func macosIcon(_ path: String, _ px: UInt32) -> Result<(UInt32, UInt32, [UInt8]), ImageError> {
    autoreleasepool {
        let icon = NSWorkspace.shared.icon(forFile: path)
        let big = max(px, 256)
        let largeRep: NSBitmapImageRep
        switch macosBitmap(side: big, draw: { _ in
            icon.draw(
                in: NSRect(x: 0, y: 0, width: CGFloat(big), height: CGFloat(big)),
                from: .zero,
                operation: .copy,
                fraction: 1.0
            )
        }) {
        case .success(let rep):
            largeRep = rep
        case .failure(let err):
            return .failure(err)
        }

        let smallRep: NSBitmapImageRep
        if big == px {
            smallRep = largeRep
        } else {
            switch macosBitmap(side: px, draw: { ctx in
                ctx.imageInterpolation = .high
                _ = largeRep.draw(
                    in: NSRect(x: 0, y: 0, width: CGFloat(px), height: CGFloat(px)),
                    from: .zero,
                    operation: .copy,
                    fraction: 1.0,
                    respectFlipped: false,
                    hints: nil
                )
            }) {
            case .success(let rep):
                smallRep = rep
            case .failure(let err):
                return .failure(err)
            }
        }

        let side = Int(px)
        let stride = smallRep.bytesPerRow
        guard let data = smallRep.bitmapData, stride >= side * 4 else {
            return .failure(ImageError("icon bitmap has no pixel data"))
        }
        var out = [UInt8]()
        out.reserveCapacity(side * side * 4)
        for y in 0..<side {
            let row = data.advanced(by: y * stride)
            for x in 0..<side {
                let p = row.advanced(by: x * 4)
                let r = UInt32(p[0])
                let g = UInt32(p[1])
                let b = UInt32(p[2])
                let a = UInt32(p[3])
                if a == 0 {
                    out.append(contentsOf: [0, 0, 0, 0])
                } else {
                    let sr = UInt8(min(255, (r * 255 + a / 2) / a))
                    let sg = UInt8(min(255, (g * 255 + a / 2) / a))
                    let sb = UInt8(min(255, (b * 255 + a / 2) / a))
                    out.append(contentsOf: [sr, sg, sb, UInt8(a)])
                }
            }
        }
        return .success((px, px, out))
    }
}

private func macosBitmap(
    side: UInt32,
    draw: (NSGraphicsContext) -> Void
) -> Result<NSBitmapImageRep, ImageError> {
    let n = Int(side)
    guard let rawRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: n,
        pixelsHigh: n,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: n * 4,
        bitsPerPixel: 32
    ) else {
        return .failure(ImageError("could not allocate an icon bitmap"))
    }
    let tagged = rawRep.converting(to: .sRGB, renderingIntent: .default) ?? rawRep
    guard let ctx = NSGraphicsContext(bitmapImageRep: tagged) else {
        return .failure(ImageError("could not create an icon context"))
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    draw(ctx)
    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return .success(tagged)
}
#endif

#if os(Linux)
private func linuxIcon(_ path: String, _ px: UInt32) -> Result<(UInt32, UInt32, [UInt8]), ImageError> {
    let resolvedFile: String
    if path.hasSuffix(".desktop") {
        guard let found = FreedesktopIconLookup.iconFile(entryPath: path, px: px, dataDirs: FreedesktopIconLookup.dataDirs()) else {
            return .failure(ImageError("no icon for \(path)"))
        }
        resolvedFile = found
    } else {
        resolvedFile = path
    }
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: resolvedFile))
        if data.count > (16 << 20) {
            return .failure(ImageError("\(resolvedFile) is too large for an icon"))
        }
        let bytes = [UInt8](data)
        if hasSvgExtension(resolvedFile) {
            return svgRgba(bytes, px)
        }
        switch RunePngCodec.decodeRgba8(bytes) {
        case .success(let (w, h, rgba)):
            if w > 1024 || h > 1024 {
                return .failure(ImageError("\(resolvedFile) is too large for an icon"))
            }
            return .success((w, h, rgba))
        case .failure(let err):
            return .failure(ImageError("\(resolvedFile): \(err)"))
        }
    } catch {
        return .failure(ImageError("\(resolvedFile): \(error.localizedDescription)"))
    }
}
#endif

/// Freedesktop `.desktop` icon lookup (`[Desktop Entry]` `Icon=` key across hicolor theme and `pixmaps`).
#if !os(WASI)
internal enum FreedesktopIconLookup {
    internal static func dataDirs() -> [String] {
        let env = ProcessInfo.processInfo.environment
        var dirs: [String] = []
        if let xdgHome = env["XDG_DATA_HOME"], !xdgHome.isEmpty {
            dirs.append(xdgHome)
        } else if let home = env["HOME"], !home.isEmpty {
            dirs.append((home as NSString).appendingPathComponent(".local/share"))
        }
        let system = (env["XDG_DATA_DIRS"].flatMap { $0.isEmpty ? nil : $0 }) ?? "/usr/local/share:/usr/share"
        for part in system.split(separator: ":") where !part.isEmpty {
            dirs.append(String(part))
        }
        return dirs
    }

    /// Extracts the `Icon=` value of the `[Desktop Entry]` group.
    internal static func iconName(_ entry: String) -> String? {
        var group = ""
        for rawLine in entry.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                group = line
                continue
            }
            guard group == "[Desktop Entry]" else { continue }
            guard let eqIdx = line.firstIndex(of: "=") else { continue }
            let key = line[..<eqIdx].trimmingCharacters(in: .whitespaces)
            guard key == "Icon" else { continue }
            let value = line[line.index(after: eqIdx)...].trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    internal static func iconFile(entryPath: String, px: UInt32, dataDirs: [String]) -> String? {
        let fm = FileManager.default
        guard let text = try? String(contentsOfFile: entryPath, encoding: .utf8),
              let rawName = iconName(text) else {
            return nil
        }
        if (rawName as NSString).isAbsolutePath || rawName.hasPrefix("/") {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: rawName, isDirectory: &isDir), !isDir.boolValue {
                return rawName
            }
            return nil
        }
        let name: String
        if rawName.hasSuffix(".png") {
            name = String(rawName.dropLast(4))
        } else if rawName.hasSuffix(".svg") {
            name = String(rawName.dropLast(4))
        } else {
            name = rawName
        }

        var found: [(UInt32?, String)] = []
        for dir in dataDirs {
            let hicolor = (dir as NSString).appendingPathComponent("icons/hicolor")
            guard let sizeLabels = try? fm.contentsOfDirectory(atPath: hicolor) else { continue }
            for label in sizeLabels.sorted() {
                let effective: UInt32?
                if label == "scalable" {
                    effective = nil
                } else {
                    let parts = label.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
                    let dims = String(parts[0])
                    let scaleStr = parts.count > 1 ? String(parts[1]) : "1"
                    let dimParts = dims.split(separator: "x", maxSplits: 1, omittingEmptySubsequences: false)
                    guard let w = UInt32(dimParts[0]),
                          let s = UInt32(scaleStr) else {
                        continue
                    }
                    effective = w * max(1, s)
                }
                let appsDir = ((hicolor as NSString).appendingPathComponent(label) as NSString)
                    .appendingPathComponent("apps")
                for ext in ["png", "svg"] {
                    let candidate = (appsDir as NSString).appendingPathComponent("\(name).\(ext)")
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: candidate, isDirectory: &isDir), !isDir.boolValue {
                        found.append((effective, candidate))
                    }
                }
            }
        }

        let covering = found
            .compactMap { pair -> (UInt32, String)? in
                guard let n = pair.0, n >= px else { return nil }
                return (n, pair.1)
            }
            .min(by: { $0.0 < $1.0 })
            .map(\.1)
        if let covering { return covering }
        if let scalable = found.first(where: { $0.0 == nil })?.1 { return scalable }
        let largest = found
            .compactMap { pair -> (UInt32, String)? in
                guard let n = pair.0 else { return nil }
                return (n, pair.1)
            }
            .max(by: { $0.0 < $1.0 })
            .map(\.1)
        if let largest { return largest }

        for dir in dataDirs {
            for ext in ["png", "svg"] {
                let candidate = (dir as NSString).appendingPathComponent("pixmaps/\(name).\(ext)")
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: candidate, isDirectory: &isDir), !isDir.boolValue {
                    return candidate
                }
            }
        }
        return nil
    }
}
#endif

// MARK: - Container & Raster Decoding

internal func decodeImageBytes(_ bytes: [UInt8]) -> Result<DecodedImageMips, ImageError> {
    if isSvg(bytes) {
        return svgRgba(bytes, 0).flatMap { mipChain($0.0, $0.1, $0.2) }
    }
    let payload: [UInt8]
    if bytes.count >= 4 && bytes[0] == 0x69 && bytes[1] == 0x63 && bytes[2] == 0x6E && bytes[3] == 0x73 {
        switch icnsPng(bytes) {
        case .success(let pngSlice):
            payload = pngSlice
        case .failure(let err):
            return .failure(err)
        }
    } else {
        payload = bytes
    }

    if payload.count >= 8 && payload.starts(with: RunePngCodec.pngSignature) {
        switch RunePngCodec.decodeRgba8(payload, maxSide: 8192) {
        case .success(let (w, h, rgba)):
            return mipChain(w, h, rgba)
        case .failure(let err):
            return .failure(err)
        }
    }

    #if canImport(ImageIO) && canImport(CoreGraphics)
    switch decodeWithImageIO(payload) {
    case .success(let (w, h, rgba)):
        return mipChain(w, h, rgba)
    case .failure(let err):
        return .failure(err)
    }
    #else
    return .failure(ImageError("unsupported or malformed image format"))
    #endif
}

internal func icnsPng(_ bytes: [UInt8]) -> Result<[UInt8], ImageError> {
    let invalid = ImageError("invalid ICNS container or no supported PNG representation")
    guard bytes.count >= 8 else { return .failure(invalid) }
    let totalLen = Int(readUInt32BE(bytes, 4))
    guard totalLen == bytes.count else { return .failure(invalid) }
    var pos = 8
    var best: ArraySlice<UInt8>? = nil
    var bestArea: UInt64 = 0
    while pos < totalLen {
        guard pos + 8 <= totalLen else { return .failure(invalid) }
        let chunkSize = Int(readUInt32BE(bytes, pos + 4))
        guard chunkSize >= 8 else { return .failure(invalid) }
        let end = pos + chunkSize
        guard end <= totalLen else { return .failure(invalid) }
        let chunk = bytes[(pos + 8)..<end]
        if chunk.count >= 24 && chunk.starts(with: RunePngCodec.pngSignature) {
            let base = chunk.startIndex
            let w = readUInt32BE(bytes, base + 16)
            let h = readUInt32BE(bytes, base + 20)
            let area = UInt64(w) * UInt64(h)
            if w <= 8192 && h <= 8192 && area > bestArea {
                best = chunk
                bestArea = area
            }
        }
        pos = end
    }
    guard let chosen = best else { return .failure(invalid) }
    return .success(Array(chosen))
}

#if canImport(ImageIO) && canImport(CoreGraphics)
private func decodeWithImageIO(_ bytes: [UInt8]) -> Result<(UInt32, UInt32, [UInt8]), ImageError> {
    let data = Data(bytes) as CFData
    guard let source = CGImageSourceCreateWithData(data, nil),
          CGImageSourceGetCount(source) > 0,
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        return .failure(ImageError("failed to decode raster image"))
    }
    let w = cgImage.width
    let h = cgImage.height
    guard w > 0, h > 0, w <= 8192, h <= 8192, w * h * 4 <= 256 * 1024 * 1024 else {
        return .failure(ImageError("image dimensions exceed 8192x8192 limit"))
    }
    var orientation = 1
    if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
        if let rawOrient = (props[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue
            ?? (props[kCGImagePropertyOrientation as String] as? Int),
           (1...8).contains(rawOrient) {
            orientation = rawOrient
        } else if let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any],
                  let rawOrient = (tiff[kCGImagePropertyTIFFOrientation as String] as? NSNumber)?.intValue
                      ?? (tiff[kCGImagePropertyTIFFOrientation as String] as? Int),
                  (1...8).contains(rawOrient) {
            orientation = rawOrient
        }
    }
    if orientation == 1, let exifOrient = jpegExifOrientation(bytes), (1...8).contains(exifOrient) {
        orientation = exifOrient
    }

    var premul = [UInt8](repeating: 0, count: w * h * 4)
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    let drawn: Bool = premul.withUnsafeMutableBytes { buf in
        guard let base = buf.baseAddress,
              let ctx = CGContext(
                  data: base,
                  width: w,
                  height: h,
                  bitsPerComponent: 8,
                  bytesPerRow: w * 4,
                  space: colorSpace,
                  bitmapInfo: bitmapInfo
              ) else {
            return false
        }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }
    guard drawn else {
        return .failure(ImageError("failed to rasterize image into sRGB buffer"))
    }

    // Unpremultiply to straight-alpha RGBA8.
    for i in stride(from: 0, to: premul.count, by: 4) {
        let a = UInt32(premul[i + 3])
        if a == 0 {
            premul[i] = 0
            premul[i + 1] = 0
            premul[i + 2] = 0
        } else if a < 255 {
            premul[i] = UInt8(min(255, (UInt32(premul[i]) * 255 + a / 2) / a))
            premul[i + 1] = UInt8(min(255, (UInt32(premul[i + 1]) * 255 + a / 2) / a))
            premul[i + 2] = UInt8(min(255, (UInt32(premul[i + 2]) * 255 + a / 2) / a))
        }
    }

    let (outW, outH, oriented) = applyExifOrientation(width: UInt32(w), height: UInt32(h), rgba: premul, orientation: orientation)
    return .success((outW, outH, oriented))
}

private func applyExifOrientation(
    width: UInt32,
    height: UInt32,
    rgba: [UInt8],
    orientation: Int
) -> (UInt32, UInt32, [UInt8]) {
    if orientation == 1 {
        return (width, height, rgba)
    }
    let w = Int(width)
    let h = Int(height)
    let swapped = orientation >= 5
    let dstW = swapped ? h : w
    let dstH = swapped ? w : h
    var out = [UInt8](repeating: 0, count: dstW * dstH * 4)
    for sy in 0..<h {
        for sx in 0..<w {
            let dx: Int
            let dy: Int
            switch orientation {
            case 2: // Flip horizontal
                dx = w - 1 - sx; dy = sy
            case 3: // Rotate 180
                dx = w - 1 - sx; dy = h - 1 - sy
            case 4: // Flip vertical
                dx = sx; dy = h - 1 - sy
            case 5: // Transpose
                dx = sy; dy = sx
            case 6: // Rotate 90 CW
                dx = h - 1 - sy; dy = sx
            case 7: // Transverse
                dx = h - 1 - sy; dy = w - 1 - sx
            case 8: // Rotate 270 CW (90 CCW)
                dx = sy; dy = w - 1 - sx
            default:
                dx = sx; dy = sy
            }
            let sIdx = (sy * w + sx) * 4
            let dIdx = (dy * dstW + dx) * 4
            out[dIdx] = rgba[sIdx]
            out[dIdx + 1] = rgba[sIdx + 1]
            out[dIdx + 2] = rgba[sIdx + 2]
            out[dIdx + 3] = rgba[sIdx + 3]
        }
    }
    return (UInt32(dstW), UInt32(dstH), out)
}

private func jpegExifOrientation(_ bytes: [UInt8]) -> Int? {
    guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
    var pos = 2
    while pos + 4 <= bytes.count {
        guard bytes[pos] == 0xFF else { return nil }
        while pos < bytes.count && bytes[pos] == 0xFF { pos += 1 }
        guard pos < bytes.count else { return nil }
        let marker = bytes[pos]
        pos += 1
        if marker == 0xD9 || marker == 0xDA { break }
        guard pos + 2 <= bytes.count else { return nil }
        let segLen = Int(bytes[pos]) << 8 | Int(bytes[pos + 1])
        guard segLen >= 2, pos + segLen <= bytes.count else { return nil }
        if marker == 0xE1 && segLen >= 16 {
            let payloadStart = pos + 2
            let payloadEnd = pos + segLen
            if payloadStart + 6 <= payloadEnd,
               bytes[payloadStart..<(payloadStart + 6)].elementsEqual([0x45, 0x78, 0x69, 0x66, 0x00, 0x00]) {
                let tiff = payloadStart + 6
                guard tiff + 8 <= payloadEnd else { return nil }
                let le: Bool
                if bytes[tiff] == 0x49 && bytes[tiff + 1] == 0x49 {
                    le = true
                } else if bytes[tiff] == 0x4D && bytes[tiff + 1] == 0x4D {
                    le = false
                } else {
                    return nil
                }
                func u16(_ o: Int) -> UInt16 {
                    le ? (UInt16(bytes[o]) | (UInt16(bytes[o + 1]) << 8))
                       : ((UInt16(bytes[o]) << 8) | UInt16(bytes[o + 1]))
                }
                func u32(_ o: Int) -> UInt32 {
                    le ? (UInt32(bytes[o]) | (UInt32(bytes[o + 1]) << 8) | (UInt32(bytes[o + 2]) << 16) | (UInt32(bytes[o + 3]) << 24))
                       : ((UInt32(bytes[o]) << 24) | (UInt32(bytes[o + 1]) << 16) | (UInt32(bytes[o + 2]) << 8) | UInt32(bytes[o + 3]))
                }
                guard u16(tiff + 2) == 42 else { return nil }
                let ifd0 = tiff + Int(u32(tiff + 4))
                guard ifd0 + 2 <= payloadEnd else { return nil }
                let entries = Int(u16(ifd0))
                var entryPos = ifd0 + 2
                for _ in 0..<entries {
                    guard entryPos + 12 <= payloadEnd else { break }
                    if u16(entryPos) == 0x0112 {
                        return Int(u16(entryPos + 8))
                    }
                    entryPos += 12
                }
            }
        }
        pos += segLen
    }
    return nil
}
#endif

// MARK: - Linear-Light Premultiplied sRGB Mip Chain

private let SRGB_STEPS: Int = 4096

private struct SrgbTransferTables: Sendable {
    let decode: [Float]
    let up: [Float]
    let coarse: [UInt8]

    init() {
        var dec = [Float](repeating: 0, count: 256)
        var upArr = [Float](repeating: 0, count: 256)
        for i in 0..<256 {
            dec[i] = srgbDecode(Float(i) / 255.0)
            upArr[i] = srgbDecode((Float(i) + 0.5) / 255.0)
        }
        upArr[255] = .infinity
        var coarseArr = [UInt8](repeating: 0, count: SRGB_STEPS + 1)
        for i in 0...SRGB_STEPS {
            let target = Float(i) / Float(SRGB_STEPS)
            var lo = 0
            var hi = 256
            while lo < hi {
                let mid = (lo + hi) / 2
                if upArr[mid] <= target {
                    lo = mid + 1
                } else {
                    hi = mid
                }
            }
            coarseArr[i] = UInt8(lo)
        }
        self.decode = dec
        self.up = upArr
        self.coarse = coarseArr
    }

    @inline(__always)
    func encode(_ v: Float, _ a: UInt8) -> UInt8 {
        let cap = Float(a) / 255.0
        let clamped = min(max(v, 0.0), cap)
        let idx = Int(clamped * Float(SRGB_STEPS))
        let b = coarse[idx]
        return b &+ (clamped >= up[Int(b)] ? 1 : 0)
    }
}

private let srgbTables = SrgbTransferTables()

@inline(__always)
internal func quantizeByte(_ v: Float) -> UInt8 {
    UInt8((min(max(v, 0.0), 1.0) * 255.0).rounded())
}

internal func mipChain(_ width: UInt32, _ height: UInt32, _ bytes: [UInt8]) -> Result<DecodedImageMips, ImageError> {
    guard width > 0, height > 0, width <= 8192, height <= 8192,
          bytes.count == Int(width) * Int(height) * 4 else {
        return .failure(ImageError("RGBA image dimensions or byte length are invalid"))
    }
    let srgb = srgbTables
    var top = bytes
    for i in stride(from: 0, to: top.count, by: 4) {
        let aByte = top[i + 3]
        if aByte == 255 { continue }
        let a = Float(aByte) / 255.0
        top[i] = srgb.encode(srgb.decode[Int(top[i])] * a, aByte)
        top[i + 1] = srgb.encode(srgb.decode[Int(top[i + 1])] * a, aByte)
        top[i + 2] = srgb.encode(srgb.decode[Int(top[i + 2])] * a, aByte)
    }

    var mips = [DecodedMipLevel(width: width, height: height, pixels: top)]
    if width > 1 || height > 1 {
        mips.append(downsampleMip(width, height, bytes) { src, offset in
            let a = Float(src[offset + 3]) / 255.0
            return (
                srgb.decode[Int(src[offset])] * a,
                srgb.decode[Int(src[offset + 1])] * a,
                srgb.decode[Int(src[offset + 2])] * a,
                a
            )
        })
    }
    while let last = mips.last, last.width > 1 || last.height > 1 {
        let next = downsampleMip(last.width, last.height, last.pixels) { src, offset in
            return (
                srgb.decode[Int(src[offset])],
                srgb.decode[Int(src[offset + 1])],
                srgb.decode[Int(src[offset + 2])],
                Float(src[offset + 3]) / 255.0
            )
        }
        mips.append(next)
    }
    return .success(DecodedImageMips(mips))
}

private func downsampleMip(
    _ w: UInt32,
    _ h: UInt32,
    _ src: [UInt8],
    _ linear: ([UInt8], Int) -> (Float, Float, Float, Float)
) -> DecodedMipLevel {
    let nw = max(1, w / 2)
    let nh = max(1, h / 2)
    let srgb = srgbTables
    var pixels = [UInt8]()
    pixels.reserveCapacity(Int(nw) * Int(nh) * 4)

    @inline(__always)
    func emit(_ r: Float, _ g: Float, _ b: Float, _ a: Float, _ area: Float) {
        let inv = 1.0 / area
        let aByte = quantizeByte(a * inv)
        pixels.append(srgb.encode(r * inv, aByte))
        pixels.append(srgb.encode(g * inv, aByte))
        pixels.append(srgb.encode(b * inv, aByte))
        pixels.append(aByte)
    }

    if w % 2 == 0 && h % 2 == 0 {
        let strideW = Int(w)
        for y in 0..<Int(nh) {
            for x in 0..<Int(nw) {
                let i0 = (2 * y * strideW + 2 * x) * 4
                let i1 = i0 + 4
                let i2 = i0 + strideW * 4
                let i3 = i2 + 4
                let p0 = linear(src, i0)
                let p1 = linear(src, i1)
                let p2 = linear(src, i2)
                let p3 = linear(src, i3)
                emit(
                    p0.0 + p1.0 + p2.0 + p3.0,
                    p0.1 + p1.1 + p2.1 + p3.1,
                    p0.2 + p1.2 + p2.2 + p3.2,
                    p0.3 + p1.3 + p2.3 + p3.3,
                    4.0
                )
            }
        }
        return DecodedMipLevel(width: nw, height: nh, pixels: pixels)
    }

    let fw = Float(w)
    let fh = Float(h)
    let fnw = Float(nw)
    let fnh = Float(nh)
    let iw = Int(w)
    for y in 0..<nh {
        let y0 = Float(y) * fh / fnh
        let y1 = Float(y + 1) * fh / fnh
        let syStart = UInt32(y0.rounded(.down))
        let syEnd = min(h, UInt32(y1.rounded(.up)))
        for x in 0..<nw {
            let x0 = Float(x) * fw / fnw
            let x1 = Float(x + 1) * fw / fnw
            let sxStart = UInt32(x0.rounded(.down))
            let sxEnd = min(w, UInt32(x1.rounded(.up)))
            var sr: Float = 0, sg: Float = 0, sb: Float = 0, sa: Float = 0
            for sy in syStart..<syEnd {
                let wy = min(Float(sy + 1), y1) - max(Float(sy), y0)
                for sx in sxStart..<sxEnd {
                    let wx = min(Float(sx + 1), x1) - max(Float(sx), x0)
                    let weight = wx * wy
                    let p = linear(src, (Int(sy) * iw + Int(sx)) * 4)
                    sr += p.0 * weight
                    sg += p.1 * weight
                    sb += p.2 * weight
                    sa += p.3 * weight
                }
            }
            emit(sr, sg, sb, sa, (x1 - x0) * (y1 - y0))
        }
    }
    return DecodedMipLevel(width: nw, height: nh, pixels: pixels)
}

// MARK: - Pure-Swift SHA-256 (Content-Addressed 32-Byte Digest)

// PORT NOTE: Pure-Swift SHA-256 replaces `blake3` for 32-byte `ImageId` digests across all platforms without external dependencies (Golden Rule 8).
internal struct RuneSha256 {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    private var state: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ]
    private var buffer: [UInt8] = []
    private var totalBytes: UInt64 = 0

    internal init() {
        buffer.reserveCapacity(64)
    }

    internal mutating func update(_ bytes: [UInt8]) {
        totalBytes &+= UInt64(bytes.count)
        var offset = 0
        if !buffer.isEmpty {
            let needed = 64 - buffer.count
            if bytes.count < needed {
                buffer.append(contentsOf: bytes)
                return
            }
            buffer.append(contentsOf: bytes[0..<needed])
            processBlock(buffer, 0)
            buffer.removeAll(keepingCapacity: true)
            offset = needed
        }
        while offset + 64 <= bytes.count {
            processBlock(bytes, offset)
            offset += 64
        }
        if offset < bytes.count {
            buffer.append(contentsOf: bytes[offset..<bytes.count])
        }
    }

    internal mutating func updateUInt32LE(_ value: UInt32) {
        update([
            UInt8(truncatingIfNeeded: value),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 24),
        ])
    }

    internal mutating func finalize() -> [UInt8] {
        let bitLen = totalBytes &* 8
        buffer.append(0x80)
        if buffer.count > 56 {
            while buffer.count < 64 { buffer.append(0) }
            processBlock(buffer, 0)
            buffer.removeAll(keepingCapacity: true)
        }
        while buffer.count < 56 { buffer.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            buffer.append(UInt8(truncatingIfNeeded: bitLen >> shift))
        }
        processBlock(buffer, 0)
        var out = [UInt8]()
        out.reserveCapacity(32)
        for word in state {
            out.append(UInt8(truncatingIfNeeded: word >> 24))
            out.append(UInt8(truncatingIfNeeded: word >> 16))
            out.append(UInt8(truncatingIfNeeded: word >> 8))
            out.append(UInt8(truncatingIfNeeded: word))
        }
        return out
    }

    private mutating func processBlock(_ data: [UInt8], _ offset: Int) {
        var w = [UInt32](repeating: 0, count: 64)
        for i in 0..<16 {
            let j = offset + i * 4
            w[i] = (UInt32(data[j]) << 24)
                | (UInt32(data[j + 1]) << 16)
                | (UInt32(data[j + 2]) << 8)
                | UInt32(data[j + 3])
        }
        for i in 16..<64 {
            let v0 = w[i - 15]
            let s0 = ((v0 >> 7) | (v0 << 25)) ^ ((v0 >> 18) | (v0 << 14)) ^ (v0 >> 3)
            let v1 = w[i - 2]
            let s1 = ((v1 >> 17) | (v1 << 15)) ^ ((v1 >> 19) | (v1 << 13)) ^ (v1 >> 10)
            w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
        }
        var a = state[0], b = state[1], c = state[2], d = state[3]
        var e = state[4], f = state[5], g = state[6], h = state[7]
        for i in 0..<64 {
            let s1 = ((e >> 6) | (e << 26)) ^ ((e >> 11) | (e << 21)) ^ ((e >> 25) | (e << 7))
            let ch = (e & f) ^ ((~e) & g)
            let temp1 = h &+ s1 &+ ch &+ Self.k[i] &+ w[i]
            let s0 = ((a >> 2) | (a << 30)) ^ ((a >> 13) | (a << 19)) ^ ((a >> 22) | (a << 10))
            let maj = (a & b) ^ (a & c) ^ (b & c)
            let temp2 = s0 &+ maj
            h = g; g = f; f = e; e = d &+ temp1
            d = c; c = b; b = a; a = temp1 &+ temp2
        }
        state[0] &+= a; state[1] &+= b; state[2] &+= c; state[3] &+= d
        state[4] &+= e; state[5] &+= f; state[6] &+= g; state[7] &+= h
    }
}

// MARK: - Pure-Swift Cross-Platform PNG Codec (Encode & Decode RGBA8)

@inline(__always)
private func readUInt32BE(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    (UInt32(bytes[offset]) << 24)
        | (UInt32(bytes[offset + 1]) << 16)
        | (UInt32(bytes[offset + 2]) << 8)
        | UInt32(bytes[offset + 3])
}

internal enum RunePngCodec {
    internal static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    private static let crcTable: [UInt32] = {
        (0..<256).map { n -> UInt32 in
            var c = UInt32(n)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    private static func crc32(type: [UInt8], data: ArraySlice<UInt8>) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in type {
            c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8)
        }
        for b in data {
            c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8)
        }
        return ~c
    }

    private static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var s1: UInt32 = 1
        var s2: UInt32 = 0
        var i = 0
        while i < bytes.count {
            let chunkEnd = min(i + 5552, bytes.count)
            while i < chunkEnd {
                s1 &+= UInt32(bytes[i])
                s2 &+= s1
                i += 1
            }
            s1 %= 65521
            s2 %= 65521
        }
        return (s2 << 16) | s1
    }

    /// Encodes straight-alpha RGBA8 pixels into a valid PNG byte stream (stored zlib blocks).
    internal static func encodeRgba8(width: UInt32, height: UInt32, rgba: [UInt8]) -> [UInt8] {
        let w = Int(width)
        let h = Int(height)
        precondition(w > 0 && h > 0 && rgba.count == w * h * 4)

        var raw = [UInt8]()
        raw.reserveCapacity(h * (1 + w * 4))
        for y in 0..<h {
            raw.append(0) // Filter 0: None
            let start = y * w * 4
            raw.append(contentsOf: rgba[start..<(start + w * 4)])
        }

        // Zlib stream with stored DEFLATE blocks
        var zlib = [UInt8]()
        zlib.reserveCapacity(2 + raw.count + (raw.count / 65535 + 1) * 5 + 4)
        zlib.append(contentsOf: [0x78, 0x01])
        var pos = 0
        while true {
            let remaining = raw.count - pos
            let blockLen = min(65535, remaining)
            let isFinal = (pos + blockLen >= raw.count)
            zlib.append(isFinal ? 0x01 : 0x00)
            let len16 = UInt16(blockLen)
            let nlen16 = ~len16
            zlib.append(UInt8(truncatingIfNeeded: len16))
            zlib.append(UInt8(truncatingIfNeeded: len16 >> 8))
            zlib.append(UInt8(truncatingIfNeeded: nlen16))
            zlib.append(UInt8(truncatingIfNeeded: nlen16 >> 8))
            if blockLen > 0 {
                zlib.append(contentsOf: raw[pos..<(pos + blockLen)])
            }
            pos += blockLen
            if isFinal { break }
        }
        let adler = adler32(raw)
        zlib.append(UInt8(truncatingIfNeeded: adler >> 24))
        zlib.append(UInt8(truncatingIfNeeded: adler >> 16))
        zlib.append(UInt8(truncatingIfNeeded: adler >> 8))
        zlib.append(UInt8(truncatingIfNeeded: adler))

        var out = [UInt8]()
        out.append(contentsOf: pngSignature)

        func writeChunk(_ type: [UInt8], _ payload: [UInt8]) {
            let len = UInt32(payload.count)
            out.append(UInt8(truncatingIfNeeded: len >> 24))
            out.append(UInt8(truncatingIfNeeded: len >> 16))
            out.append(UInt8(truncatingIfNeeded: len >> 8))
            out.append(UInt8(truncatingIfNeeded: len))
            out.append(contentsOf: type)
            out.append(contentsOf: payload)
            let crc = crc32(type: type, data: payload[...])
            out.append(UInt8(truncatingIfNeeded: crc >> 24))
            out.append(UInt8(truncatingIfNeeded: crc >> 16))
            out.append(UInt8(truncatingIfNeeded: crc >> 8))
            out.append(UInt8(truncatingIfNeeded: crc))
        }

        var ihdr = [UInt8]()
        ihdr.reserveCapacity(13)
        for v in [width, height] {
            ihdr.append(UInt8(truncatingIfNeeded: v >> 24))
            ihdr.append(UInt8(truncatingIfNeeded: v >> 16))
            ihdr.append(UInt8(truncatingIfNeeded: v >> 8))
            ihdr.append(UInt8(truncatingIfNeeded: v))
        }
        ihdr.append(contentsOf: [8, 6, 0, 0, 0]) // 8-bit RGBA, non-interlaced
        writeChunk([0x49, 0x48, 0x44, 0x52], ihdr) // IHDR
        writeChunk([0x49, 0x44, 0x41, 0x54], zlib) // IDAT
        writeChunk([0x49, 0x45, 0x4E, 0x44], [])   // IEND
        return out
    }

    /// Decodes a PNG byte stream into straight-alpha RGBA8 pixels.
    internal static func decodeRgba8(
        _ bytes: [UInt8],
        maxSide: UInt32 = 8192
    ) -> Result<(UInt32, UInt32, [UInt8]), ImageError> {
        guard bytes.count >= 8, bytes.starts(with: pngSignature) else {
            return .failure("invalid PNG signature")
        }
        var pos = 8
        var width: UInt32 = 0
        var height: UInt32 = 0
        var bitDepth: UInt8 = 0
        var colorType: UInt8 = 0
        var interlace: UInt8 = 0
        var sawIhdr = false
        var sawIend = false
        var palette: [UInt8] = []
        var trns: [UInt8] = []
        var idat = [UInt8]()

        while pos + 8 <= bytes.count {
            let chunkLen = Int(readUInt32BE(bytes, pos))
            guard chunkLen >= 0, pos + 12 + chunkLen <= bytes.count else {
                return .failure("truncated PNG chunk")
            }
            let typeBytes = Array(bytes[(pos + 4)..<(pos + 8)])
            let dataSlice = bytes[(pos + 8)..<(pos + 8 + chunkLen)]
            let expectedCrc = readUInt32BE(bytes, pos + 8 + chunkLen)
            if crc32(type: typeBytes, data: dataSlice) != expectedCrc {
                return .failure("corrupt PNG chunk CRC")
            }
            pos += 12 + chunkLen

            if typeBytes == [0x49, 0x48, 0x44, 0x52] { // IHDR
                guard !sawIhdr, chunkLen == 13 else { return .failure("invalid PNG IHDR") }
                let base = dataSlice.startIndex
                width = readUInt32BE(bytes, base)
                height = readUInt32BE(bytes, base + 4)
                bitDepth = bytes[base + 8]
                colorType = bytes[base + 9]
                let compression = bytes[base + 10]
                let filter = bytes[base + 11]
                interlace = bytes[base + 12]
                guard width > 0, height > 0 else {
                    return .failure("zero PNG dimensions")
                }
                if width > maxSide || height > maxSide {
                    return .failure("\(width)×\(height) px is over the \(maxSide) px limit")
                }
                if UInt64(width) * UInt64(height) * 4 > 256 * 1024 * 1024 {
                    return .failure("PNG image exceeds 256 MiB allocation limit")
                }
                guard compression == 0, filter == 0, interlace <= 1 else {
                    return .failure("unsupported PNG header parameters")
                }
                let validDepth: Bool
                switch colorType {
                case 0: validDepth = [1, 2, 4, 8, 16].contains(bitDepth)
                case 2: validDepth = [8, 16].contains(bitDepth)
                case 3: validDepth = [1, 2, 4, 8].contains(bitDepth)
                case 4: validDepth = [8, 16].contains(bitDepth)
                case 6: validDepth = [8, 16].contains(bitDepth)
                default: validDepth = false
                }
                guard validDepth else { return .failure("invalid PNG colorType/bitDepth") }
                sawIhdr = true
            } else if typeBytes == [0x50, 0x4C, 0x54, 0x45] { // PLTE
                guard sawIhdr, chunkLen % 3 == 0, chunkLen <= 768 else { return .failure("invalid PNG PLTE") }
                palette = Array(dataSlice)
            } else if typeBytes == [0x74, 0x52, 0x4E, 0x53] { // tRNS
                trns = Array(dataSlice)
            } else if typeBytes == [0x49, 0x44, 0x41, 0x54] { // IDAT
                guard sawIhdr else { return .failure("IDAT before IHDR") }
                idat.append(contentsOf: dataSlice)
            } else if typeBytes == [0x49, 0x45, 0x4E, 0x44] { // IEND
                sawIend = true
                break
            }
        }

        guard sawIhdr, sawIend, !idat.isEmpty else {
            return .failure("incomplete PNG stream")
        }
        if colorType == 3 && palette.isEmpty {
            return .failure("indexed PNG missing PLTE")
        }

        let raw: [UInt8]
        switch ZlibInflater.inflateZlib(idat) {
        case .success(let inflated):
            raw = inflated
        case .failure(let err):
            return .failure(err)
        }

        let channels: Int
        switch colorType {
        case 0, 3: channels = 1
        case 2: channels = 3
        case 4: channels = 2
        case 6: channels = 4
        default: return .failure("unsupported PNG color type")
        }
        let bitsPerPixel = channels * Int(bitDepth)
        let bpp = max(1, (bitsPerPixel + 7) / 8)

        var rgba = [UInt8](repeating: 0, count: Int(width) * Int(height) * 4)
        var rawOffset = 0

        func decodePass(x0: Int, y0: Int, dx: Int, dy: Int) -> String? {
            let passW = (Int(width) - x0 + dx - 1) / dx
            let passH = (Int(height) - y0 + dy - 1) / dy
            if passW <= 0 || passH <= 0 { return nil }
            let rowBytes = (passW * bitsPerPixel + 7) / 8
            guard rawOffset + passH * (1 + rowBytes) <= raw.count else {
                return "truncated PNG image data"
            }
            var prev = [UInt8](repeating: 0, count: rowBytes)
            var curr = [UInt8](repeating: 0, count: rowBytes)

            for py in 0..<passH {
                let filter = raw[rawOffset]
                rawOffset += 1
                for i in 0..<rowBytes {
                    let xByte = raw[rawOffset + i]
                    let a: UInt8 = i >= bpp ? curr[i - bpp] : 0
                    let b: UInt8 = prev[i]
                    let c: UInt8 = i >= bpp ? prev[i - bpp] : 0
                    switch filter {
                    case 0:
                        curr[i] = xByte
                    case 1:
                        curr[i] = xByte &+ a
                    case 2:
                        curr[i] = xByte &+ b
                    case 3:
                        curr[i] = xByte &+ UInt8((Int(a) + Int(b)) >> 1)
                    case 4:
                        curr[i] = xByte &+ paethPredictor(a, b, c)
                    default:
                        return "invalid PNG scanline filter \(filter)"
                    }
                }
                rawOffset += rowBytes

                let dstY = y0 + py * dy
                for px in 0..<passW {
                    let dstX = x0 + px * dx
                    let outIdx = (dstY * Int(width) + dstX) * 4
                    writePixel(
                        row: curr,
                        px: px,
                        colorType: colorType,
                        bitDepth: bitDepth,
                        palette: palette,
                        trns: trns,
                        out: &rgba,
                        outIdx: outIdx
                    )
                }
                swap(&prev, &curr)
            }
            return nil
        }

        if interlace == 0 {
            if let err = decodePass(x0: 0, y0: 0, dx: 1, dy: 1) {
                return .failure(ImageError(err))
            }
        } else {
            let passes = [
                (0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4),
                (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2),
            ]
            for (x0, y0, dx, dy) in passes {
                if let err = decodePass(x0: x0, y0: y0, dx: dx, dy: dy) {
                    return .failure(ImageError(err))
                }
            }
        }

        return .success((width, height, rgba))
    }

    @inline(__always)
    private static func paethPredictor(_ a: UInt8, _ b: UInt8, _ c: UInt8) -> UInt8 {
        let ia = Int(a), ib = Int(b), ic = Int(c)
        let p = ia + ib - ic
        let pa = abs(p - ia)
        let pb = abs(p - ib)
        let pc = abs(p - ic)
        if pa <= pb && pa <= pc { return a }
        if pb <= pc { return b }
        return c
    }

    private static func writePixel(
        row: [UInt8],
        px: Int,
        colorType: UInt8,
        bitDepth: UInt8,
        palette: [UInt8],
        trns: [UInt8],
        out: inout [UInt8],
        outIdx: Int
    ) {
        switch colorType {
        case 6: // RGBA
            if bitDepth == 8 {
                let i = px * 4
                out[outIdx] = row[i]
                out[outIdx + 1] = row[i + 1]
                out[outIdx + 2] = row[i + 2]
                out[outIdx + 3] = row[i + 3]
            } else {
                let i = px * 8
                out[outIdx] = row[i]
                out[outIdx + 1] = row[i + 2]
                out[outIdx + 2] = row[i + 4]
                out[outIdx + 3] = row[i + 6]
            }
        case 2: // RGB
            if bitDepth == 8 {
                let i = px * 3
                let r = row[i], g = row[i + 1], b = row[i + 2]
                let isTransparent = trns.count >= 6
                    && trns[1] == r && trns[3] == g && trns[5] == b
                out[outIdx] = r
                out[outIdx + 1] = g
                out[outIdx + 2] = b
                out[outIdx + 3] = isTransparent ? 0 : 255
            } else {
                let i = px * 6
                let r16 = (UInt16(row[i]) << 8) | UInt16(row[i + 1])
                let g16 = (UInt16(row[i + 2]) << 8) | UInt16(row[i + 3])
                let b16 = (UInt16(row[i + 4]) << 8) | UInt16(row[i + 5])
                let isTransparent = trns.count >= 6
                    && ((UInt16(trns[0]) << 8) | UInt16(trns[1])) == r16
                    && ((UInt16(trns[2]) << 8) | UInt16(trns[3])) == g16
                    && ((UInt16(trns[4]) << 8) | UInt16(trns[5])) == b16
                out[outIdx] = row[i]
                out[outIdx + 1] = row[i + 2]
                out[outIdx + 2] = row[i + 4]
                out[outIdx + 3] = isTransparent ? 0 : 255
            }
        case 3: // Indexed
            let idx = extractSubByteSample(row: row, px: px, bitDepth: Int(bitDepth))
            let pOff = idx * 3
            if pOff + 2 < palette.count {
                out[outIdx] = palette[pOff]
                out[outIdx + 1] = palette[pOff + 1]
                out[outIdx + 2] = palette[pOff + 2]
            }
            out[outIdx + 3] = idx < trns.count ? trns[idx] : 255
        case 0: // Grayscale
            if bitDepth == 16 {
                let i = px * 2
                let g16 = (UInt16(row[i]) << 8) | UInt16(row[i + 1])
                let isTransparent = trns.count >= 2 && ((UInt16(trns[0]) << 8) | UInt16(trns[1])) == g16
                out[outIdx] = row[i]
                out[outIdx + 1] = row[i]
                out[outIdx + 2] = row[i]
                out[outIdx + 3] = isTransparent ? 0 : 255
            } else {
                let rawSample = extractSubByteSample(row: row, px: px, bitDepth: Int(bitDepth))
                let maxVal = (1 << Int(bitDepth)) - 1
                let g8 = UInt8((rawSample * 255 + maxVal / 2) / maxVal)
                let isTransparent = trns.count >= 2 && Int(trns[1]) == rawSample
                out[outIdx] = g8
                out[outIdx + 1] = g8
                out[outIdx + 2] = g8
                out[outIdx + 3] = isTransparent ? 0 : 255
            }
        case 4: // Grayscale + Alpha
            if bitDepth == 8 {
                let i = px * 2
                let g = row[i]
                out[outIdx] = g
                out[outIdx + 1] = g
                out[outIdx + 2] = g
                out[outIdx + 3] = row[i + 1]
            } else {
                let i = px * 4
                let g = row[i]
                out[outIdx] = g
                out[outIdx + 1] = g
                out[outIdx + 2] = g
                out[outIdx + 3] = row[i + 2]
            }
        default:
            break
        }
    }

    private static func extractSubByteSample(row: [UInt8], px: Int, bitDepth: Int) -> Int {
        if bitDepth == 8 { return Int(row[px]) }
        let samplesPerByte = 8 / bitDepth
        let byteIdx = px / samplesPerByte
        let shift = (samplesPerByte - 1 - (px % samplesPerByte)) * bitDepth
        let mask = (1 << bitDepth) - 1
        return (Int(row[byteIdx]) >> shift) & mask
    }

    fileprivate static func verifyAdler32(_ bytes: [UInt8], expected: UInt32) -> Bool {
        adler32(bytes) == expected
    }
}

// MARK: - RFC 1950 / RFC 1951 Zlib + DEFLATE Inflater

private enum ZlibInflater {
    private struct BitReader {
        let data: [UInt8]
        var bytePos: Int
        let byteEnd: Int
        var bitBuf: UInt64 = 0
        var bitCount: Int = 0

        mutating func fill(_ needed: Int) -> Bool {
            while bitCount < needed && bytePos < byteEnd {
                bitBuf |= UInt64(data[bytePos]) << bitCount
                bytePos += 1
                bitCount += 8
            }
            return bitCount >= needed
        }

        mutating func readBits(_ count: Int) -> Int? {
            if count == 0 { return 0 }
            guard fill(count) else { return nil }
            let val = Int(bitBuf & ((1 << count) - 1))
            bitBuf >>= count
            bitCount -= count
            return val
        }

        mutating func alignToByte() {
            let drop = bitCount & 7
            bitBuf >>= drop
            bitCount -= drop
        }

        mutating func readAlignedByte() -> UInt8? {
            if bitCount >= 8 {
                let b = UInt8(truncatingIfNeeded: bitBuf)
                bitBuf >>= 8
                bitCount -= 8
                return b
            }
            guard bytePos < byteEnd else { return nil }
            let b = data[bytePos]
            bytePos += 1
            return b
        }
    }

    private struct HuffmanTree {
        // Canonical Huffman table by code length (1...15)
        var counts: [Int] = [Int](repeating: 0, count: 16)
        var symbols: [Int] = []
        var maxBits: Int = 0

        static func build(lengths: [Int]) -> HuffmanTree? {
            var tree = HuffmanTree()
            for len in lengths where len > 0 {
                guard len <= 15 else { return nil }
                tree.counts[len] += 1
                if len > tree.maxBits { tree.maxBits = len }
            }
            var offsets = [Int](repeating: 0, count: 16)
            var total = 0
            for bits in 1...15 {
                offsets[bits] = total
                total += tree.counts[bits]
            }
            tree.symbols = [Int](repeating: 0, count: total)
            for (sym, len) in lengths.enumerated() where len > 0 {
                tree.symbols[offsets[len]] = sym
                offsets[len] += 1
            }
            return tree
        }

        func decode(_ reader: inout BitReader) -> Int? {
            var code = 0
            var first = 0
            var index = 0
            for len in 1...max(1, maxBits) {
                guard let bit = reader.readBits(1) else { return nil }
                code |= bit
                let count = counts[len]
                if code - count < first {
                    return symbols[index + (code - first)]
                }
                index += count
                first = (first + count) << 1
                code <<= 1
            }
            return nil
        }
    }

    private static let fixedLitTree: HuffmanTree = {
        var lengths = [Int](repeating: 0, count: 288)
        for i in 0...143 { lengths[i] = 8 }
        for i in 144...255 { lengths[i] = 9 }
        for i in 256...279 { lengths[i] = 7 }
        for i in 280...287 { lengths[i] = 8 }
        return HuffmanTree.build(lengths: lengths)!
    }()

    private static let fixedDistTree: HuffmanTree = {
        HuffmanTree.build(lengths: [Int](repeating: 5, count: 32))!
    }()

    private static let lengthBase: [Int] = [
        3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
        35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258,
    ]
    private static let lengthExtra: [Int] = [
        0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
        3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
    ]
    private static let distBase: [Int] = [
        1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
        257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
    ]
    private static let distExtra: [Int] = [
        0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
        7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13,
    ]
    private static let codeLengthOrder: [Int] = [
        16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
    ]

    static func inflateZlib(_ zlib: [UInt8]) -> Result<[UInt8], ImageError> {
        guard zlib.count >= 6 else { return .failure("zlib stream too short") }
        let cmf = Int(zlib[0])
        let flg = Int(zlib[1])
        guard (cmf & 0x0F) == 8, ((cmf << 8) + flg) % 31 == 0, (flg & 0x20) == 0 else {
            return .failure("invalid zlib header")
        }

        var reader = BitReader(data: zlib, bytePos: 2, byteEnd: zlib.count - 4)
        var out = [UInt8]()
        var isFinal = false

        while !isFinal {
            guard let bfinal = reader.readBits(1),
                  let btype = reader.readBits(2) else {
                return .failure("truncated DEFLATE block header")
            }
            isFinal = (bfinal == 1)

            switch btype {
            case 0: // Stored
                reader.alignToByte()
                guard let l0 = reader.readAlignedByte(),
                      let l1 = reader.readAlignedByte(),
                      let nl0 = reader.readAlignedByte(),
                      let nl1 = reader.readAlignedByte() else {
                    return .failure("truncated stored DEFLATE header")
                }
                let len = UInt16(l0) | (UInt16(l1) << 8)
                let nlen = UInt16(nl0) | (UInt16(nl1) << 8)
                guard len == ~nlen else {
                    return .failure("corrupt stored DEFLATE block length")
                }
                for _ in 0..<Int(len) {
                    guard let b = reader.readAlignedByte() else {
                        return .failure("truncated stored DEFLATE block data")
                    }
                    out.append(b)
                }

            case 1: // Fixed Huffman
                if let err = decodeHuffmanBlock(reader: &reader, litTree: fixedLitTree, distTree: fixedDistTree, out: &out) {
                    return .failure(ImageError(err))
                }

            case 2: // Dynamic Huffman
                guard let hlit = reader.readBits(5).map({ $0 + 257 }),
                      let hdist = reader.readBits(5).map({ $0 + 1 }),
                      let hclen = reader.readBits(4).map({ $0 + 4 }) else {
                    return .failure("truncated dynamic Huffman header")
                }
                var clLengths = [Int](repeating: 0, count: 19)
                for i in 0..<hclen {
                    guard let cl = reader.readBits(3) else {
                        return .failure("truncated code-length Huffman table")
                    }
                    clLengths[codeLengthOrder[i]] = cl
                }
                guard let clTree = HuffmanTree.build(lengths: clLengths) else {
                    return .failure("invalid code-length Huffman tree")
                }
                var allLengths = [Int]()
                allLengths.reserveCapacity(hlit + hdist)
                while allLengths.count < hlit + hdist {
                    guard let sym = clTree.decode(&reader) else {
                        return .failure("corrupt dynamic Huffman lengths")
                    }
                    if sym <= 15 {
                        allLengths.append(sym)
                    } else if sym == 16 {
                        guard let prev = allLengths.last,
                              let rep = reader.readBits(2).map({ $0 + 3 }) else {
                            return .failure("invalid repeat code 16")
                        }
                        for _ in 0..<rep { allLengths.append(prev) }
                    } else if sym == 17 {
                        guard let rep = reader.readBits(3).map({ $0 + 3 }) else {
                            return .failure("invalid repeat code 17")
                        }
                        for _ in 0..<rep { allLengths.append(0) }
                    } else if sym == 18 {
                        guard let rep = reader.readBits(7).map({ $0 + 11 }) else {
                            return .failure("invalid repeat code 18")
                        }
                        for _ in 0..<rep { allLengths.append(0) }
                    } else {
                        return .failure("unknown code-length symbol")
                    }
                }
                guard allLengths.count == hlit + hdist,
                      let litTree = HuffmanTree.build(lengths: Array(allLengths[0..<hlit])),
                      let distTree = HuffmanTree.build(lengths: Array(allLengths[hlit..<(hlit + hdist)])) else {
                    return .failure("invalid dynamic Huffman trees")
                }
                if let err = decodeHuffmanBlock(reader: &reader, litTree: litTree, distTree: distTree, out: &out) {
                    return .failure(ImageError(err))
                }

            default:
                return .failure("reserved DEFLATE block type 3")
            }
        }

        let expectedAdler = readUInt32BE(zlib, zlib.count - 4)
        guard RunePngCodec.verifyAdler32(out, expected: expectedAdler) else {
            return .failure("zlib Adler-32 checksum mismatch")
        }
        return .success(out)
    }

    private static func decodeHuffmanBlock(
        reader: inout BitReader,
        litTree: HuffmanTree,
        distTree: HuffmanTree,
        out: inout [UInt8]
    ) -> String? {
        while true {
            guard let sym = litTree.decode(&reader) else {
                return "corrupt Huffman literal/length symbol"
            }
            if sym < 256 {
                out.append(UInt8(sym))
            } else if sym == 256 {
                return nil
            } else {
                let lenIdx = sym - 257
                guard lenIdx < lengthBase.count,
                      let extraLen = reader.readBits(lengthExtra[lenIdx]),
                      let distSym = distTree.decode(&reader),
                      distSym < distBase.count,
                      let extraDist = reader.readBits(distExtra[distSym]) else {
                    return "corrupt LZ77 length/distance pair"
                }
                let length = lengthBase[lenIdx] + extraLen
                let distance = distBase[distSym] + extraDist
                guard distance > 0 && distance <= out.count else {
                    return "LZ77 distance out of bounds"
                }
                let start = out.count - distance
                for i in 0..<length {
                    out.append(out[start + i])
                }
            }
        }
    }
}
