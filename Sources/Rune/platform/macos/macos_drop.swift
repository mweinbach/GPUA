// Ported from: crates/rune/src/platform/macos/drop.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Drags from other apps onto a window, on macOS: file URLs, file promises, and raw image data.

#if !os(WASI)
import Foundation
#endif
#if os(macOS)
import AppKit
import ObjectiveC.runtime
#endif

/// One step of a drag over a content view, in points from its top-left.
enum MacDropStep: Sendable, Equatable {
    case enter([String], (Float, Float))
    case move((Float, Float))
    case drop([String], (Float, Float))
    case leave

    static func == (lhs: MacDropStep, rhs: MacDropStep) -> Bool {
        switch (lhs, rhs) {
        case (.enter(let lp, let la), .enter(let rp, let ra)):
            return lp == rp && la.0 == ra.0 && la.1 == ra.1
        case (.move(let la), .move(let ra)):
            return la.0 == ra.0 && la.1 == ra.1
        case (.drop(let lp, let la), .drop(let rp, let ra)):
            return lp == rp && la.0 == ra.0 && la.1 == ra.1
        case (.leave, .leave):
            return true
        default:
            return false
        }
    }
}

/// What one pasteboard item gives a drop.
enum MacDropItem: Sendable, Equatable {
    case file(String)
    /// A file the source writes when asked, with its type's extension when known.
    case promise(String?)
    /// Image data: its pasteboard type and file extension.
    case image(String, String)

    /// The path a drag over the window reports: the file, else a stand-in named for its type.
    func hoverPath() -> String {
        switch self {
        case .file(let path):
            return path
        case .promise(let ext):
            return ext.map { "File.\($0)" } ?? "File"
        case .image(_, let ext):
            return "Image.\(ext)"
        }
    }
}

let macDropFileUrlType = "public.file-url"
let macDropPromisedType = "com.apple.pasteboard.promised-file-content-type"
let macDropImageTypes: [(String, String)] = [
    ("public.png", "png"),
    ("public.jpeg", "jpg"),
    ("com.compuserve.gif", "gif"),
    ("org.webmproject.webp", "webp"),
    ("public.heic", "heic"),
    ("public.tiff", "png"),
]

private struct MacDropDest {
    var steps: [MacDropStep] = []
    var over: Bool = false
}

private let macDropDestsLock = LiveLock()
// PORT NOTE: Guarded by `macDropDestsLock`, matching `DESTS` in `drop.rs`.
nonisolated(unsafe) private var macDropDests: [UInt: MacDropDest] = [:]

func macDropPush(_ key: UInt, _ step: MacDropStep) {
    macDropDestsLock.withLock {
        var dest = macDropDests[key, default: MacDropDest()]
        if case .move = step, case .some(.move) = dest.steps.last {
            _ = dest.steps.popLast()
        }
        switch step {
        case .enter, .move:
            dest.over = true
        case .drop, .leave:
            dest.over = false
        }
        dest.steps.append(step)
        macDropDests[key] = dest
    }
}

func macDropOver(_ key: UInt) -> Bool {
    macDropDestsLock.withLock {
        macDropDests[key]?.over ?? false
    }
}

func macDropTakeSteps(_ key: UInt) -> [MacDropStep] {
    macDropDestsLock.withLock {
        guard var dest = macDropDests[key] else { return [] }
        let out = dest.steps
        dest.steps.removeAll()
        macDropDests[key] = dest
        return out
    }
}

/// The operation a drag gets: copy, else generic, else none.
func macDropOperation(_ mask: UInt) -> UInt {
    let copyOp: UInt = 1
    let genericOp: UInt = 4
    if (mask & copyOp) != 0 { return copyOp }
    if (mask & genericOp) != 0 { return genericOp }
    return 0
}

/// A file extension for common types a promise names.
func macDropExtension(_ uti: String) -> String? {
    switch uti {
    case "public.png": return "png"
    case "public.jpeg": return "jpg"
    case "public.tiff": return "tiff"
    case "public.heic": return "heic"
    case "com.compuserve.gif": return "gif"
    case "org.webmproject.webp": return "webp"
    case "com.adobe.pdf": return "pdf"
    case "public.plain-text", "public.utf8-plain-text": return "txt"
    case "com.apple.quicktime-movie": return "mov"
    case "public.mpeg-4": return "mp4"
    default: return nil
    }
}

func macDropUrlStem(_ url: String) -> String? {
    guard let schemeRange = url.range(of: "://") else { return nil }
    let rest = url[schemeRange.upperBound...]
    let beforeQuery = rest.split(whereSeparator: { $0 == "?" || $0 == "#" }).first ?? Substring()
    guard let slashIdx = beforeQuery.firstIndex(of: "/") else { return nil }
    let pathPart = beforeQuery[beforeQuery.index(after: slashIdx)...]
    var trimmed = Substring(pathPart)
    while trimmed.last == "/" {
        trimmed = trimmed.dropLast()
    }
    guard let lastSeg = trimmed.split(separator: "/").last, !lastSeg.isEmpty else { return nil }
    let stemSub: Substring
    if let dot = lastSeg.lastIndex(of: ".") {
        stemSub = lastSeg[..<dot]
    } else {
        stemSub = lastSeg
    }
    let filtered = stemSub.filter { $0 != ":" && $0 != "\\" && $0 != "\0" }
    let stem = String(filtered.prefix(80))
    return (!stem.isEmpty && !stem.hasPrefix(".")) ? stem : nil
}

#if !os(WASI)
private let macDropNextDirLock = LiveLock()
// PORT NOTE: Guarded by `macDropNextDirLock`, matching `NEXT: AtomicU64` in `drop.rs`.
nonisolated(unsafe) private var macDropNextDirCounter: UInt64 = 0

func macDropMakeDir() -> URL? {
    let n = macDropNextDirLock.withLock { () -> UInt64 in
        let cur = macDropNextDirCounter
        macDropNextDirCounter += 1
        return cur
    }
    let stamp = UInt64(Date().timeIntervalSince1970 * 1000.0)
    let pid = ProcessInfo.processInfo.processIdentifier
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("rune-drops", isDirectory: true)
        .appendingPathComponent("\(pid)-\(stamp)-\(n)", isDirectory: true)
    return ((try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil) ? dir : nil
}

/// `stem.ext` in `dir`, numbered when the name is taken.
func macDropFreeName(_ dir: URL, _ stem: String, _ ext: String) -> URL {
    let fm = FileManager.default
    var i = 1
    while true {
        let filename = (i == 1) ? "\(stem).\(ext)" : "\(stem) \(i).\(ext)"
        let candidate = dir.appendingPathComponent(filename)
        if !fm.fileExists(atPath: candidate.path) {
            return candidate
        }
        i += 1
    }
}
#endif

#if os(macOS)
/// The path of a `file://` URL, resolving the file-reference form (`file:///.file/id=…`).
func macDropFilePath(_ urlString: String) -> String? {
    guard let nsUrl = NSURL(string: urlString),
          let fileUrl = nsUrl.filePathURL,
          !fileUrl.path.isEmpty
    else {
        return nil
    }
    return fileUrl.path
}

func macDropPromiseTypes() -> [NSPasteboard.PasteboardType] {
    NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
}

func macDropRegisteredTypes() -> [NSPasteboard.PasteboardType] {
    var types: [NSPasteboard.PasteboardType] = [
        NSPasteboard.PasteboardType(macDropFileUrlType),
        NSPasteboard.PasteboardType("NSFilenamesPboardType"),
    ]
    for (kind, _) in macDropImageTypes {
        types.append(NSPasteboard.PasteboardType(kind))
    }
    types.append(contentsOf: macDropPromiseTypes())
    return types
}

/// What each item of `pb` gives a drop, in order. An item that gives nothing is left out.
func macDropItems(_ pb: NSPasteboard) -> [(NSPasteboardItem, MacDropItem)] {
    let promises = Set(NSFilePromiseReceiver.readableDraggedTypes)
    guard let list = pb.pasteboardItems else { return [] }
    return list.compactMap { item in
        let typeStrings = item.types.map(\.rawValue)
        let has: (String) -> Bool = { t in typeStrings.contains(t) }
        let found: MacDropItem?
        if has(macDropFileUrlType) {
            if let urlStr = item.string(forType: NSPasteboard.PasteboardType(macDropFileUrlType)),
               let path = macDropFilePath(urlStr)
            {
                found = .file(path)
            } else {
                found = nil
            }
        } else if typeStrings.contains(where: { promises.contains($0) }) {
            let uti = item.string(forType: NSPasteboard.PasteboardType(macDropPromisedType))
            found = .promise(uti.flatMap(macDropExtension))
        } else if let (kind, ext) = macDropImageTypes.first(where: { has($0.0) }) {
            found = .image(kind, ext)
        } else {
            found = nil
        }
        return found.map { (item, $0) }
    }
}

private func macDropImageStem(_ item: NSPasteboardItem) -> String {
    let url = item.string(forType: NSPasteboard.PasteboardType("public.url"))
    return url.flatMap(macDropUrlStem) ?? "Image"
}

/// Writes an item's image to `dir`, as PNG when it's TIFF.
func macDropWriteImage(_ item: NSPasteboardItem, _ kind: String, _ ext: String, _ dir: URL) -> URL? {
    guard let rawData = item.data(forType: NSPasteboard.PasteboardType(kind)) else { return nil }
    let outData: Data
    if kind == "public.tiff" {
        guard let rep = NSBitmapImageRep(data: rawData),
              let pngData = rep.representation(using: .png, properties: [:])
        else {
            return nil
        }
        outData = pngData
    } else {
        outData = rawData
    }
    let pathURL = macDropFreeName(dir, macDropImageStem(item), ext)
    return ((try? outData.write(to: pathURL)) != nil) ? pathURL : nil
}

@MainActor
private func macDropLocation(_ view: NSView, _ info: any NSDraggingInfo) -> (Float, Float) {
    let p = view.convert(info.draggingLocation, from: nil)
    let y = view.isFlipped ? p.y : (view.bounds.size.height - p.y)
    return (Float(p.x), Float(y))
}

@MainActor
private func macDropUpdate(_ view: NSView, _ info: any NSDraggingInfo) -> UInt {
    let key = UInt(bitPattern: Unmanaged.passUnretained(view).toOpaque())
    let mask = info.draggingSourceOperationMask.rawValue
    let op = macDropOperation(mask)
    let at = macDropLocation(view, info)
    if op == 0 {
        if macDropOver(key) {
            macDropPush(key, .leave)
        }
        return 0
    }
    if macDropOver(key) {
        macDropPush(key, .move(at))
        return op
    }
    let paths = macDropItems(info.draggingPasteboard).map { $0.1.hoverPath() }
    if paths.isEmpty {
        return 0
    }
    macDropPush(key, .enter(paths, at))
    return op
}

@MainActor
private func macDropReceivePromises(
    _ key: UInt,
    _ pb: NSPasteboard,
    _ dir: URL,
    _ initialPaths: [String],
    _ at: (Float, Float)
) -> Bool {
    guard let receivers = pb.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
          !receivers.isEmpty
    else {
        return false
    }
    let totalFiles = receivers.reduce(0) { $0 + max($1.fileTypes.count, 1) }
    guard totalFiles > 0 else { return false }

    // PORT NOTE: Synchronized via `lock` (`LiveLock`) across `NSFilePromiseReceiver` completion callbacks.
    final class PendingPromises: @unchecked Sendable {
        let lock = LiveLock()
        var remaining: Int
        var paths: [String]
        init(remaining: Int, paths: [String]) {
            self.remaining = remaining
            self.paths = paths
        }
    }

    let pending = PendingPromises(remaining: totalFiles, paths: initialPaths)
    let queue = OperationQueue()
    for receiver in receivers {
        receiver.receivePromisedFiles(atDestination: dir, options: [:], operationQueue: queue) { fileURL, error in
            _ = receiver
            let deliveredPath: String? = (error == nil) ? fileURL.path : nil
            let finishedPaths: [String]? = pending.lock.withLock {
                pending.remaining = max(0, pending.remaining - 1)
                if let deliveredPath {
                    pending.paths.append(deliveredPath)
                }
                guard pending.remaining == 0 else { return nil }
                let out = pending.paths
                pending.paths.removeAll()
                return out
            }
            if let finishedPaths {
                OperationQueue.main.addOperation {
                    if finishedPaths.isEmpty {
                        macDropPush(key, .leave)
                    } else {
                        macDropPush(key, .drop(finishedPaths, at))
                    }
                }
            }
        }
    }
    return true
}

private let macDropEnteredImp: @convention(c) (NSView, Selector, AnyObject) -> UInt = { view, _, infoObj in
    guard Thread.isMainThread else { return 0 }
    let infoBits = UInt(bitPattern: Unmanaged.passUnretained(infoObj).toOpaque())
    return MainActor.assumeIsolated {
        guard let rawPtr = UnsafeRawPointer(bitPattern: infoBits),
              let info = Unmanaged<AnyObject>.fromOpaque(rawPtr).takeUnretainedValue() as? (any NSDraggingInfo)
        else { return 0 }
        return macDropUpdate(view, info)
    }
}

private let macDropUpdatedImp: @convention(c) (NSView, Selector, AnyObject) -> UInt = { view, _, infoObj in
    guard Thread.isMainThread else { return 0 }
    let infoBits = UInt(bitPattern: Unmanaged.passUnretained(infoObj).toOpaque())
    return MainActor.assumeIsolated {
        guard let rawPtr = UnsafeRawPointer(bitPattern: infoBits),
              let info = Unmanaged<AnyObject>.fromOpaque(rawPtr).takeUnretainedValue() as? (any NSDraggingInfo)
        else { return 0 }
        return macDropUpdate(view, info)
    }
}

private let macDropExitedImp: @convention(c) (NSView, Selector, AnyObject?) -> Void = { view, _, _ in
    let key = UInt(bitPattern: Unmanaged.passUnretained(view).toOpaque())
    if macDropOver(key) {
        macDropPush(key, .leave)
    }
}

private let macDropPrepareImp: @convention(c) (NSView, Selector, AnyObject) -> ObjCBool = { view, _, _ in
    let key = UInt(bitPattern: Unmanaged.passUnretained(view).toOpaque())
    return ObjCBool(macDropOver(key))
}

private let macDropPerformImp: @convention(c) (NSView, Selector, AnyObject) -> ObjCBool = { view, _, infoObj in
    guard Thread.isMainThread else { return false }
    let infoBits = UInt(bitPattern: Unmanaged.passUnretained(infoObj).toOpaque())
    return MainActor.assumeIsolated {
        guard let rawPtr = UnsafeRawPointer(bitPattern: infoBits),
              let info = Unmanaged<AnyObject>.fromOpaque(rawPtr).takeUnretainedValue() as? (any NSDraggingInfo)
        else { return ObjCBool(false) }
        let key = UInt(bitPattern: Unmanaged.passUnretained(view).toOpaque())
        let at = macDropLocation(view, info)
        let pb = info.draggingPasteboard
        let foundItems = macDropItems(pb)
        var dir: URL? = nil
        var paths: [String] = []
        var promised = false
        for (item, found) in foundItems {
            switch found {
            case .file(let path):
                paths.append(path)
            case .image(let kind, let ext):
                if dir == nil { dir = macDropMakeDir() }
                if let d = dir, let written = macDropWriteImage(item, kind, ext, d) {
                    paths.append(written.path)
                }
            case .promise:
                promised = true
            }
        }
        if promised, let d = dir ?? macDropMakeDir(), macDropReceivePromises(key, pb, d, paths, at) {
            return ObjCBool(true)
        }
        if paths.isEmpty {
            macDropPush(key, .leave)
            return ObjCBool(false)
        }
        macDropPush(key, .drop(paths, at))
        return ObjCBool(true)
    }
}

/// The content view takes drags of files, file promises and image data.
@MainActor
func macDropInstall(view: NSView) {
    guard let base: AnyClass = object_getClass(view) else { return }
    let baseName = String(cString: class_getName(base))
    if !baseName.contains("RuneDrops_") {
        let subName = "RuneDrops_\(baseName)"
        let subclass: AnyClass
        if let existing = objc_getClass(subName) as? AnyClass {
            subclass = existing
        } else {
            guard let allocated = objc_allocateClassPair(base, subName, 0) else { return }
            #if arch(arm64)
            let boolEnc = "B@:@"
            #else
            let boolEnc = "c@:@"
            #endif
            _ = "Q@:@".withCString { class_addMethod(allocated, NSSelectorFromString("draggingEntered:"), unsafeBitCast(macDropEnteredImp, to: IMP.self), $0) }
            _ = "Q@:@".withCString { class_addMethod(allocated, NSSelectorFromString("draggingUpdated:"), unsafeBitCast(macDropUpdatedImp, to: IMP.self), $0) }
            _ = "v@:@".withCString { class_addMethod(allocated, NSSelectorFromString("draggingExited:"), unsafeBitCast(macDropExitedImp, to: IMP.self), $0) }
            _ = boolEnc.withCString { class_addMethod(allocated, NSSelectorFromString("prepareForDragOperation:"), unsafeBitCast(macDropPrepareImp, to: IMP.self), $0) }
            _ = boolEnc.withCString { class_addMethod(allocated, NSSelectorFromString("performDragOperation:"), unsafeBitCast(macDropPerformImp, to: IMP.self), $0) }
            objc_registerClassPair(allocated)
            subclass = allocated
        }
        object_setClass(view, subclass)
    }
    view.registerForDraggedTypes(macDropRegisteredTypes())
}

/// The steps of drags over `view` since the last call.
func macDropTake(view: NSView) -> [MacDropStep] {
    let key = UInt(bitPattern: Unmanaged.passUnretained(view).toOpaque())
    return macDropTakeSteps(key)
}
#endif
