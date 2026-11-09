import Darwin
import Foundation

final class MemoryMonitor {
    private let total = ProcessInfo.processInfo.physicalMemory

    /// Mirrors Activity Monitor: used = app + wired + compressed; cached files are reclaimable.
    func sample() -> MemoryStats {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var memory = MemoryStats(total: total)
        guard result == KERN_SUCCESS else { return memory }

        let page = UInt64(getpagesize())
        let purgeable = UInt64(stats.purgeable_count)
        memory.app = (UInt64(stats.internal_page_count) &- purgeable) * page
        memory.wired = UInt64(stats.wire_count) * page
        memory.compressed = UInt64(stats.compressor_page_count) * page
        memory.cached = (UInt64(stats.external_page_count) + purgeable) * page
        memory.swapUsed = swapUsed()
        memory.pressure = pressure()
        return memory
    }

    private func swapUsed() -> UInt64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return usage.xsu_used
    }

    private func pressure() -> MemoryStats.Pressure {
        switch sysctlInt("kern.memorystatus_vm_pressure_level") ?? 1 {
        case 4...: return .critical
        case 2...: return .warning
        default: return .normal
        }
    }
}
