// Ported from: crates/rune-register/src/lib.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Lists a feature adds itself to from its own file, so new scenes, stories and knob groups don't
//! all edit one central list. A list is a `Registry<T>` of `Part<T>` contributions: declare it once
//! with `slice(Scene.self)` (or `Registry<Scene>()`), add to it from any module with `register(...)`,
//! and read it with `collect(...)`, which orders parts by module path so the result doesn't depend
//! on registration order.

#if !os(WASI)
import Foundation
#endif

/// One module's contribution to a list.
public struct Part<T> {
    public var module: String
    public var items: [T]

    public init(module: String, items: [T]) {
        self.module = module
        self.items = items
    }

    public init(_ module: String, _ items: [T]) {
        self.module = module
        self.items = items
    }
}

extension Part: Sendable where T: Sendable {}
extension Part: Equatable where T: Equatable {}
extension Part: Hashable where T: Hashable {}

/// Every part's items: parts by module path, each part's items in its own order.
public func collect<T>(_ parts: [Part<T>]) -> [T] {
    let sorted = parts.enumerated().sorted { lhs, rhs in
        if lhs.element.module != rhs.element.module {
            return lhs.element.module < rhs.element.module
        }
        return lhs.offset < rhs.offset
    }
    var result: [T] = []
    for (_, part) in sorted {
        result.append(contentsOf: part.items)
    }
    return result
}

/// Every registered part's items in `registry`: parts by module path, each part's items in its own order.
public func collect<T>(_ registry: Registry<T>) -> [T] {
    registry.collect()
}

/// `own` with `more` folded in by name: an item named like one of `own` joins it, any other is new
/// and goes before `own`'s last item (the list's footer).
public func merge<T>(
    _ own: [T],
    _ more: [T],
    _ name: (T) -> String,
    _ join: (inout T, T) -> Void
) -> [T] {
    let last: T?
    var out: [T]
    if let footer = own.last {
        last = footer
        out = Array(own.dropLast())
    } else {
        last = nil
        out = []
    }
    for m in more {
        let targetName = name(m)
        if let index = out.firstIndex(where: { name($0) == targetName }) {
            join(&out[index], m)
        } else {
            out.append(m)
        }
    }
    if let last {
        out.append(last)
    }
    return out
}

/// Token returned by registration calls so static `let` properties can trigger registration on touch.
public struct RegistrationToken: Equatable, Hashable, Sendable {
    public init() {}
}

/// Thread-safe generic self-registration list replacing Rust's `linkme` distributed slices (`slice!` / `register!`).
// PORT NOTE: Swift has no portable linker-section `linkme` macro without swift-syntax or platform-specific section attributes (ADR-0007); `Registry<T>` provides explicit thread-safe registration synchronized with `NSLock` on multi-threaded hosts and single-threaded access on WASI.
public final class Registry<T>: @unchecked Sendable {
    #if !os(WASI)
    private let lock = NSLock()
    #endif
    private var registeredParts: [Part<T>] = []

    /// Whether incoming `register` calls store their items (`false` emulates disabled/empty slices).
    public let isEnabled: Bool

    public init(enabled: Bool = true) {
        self.isEnabled = enabled
    }

    @inline(__always)
    private func withLock<R>(_ body: () throws -> R) rethrows -> R {
        #if !os(WASI)
        lock.lock()
        defer { lock.unlock() }
        #endif
        return try body()
    }

    /// Adds `module`'s `items` to this registry.
    @discardableResult
    public func register(_ module: String = #fileID, _ items: [T]) -> RegistrationToken {
        guard isEnabled else { return RegistrationToken() }
        withLock {
            registeredParts.append(Part(module: module, items: items))
        }
        return RegistrationToken()
    }

    /// Adds `part` to this registry.
    @discardableResult
    public func register(_ part: Part<T>) -> RegistrationToken {
        guard isEnabled else { return RegistrationToken() }
        withLock {
            registeredParts.append(part)
        }
        return RegistrationToken()
    }

    /// Snapshot of all registered parts in registration order.
    public func parts() -> [Part<T>] {
        withLock { registeredParts }
    }

    /// Every registered part's items: parts ordered by module path, each part's items in its own order.
    public func collect() -> [T] {
        let snapshot = withLock { registeredParts }
        return RuneRegister.collect(snapshot)
    }

    /// Number of registered module parts.
    public var count: Int {
        withLock { registeredParts.count }
    }

    /// Whether no parts have been registered.
    public var isEmpty: Bool {
        withLock { registeredParts.isEmpty }
    }

    /// Clears all registered parts.
    public func clear() {
        withLock {
            registeredParts.removeAll()
        }
    }
}

/// Declares a self-registration list (`slice!(pub SCENES: Scene)` -> `public let scenes = slice(Scene.self)`).
// PORT NOTE: Replaces upstream's `slice!` macro per ADR-0007.
public func slice<T>(_ type: T.Type = T.self, enabled: Bool = true) -> Registry<T> {
    Registry<T>(enabled: enabled)
}

/// Adds a module's items to `registry` (`register!(LIST: Type = [item, ...])`).
// PORT NOTE: Replaces upstream's `register!` macro per ADR-0007.
@discardableResult
public func register<T>(
    _ registry: Registry<T>,
    module: String = #fileID,
    _ items: [T]
) -> RegistrationToken {
    registry.register(module, items)
}
