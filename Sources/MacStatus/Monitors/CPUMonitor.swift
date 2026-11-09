import Darwin
import Foundation

final class CPUMonitor {
    struct Usage {
        var total: Double
        var user: Double
        var system: Double
        var idle: Double
    }

    let chipName = sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
    let logicalCores = sysctlInt("hw.logicalcpu") ?? 0
    let performanceCores = sysctlInt("hw.perflevel0.physicalcpu") ?? 0
    let efficiencyCores = sysctlInt("hw.perflevel1.physicalcpu") ?? 0

    private var previous: [UInt32] = []

    /// Usage since the previous call. The first call only primes the counters and returns nil.
    func sample() -> Usage? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        let current = (0..<Int(infoCount)).map { UInt32(bitPattern: info[$0]) }
        defer { previous = current }
        guard previous.count == current.count else { return nil }

        let states = Int(CPU_STATE_MAX)
        var user = 0.0, system = 0.0, idle = 0.0
        for cpu in 0..<Int(cpuCount) {
            let base = cpu * states
            func delta(_ state: Int32) -> Double { Double(current[base + Int(state)] &- previous[base + Int(state)]) }
            user += delta(CPU_STATE_USER) + delta(CPU_STATE_NICE)
            system += delta(CPU_STATE_SYSTEM)
            idle += delta(CPU_STATE_IDLE)
        }
        let total = user + system + idle
        guard total > 0 else { return nil }
        return Usage(total: (user + system) / total * 100,
                     user: user / total * 100,
                     system: system / total * 100,
                     idle: idle / total * 100)
    }
}
