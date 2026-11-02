// Ported from: crates/procwatch/src/lib.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#elseif canImport(WASILibc)
import WASILibc
#elseif canImport(WinSDK)
import WinSDK
#endif

public typealias Instant = ContinuousClock.Instant

/// Locale-independent fixed-point formatter matching Rust's `{:.N}` round-half-to-even output.
internal func formatFixed(_ value: Double, decimals: Int) -> String {
    guard value.isFinite else {
        if value.isNaN { return "NaN" }
        return value < 0 ? "-inf" : "inf"
    }
    if decimals <= 0 {
        let r = value.rounded(.toNearestOrEven)
        if r == 0 { return "0" }
        return String(Int64(r))
    }
    var scale = 1.0
    var intScale: Int64 = 1
    for _ in 0..<decimals {
        scale *= 10.0
        intScale *= 10
    }
    let scaled = (value * scale).rounded(.toNearestOrEven)
    let isNeg = scaled < 0
    let absScaled = Int64(abs(scaled))
    let whole = absScaled / intScale
    let frac = absScaled % intScale
    var fracStr = String(frac)
    if fracStr.count < decimals {
        fracStr = String(repeating: "0", count: decimals - fracStr.count) + fracStr
    }
    return "\(isNeg ? "-" : "")\(whole).\(fracStr)"
}

@inline(__always)
private func durationSince(_ earlier: Instant, _ now: Instant) -> Duration {
    now >= earlier ? earlier.duration(to: now) : .zero
}

@inline(__always)
private func durationSeconds(_ d: Duration) -> Double {
    let (secs, attos) = d.components
    return Double(secs) + Double(attos) * 1e-18
}

/// Per-thread CPU sample inside a ``Snapshot``.
public struct Thread: Equatable, Sendable {
    /// The kernel's id for the thread, stable for its life.
    public var id: UInt64
    public var name: String
    /// CPU seconds since the thread started.
    public var cpuS: Double

    public init(id: UInt64 = 0, name: String = "", cpuS: Double = 0.0) {
        self.id = id
        self.name = name
        self.cpuS = cpuS
    }
}

/// Point-in-time process memory, CPU, descriptor, thread, heap, and gauge snapshot.
public struct Snapshot: Equatable, Sendable {
    public var pid: Int32
    /// Physical footprint: dirty memory, compressed and swapped included.
    public var footprint: UInt64
    public var footprintPeak: UInt64
    public var resident: UInt64
    /// User plus system CPU seconds over the process's life, exited threads included.
    public var cpuS: Double
    /// Open file descriptors, sockets and pipes included.
    public var fds: UInt32
    public var threads: [Thread]
    public var heap: alloc.Heap?
    /// Every ``Gauge`` used so far, biggest first.
    public var gauges: [(String, Int64)]

    public init(
        pid: Int32 = 0,
        footprint: UInt64 = 0,
        footprintPeak: UInt64 = 0,
        resident: UInt64 = 0,
        cpuS: Double = 0.0,
        fds: UInt32 = 0,
        threads: [Thread] = [],
        heap: alloc.Heap? = nil,
        gauges: [(String, Int64)] = []
    ) {
        self.pid = pid
        self.footprint = footprint
        self.footprintPeak = footprintPeak
        self.resident = resident
        self.cpuS = cpuS
        self.fds = fds
        self.threads = threads
        self.heap = heap
        self.gauges = gauges
    }

    public static func == (lhs: Snapshot, rhs: Snapshot) -> Bool {
        guard lhs.pid == rhs.pid,
              lhs.footprint == rhs.footprint,
              lhs.footprintPeak == rhs.footprintPeak,
              lhs.resident == rhs.resident,
              lhs.cpuS == rhs.cpuS,
              lhs.fds == rhs.fds,
              lhs.threads == rhs.threads,
              lhs.heap == rhs.heap,
              lhs.gauges.count == rhs.gauges.count
        else {
            return false
        }
        for (a, b) in zip(lhs.gauges, rhs.gauges) where a.0 != b.0 || a.1 != b.1 {
            return false
        }
        return true
    }

    /// CPU seconds spent by threads that have since exited.
    public func exitedCpuS() -> Double {
        let liveSum = threads.reduce(0.0) { $0 + $1.cpuS }
        return max(0.0, cpuS - liveSum)
    }

    /// Footprint minus the counted heap and every gauge; `nil` without ``alloc/Counting``.
    /// It has a floor (code, stacks, allocator overhead, system libraries), so watch it grow
    /// rather than reading it alone.
    public func unaccounted() -> Int64? {
        guard let heap else { return nil }
        let gaugeSum = gauges.reduce(Int64(0)) { $0 + $1.1 }
        return Int64(bitPattern: footprint) - max(0, heap.live) - gaugeSum
    }

    public func toJson() -> String {
        var s = ""
        s.reserveCapacity(256)
        s += "{\"pid\":\(pid)"
        s += ",\"footprint\":\(footprint)"
        s += ",\"footprint_peak\":\(footprintPeak)"
        s += ",\"resident\":\(resident)"
        s += ",\"cpu_s\":\(formatFixed(cpuS, decimals: 3))"
        s += ",\"exited_cpu_s\":\(formatFixed(exitedCpuS(), decimals: 3))"
        s += ",\"fds\":\(fds)"
        s += ",\"threads\":["
        for (i, t) in threads.enumerated() {
            if i > 0 { s.append(",") }
            s += "{\"name\":\"\(cleanJsonName(t.name))\",\"cpu_s\":\(formatFixed(t.cpuS, decimals: 3))}"
        }
        s.append("]")
        if let h = heap {
            s += ",\"heap\":{\"live\":\(h.live),\"peak\":\(h.peak),\"allocations\":\(h.allocations)"
            s += ",\"largest\":\(h.largest),\"big_live\":\(h.bigLive),\"big_blocks\":\(h.bigBlocks),\"tags\":"
            appendJsonMap(&s, h.tags)
            s.append("}")
        }
        s += ",\"gauges\":"
        appendJsonMap(&s, gauges)
        if let bytes = unaccounted() {
            s += ",\"unaccounted\":\(bytes)"
        }
        s.append("}")
        return s
    }
}

private func cleanJsonName(_ name: String) -> String {
    var out = String.UnicodeScalarView()
    out.reserveCapacity(name.unicodeScalars.count)
    for scalar in name.unicodeScalars {
        let v = scalar.value
        let isControl = v < 0x20 || (v >= 0x7F && v <= 0x9F)
        if !isControl && scalar != "\"" && scalar != "\\" {
            out.append(scalar)
        }
    }
    return String(out)
}

private func appendJsonMap(_ s: inout String, _ entries: [(String, Int64)]) {
    s.append("{")
    for (i, (name, bytes)) in entries.enumerated() {
        if i > 0 { s.append(",") }
        s += "\"\(cleanJsonName(name))\":\(bytes)"
    }
    s.append("}")
}

@inline(__always)
internal func currentPid() -> Int32 {
    #if os(WASI)
    return 1
    #elseif os(Windows)
    return Int32(bitPattern: GetCurrentProcessId())
    #else
    return Int32(getpid())
    #endif
}

/// This process now.
public func snapshot() -> Snapshot? {
    guard var s = snapshotOf(currentPid()) else {
        return nil
    }
    s.heap = alloc.heap()
    s.gauges = gauges()
    return s
}

/// This process's memory and open files, each `nil` where it can't be read.
public struct Usage: Equatable, Hashable, Sendable {
    /// Physical footprint, as in ``Snapshot/footprint``.
    public var footprint: UInt64?
    public var footprintPeak: UInt64?
    public var resident: UInt64?
    public var fds: UInt32?

    public init(
        footprint: UInt64? = nil,
        footprintPeak: UInt64? = nil,
        resident: UInt64? = nil,
        fds: UInt32? = nil
    ) {
        self.footprint = footprint
        self.footprintPeak = footprintPeak
        self.resident = resident
        self.fds = fds
    }
}

// MARK: - Platform Introspection

#if canImport(Darwin)
@_silgen_name("mach_task_self")
private func darwinMachTaskSelf() -> mach_port_t

private func ticksToSeconds() -> Double {
    var base = mach_timebase_info_data_t(numer: 0, denom: 0)
    _ = mach_timebase_info(&base)
    if base.denom == 0 {
        return 1e-9
    }
    return Double(base.numer) / Double(base.denom) / 1e9
}

private func darwinSelfVmUsage() -> (footprint: UInt64, peak: UInt64, resident: UInt64)? {
    var vmInfo = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &vmInfo) { ptr in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
            task_info(darwinMachTaskSelf(), task_flavor_t(TASK_VM_INFO), intPtr, &count)
        }
    }
    guard kr == KERN_SUCCESS else {
        return nil
    }
    let footprint = UInt64(vmInfo.phys_footprint)
    let rawPeak = vmInfo.ledger_phys_footprint_peak
    let peak = max(footprint, rawPeak > 0 ? UInt64(rawPeak) : footprint)
    let resident = UInt64(vmInfo.resident_size)
    return (footprint, peak, resident)
}

#if os(macOS)
private func darwinRusage(_ pid: Int32) -> rusage_info_v4? {
    var info = rusage_info_v4()
    let rc = withUnsafeMutablePointer(to: &info) { ptr in
        ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rusagePtr in
            proc_pid_rusage(pid, RUSAGE_INFO_V4, rusagePtr)
        }
    }
    return rc == 0 ? info : nil
}

private func darwinOpenFds(_ pid: Int32) -> UInt32? {
    let procPidListFds: Int32 = 1
    let fdInfoSize = 8
    let want = proc_pidinfo(pid, procPidListFds, 0, nil, 0)
    guard want > 0 else { return nil }
    var buf = [UInt64](repeating: 0, count: Int(want) / fdInfoSize + 1)
    let byteLen = Int32(buf.count * fdInfoSize)
    let got = buf.withUnsafeMutableBytes { rawBuf in
        proc_pidinfo(pid, procPidListFds, 0, rawBuf.baseAddress, byteLen)
    }
    guard got > 0 else { return nil }
    return UInt32(Int(got) / fdInfoSize)
}

/// Another process of this user (or this one), read through `proc_pid_rusage` and `proc_pidinfo`,
/// falling back to Mach `task_info` for `self` if needed.
public func snapshotOf(_ pid: Int32) -> Snapshot? {
    if let ru = darwinRusage(pid) {
        let ticks = ticksToSeconds()
        let procPidListThreads: Int32 = 6
        var ids = [UInt64](repeating: 0, count: 512)
        let idBytes = ids.withUnsafeMutableBytes { rawBuf in
            proc_pidinfo(pid, procPidListThreads, 0, rawBuf.baseAddress, Int32(rawBuf.count))
        }
        let threadCount = max(0, Int(idBytes)) / 8
        var threads: [Thread] = []
        threads.reserveCapacity(threadCount)
        let infoSize = Int32(MemoryLayout<proc_threadinfo>.size)
        for i in 0..<threadCount {
            let tid = ids[i]
            var tinfo = proc_threadinfo()
            let got = withUnsafeMutableBytes(of: &tinfo) { rawBuf in
                proc_pidinfo(pid, PROC_PIDTHREADINFO, tid, rawBuf.baseAddress, infoSize)
            }
            if got == infoSize {
                let name = withUnsafePointer(to: tinfo.pth_name) { namePtr in
                    namePtr.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: tinfo.pth_name)) { cStr in
                        String(cString: cStr)
                    }
                }
                let cpuS = Double(tinfo.pth_user_time + tinfo.pth_system_time) / 1e9
                threads.append(Thread(id: tid, name: name, cpuS: cpuS))
            }
        }
        return Snapshot(
            pid: pid,
            footprint: ru.ri_phys_footprint,
            footprintPeak: ru.ri_lifetime_max_phys_footprint,
            resident: ru.ri_resident_size,
            cpuS: Double(ru.ri_user_time + ru.ri_system_time) * ticks,
            fds: darwinOpenFds(pid) ?? 0,
            threads: threads,
            heap: nil,
            gauges: []
        )
    }
    if pid == getpid(), let vm = darwinSelfVmUsage() {
        return darwinSelfTaskSnapshot(pid: pid, vm: vm)
    }
    return nil
}

/// ``snapshot()``'s memory and file counts without its thread walk or heap counters.
public func usage() -> Usage {
    let pid = getpid()
    var out = Usage(fds: darwinOpenFds(pid))
    if let ru = darwinRusage(pid) {
        out.footprint = ru.ri_phys_footprint
        out.footprintPeak = ru.ri_lifetime_max_phys_footprint
        out.resident = ru.ri_resident_size
    } else if let vm = darwinSelfVmUsage() {
        out.footprint = vm.footprint
        out.footprintPeak = vm.peak
        out.resident = vm.resident
    }
    return out
}
#else
// PORT NOTE: On iOS / visionOS / macCatalyst where `<libproc.h>` is unavailable, `snapshotOf` and
// `usage` use Mach `task_info(TASK_VM_INFO)`, `task_threads`, `getrusage(RUSAGE_SELF)`, and `/dev/fd`.
private func darwinDevFdCount() -> UInt32? {
    guard let dir = opendir("/dev/fd") else { return nil }
    defer { closedir(dir) }
    var count: UInt32 = 0
    while let entry = readdir(dir) {
        let firstByte = withUnsafeBytes(of: entry.pointee.d_name) { $0.first ?? 0 }
        if firstByte != 0 && firstByte != UInt8(ascii: ".") {
            count += 1
        }
    }
    return count > 0 ? (count - 1) : 0
}

public func snapshotOf(_ pid: Int32) -> Snapshot? {
    guard pid == getpid(), let vm = darwinSelfVmUsage() else {
        return nil
    }
    return darwinSelfTaskSnapshot(pid: pid, vm: vm)
}

public func usage() -> Usage {
    var out = Usage(fds: darwinDevFdCount())
    if let vm = darwinSelfVmUsage() {
        out.footprint = vm.footprint
        out.footprintPeak = vm.peak
        out.resident = vm.resident
    }
    return out
}
#endif

private func darwinSelfTaskSnapshot(
    pid: Int32,
    vm: (footprint: UInt64, peak: UInt64, resident: UInt64)
) -> Snapshot {
    var ru = rusage()
    var totalCpu = 0.0
    if getrusage(RUSAGE_SELF, &ru) == 0 {
        totalCpu = Double(ru.ru_utime.tv_sec) + Double(ru.ru_utime.tv_usec) / 1e6
            + Double(ru.ru_stime.tv_sec) + Double(ru.ru_stime.tv_usec) / 1e6
    }

    var threads: [Thread] = []
    var threadList: thread_act_array_t?
    var threadCount: mach_msg_type_number_t = 0
    let task = darwinMachTaskSelf()
    if task_threads(task, &threadList, &threadCount) == KERN_SUCCESS, let list = threadList {
        threads.reserveCapacity(Int(threadCount))
        for i in 0..<Int(threadCount) {
            let port = list[i]
            defer { mach_port_deallocate(task, port) }

            var tid: UInt64 = UInt64(port)
            var idInfo = thread_identifier_info_data_t()
            var idCount = mach_msg_type_number_t(MemoryLayout<thread_identifier_info_data_t>.size / MemoryLayout<natural_t>.size)
            let idKr = withUnsafeMutablePointer(to: &idInfo) { ptr in
                ptr.withMemoryRebound(to: integer_t.self, capacity: Int(idCount)) { intPtr in
                    thread_info(port, thread_flavor_t(THREAD_IDENTIFIER_INFO), intPtr, &idCount)
                }
            }
            if idKr == KERN_SUCCESS {
                tid = idInfo.thread_id
            }

            var extInfo = thread_extended_info_data_t()
            var extCount = mach_msg_type_number_t(MemoryLayout<thread_extended_info_data_t>.size / MemoryLayout<natural_t>.size)
            let extKr = withUnsafeMutablePointer(to: &extInfo) { ptr in
                ptr.withMemoryRebound(to: integer_t.self, capacity: Int(extCount)) { intPtr in
                    thread_info(port, thread_flavor_t(THREAD_EXTENDED_INFO), intPtr, &extCount)
                }
            }
            if extKr == KERN_SUCCESS {
                let name = withUnsafePointer(to: extInfo.pth_name) { namePtr in
                    namePtr.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: extInfo.pth_name)) { cStr in
                        String(cString: cStr)
                    }
                }
                let cpuS = Double(extInfo.pth_user_time + extInfo.pth_system_time) / 1e9
                threads.append(Thread(id: tid, name: name, cpuS: cpuS))
            }
        }
        let byteSize = vm_size_t(Int(threadCount) * MemoryLayout<thread_act_t>.stride)
        _ = vm_deallocate(task, vm_address_t(UInt(bitPattern: list)), byteSize)
    }

    var fds: UInt32 = 0
    #if os(macOS)
    fds = darwinOpenFds(pid) ?? 0
    #else
    if let dir = opendir("/dev/fd") {
        var c: UInt32 = 0
        while let entry = readdir(dir) {
            let firstByte = withUnsafeBytes(of: entry.pointee.d_name) { $0.first ?? 0 }
            if firstByte != 0 && firstByte != UInt8(ascii: ".") {
                c += 1
            }
        }
        closedir(dir)
        fds = c > 0 ? (c - 1) : 0
    }
    #endif

    return Snapshot(
        pid: pid,
        footprint: vm.footprint,
        footprintPeak: vm.peak,
        resident: vm.resident,
        cpuS: totalCpu,
        fds: fds,
        threads: threads,
        heap: nil,
        gauges: []
    )
}

#elseif os(Linux) || os(Android)
// PORT NOTE: On Linux and Android, process memory, CPU, threads, and open descriptors are read
// from `/proc/self/{statm,status,stat,task,fd}` (or `/proc/<pid>/...`).
private func linuxPageSize() -> UInt64 {
    let sc = sysconf(Int32(_SC_PAGESIZE))
    return sc > 0 ? UInt64(sc) : 4096
}

private func linuxClockTicks() -> Double {
    let sc = sysconf(Int32(_SC_CLK_TCK))
    return sc > 0 ? Double(sc) : 100.0
}

private func linuxOpenFds(_ prefix: String, isSelf: Bool) -> UInt32? {
    guard let dir = opendir("\(prefix)/fd") else { return nil }
    defer { closedir(dir) }
    var count: UInt32 = 0
    while let entry = readdir(dir) {
        let firstByte = withUnsafeBytes(of: entry.pointee.d_name) { $0.first ?? 0 }
        if firstByte != 0 && firstByte != UInt8(ascii: ".") {
            count += 1
        }
    }
    if isSelf && count > 0 {
        return count - 1
    }
    return count
}

private func linuxMemory(_ prefix: String) -> (footprint: UInt64, peak: UInt64, resident: UInt64)? {
    guard let statm = try? String(contentsOfFile: "\(prefix)/statm", encoding: .utf8) else {
        return nil
    }
    let parts = statm.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
    guard parts.count >= 2, let residentPages = UInt64(parts[1]) else {
        return nil
    }
    let pageSize = linuxPageSize()
    let resident = residentPages * pageSize
    var vmHwmBytes: UInt64 = resident
    if let status = try? String(contentsOfFile: "\(prefix)/status", encoding: .utf8) {
        for line in status.split(separator: "\n") where line.hasPrefix("VmHWM:") {
            let tokens = line.dropFirst(6).split(whereSeparator: { $0 == " " || $0 == "\t" })
            if let kb = tokens.first, let kbVal = UInt64(kb) {
                vmHwmBytes = kbVal * 1024
            }
            break
        }
    }
    return (resident, max(vmHwmBytes, resident), resident)
}

private func parseLinuxStat(_ text: String) -> (name: String, cpuTicks: UInt64)? {
    guard let openParen = text.firstIndex(of: "("),
          let closeParen = text.lastIndex(of: ")"),
          openParen < closeParen
    else {
        return nil
    }
    let name = String(text[text.index(after: openParen)..<closeParen])
    let rest = text[text.index(after: closeParen)...]
    let fields = rest.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
    // After `(comm)`: field[0] = state (3), field[11] = utime (14), field[12] = stime (15)
    guard fields.count > 12,
          let utime = UInt64(fields[11]),
          let stime = UInt64(fields[12])
    else {
        return nil
    }
    return (name, utime + stime)
}

public func snapshotOf(_ pid: Int32) -> Snapshot? {
    let isSelf = (pid == Int32(getpid()))
    let prefix = isSelf ? "/proc/self" : "/proc/\(pid)"
    guard let mem = linuxMemory(prefix),
          let procStatText = try? String(contentsOfFile: "\(prefix)/stat", encoding: .utf8),
          let procStat = parseLinuxStat(procStatText)
    else {
        return nil
    }
    let hz = linuxClockTicks()
    let totalCpu = Double(procStat.cpuTicks) / hz

    var threads: [Thread] = []
    if let taskDir = opendir("\(prefix)/task") {
        defer { closedir(taskDir) }
        while let entry = readdir(taskDir) {
            let tidStr: String = withUnsafePointer(to: entry.pointee.d_name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: entry.pointee.d_name)) {
                    String(cString: $0)
                }
            }
            guard let tid = UInt64(tidStr),
                  let tStatText = try? String(contentsOfFile: "\(prefix)/task/\(tidStr)/stat", encoding: .utf8),
                  let tStat = parseLinuxStat(tStatText)
            else {
                continue
            }
            threads.append(Thread(id: tid, name: tStat.name, cpuS: Double(tStat.cpuTicks) / hz))
        }
    }

    return Snapshot(
        pid: pid,
        footprint: mem.footprint,
        footprintPeak: mem.peak,
        resident: mem.resident,
        cpuS: totalCpu,
        fds: linuxOpenFds(prefix, isSelf: isSelf) ?? 0,
        threads: threads,
        heap: nil,
        gauges: []
    )
}

public func usage() -> Usage {
    let prefix = "/proc/self"
    var out = Usage(fds: linuxOpenFds(prefix, isSelf: true))
    if let mem = linuxMemory(prefix) {
        out.footprint = mem.footprint
        out.footprintPeak = mem.peak
        out.resident = mem.resident
    }
    return out
}

#elseif os(Windows)
// PORT NOTE: On Windows, `snapshotOf` and `usage` query Win32 `K32GetProcessMemoryInfo`,
// `GetProcessTimes`, and `GetProcessHandleCount` for the current process.
private struct WinProcessMemoryCounters {
    var cb: DWORD = DWORD(MemoryLayout<WinProcessMemoryCounters>.size)
    var PageFaultCount: DWORD = 0
    var PeakWorkingSetSize: UInt = 0
    var WorkingSetSize: UInt = 0
    var QuotaPeakPagedPoolUsage: UInt = 0
    var QuotaPagedPoolUsage: UInt = 0
    var QuotaPeakNonPagedPoolUsage: UInt = 0
    var QuotaNonPagedPoolUsage: UInt = 0
    var PagefileUsage: UInt = 0
    var PeakPagefileUsage: UInt = 0
}

@_silgen_name("K32GetProcessMemoryInfo")
private func winGetProcessMemoryInfo(
    _ process: HANDLE?,
    _ ppsmemCounters: UnsafeMutablePointer<WinProcessMemoryCounters>,
    _ cb: DWORD
) -> WINBOOL

private func filetimeToSeconds(_ ft: FILETIME) -> Double {
    let ticks = (UInt64(ft.dwHighDateTime) << 32) | UInt64(ft.dwLowDateTime)
    return Double(ticks) * 1e-7
}

public func snapshotOf(_ pid: Int32) -> Snapshot? {
    guard pid == Int32(bitPattern: GetCurrentProcessId()) else {
        return nil
    }
    let hProc = GetCurrentProcess()
    var pmc = WinProcessMemoryCounters()
    guard winGetProcessMemoryInfo(hProc, &pmc, pmc.cb) != 0 else {
        return nil
    }
    var creation = FILETIME()
    var exit = FILETIME()
    var kernel = FILETIME()
    var user = FILETIME()
    var cpuS = 0.0
    if GetProcessTimes(hProc, &creation, &exit, &kernel, &user) != 0 {
        cpuS = filetimeToSeconds(kernel) + filetimeToSeconds(user)
    }
    var handleCount: DWORD = 0
    let hasHandles = GetProcessHandleCount(hProc, &handleCount) != 0
    let footprint = pmc.PagefileUsage > 0 ? UInt64(pmc.PagefileUsage) : UInt64(pmc.WorkingSetSize)
    let peak = max(UInt64(pmc.PeakPagefileUsage), footprint)
    return Snapshot(
        pid: pid,
        footprint: footprint,
        footprintPeak: peak,
        resident: UInt64(pmc.WorkingSetSize),
        cpuS: cpuS,
        fds: hasHandles ? UInt32(handleCount) : 0,
        threads: [Thread(id: UInt64(GetCurrentThreadId()), name: "main", cpuS: cpuS)],
        heap: nil,
        gauges: []
    )
}

public func usage() -> Usage {
    let hProc = GetCurrentProcess()
    var pmc = WinProcessMemoryCounters()
    var out = Usage()
    if winGetProcessMemoryInfo(hProc, &pmc, pmc.cb) != 0 {
        let footprint = pmc.PagefileUsage > 0 ? UInt64(pmc.PagefileUsage) : UInt64(pmc.WorkingSetSize)
        out.footprint = footprint
        out.footprintPeak = max(UInt64(pmc.PeakPagefileUsage), footprint)
        out.resident = UInt64(pmc.WorkingSetSize)
    }
    var handleCount: DWORD = 0
    if GetProcessHandleCount(hProc, &handleCount) != 0 {
        out.fds = UInt32(handleCount)
    }
    return out
}

#else
// PORT NOTE: Deterministic zero-overhead fallback on WASI (`wasm32-unknown-wasip1`) and other platforms.
public func snapshotOf(_ pid: Int32) -> Snapshot? {
    _ = pid
    return nil
}

public func usage() -> Usage {
    Usage()
}
#endif

// MARK: - Watcher & Configuration

/// Periodic sampling and warning thresholds for ``Watcher`` and ``watch(_:)``.
public struct Config: Equatable, Sendable {
    /// How often to sample.
    public var every: Duration
    /// A status line this often even when all is well; `nil`: only warnings.
    public var report: Duration?
    /// Warn when the footprint passes this, then again at each doubling.
    public var warnFootprint: UInt64
    /// Warn when the footprint grew by this much over `growthWindow`, every sample of it up.
    public var warnGrowth: UInt64
    public var growthWindow: Duration
    /// Warn when the process averaged more than this many cores over `cpuWindow`.
    public var warnCpuCores: Double
    public var cpuWindow: Duration
    /// Prefix for log lines.
    public var name: String

    public init(
        every: Duration,
        report: Duration?,
        warnFootprint: UInt64,
        warnGrowth: UInt64,
        growthWindow: Duration,
        warnCpuCores: Double,
        cpuWindow: Duration,
        name: String
    ) {
        self.every = every
        self.report = report
        self.warnFootprint = warnFootprint
        self.warnGrowth = warnGrowth
        self.growthWindow = growthWindow
        self.warnCpuCores = warnCpuCores
        self.cpuWindow = cpuWindow
        self.name = name
    }

    /// Quiet in a release build: one line an hour, and warnings.
    public static func release(_ name: String) -> Config {
        Config(
            every: .seconds(10),
            report: .seconds(3600),
            warnFootprint: 1 << 30,
            warnGrowth: 256 << 20,
            growthWindow: .seconds(60),
            warnCpuCores: 0.8,
            cpuWindow: .seconds(60),
            name: name
        )
    }

    /// Chatty in a dev build: a line a minute, lower thresholds.
    public static func dev(_ name: String) -> Config {
        Config(
            every: .seconds(2),
            report: .seconds(60),
            warnFootprint: 512 << 20,
            warnGrowth: 64 << 20,
            growthWindow: .seconds(20),
            warnCpuCores: 0.5,
            cpuWindow: .seconds(20),
            name: name
        )
    }
}

public typealias WatchConfig = Config

/// What a ``Watcher`` noticed in a sample.
public enum Kind: Equatable, Hashable, Sendable {
    /// The footprint passed `warnFootprint`, or doubled since the last such warning.
    case footprint
    /// The footprint rose every sample for `growthWindow`, by at least `warnGrowth`.
    case growth
    /// The process averaged at least `warnCpuCores` over `cpuWindow`.
    case cpu
    /// The periodic status line.
    case report
}

/// Warning or status report emitted by ``Watcher``.
public struct Event: Equatable, CustomStringConvertible, Sendable {
    public var kind: Kind
    public var line: String

    public init(kind: Kind, line: String) {
        self.kind = kind
        self.line = line
    }

    public func isWarning() -> Bool {
        kind != .report
    }

    public var description: String {
        line
    }
}

// PORT NOTE: Synchronized via internal NSLock protecting the watcher's latest Snapshot sample.
private final class LatestStore: @unchecked Sendable {
    static let shared = LatestStore()

    private let lock = NSLock()
    private var snapshot: Snapshot?

    func get() -> Snapshot? {
        lock.lock()
        let v = snapshot
        lock.unlock()
        return v
    }

    func set(_ s: Snapshot?) {
        lock.lock()
        snapshot = s
        lock.unlock()
    }
}

/// The watcher's last sample, if it runs.
public func latest() -> Snapshot? {
    LatestStore.shared.get()
}

/// Samples on a `procwatch` thread for the life of the process, logging to stderr.
public func watch(_ config: Config) {
    watchWith(config) { _, _ in }
}

/// ``watch(_:)``, and calls `onWarning` on the watcher thread for every warning (not the
/// periodic report): to drop a cache, write a capture, or post the numbers somewhere.
public func watchWith(_ config: Config, _ onWarning: @escaping @Sendable (Event, Snapshot) -> Void) {
    #if !os(WASI)
    guard snapshot() != nil else {
        return
    }
    let thread = Foundation.Thread {
        var watcher = Watcher(config)
        let sleepSecs = max(0.001, durationSeconds(watcher.config.every))
        while true {
            if let s = snapshot() {
                for event in watcher.observe(Instant.now, s) {
                    FileHandle.standardError.write(Data("\(event.line)\n".utf8))
                    if event.isWarning() {
                        onWarning(event, s)
                    }
                }
                LatestStore.shared.set(s)
            }
            Foundation.Thread.sleep(forTimeInterval: sleepSecs)
        }
    }
    thread.name = "procwatch"
    thread.start()
    #else
    _ = config
    _ = onWarning
    #endif
}

/// The judging half of ``watch(_:)``, fed samples so tests can drive it.
public struct Watcher: Sendable {
    public var config: Config
    private var history: [(Instant, Snapshot)] = []
    private var warnedFootprint: UInt64 = 0
    private var warnedGrowth: Instant?
    private var warnedCpu: Instant?
    private var reported: Instant?

    public init(_ config: Config) {
        self.config = config
    }

    public static func new(_ config: Config) -> Watcher {
        Watcher(config)
    }

    /// Takes a sample; returns what to log.
    public mutating func observe(_ now: Instant, _ s: Snapshot) -> [Event] {
        let c = config
        var out: [Event] = []

        // Keep one sample at or past the longest window, so a window always has a start even
        // when sleeps run a little long.
        let keep = max(c.growthWindow, c.cpuWindow)
        if let edge = history.lastIndex(where: { durationSince($0.0, now) >= keep }) {
            history.removeSubrange(0..<edge)
        }
        history.append((now, s))

        func since(_ window: Duration) -> ArraySlice<(Instant, Snapshot)> {
            let start = history.lastIndex(where: { durationSince($0.0, now) >= window }) ?? 0
            return history[start...]
        }

        func quiet(_ warned: Instant?, _ window: Duration) -> Bool {
            guard let at = warned else { return true }
            return durationSince(at, now) >= window
        }

        let doubled = warnedFootprint.multipliedReportingOverflow(by: 2)
        let footprintNext = doubled.overflow ? UInt64.max : doubled.partialValue
        if s.footprint >= c.warnFootprint && s.footprint >= footprintNext {
            warnedFootprint = s.footprint
            out.append(
                Event(
                    kind: .footprint,
                    line: "\(c.name): warning: footprint \(mb(s.footprint)) (peak \(mb(s.footprintPeak)))\(memoryNote(s))"
                )
            )
        }

        let window = since(c.growthWindow)
        if let (then, first) = window.first,
           durationSeconds(durationSince(then, now)) >= durationSeconds(c.growthWindow) * 0.9
        {
            let rising = zip(window, window.dropFirst()).allSatisfy { $1.1.footprint >= $0.1.footprint }
            let grew = s.footprint >= first.footprint ? (s.footprint - first.footprint) : 0
            if rising && grew >= c.warnGrowth && quiet(warnedGrowth, c.growthWindow) {
                warnedGrowth = now
                let secsStr = formatFixed(durationSeconds(c.growthWindow), decimals: 0)
                out.append(
                    Event(
                        kind: .growth,
                        line: "\(c.name): warning: footprint grew \(mb(grew)) in \(secsStr)s to \(mb(s.footprint))\(memoryNote(s))"
                    )
                )
            }
        }

        if let (then, old) = since(c.cpuWindow).first {
            let span = durationSeconds(durationSince(then, now))
            let cores = (s.cpuS - old.cpuS) / max(span, 1e-9)
            if span >= durationSeconds(c.cpuWindow) * 0.9 && cores >= c.warnCpuCores && quiet(warnedCpu, c.cpuWindow) {
                warnedCpu = now
                let pctStr = formatFixed(cores * 100.0, decimals: 0)
                let spanStr = formatFixed(span, decimals: 0)
                out.append(
                    Event(
                        kind: .cpu,
                        line: "\(c.name): warning: \(pctStr)% CPU over \(spanStr)s: \(busiest(old, s, span))"
                    )
                )
            }
        }

        if let every = c.report, quiet(reported, every) {
            reported = now
            let cpuStr = formatFixed(s.cpuS, decimals: 1)
            let exitedStr = formatFixed(s.exitedCpuS(), decimals: 1)
            out.append(
                Event(
                    kind: .report,
                    line: "\(c.name): footprint \(mb(s.footprint)) (peak \(mb(s.footprintPeak))), resident \(mb(s.resident)), CPU \(cpuStr)s (\(exitedStr)s in exited threads), \(s.threads.count) threads, \(s.fds) fds\(memoryNote(s))"
                )
            )
        }

        return out
    }
}

/// The threads that used the most CPU between two samples, as percentages of one core.
internal func busiest(_ old: Snapshot, _ new: Snapshot, _ span: Double) -> String {
    var used: [(String, Double)] = new.threads.map { t in
        let before = old.threads.first(where: { $0.id == t.id })?.cpuS ?? 0.0
        let name = t.name.isEmpty ? "unnamed" : t.name
        return (name, max(0.0, t.cpuS - before))
    }
    let liveUsed = used.reduce(0.0) { $0 + $1.1 }
    let exited = (new.cpuS - old.cpuS) - liveUsed
    if exited > 0.01 * span {
        used.append(("exited threads", exited))
    }
    used.sort { a, b in
        if a.1.isNaN && b.1.isNaN { return false }
        if a.1.isNaN { return false }
        if b.1.isNaN { return true }
        return b.1 < a.1
    }
    let denom = max(span, 1e-9)
    return used
        .prefix(4)
        .filter { $0.1 > 0.0 }
        .map { (n, s) in "\(n) \(formatFixed(100.0 * s / denom, decimals: 0))%" }
        .joined(separator: ", ")
}

/// Where the footprint sits: the counted heap, the biggest gauges, and what nothing claims.
internal func memoryNote(_ s: Snapshot) -> String {
    var note: String
    if let h = s.heap {
        if h.bigBlocks > 0 {
            let liveBytes = UInt64(max(0, h.live))
            let bigLiveBytes = UInt64(max(0, h.bigLive))
            let largestBytes = UInt64(max(0, h.largest))
            note = "; heap \(mb(liveBytes)) live, \(mb(bigLiveBytes)) in \(h.bigBlocks) big blocks, largest request \(mb(largestBytes))"
        } else {
            let liveBytes = UInt64(max(0, h.live))
            let peakBytes = UInt64(max(0, h.peak))
            note = "; heap \(mb(liveBytes)) live (peak \(mb(peakBytes)))"
        }
    } else {
        note = ""
    }
    let top = s.gauges
        .filter { $0.1 > 0 }
        .prefix(3)
        .map { (n, b) in "\(n) \(mb(UInt64(b)))" }
    if !top.isEmpty {
        note += "; \(top.joined(separator: ", "))"
    }
    if let bytes = s.unaccounted() {
        note += "; unaccounted \(mb(UInt64(max(0, bytes))))"
    }
    return note
}

/// Formats a byte count into MB / GB matching upstream `procwatch::mb`.
public func mb(_ bytes: UInt64) -> String {
    let oneGb = UInt64(1) << 30
    let tenGb = UInt64(10) << 30
    let oneMb = UInt64(1) << 20
    if bytes >= tenGb {
        return "\(formatFixed(Double(bytes) / Double(oneGb), decimals: 0)) GB"
    } else if bytes >= oneGb {
        return "\(formatFixed(Double(bytes) / Double(oneGb), decimals: 1)) GB"
    } else {
        return "\(formatFixed(Double(bytes) / Double(oneMb), decimals: 0)) MB"
    }
}

// MARK: - Loopback HTTP JSON Endpoint

/// IPv4 socket address for ``serve(_:)``.
public struct SocketAddr: Equatable, Hashable, CustomStringConvertible, Sendable {
    public var ip: String
    public var port: UInt16

    public init(ip: String = "127.0.0.1", port: UInt16) {
        self.ip = ip
        self.port = port
    }

    public init?(_ string: String) {
        guard let colon = string.lastIndex(of: ":"),
              let parsedPort = UInt16(string[string.index(after: colon)...])
        else {
            return nil
        }
        self.ip = String(string[..<colon])
        self.port = parsedPort
    }

    public var description: String {
        "\(ip):\(port)"
    }
}

public enum ProcwatchError: Error, CustomStringConvertible, Sendable {
    case invalidAddress(String)
    case ioError(Int32, String)
    case unsupportedPlatform(String)

    public var description: String {
        switch self {
        case .invalidAddress(let addr):
            return "invalid socket address: \(addr)"
        case .ioError(let code, let op):
            return "\(op) failed with errno \(code)"
        case .unsupportedPlatform(let msg):
            return msg
        }
    }
}

/// Answers every request on `addr` (keep it loopback) with a fresh ``snapshot()`` as JSON.
public func serve(_ addr: SocketAddr) throws -> SocketAddr {
    #if os(WASI) || os(Windows)
    // PORT NOTE: Loopback TCP listener requires POSIX sockets + OS threads; guarded out on WASI and unlinked WinSock.
    _ = addr
    throw ProcwatchError.unsupportedPlatform("procwatch.serve is unavailable on this platform")
    #else
    #if os(Linux)
    let sockStream = Int32(SOCK_STREAM.rawValue)
    #else
    let sockStream = SOCK_STREAM
    #endif
    let listenerFd = socket(AF_INET, sockStream, 0)
    guard listenerFd >= 0 else {
        throw ProcwatchError.ioError(errno, "socket")
    }

    var reuse: Int32 = 1
    _ = setsockopt(listenerFd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

    var sin = sockaddr_in()
    #if canImport(Darwin)
    sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    #endif
    sin.sin_family = sa_family_t(AF_INET)
    sin.sin_port = addr.port.bigEndian
    guard inet_pton(AF_INET, addr.ip, &sin.sin_addr) == 1 else {
        close(listenerFd)
        throw ProcwatchError.invalidAddress(addr.ip)
    }

    let bindRc = withUnsafePointer(to: &sin) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
            bind(listenerFd, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindRc == 0 else {
        let err = errno
        close(listenerFd)
        throw ProcwatchError.ioError(err, "bind")
    }

    guard listen(listenerFd, 16) == 0 else {
        let err = errno
        close(listenerFd)
        throw ProcwatchError.ioError(err, "listen")
    }

    var boundSin = sockaddr_in()
    var boundLen = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &boundSin) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
            getsockname(listenerFd, saPtr, &boundLen)
        }
    }
    var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
    let boundIp: String = ipBuf.withUnsafeMutableBufferPointer { buf in
        var inAddr = boundSin.sin_addr
        if let base = buf.baseAddress,
           inet_ntop(AF_INET, &inAddr, base, socklen_t(buf.count)) != nil
        {
            return String(cString: base)
        }
        return addr.ip
    }
    let boundAddr = SocketAddr(ip: boundIp, port: UInt16(bigEndian: boundSin.sin_port))

    let thread = Foundation.Thread {
        var reqBuf = [UInt8](repeating: 0, count: 1024)
        while true {
            var peerSin = sockaddr_in()
            var peerLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let clientFd = withUnsafeMutablePointer(to: &peerSin) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                    accept(listenerFd, saPtr, &peerLen)
                }
            }
            if clientFd < 0 {
                continue
            }
            let hostOrderIp = UInt32(bigEndian: peerSin.sin_addr.s_addr)
            let isLoopback = (hostOrderIp >> 24) == 127
            if !isLoopback {
                close(clientFd)
                continue
            }
            var pfd = pollfd(fd: clientFd, events: Int16(POLLIN), revents: 0)
            if poll(&pfd, 1, 1000) > 0 {
                reqBuf.withUnsafeMutableBytes { rawBuf in
                    if let base = rawBuf.baseAddress {
                        _ = read(clientFd, base, rawBuf.count)
                    }
                }
            }
            let body = snapshot()?.toJson() ?? "null"
            let response = "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: \(body.utf8.count)\r\nconnection: close\r\n\r\n\(body)"
            let utf8Bytes = Array(response.utf8)
            utf8Bytes.withUnsafeBytes { bytes in
                if let base = bytes.baseAddress {
                    _ = write(clientFd, base, bytes.count)
                }
            }
            close(clientFd)
        }
    }
    thread.name = "procwatch-http"
    thread.start()
    return boundAddr
    #endif
}
