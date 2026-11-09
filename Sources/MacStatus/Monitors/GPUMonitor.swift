import Foundation
import IOKit

final class GPUMonitor {
    struct Usage {
        var utilization: Double
        var memoryUsed: UInt64
        var coreCount: Int
        var name: String
    }

    func sample() -> Usage? {
        var best: Usage?
        forEachService(named: "IOAccelerator") { entry in
            guard let stats = ioProperty(entry, "PerformanceStatistics") as? [String: Any] else { return }
            let utilization = Double(asInt(stats["Device Utilization %"]) ?? 0)
            let usage = Usage(
                utilization: utilization,
                memoryUsed: asUInt64(stats["In use system memory"]) ?? 0,
                coreCount: asInt(ioProperty(entry, "gpu-core-count")) ?? 0,
                name: asString(ioProperty(entry, "model")) ?? "GPU"
            )
            if best == nil || utilization > best!.utilization { best = usage }
        }
        return best
    }
}
