// Ported from: crates/gpui_web/src/logging.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
#if os(WASI)
import CWebSys
#endif

/// Severity levels mapped onto `console.error` / `warn` / `info` / `log`.
public enum WebLogLevel: Int32, Sendable, Comparable {
    case error = 0
    case warn = 1
    case info = 2
    case debug = 3
    case trace = 4

    public static func < (lhs: WebLogLevel, rhs: WebLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .error: return "ERROR"
        case .warn: return "WARN"
        case .info: return "INFO"
        case .debug: return "DEBUG"
        case .trace: return "TRACE"
        }
    }
}

// PORT NOTE: ConsoleLoggerState stores logger configuration behind NSLock (or single-threaded WASI main thread).
final class ConsoleLoggerState: @unchecked Sendable {
    static let shared = ConsoleLoggerState()

    #if !os(WASI)
    private let lock = NSLock()
    #endif
    private var initialized: Bool = false
    private var maxLevel: WebLogLevel = .info

    func initialize(maxLevel: WebLogLevel = .info) {
        #if !os(WASI)
        lock.lock()
        defer { lock.unlock() }
        #endif
        self.initialized = true
        self.maxLevel = maxLevel
    }

    func isEnabled(_ level: WebLogLevel) -> Bool {
        #if !os(WASI)
        lock.lock()
        defer { lock.unlock() }
        #endif
        if !initialized {
            return level <= .info
        }
        return level <= maxLevel
    }
}

struct ConsoleLogger: Sendable {
    func enabled(_ level: WebLogLevel) -> Bool {
        ConsoleLoggerState.shared.isEnabled(level)
    }

    func log(level: WebLogLevel, target: String = "gpui_web", _ message: String) {
        guard enabled(level) else { return }
        let formatted = "[\(level.label)] \(target): \(message)"
        #if os(WASI)
        var utf8 = Array(formatted.utf8)
        utf8.withUnsafeBufferPointer { buffer in
            cwebsys_console_log(level.rawValue, buffer.baseAddress, buffer.count)
        }
        #else
        if level == .error || level == .warn {
            FileHandle.standardError.write(Data((formatted + "\n").utf8))
        } else {
            print(formatted)
        }
        #endif
    }

    func flush() {
        #if !os(WASI)
        fflush(nil)
        #endif
    }
}

/// Initializes browser console logging with default `Info` level filtering.
public func initLogging() {
    ConsoleLoggerState.shared.initialize(maxLevel: .info)
}

func webLog(_ level: WebLogLevel, target: String = "gpui_web", _ message: @autoclosure () -> String) {
    let logger = ConsoleLogger()
    guard logger.enabled(level) else { return }
    logger.log(level: level, target: target, message())
}
