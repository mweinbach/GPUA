// Ported from: crates/rune/src/el/drop.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Files dropped on an element from another app: `El.onDropFiles` and the hover, move
//! and reject callbacks around it, and `Tx.dropPoint`.

#if !os(WASI)
import Foundation
#endif

// PORT NOTE: Uses `[String]` file paths as the canonical storage to match `DragItem.paths: [String]`
// and keep WASI builds free of file-URL assumptions, with `Foundation.URL` convenience overloads on
// platforms importing `Foundation`.
typealias DropFilesFn = (States, [String], inout Tx) -> Void
typealias AcceptsFn = (String) -> Bool
typealias DropHoverFn = (States, Bool, inout Tx) -> Void
typealias DropMoveFn = (States, PointerEvent, inout Tx) -> Void

/// ``El/onDropFiles(_:)``, ``El/acceptsFiles(_:)``, ``El/onDropHover(_:)``, ``El/onDropMove(_:)``,
/// ``El/onDropRejected(_:)`` and ``El/onDropRejectedHover(_:)``.
struct DropSpec {
    var onDrop: DropFilesFn? = nil
    var accepts: AcceptsFn? = nil
    var onHover: DropHoverFn? = nil
    var onReject: DropFilesFn? = nil
    var onRejectHover: DropHoverFn? = nil
    var onMove: DropMoveFn? = nil

    /// The files of `paths` this element takes, when it's a drop target, and the rest.
    func split(_ paths: [String]) -> ([String], [String]) {
        guard onDrop != nil else {
            return ([], paths)
        }
        var accepted: [String] = []
        var rejected: [String] = []
        for path in paths {
            if accepts?(path) ?? true {
                accepted.append(path)
            } else {
                rejected.append(path)
            }
        }
        return (accepted, rejected)
    }

    /// It stops a drag it takes none of, rather than passing it to the target around it.
    func claimsRejects() -> Bool {
        onReject != nil || onRejectHover != nil
    }

    /// Its hover callback for a drag it takes (`accepted`) or rejects.
    func hoverFn(_ accepted: Bool) -> DropHoverFn? {
        accepted ? onHover : onRejectHover
    }
}

/// Extracts a file path's extension matching Rust `std::path::Path::extension()` semantics
/// (leading dot on dotfiles like `.gitignore` is part of the stem, not an extension).
func pathExtension(_ path: String) -> Substring? {
    let trimmed = path.replacingOccurrences(of: "\\", with: "/")
    var slice = Substring(trimmed)
    while slice.count > 1 && slice.last == "/" {
        slice.removeLast()
    }
    let fileName: Substring
    if let slash = slice.lastIndex(of: "/") {
        fileName = slice[slice.index(after: slash)...]
    } else {
        fileName = slice
    }
    if fileName.isEmpty || fileName == "." || fileName == ".." {
        return nil
    }
    let afterLeadingDot = fileName.first == "." ? fileName.dropFirst() : fileName
    guard let dot = afterLeadingDot.lastIndex(of: ".") else {
        return nil
    }
    let ext = afterLeadingDot[afterLeadingDot.index(after: dot)...]
    return ext.isEmpty ? nil : ext
}

extension El {
    /// Take files dropped on this element from another app (Finder, Explorer, a file manager).
    /// The innermost target under the drop that accepts any of the files gets the ones it
    /// accepts, all in one call; files it doesn't accept are left out.
    public func onDropFiles<S>(_ f: @escaping (inout S, [String], inout Tx) -> Void) -> El {
        var copy = self
        var spec = copy.handlers.value.drop ?? DropSpec()
        spec.onDrop = { states, files, tx in
            states.withDowncast { (state: inout S) in
                f(&state, files, &tx)
            }
        }
        copy.handlers.value.drop = spec
        return copy
    }

    #if !os(WASI)
    /// Convenience overload of ``onDropFiles(_:)`` delivering `[URL]` file URLs.
    public func onDropFiles<S>(_ f: @escaping (inout S, [URL], inout Tx) -> Void) -> El {
        onDropFiles { (state: inout S, paths: [String], tx: inout Tx) in
            f(&state, paths.map { URL(fileURLWithPath: $0) }, &tx)
        }
    }
    #endif

    /// Only the files `accepts` returns `true` for reach this element's ``onDropFiles(_:)``.
    public func acceptsFiles(_ accepts: @escaping (String) -> Bool) -> El {
        var copy = self
        var spec = copy.handlers.value.drop ?? DropSpec()
        spec.accepts = accepts
        copy.handlers.value.drop = spec
        return copy
    }

    #if !os(WASI)
    /// Convenience overload of ``acceptsFiles(_:)`` receiving a `URL`.
    public func acceptsFiles(_ accepts: @escaping (URL) -> Bool) -> El {
        acceptsFiles { path in
            accepts(URL(fileURLWithPath: path))
        }
    }
    #endif

    /// ``acceptsFiles(_:)`` for files with one of these extensions, compared without case.
    public func acceptsExtensions(_ extensions: [String]) -> El {
        let normalized: [String] = extensions.map { ext in
            var s = Substring(ext)
            while s.first == "." {
                s.removeFirst()
            }
            return s.lowercased()
        }
        return acceptsFiles { path in
            guard let ext = pathExtension(path)?.lowercased() else {
                return false
            }
            return normalized.contains(ext)
        }
    }

    /// Called with `true` when a file drag over the window makes this element the drop target,
    /// and with `false` when the drag moves off it, leaves the window, or drops, or when the
    /// element goes away under the drag.
    public func onDropHover<S>(_ f: @escaping (inout S, Bool, inout Tx) -> Void) -> El {
        var copy = self
        var spec = copy.handlers.value.drop ?? DropSpec()
        spec.onHover = { states, over, tx in
            states.withDowncast { (state: inout S) in
                f(&state, over, &tx)
            }
        }
        copy.handlers.value.drop = spec
        return copy
    }

    /// Follow a file drag this element takes while it's over it: `f` hears the drag's point on
    /// the element, in the element's own points as ``onPointerMoveLocal(_:file:line:)`` gives them.
    public func onDropMove<S>(_ f: @escaping (inout S, PointerEvent, inout Tx) -> Void) -> El {
        var copy = self
        var spec = copy.handlers.value.drop ?? DropSpec()
        spec.onMove = { states, p, tx in
            states.withDowncast { (state: inout S) in
                f(&state, p, &tx)
            }
        }
        copy.handlers.value.drop = spec
        return copy
    }

    /// Hear the files dropped on this element that it doesn't accept (``acceptsFiles(_:)``),
    /// to say why ("that isn't an export").
    public func onDropRejected<S>(_ f: @escaping (inout S, [String], inout Tx) -> Void) -> El {
        var copy = self
        var spec = copy.handlers.value.drop ?? DropSpec()
        spec.onReject = { states, files, tx in
            states.withDowncast { (state: inout S) in
                f(&state, files, &tx)
            }
        }
        copy.handlers.value.drop = spec
        return copy
    }

    #if !os(WASI)
    /// Convenience overload of ``onDropRejected(_:)`` delivering `[URL]` file URLs.
    public func onDropRejected<S>(_ f: @escaping (inout S, [URL], inout Tx) -> Void) -> El {
        onDropRejected { (state: inout S, paths: [String], tx: inout Tx) in
            f(&state, paths.map { URL(fileURLWithPath: $0) }, &tx)
        }
    }
    #endif

    /// ``onDropHover(_:)`` for a drag this element stops but takes none of (see ``onDropRejected(_:)``).
    public func onDropRejectedHover<S>(_ f: @escaping (inout S, Bool, inout Tx) -> Void) -> El {
        var copy = self
        var spec = copy.handlers.value.drop ?? DropSpec()
        spec.onRejectHover = { states, over, tx in
            states.withDowncast { (state: inout S) in
                f(&state, over, &tx)
            }
        }
        copy.handlers.value.drop = spec
        return copy
    }
}

extension Tx {
    /// In ``El/onDropFiles(_:)``, ``El/onDropRejected(_:)``, ``El/onDropMove(_:)`` and
    /// ``El/onDropHover(_:)``'s `true`: where the file drag is on the element, in its own points
    /// (`x`, `y`, following its scroll and transforms) and in the window's. `nil` when the
    /// platform gave no position and in every other handler.
    public func dropPoint() -> PointerEvent? {
        dropPointEvent
    }
}
