// Ported from: crates/gpui/src/util.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
import GPUIUtil

public typealias PNGEncoder = GPUIUtil.PNGEncoder

/// A helper protocol for building complex objects with imperative conditionals in a fluent style.
public protocol FluentBuilder {}

extension FluentBuilder {
    /// Imperatively modify self with the given closure.
    public func map<U>(_ f: (Self) throws -> U) rethrows -> U {
        try f(self)
    }

    /// Conditionally modify self with the given closure.
    public func when(_ condition: Bool, then: (Self) throws -> Self) rethrows -> Self {
        if condition {
            return try then(self)
        } else {
            return self
        }
    }

    /// Conditionally modify self with the given closure.
    public func whenElse(
        _ condition: Bool,
        then: (Self) throws -> Self,
        else elseFn: (Self) throws -> Self
    ) rethrows -> Self {
        if condition {
            return try then(self)
        } else {
            return try elseFn(self)
        }
    }

    /// Conditionally unwrap and modify self with the given closure, if the given option is Some.
    public func whenSome<T>(_ option: T?, then: (Self, T) throws -> Self) rethrows -> Self {
        if let option {
            return try then(self, option)
        } else {
            return self
        }
    }

    /// Conditionally unwrap and modify self with the given closure, if the given option is None.
    public func whenNone<T>(_ option: T?, then: (Self) throws -> Self) rethrows -> Self {
        if option == nil {
            return try then(self)
        } else {
            return self
        }
    }
}

/// Error returned by with_timeout when the timeout duration elapsed before the future resolved.
public struct Timeout: Error, CustomStringConvertible, Sendable, Equatable {
    public init() {}

    public var description: String {
        "Timed out before future resolved"
    }
}

/// A wrapper struct representing an async operation with a timeout.
public struct WithTimeout<T: Sendable>: Sendable {
    public let future: Task<T>
    public let timerTask: Task<Void>

    public init(
        task: Task<T>,
        timerTask: Task<Void>
    ) {
        self.future = task
        self.timerTask = timerTask
    }

    public var value: Result<T, Timeout> {
        get async {
            if future.isReady() {
                return .success(await future.value)
            }
            if timerTask.isReady() {
                return .failure(Timeout())
            }
            let fut = future
            let timer = timerTask
            return await withTaskGroup(of: Result<T, Timeout>.self) { group in
                group.addTask {
                    let res = await fut.value
                    return .success(res)
                }
                group.addTask {
                    _ = await timer.value
                    return .failure(Timeout())
                }
                let first = await group.next()!
                group.cancelAll()
                return first
            }
        }
    }
}

/// Extensions for async operations that provide timeout utilities.
public protocol FutureExt {}

extension Task: FutureExt {
    public func withTimeout(_ timeout: Duration, executor: BackgroundExecutor) -> WithTimeout<T> {
        let timer = executor.timer(timeout)
        return WithTimeout(task: self, timerTask: timer)
    }
}

/// Increment the given atomic counter if it is not zero.
/// Return the new value of the counter.
public func atomicIncrIfNotZero(_ counter: inout Int) -> Int {
    if counter == 0 {
        return 0
    }
    counter += 1
    return counter
}
