// Ported from: crates/util/src/test/assertions.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

public enum SetEqError<T>: Error, Sendable, Equatable where T: Equatable & Sendable {
    case leftMissing(T)
    case rightMissing(T)

    public func map<R>(_ update: (T) -> R) -> SetEqError<R> where R: Equatable & Sendable {
        switch self {
        case .leftMissing(let missing):
            .leftMissing(update(missing))
        case .rightMissing(let missing):
            .rightMissing(update(missing))
        }
    }
}

public func setEq<T: Hashable & Sendable>(_ left: Set<T>, _ right: Set<T>) -> Result<Void, SetEqError<T>> {
    for rightVal in right {
        if !left.contains(rightVal) {
            return .failure(.leftMissing(rightVal))
        }
    }
    for leftVal in left {
        if !right.contains(leftVal) {
            return .failure(.rightMissing(leftVal))
        }
    }
    return .success(())
}

public func assertSetEq<T: Hashable & Sendable>(_ left: Set<T>, _ right: Set<T>, file: StaticString = #file, line: UInt = #line) {
    switch setEq(left, right) {
    case .failure(.leftMissing(let missing)):
        fatalError("assertion failed: (left == right)\nleft: \(left)\nright: \(right)\nleft does not contain \(missing)", file: file, line: line)
    case .failure(.rightMissing(let missing)):
        fatalError("assertion failed: (left == right)\nleft: \(left)\nright: \(right)\nright does not contain \(missing)", file: file, line: line)
    case .success:
        break
    }
}
