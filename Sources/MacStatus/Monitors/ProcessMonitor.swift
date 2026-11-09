import Darwin
import Foundation

/// Top processes by CPU and memory, grouped by app bundle (so Chrome's 30 helpers count as one "Google Chrome").
///
/// Uses libproc, which needs no privileges but can only see processes owned by the current user;
/// root/system daemons (WindowServer, kernel_task, ...) are not readable without elevation.
final class ProcessMonitor {
    struct Result {
        var cpu: [ProcessUsage] = []
        var memory: [ProcessUsage] = []
    }

    private struct Previous { var cpuNanos: UInt64; var start: UInt64 }

    private var previous: [pid_t: Previous] = [:]
    private var previousTime: UInt64 = 0
    private var names: [pid_t: (start: UInt64, name: String)] = [:]
    private let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    func sample(limit: Int = 5) -> Result {
        let now = monotonicNanos()
        let elapsed = previousTime == 0 ? 0 : Double(now &- previousTime)

        var cpuByName: [String: Double] = [:]
        var memoryByName: [String: UInt64] = [:]
        var current: [pid_t: Previous] = [:]

        for pid in allPIDs() where pid > 0 {
            var usage = rusage_info_v4()
            let status = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            guard status == 0 else { continue }

            let cpuNanos = (usage.ri_user_time &+ usage.ri_system_time) &* UInt64(timebase.numer) / UInt64(timebase.denom)
            let start = usage.ri_proc_start_abstime
            current[pid] = Previous(cpuNanos: cpuNanos, start: start)

            let name = displayName(pid: pid, start: start)
            memoryByName[name, default: 0] += usage.ri_phys_footprint

            // pid reuse guard: only diff against the same process instance.
            if elapsed > 0, let old = previous[pid], old.start == start, cpuNanos >= old.cpuNanos {
                cpuByName[name, default: 0] += Double(cpuNanos - old.cpuNanos) / elapsed * 100
            }
        }

        previous = current
        previousTime = now
        names = names.filter { current[$0.key] != nil }

        let topCPU = cpuByName
            .filter { $0.value >= 0.05 }
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { ProcessUsage(name: $0.key, cpu: $0.value, memory: memoryByName[$0.key] ?? 0) }
        let topMemory = memoryByName
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { ProcessUsage(name: $0.key, cpu: cpuByName[$0.key] ?? 0, memory: $0.value) }
        return Result(cpu: Array(topCPU), memory: Array(topMemory))
    }

    // MARK: Helpers

    private func allPIDs() -> [pid_t] {
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytes > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(bytes) / MemoryLayout<pid_t>.size + 32)
        let written = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return Array(pids.prefix(Int(written) / MemoryLayout<pid_t>.size))
    }

    /// "/Applications/Google Chrome.app/Contents/.../Helper (GPU)" -> "Google Chrome"
    /// "~/.local/share/claude/versions/2.1.319"                     -> "claude"
    static func appName(fromPath path: String) -> String {
        // Outermost bundle wins, so nested helper apps roll up into their parent app.
        if let marker = path.range(of: ".app/"),
           let app = path[..<marker.lowerBound].split(separator: "/").last {
            return String(app)
        }
        let components = path.split(separator: "/").map(String.init)
        guard var name = components.last else { return "" }
        // Binaries named after their version carry no meaning; use the directory that owns them.
        if name.allSatisfy({ $0.isNumber || $0 == "." }), components.count >= 2 {
            let parent = components[components.count - 2]
            name = (parent == "versions" && components.count >= 3) ? components[components.count - 3] : parent
        }
        // Reverse-DNS service names are long; the vendor prefix adds nothing in a 160pt column.
        if name.hasPrefix("com.apple.") { name.removeFirst("com.apple.".count) }
        return name
    }

    private func displayName(pid: pid_t, start: UInt64) -> String {
        if let cached = names[pid], cached.start == start { return cached.name }

        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        var name: String
        if length > 0 {
            name = Self.appName(fromPath: String(cString: buffer))
        } else {
            var short = [CChar](repeating: 0, count: 64)
            proc_name(pid, &short, UInt32(short.count))
            name = String(cString: short)
        }
        if name.isEmpty { name = "pid \(pid)" }
        names[pid] = (start, name)
        return name
    }
}
