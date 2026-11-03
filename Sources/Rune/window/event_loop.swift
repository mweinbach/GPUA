// Ported from: crates/rune/src/window/event_loop.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Multi-host event-loop scheduler and control-flow calculation (`crates/rune/src/window/event_loop.rs`).

/// Control-flow decision after an event-loop turn (`crates/rune/src/window/event_loop.rs`).
enum EventLoopControl: Sendable, Equatable {
    case wait
    case waitUntil(RuneInstant)
    case exit
}

/// Computes the next `EventLoopControl` across all active hosts (`crates/rune/src/window/event_loop.rs`).
func computeControlFlow(hosts: [any AnyHost], now: RuneInstant = .now()) -> EventLoopControl {
    guard hosts.contains(where: { $0.isAlive }) else {
        return .exit
    }
    var earliest: RuneInstant? = nil
    for host in hosts {
        if let deadline = host.nextWakeDeadline(now: now) {
            if let cur = earliest {
                earliest = min(cur, deadline)
            } else {
                earliest = deadline
            }
        }
    }
    if let target = earliest {
        return .waitUntil(target)
    }
    return .wait
}

/// Coordinates multiple `AnyHost` instances through startup, wakes, reopen, URL routing, and shutdown (`crates/rune/src/window/event_loop.rs`).
// PORT NOTE: Synchronized via `wakeLock` (`LiveLock`) so `WindowHandle` and `AppHandle` wakers can post events from any thread.
final class ShellEventLoop: @unchecked Sendable {
    private(set) var hosts: [any AnyHost]
    var displays: [Display]
    private var pendingWakes: [WakeEvent] = []
    private let wakeLock = LiveLock()
    private(set) var exited: Bool = false

    init(hosts: [any AnyHost], displays: [Display] = [Display()]) {
        self.hosts = hosts
        self.displays = displays
    }

    func postWake(_ event: WakeEvent) {
        wakeLock.withLock {
            pendingWakes.append(event)
        }
    }

    func start() {
        for i in 0..<hosts.count {
            let idx = i
            hosts[i].attachHost(
                hostIndex: idx,
                wakeHost: { [weak self] in
                    self?.postWake(.host(idx))
                },
                wakeSink: { [weak self] ev in
                    self?.postWake(ev)
                }
            )
        }
        for i in 0..<hosts.count {
            hosts[i].resumeHost(hostIndex: i, displays: displays)
        }
        if computeControlFlow(hosts: hosts) == .exit {
            shutdown()
        }
    }

    @discardableResult
    func pump(now: RuneInstant = .now()) -> EventLoopControl {
        if exited {
            return .exit
        }
        let wakes = wakeLock.withLock { () -> [WakeEvent] in
            let out = pendingWakes
            pendingWakes.removeAll()
            return out
        }

        for w in wakes {
            switch w {
            case .host(let idx) where idx >= 0 && idx < hosts.count:
                if hosts[idx].stepHost(now: now, displays: displays) {
                    shutdown()
                    return .exit
                }
            case .overlay(let hostIdx, _) where hostIdx >= 0 && hostIdx < hosts.count:
                if hosts[hostIdx].stepHost(now: now, displays: displays) {
                    shutdown()
                    return .exit
                }
            case .window(let idx, _), .focus(let idx), .level(let idx, _), .position(let idx, _), .place(let idx, _), .frame(let idx, _):
                if idx >= 0 && idx < hosts.count {
                    if hosts[idx].handleHostWakeEvent(w, displays: displays) {
                        shutdown()
                        return .exit
                    }
                }
            case .reopen:
                let hasVisible = hosts.contains { $0.hasVisibleReopenableWindow() }
                var anyHandled = false
                for host in hosts {
                    if host.handleReopen(hasVisibleWindows: hasVisible) {
                        anyHandled = true
                    }
                }
                if !anyHandled && !hasVisible {
                    if let primaryIdx = hosts.firstIndex(where: { $0.isPrimaryHost }) {
                        _ = hosts[primaryIdx].handleHostWakeEvent(.window(primaryIdx, .open(nil)), displays: displays)
                    }
                }
            case .openUrls(let urls):
                for host in hosts {
                    host.handleIncomingUrls(urls)
                }
            default:
                break
            }
        }

        for host in hosts {
            if host.stepHost(now: now, displays: displays) {
                shutdown()
                return .exit
            }
        }

        let control = computeControlFlow(hosts: hosts, now: now)
        if control == .exit {
            shutdown()
        }
        return control
    }

    func shutdown() {
        guard !exited else { return }
        exited = true
        for host in hosts {
            host.shutdownHost()
        }
        shutdownClipboard()
    }
}
