// Ported from: crates/rune-kit/src/markdown/cache.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Parsed documents kept across commits, and growing a stream's parse from its last block.

#if !os(WASI)
import Foundation
#endif
import Rune

/// Estimated bytes of parsed documents kept beyond those on screen (see ``Budget``).
private let CACHE_BYTES: Int = 16 << 20

final class CachedDoc: Sendable {
    let blocks: [MarkdownBlock]
    let sources: [Source]
    let tasks: [(Bool, Int)?]
    let starts: [Int]
    let maps: [BlockMap]

    init(
        blocks: [MarkdownBlock],
        sources: [Source],
        tasks: [(Bool, Int)?],
        starts: [Int],
        maps: [BlockMap]
    ) {
        self.blocks = blocks
        self.sources = sources
        self.tasks = tasks
        self.starts = starts
        self.maps = maps
    }
}

struct ParsedCacheEntry: Sendable {
    var doc: CachedDoc
    var cuts: [Cut]
}

final class MarkdownCache {
    var docs: Budget<String, ParsedCacheEntry>
    /// The source parsed last, which a stream's next string extends.
    var last: String? = nil

    init(_ bytes: Int) {
        self.docs = Budget(bytes)
    }
}

private final class MarkdownThreadCaches {
    let cache = MarkdownCache(CACHE_BYTES)
    let streams = MarkdownCache(CACHE_BYTES / 4)
    /// `(wholeDocumentsParsed, streamsParsedFromLastBlock)` for test verification.
    var parses: (Int, Int) = (0, 0)
}

#if os(WASI)
// PORT NOTE: WASI (`wasm32-unknown-wasip1`) is single-threaded, matching Rust `thread_local!` in `markdown/cache.rs`.
nonisolated(unsafe) private let wasiMarkdownCaches = MarkdownThreadCaches()
#else
private let markdownCacheThreadKey = "gpua.runekit.markdown.caches"
#endif

private func currentMarkdownCaches() -> MarkdownThreadCaches {
    #if os(WASI)
    return wasiMarkdownCaches
    #else
    let dict = Thread.current.threadDictionary
    if let existing = dict[markdownCacheThreadKey] as? MarkdownThreadCaches {
        return existing
    }
    let created = MarkdownThreadCaches()
    dict[markdownCacheThreadKey] = created
    return created
    #endif
}

func markdownParseStats() -> (Int, Int) {
    currentMarkdownCaches().parses
}

func withMarkdownDocCache<R>(_ body: (MarkdownCache) -> R) -> R {
    body(currentMarkdownCaches().cache)
}

func withMarkdownStreamCache<R>(_ body: (MarkdownCache) -> R) -> R {
    body(currentMarkdownCaches().streams)
}

/// ``parse(_:)`` memoised by source on this thread. Every document the last two commits drew stays
/// cached however many there are; past a memory budget the least recently drawn of the rest go.
public func parseCached(_ src: String) -> [MarkdownBlock] {
    parseMarkdownCached(src)
}

func parseMarkdownCached(_ src: String) -> [MarkdownBlock] {
    docCached(src).blocks
}

func docCached(_ src: String) -> CachedDoc {
    let tc = currentMarkdownCaches()
    return cached(tc, tc.cache, src, parseDoc)
}

/// ``docCached(_:)`` for a source still arriving.
func streamCached(_ src: String) -> CachedDoc {
    let tc = currentMarkdownCaches()
    return cached(tc, tc.streams, src, parseStreaming)
}

private func cached(
    _ tc: MarkdownThreadCaches,
    _ c: MarkdownCache,
    _ src: String,
    _ parseFn: (String, Bool) -> ParsedDoc
) -> CachedDoc {
    if let hit = c.docs.get(src) {
        return hit.doc
    }
    let srcLen = src.utf8.count
    let grown: String?
    if let last = c.last, srcLen > last.utf8.count, src.hasPrefix(last) {
        grown = last
    } else {
        grown = nil
    }
    let parsed: ParsedCacheEntry
    if let last = grown,
       let base = c.docs.peek(last),
       let extended = extend(tc, base, last.utf8.count, src, parseFn)
    {
        parsed = extended
    } else {
        tc.parses.0 += 1
        let d = parseFn(src, true)
        parsed = ParsedCacheEntry(
            doc: CachedDoc(blocks: d.blocks, sources: d.sources, tasks: d.tasks, starts: d.starts, maps: d.maps),
            cuts: d.cuts
        )
    }
    // A stream's earlier string is dead once it grows, unless something drew it this commit.
    if let last = grown, !c.docs.usedNow(last) {
        c.docs.remove(last)
    }
    let bytes = 2 * srcLen + 64 * parsed.cuts.count + 128
    c.docs.insert(src, parsed, bytes)
    c.last = src
    return parsed.doc
}

/// The parse of `src`, which extends the `baseLen` bytes `base` parsed, reusing every
/// top-level block before `base`'s last.
private func extend(
    _ tc: MarkdownThreadCaches,
    _ base: ParsedCacheEntry,
    _ baseLen: Int,
    _ src: String,
    _ parseFn: (String, Bool) -> ParsedDoc
) -> ParsedCacheEntry? {
    let srcBytes = Array(src.utf8)
    guard let i = base.cuts.lastIndex(where: { c in
        guard c.at <= baseLen && c.at < srcBytes.count else { return false }
        let upper = min(baseLen, srcBytes.count)
        return srcBytes[c.at..<upper].contains(0x0A)
    }) else {
        return nil
    }
    let cut = base.cuts[i]
    if cut.at == 0 || cut.blocks >= base.doc.blocks.count || src.contains("]:") {
        return nil
    }
    tc.parses.1 += 1
    let tailStr = String(decoding: srcBytes[cut.at..<srcBytes.count], as: UTF8.self)
    let tail = parseFn(tailStr, true)

    var blocks = Array(base.doc.blocks[0..<cut.blocks])
    blocks.append(contentsOf: tail.blocks)

    var sources = Array(base.doc.sources[0..<cut.sources])
    sources.append(contentsOf: tail.sources)

    var tasks = Array(base.doc.tasks[0..<cut.tasks])
    for t in tail.tasks {
        tasks.append(t.map { ($0.0, $0.1 + cut.at) })
    }

    var starts = Array(base.doc.starts[0..<cut.blocks])
    for at in tail.starts {
        starts.append(at + cut.at)
    }

    var maps = Array(base.doc.maps[0..<cut.blocks])
    for m in tail.maps {
        maps.append(m.shiftSrc(cut.at))
    }

    var cuts = Array(base.cuts[0..<i])
    for c in tail.cuts {
        cuts.append(Cut(
            at: c.at + cut.at,
            blocks: c.blocks + cut.blocks,
            sources: c.sources + cut.sources,
            tasks: c.tasks + cut.tasks
        ))
    }

    return ParsedCacheEntry(
        doc: CachedDoc(blocks: blocks, sources: sources, tasks: tasks, starts: starts, maps: maps),
        cuts: cuts
    )
}
