import Foundation

struct CPUStats: Equatable, Sendable {
    var total = 0.0       // percent, 0...100
    var user = 0.0
    var system = 0.0
    var idle = 100.0
    var temperature: Double?
    var chipName = "Apple Silicon"
    var logicalCores = 0
    var performanceCores = 0
    var efficiencyCores = 0
}

struct GPUStats: Equatable, Sendable {
    var utilization = 0.0 // percent, 0...100
    var temperature: Double?
    var memoryUsed: UInt64 = 0
    var coreCount = 0
    var name = "GPU"
}

struct MemoryStats: Equatable, Sendable {
    enum Pressure: Sendable { case normal, warning, critical }

    var total: UInt64 = 0
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var swapUsed: UInt64 = 0
    var pressure: Pressure = .normal

    var used: UInt64 { app + wired + compressed }
    var usedFraction: Double { total == 0 ? 0 : min(1, Double(used) / Double(total)) }
}

struct NetworkStats: Equatable, Sendable {
    var upBytesPerSecond = 0.0
    var downBytesPerSecond = 0.0
}

enum PowerState: Sendable {
    case charging       // battery is taking charge          -> green
    case discharging    // running on battery                -> red
    case pluggedIn      // on AC, battery not charging       -> blue
}

struct EnergyStats: Equatable, Sendable {
    var systemWatts: Double?
    var hasBattery = false
    var batteryPercent = 0
    var state: PowerState = .pluggedIn
    /// Signed: positive = flowing into the battery, negative = drawn from it.
    var batteryWatts = 0.0
    /// Live power coming in from the charger (0 when unplugged).
    var adapterWatts = 0.0
    var adapterRatedWatts: Int?
    var adapterName: String?
    var healthPercent: Int?
    var cycleCount: Int?
    var batteryTemperature: Double?
    var minutesRemaining: Int?
}

struct ProcessUsage: Identifiable, Equatable, Sendable {
    var id: String { name }
    var name: String
    var cpu: Double       // percent of one core (can exceed 100 for multithreaded apps)
    var memory: UInt64    // physical footprint, bytes
}

struct DiskStats: Identifiable, Equatable, Sendable {
    var id: UInt64
    var name: String
    var model: String
    var interconnect: String
    var isInternal: Bool
    var capacity: UInt64
    var used: UInt64?
    var readBytesPerSecond = 0.0
    var writeBytesPerSecond = 0.0
    var temperature: Double?
}

struct SystemSnapshot: Equatable, Sendable {
    var cpu = CPUStats()
    var gpu = GPUStats()
    var memory = MemoryStats()
    var network = NetworkStats()
    var energy = EnergyStats()
    var topCPU: [ProcessUsage] = []
    var topMemory: [ProcessUsage] = []
    var disks: [DiskStats] = []
}

/// Rolling windows behind the sparklines.
struct StatsHistory: Equatable, Sendable {
    static let capacity = 60

    var cpu: [Double] = []
    var gpu: [Double] = []
    var memory: [Double] = []

    mutating func record(_ snapshot: SystemSnapshot) {
        Self.append(&cpu, snapshot.cpu.total)
        Self.append(&gpu, snapshot.gpu.utilization)
        Self.append(&memory, snapshot.memory.usedFraction * 100)
    }

    private static func append(_ array: inout [Double], _ value: Double) {
        array.append(value)
        if array.count > capacity { array.removeFirst(array.count - capacity) }
    }
}
