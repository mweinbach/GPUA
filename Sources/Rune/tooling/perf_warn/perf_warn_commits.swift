// Ported from: crates/rune/src/tooling/perf_warn/commits.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The commit warnings: something in the app that commits the view on most frames of a scroll,
//! an app stepping its own scroll glide with an instant scroll every frame, and hover kept in
//! state on many rows.

let PERF_COMMIT_COUNT: UInt32 = 6
let PERF_COMMIT_SHARE: UInt32 = 4
let PERF_INSTANT_FRAMES: UInt32 = 8
let PERF_HOVER_ROWS: Int = 8

enum PerfCommitCause: Sendable, Equatable {
    case poll
    case handler(String)
    case read
}

private struct PerfCommitSource {
    var site: String
    var cause: PerfCommitCause
    var subject: String?
    var at: String?
}

/// One window's commit meters.
final class PerfCommitMeter {
    private var sources: [PerfCommitSource] = []
    private var frames: UInt32 = 0
    private var counts: [String: UInt32] = [:]
    private var instant: UInt32 = 0
    private var hoverRows: [String: [String]] = [:]

    init() {}

    @inline(__always)
    func poll() {
        sources.append(PerfCommitSource(site: "poll", cause: .poll, subject: nil, at: nil))
    }

    @inline(__always)
    func handler(_ name: String, path: String?, at: String?) {
        let site: String
        if let at {
            site = "\(name) \(at)"
        } else if let path {
            site = perfHandlerSite(name, path)
        } else {
            site = name
        }
        if let at, let path, name == "on_hover" || name == "on_hover_change" {
            recordHoverRow(name: name, at: at, path: path)
        }
        sources.append(PerfCommitSource(site: site, cause: .handler(name), subject: path, at: at))
    }

    private func recordHoverRow(name: String, at: String, path: String) {
        var rows = hoverRows[at] ?? []
        if rows.count >= PERF_HOVER_ROWS || rows.contains(path) {
            return
        }
        rows.append(path)
        hoverRows[at] = rows
        guard rows.count >= PERF_HOVER_ROWS else { return }
        let example = rows[0]
        perfWarnOnce("hover rows \(at)") {
            "`\(name)` set at \(at) committed the view for \(PERF_HOVER_ROWS) elements (as \(toolingEscapeJsonString(example))): each one the pointer crosses runs the whole view; \(perfCommitHandlerFix(name))"
        }
    }

    func read(_ key: String, at: String?) {
        sources.append(PerfCommitSource(site: "read \(key)", cause: .read, subject: key, at: at))
    }

    @inline(__always)
    func frameEnds(scrolling: Bool, committed: Bool, instant instantKey: String?) {
        let currentSources = sources
        sources.removeAll(keepingCapacity: true)

        if let key = instantKey, committed {
            instant += 1
            if instant == PERF_INSTANT_FRAMES {
                perfWarnOnce("instant scroll \(key)") {
                    perfInstantScrollMessage(key)
                }
            }
        } else {
            instant = 0
        }

        if !scrolling {
            frames = 0
            counts.removeAll(keepingCapacity: true)
            return
        }

        frames += 1
        guard committed else { return }
        var seen = Set<String>()
        for s in currentSources {
            guard seen.insert(s.site).inserted else { continue }
            let count = (counts[s.site] ?? 0) + 1
            counts[s.site] = count
            if count >= PERF_COMMIT_COUNT && count * PERF_COMMIT_SHARE >= frames {
                let capturedCount = count
                let capturedFrames = frames
                perfWarnOnce("scroll commit \(s.site)") {
                    perfScrollCommitMessage(s, count: capturedCount, frames: capturedFrames)
                }
            }
        }
    }
}

private func perfWindowReadKey(_ subject: String) -> String? {
    if subject.hasPrefix("window:") {
        return String(subject.dropFirst("window:".count))
    }
    return nil
}

private func perfScrollCommitMessage(_ s: PerfCommitSource, count: UInt32, frames: UInt32) -> String {
    let subject = s.subject ?? ""
    let who: String
    let fix: String
    switch s.cause {
    case .poll:
        who = "`poll` returned true and"
        fix = "return true only when visible state changed; to act on where a scroll stops, wait until it has been still a moment (`Tx::wake_after`), and follow it frame by frame with `El::on_scroll_offset` and live values"
    case .read:
        let winKey = perfWindowReadKey(subject)
        let atSuffix = s.at.map { " at \($0)" } ?? ""
        let readDesc: String
        if let k = winKey {
            readDesc = "the view's `Cx::window_layout` read of \(toolingEscapeJsonString(k))\(atSuffix)"
            fix = "read `Cx::layout_size` or `Cx::layout` (unscrolled) unless the view needs where the element is in the window, and then only through `window_layout_with` and what it computes"
        } else {
            readDesc = "the view's layout read of \(toolingEscapeJsonString(subject))\(atSuffix)"
            fix = "read only what the view needs (`Cx::layout_size`, `Cx::layout_with`), or follow it with `El::on_layout_tx` and a live value"
        }
        who = "\(readDesc) moved and"
    case .handler(let name):
        let atSuffix = s.at.map { " (set at \($0))" } ?? ""
        who = "`\(name)` on \(toolingEscapeJsonString(subject))\(atSuffix)"
        fix = perfCommitHandlerFix(name)
    }
    return "\(who) committed the view on \(count) of \(frames) frames of a scroll: \(fix)"
}

private func perfCommitHandlerFix(_ name: String) -> String {
    switch name {
    case "on_hover", "on_hover_change":
        return "paint hover with `El::hover`, `hover_group` and `group_*` styles (`hover_alone` for a target inside a lit row) instead of state, or say `Tx::live_only` when the handler only sets live values"
    case "on_layout_tx", "on_drawn_layout_tx", "on_pointer_move_local", "on_wheel":
        return "when the handler only moves live values or bookkeeping, say `Tx::live_only` (`on_layout` and `on_drawn_layout` take one in their `_tx` forms)"
    case "on_visible_rows":
        return "return true only when the visible range changed what the view shows"
    default:
        return "say `Tx::live_only` when the handler changes nothing the view reads"
    }
}

private func perfInstantScrollMessage(_ key: String) -> String {
    "an instant scroll (`Tx::scroll_to_instant`, `scroll_to_y`, `scroll_key_to`) moved \(toolingEscapeJsonString(key)) on \(PERF_INSTANT_FRAMES) frames in a row, each with a commit: an app stepping its own glide this way runs the view every frame; glide with `Tx::scroll_to_with(key, x, y, spring)`, which runs on Rune's clock with no commits"
}
