// Ported from: crates/gpui_util/src/lib.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

public func postInc<T: Numeric>(_ value: inout T) -> T {
    let prev = value
    value += 1
    return prev
}

public func measure<R>(_ label: String, _ f: () throws -> R) rethrows -> R {
    let isMeasurementsEnabled: Bool = {
        let envVal = ProcessInfo.processInfo.environment["ZED_MEASUREMENTS"]
        return envVal == "1" || envVal == "true"
    }()

    if isMeasurementsEnabled {
        let clock = ContinuousClock()
        let start = clock.now
        let result = try f()
        let elapsed = clock.now - start
        FileHandle.standardError.write(Data("\(label): \(elapsed)\n".utf8))
        return result
    } else {
        return try f()
    }
}

public func someOrDebugPanic<T>(_ option: T?, file: StaticString = #file, line: UInt = #line) -> T? {
    #if DEBUG
    if option == nil {
        preconditionFailure("Unexpected nil at \(file):\(line)")
    }
    #endif
    return option
}

public protocol ResultExt {
    associatedtype Success
    associatedtype Failure: Error

    func logErr(file: StaticString, line: UInt) -> Success?
    func warnOnErr(file: StaticString, line: UInt) -> Success?
    func debugAssertOk(_ reason: String, file: StaticString, line: UInt) -> Self
}

extension Result: ResultExt {
    @discardableResult
    public func logErr(file: StaticString = #file, line: UInt = #line) -> Success? {
        switch self {
        case .success(let val):
            return val
        case .failure(let err):
            FileHandle.standardError.write(Data("[ERROR] \(file):\(line): \(err)\n".utf8))
            return nil
        }
    }

    @discardableResult
    public func warnOnErr(file: StaticString = #file, line: UInt = #line) -> Success? {
        switch self {
        case .success(let val):
            return val
        case .failure(let err):
            FileHandle.standardError.write(Data("[WARN] \(file):\(line): \(err)\n".utf8))
            return nil
        }
    }

    public func debugAssertOk(_ reason: String, file: StaticString = #file, line: UInt = #line) -> Result<Success, Failure> {
        #if DEBUG
        if case .failure(let err) = self {
            preconditionFailure("\(reason): \(err) at \(file):\(line)")
        }
        #else
        if case .failure(let err) = self {
            FileHandle.standardError.write(Data("[ERROR] \(file):\(line): \(reason): \(err)\n".utf8))
        }
        #endif
        return self
    }
}

/// Scope-guard RAII wrapper that executes an action when dropped, unless aborted.
// PORT NOTE: Deferred is a single-scope RAII guard that executes its action upon deinit within the local lexical scope matching upstream scopeguard.
public final class Deferred: @unchecked Sendable {
    private var action: (() -> Void)?

    public init(_ action: @escaping () -> Void) {
        self.action = action
    }

    public func abort() {
        action = nil
    }

    deinit {
        action?()
    }
}

public func defer_(_ action: @escaping () -> Void) -> Deferred {
    Deferred(action)
}
