// Ported from: crates/gpui/src/keymap/context.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

/// An entry in a KeyContext.
public struct ContextEntry: Equatable, Hashable, Sendable, CustomDebugStringConvertible {
    /// The key (or name if no value).
    public var key: SharedString
    /// The value.
    public var value: SharedString?

    public init(key: SharedString, value: SharedString? = nil) {
        self.key = key
        self.value = value
    }

    public var debugDescription: String {
        if let value {
            return "\(key)=\(value)"
        }
        return "\(key)"
    }
}

/// A datastructure for resolving whether an action should be dispatched
/// at this point in the element tree. Contains a set of identifiers
/// and/or key value pairs representing the current context for the keymap.
public struct KeyContext: Equatable, Hashable, Sendable, CustomDebugStringConvertible, CustomStringConvertible {
    private var entries: [ContextEntry]

    public init(entries: [ContextEntry] = []) {
        self.entries = entries
    }

    /// Initialize a new KeyContext that contains an `os` key set to either `macos`, `linux`, `windows` or `unknown`.
    public static func newWithDefaults() -> KeyContext {
        var context = KeyContext()
        #if os(macOS)
        context.set("os", "macos")
        #elseif os(Linux) || os(FreeBSD)
        context.set("os", "linux")
        #elseif os(Windows)
        context.set("os", "windows")
        #else
        context.set("os", "unknown")
        #endif
        return context
    }

    public static func new_with_defaults() -> KeyContext {
        newWithDefaults()
    }

    /// Returns the primary context entry (usually the name of the component).
    public func primary() -> ContextEntry? {
        entries.first { $0.value == nil }
    }

    /// Returns everything except the primary context entry.
    public func secondary() -> [ContextEntry] {
        let prim = primary()
        return entries.filter { $0 != prim }
    }

    /// Parse a key context from a string.
    /// Format: `StatusBar mode=visible` or `StatusBar mode = visible`
    public static func parse(_ source: String) throws -> KeyContext {
        var context = KeyContext()
        var remaining = skipWhitespace(source[...])
        try parseExpr(&remaining, into: &context)
        return context
    }

    private static func parseExpr(_ source: inout Substring, into context: inout KeyContext) throws {
        source = skipWhitespace(source)
        if source.isEmpty {
            return
        }

        let keyChars = source.prefix(while: { isIdentifierChar($0) })
        guard !keyChars.isEmpty else {
            return
        }
        let key = String(keyChars)
        source = skipWhitespace(source.dropFirst(keyChars.count))

        if source.hasPrefix("=") {
            source = skipWhitespace(source.dropFirst())
            let valueChars = source.prefix(while: { isIdentifierChar($0) })
            let value = String(valueChars)
            source = skipWhitespace(source.dropFirst(valueChars.count))
            context.set(SharedString(key), SharedString(value))
        } else {
            context.add(SharedString(key))
        }

        try parseExpr(&source, into: &context)
    }

    /// Check if this context is empty.
    public var isEmpty: Bool {
        entries.isEmpty
    }

    public func is_empty() -> Bool {
        isEmpty
    }

    /// Clear this context.
    public mutating func clear() {
        entries.removeAll()
    }

    /// Extend this context with another context.
    public mutating func extend(_ other: KeyContext) {
        for entry in other.entries {
            if !contains(entry.key.asString) {
                entries.append(entry)
            }
        }
    }

    /// Add an identifier to this context, if it's not already in this context.
    public mutating func add(_ identifier: SharedString) {
        if !contains(identifier.asString) {
            entries.append(ContextEntry(key: identifier, value: nil))
        }
    }

    public mutating func add(_ identifier: String) {
        add(SharedString(identifier))
    }

    /// Set a key value pair in this context, if it's not already set.
    public mutating func set(_ key: SharedString, _ value: SharedString) {
        if !contains(key.asString) {
            entries.append(ContextEntry(key: key, value: value))
        }
    }

    public mutating func set(_ key: String, _ value: String) {
        set(SharedString(key), SharedString(value))
    }

    /// Check if this context contains a given identifier or key.
    public func contains(_ key: String) -> Bool {
        entries.contains(where: { $0.key.value == key })
    }

    /// Get the associated value for a given identifier or key.
    public func get(_ key: String) -> SharedString? {
        entries.first(where: { $0.key.value == key })?.value
    }

    public var debugDescription: String {
        entries.map { entry in
            if let val = entry.value {
                return "\(entry.key)=\(val)"
            }
            return "\(entry.key)"
        }.joined(separator: " ")
    }

    public var description: String {
        debugDescription
    }
}

// MARK: - Predicate AST

/// Error parsing context expressions or predicates.
public enum ContextParseError: Error, CustomStringConvertible, Sendable, Equatable {
    case message(String)
    case unexpectedEnd
    case expectedClosingParen

    public var description: String {
        switch self {
        case .message(let msg):
            return msg
        case .unexpectedEnd:
            return "unexpected end"
        case .expectedClosingParen:
            return "expected a ')'"
        }
    }
}

private let PRECEDENCE_CHILD: UInt32 = 1 // >
private let PRECEDENCE_OR: UInt32 = 2    // ||
private let PRECEDENCE_AND: UInt32 = 3   // &&
private let PRECEDENCE_EQ: UInt32 = 4    // ==, !=
private let PRECEDENCE_NOT: UInt32 = 5   // !

private enum LogicalOperator {
    case and
    case or
}

/// A datastructure for resolving whether an action should be dispatched.
/// Represents a small predicate language for describing which contexts correspond to which actions.
public indirect enum KeyBindingContextPredicate: Equatable, Hashable, Sendable, CustomStringConvertible {
    case identifier(SharedString)
    case equal(SharedString, SharedString)
    case notEqual(SharedString, SharedString)
    case descendant(KeyBindingContextPredicate, KeyBindingContextPredicate)
    case not(KeyBindingContextPredicate)
    case and(KeyBindingContextPredicate, KeyBindingContextPredicate)
    case or(KeyBindingContextPredicate, KeyBindingContextPredicate)

    public var description: String {
        switch self {
        case .identifier(let name):
            return "\(name)"
        case .equal(let left, let right):
            return "\(left) == \(right)"
        case .notEqual(let left, let right):
            return "\(left) != \(right)"
        case .descendant(let parent, let child):
            return "\(parent) > \(child)"
        case .not(let pred):
            if case .identifier(let name) = pred {
                return "!\(name)"
            }
            return "!(\(pred))"
        case .and:
            return fmtJoined(separator: " && ", op: .and) { node in
                if case .or = node { return true }
                return false
            }
        case .or:
            return fmtJoined(separator: " || ", op: .or) { node in
                if case .and = node { return true }
                return false
            }
        }
    }

    private func fmtJoined(
        separator: String,
        op: LogicalOperator,
        needsParens: (KeyBindingContextPredicate) -> Bool
    ) -> String {
        var parts: [String] = []
        flatten(op: op, into: &parts, needsParens: needsParens)
        return parts.joined(separator: separator)
    }

    private func flatten(
        op: LogicalOperator,
        into parts: inout [String],
        needsParens: (KeyBindingContextPredicate) -> Bool
    ) {
        switch (op, self) {
        case (.and, .and(let left, let right)),
             (.or, .or(let left, let right)):
            left.flatten(op: op, into: &parts, needsParens: needsParens)
            right.flatten(op: op, into: &parts, needsParens: needsParens)
        default:
            if needsParens(self) {
                parts.append("(\(self))")
            } else {
                parts.append("\(self)")
            }
        }
    }

    /// Parse a predicate expression string.
    public static func parse(_ source: String) throws -> KeyBindingContextPredicate {
        let rest = skipWhitespace(source[...])
        let (predicate, after) = try parseExpr(rest, minPrecedence: 0)
        let trimmed = skipWhitespace(after)
        if let next = trimmed.first {
            throw ContextParseError.message("unexpected character '\(next)'")
        }
        return predicate
    }

    private static func parseExpr(
        _ source: Substring,
        minPrecedence: UInt32
    ) throws -> (KeyBindingContextPredicate, Substring) {
        var (predicate, varRest) = try parsePrimary(source)
        var current = varRest

        parseLoop: while true {
            let operators: [(String, UInt32)] = [
                (">", PRECEDENCE_CHILD),
                ("&&", PRECEDENCE_AND),
                ("||", PRECEDENCE_OR),
                ("==", PRECEDENCE_EQ),
                ("!=", PRECEDENCE_EQ)
            ]

            for (op, prec) in operators {
                if current.hasPrefix(op) && prec >= minPrecedence {
                    current = skipWhitespace(current.dropFirst(op.count))
                    let (right, afterRight) = try parseExpr(current, minPrecedence: prec + 1)
                    switch op {
                    case ">":
                        predicate = .descendant(predicate, right)
                    case "&&":
                        predicate = .and(predicate, right)
                    case "||":
                        predicate = .or(predicate, right)
                    case "==":
                        guard case .identifier(let l) = predicate, case .identifier(let r) = right else {
                            throw ContextParseError.message("operands of == must be identifiers")
                        }
                        predicate = .equal(l, r)
                    case "!=":
                        guard case .identifier(let l) = predicate, case .identifier(let r) = right else {
                            throw ContextParseError.message("operands of != must be identifiers")
                        }
                        predicate = .notEqual(l, r)
                    default:
                        break
                    }
                    current = afterRight
                    continue parseLoop
                }
            }
            break
        }

        return (predicate, current)
    }

    private static func parsePrimary(
        _ source: Substring
    ) throws -> (KeyBindingContextPredicate, Substring) {
        guard let next = source.first else {
            throw ContextParseError.unexpectedEnd
        }

        switch next {
        case "(":
            let inner = skipWhitespace(source.dropFirst())
            let (predicate, after) = try parseExpr(inner, minPrecedence: 0)
            guard after.hasPrefix(")") else {
                throw ContextParseError.expectedClosingParen
            }
            let rest = skipWhitespace(after.dropFirst())
            return (predicate, rest)

        case "!":
            let afterNot = skipWhitespace(source.dropFirst())
            let (predicate, rest) = try parseExpr(afterNot, minPrecedence: PRECEDENCE_NOT)
            return (.not(predicate), rest)

        case _ where isIdentifierChar(next):
            let identChars = source.prefix(while: { isIdentifierChar($0) || isVimOperatorChar($0) })
            let identStr = String(identChars)
            let rest = skipWhitespace(source.dropFirst(identChars.count))
            return (.identifier(SharedString(identStr)), rest)

        case _ where isVimOperatorChar(next):
            let opStr = String(next)
            let rest = skipWhitespace(source.dropFirst())
            return (.identifier(SharedString(opStr)), rest)

        default:
            throw ContextParseError.message("unexpected character '\(next)'")
        }
    }

    /// Find the deepest depth at which the predicate matches.
    public func depthOf(_ contexts: [KeyContext]) -> Int? {
        for depth in (0...contexts.count).reversed() {
            let slice = Array(contexts[0..<depth])
            if evalInner(slice, allContexts: contexts) {
                return depth
            }
        }
        return nil
    }

    public func depth_of(_ contexts: [KeyContext]) -> Int? {
        depthOf(contexts)
    }

    /// Eval a predicate against a set of contexts, arranged from lowest to highest.
    public func eval(_ contexts: [KeyContext]) -> Bool {
        evalInner(contexts, allContexts: contexts)
    }

    /// Eval a predicate against a set of contexts, arranged from lowest to highest.
    public func evalInner(_ contexts: [KeyContext], allContexts: [KeyContext]) -> Bool {
        guard let context = contexts.last else {
            return false
        }

        switch self {
        case .identifier(let name):
            return context.contains(name.asString)

        case .equal(let left, let right):
            return context.get(left.asString) == right

        case .notEqual(let left, let right):
            if let val = context.get(left.asString) {
                return val != right
            }
            return true

        case .not(let pred):
            for i in 0..<allContexts.count {
                let slice = Array(allContexts[0...i])
                if pred.evalInner(slice, allContexts: allContexts) {
                    return false
                }
            }
            return true

        case .descendant(let parent, let child):
            guard contexts.count > 1 else { return false }
            for i in 0..<(contexts.count - 1) {
                let parentSlice = Array(contexts[0...i])
                if parent.evalInner(parentSlice, allContexts: allContexts) {
                    let childSlice = Array(contexts[(i + 1)...])
                    if !child.evalInner(childSlice, allContexts: childSlice) {
                        return false
                    }
                    return true
                }
            }
            return false

        case .and(let left, let right):
            return left.evalInner(contexts, allContexts: allContexts)
                && right.evalInner(contexts, allContexts: allContexts)

        case .or(let left, let right):
            return left.evalInner(contexts, allContexts: allContexts)
                || right.evalInner(contexts, allContexts: allContexts)
        }
    }

    public func eval_inner(_ contexts: [KeyContext], all_contexts: [KeyContext]) -> Bool {
        evalInner(contexts, allContexts: all_contexts)
    }

    /// Returns whether or not this predicate matches all possible contexts matched by the other predicate.
    public func isSuperset(of other: KeyBindingContextPredicate) -> Bool {
        if self == other {
            return true
        }

        if case .or(let left, let right) = self {
            return left.isSuperset(of: other) || right.isSuperset(of: other)
        }

        switch other {
        case .descendant(_, let child):
            return isSuperset(of: child)
        case .and(let left, let right):
            return isSuperset(of: left) || isSuperset(of: right)
        default:
            return false
        }
    }

    public func is_superset(_ other: KeyBindingContextPredicate) -> Bool {
        isSuperset(of: other)
    }
}

// MARK: - Character Helpers

func isIdentifierChar(_ c: Character) -> Bool {
    guard let scalar = c.unicodeScalars.first, c.unicodeScalars.count == 1 else {
        return false
    }
    return CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-"
}

func isVimOperatorChar(_ c: Character) -> Bool {
    c == ">" || c == "<" || c == "~" || c == "\"" || c == "?"
}

func skipWhitespace(_ source: Substring) -> Substring {
    var s = source
    while let first = s.first, first.isWhitespace {
        s = s.dropFirst()
    }
    return s
}
