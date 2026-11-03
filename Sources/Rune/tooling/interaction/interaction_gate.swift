// Ported from: crates/rune/src/tooling/interaction/gate.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Environment gate for interaction timing (`RUNE_PERF`, `OTEL_EXPORTER_OTLP_ENDPOINT`).

#if !os(WASI)
import Foundation
#endif

let INTERACTION_DEFAULT_ENDPOINT = "127.0.0.1:27686"

struct InteractionEndpoint: Sendable, Equatable, CustomStringConvertible {
    var host: String
    var port: UInt16
    var isIpv6: Bool

    var description: String {
        isIpv6 ? "[\(host)]:\(port)" : "\(host):\(port)"
    }
}

private let gateLock = LiveLock()
private enum GateState { case unknown, off, on }
// PORT NOTE: Synchronized via `gateLock`, mirroring `STATE` and `ENDPOINT` atomics in `crates/rune/src/tooling/interaction/gate.rs`.
nonisolated(unsafe) private var cachedGateState: GateState = .unknown
// PORT NOTE: Synchronized via `gateLock`, mirroring `ENDPOINT: OnceLock<Option<SocketAddr>>`.
nonisolated(unsafe) private var cachedCollectorEndpoint: InteractionEndpoint? = nil
// PORT NOTE: Synchronized via `gateLock`, supporting test capture mode without mutating process env.
nonisolated(unsafe) private var testCaptureModeEnabled: Bool = false

#if !os(WASI)
private let forcedThreadKey = "gpua.rune.interaction.forced"
#endif

func interactionGateOn() -> Bool {
    #if !os(WASI)
    if let forced = Thread.current.threadDictionary[forcedThreadKey] as? Bool {
        return forced
    }
    #endif
    return gateLock.withLock {
        switch cachedGateState {
        case .on: return true
        case .off: return false
        case .unknown: return decideLocked(headless: false)
        }
    }
}

func interactionGateHeadless() {
    gateLock.withLock {
        _ = decideLocked(headless: true)
    }
}

private func decideLocked(headless: Bool) -> Bool {
    #if os(WASI)
    cachedGateState = .off
    return false
    #else
    if testCaptureModeEnabled {
        cachedGateState = .off
        return false
    }
    let env = ProcessInfo.processInfo.environment
    let perf = env["RUNE_PERF"]
    let otel = env["OTEL_EXPORTER_OTLP_ENDPOINT"]
    let on = interactionGateWanted(perf: perf, otel: otel, headless: headless)
    if on && cachedCollectorEndpoint == nil {
        cachedCollectorEndpoint = interactionGateEndpoint(otel: otel)
    }
    cachedGateState = on ? .on : .off
    return on
    #endif
}

func interactionGateWanted(perf: String?, otel: String?, headless: Bool) -> Bool {
    switch perf.map(trimAsciiWhitespace) {
    case "0"?:
        return false
    case "1"?:
        return true
    default:
        return !headless && (otel.flatMap(interactionGateLoopback) != nil)
    }
}

func interactionGateEndpoint(otel: String?) -> InteractionEndpoint? {
    otel.flatMap(interactionGateLoopback) ?? interactionGateLoopback(INTERACTION_DEFAULT_ENDPOINT)
}

func interactionGateLoopback(_ setting: String) -> InteractionEndpoint? {
    var rest = trimAsciiWhitespace(setting)
    if rest.hasPrefix("https://") {
        return nil
    }
    if rest.hasPrefix("http://") {
        rest = String(rest.dropFirst("http://".count))
    }
    guard let hostPortRaw = rest.split(separator: "/", omittingEmptySubsequences: false).first.map(String.init),
          !hostPortRaw.isEmpty
    else { return nil }
    let normalized = hostPortRaw.replacingOccurrences(of: "localhost", with: "127.0.0.1")

    if normalized.hasPrefix("[") {
        guard let closeBracket = normalized.firstIndex(of: "]") else { return nil }
        let ipv6 = String(normalized[normalized.index(after: normalized.startIndex)..<closeBracket])
        let after = normalized[normalized.index(after: closeBracket)...]
        guard after.hasPrefix(":"), let port = UInt16(after.dropFirst()), port > 0 else { return nil }
        guard ipv6 == "::1" || ipv6 == "0:0:0:0:0:0:0:1" else { return nil }
        return InteractionEndpoint(host: "::1", port: port, isIpv6: true)
    }

    let parts = normalized.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2, let port = UInt16(parts[1]), port > 0 else { return nil }
    let ip = String(parts[0])
    let octets = ip.split(separator: ".", omittingEmptySubsequences: false).compactMap { UInt8($0) }
    guard octets.count == 4, octets[0] == 127 else { return nil }
    return InteractionEndpoint(host: ip, port: port, isIpv6: false)
}

func interactionGateCollector() -> InteractionEndpoint? {
    gateLock.withLock { cachedCollectorEndpoint }
}

func interactionGateForceOnForTests(_ enabled: Bool? = true) {
    gateLock.withLock { testCaptureModeEnabled = true }
    #if !os(WASI)
    if let enabled {
        Thread.current.threadDictionary[forcedThreadKey] = enabled
    } else {
        Thread.current.threadDictionary.removeObject(forKey: forcedThreadKey)
    }
    #endif
}

func interactionGateIsTestMode() -> Bool {
    #if !os(WASI)
    if Thread.current.threadDictionary[forcedThreadKey] != nil {
        return true
    }
    #endif
    return gateLock.withLock { testCaptureModeEnabled }
}
