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
    /// Bytes moved by the physical interfaces since they came up (normally since boot).
    var totalSent: UInt64 = 0
    var totalReceived: UInt64 = 0
}

enum ConnectionKind: Sendable { case wifi, ethernet, vpn, other, offline }

struct WiFiInfo: Equatable, Sendable {
    /// nil until MacStatus is allowed to use Location Services: macOS hides the network name otherwise.
    var ssid: String?
    var rssi = 0               // dBm
    var noise = 0              // dBm
    var transmitRate = 0.0     // Mbps
    var channel: Int?
    var band: String?          // "2.4 GHz", "5 GHz", "6 GHz"
}

struct PublicIPInfo: Equatable, Sendable {
    var ipv4: String?
    var ipv6: String?
    var isp: String?
    var asn: String?
    var location: String?      // "City, Country"
}

enum PublicIPLookup: Equatable, Sendable {
    case pending               // not looked up yet, or in flight
    case found(PublicIPInfo)
    case failed
}

/// The primary connection and its addresses. Only gathered while the popup is open.
struct ConnectionInfo: Equatable, Sendable {
    var kind: ConnectionKind = .offline
    var interface: String?     // BSD name, "en0"
    var adapterName: String?   // "Wi-Fi", "Thunderbolt Ethernet"
    var localIPv4: String?
    var prefixLength: Int?     // from the subnet mask: 24 for 255.255.255.0
    var localIPv6: String?     // first global address, when the network has IPv6
    var router: String?
    var dns: [String] = []
    var macAddress: String?
    var linkSpeed: UInt64?     // bits per second, Ethernet only
    var wifi: WiFiInfo?
    var publicIP: PublicIPLookup = .pending

    /// Changes whenever the Mac moves to another network, which is when the public address is looked up again.
    var networkKey: String? {
        guard kind != .offline, let interface else { return nil }
        return [interface, localIPv4 ?? "", localIPv6 ?? "", router ?? ""].joined(separator: "|")
    }
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
    var connection = ConnectionInfo()
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
    var upload: [Double] = []      // bytes per second
    var download: [Double] = []

    mutating func record(_ snapshot: SystemSnapshot) {
        Self.append(&cpu, snapshot.cpu.total)
        Self.append(&gpu, snapshot.gpu.utilization)
        Self.append(&memory, snapshot.memory.usedFraction * 100)
        Self.append(&upload, snapshot.network.upBytesPerSecond)
        Self.append(&download, snapshot.network.downBytesPerSecond)
    }

    private static func append(_ array: inout [Double], _ value: Double) {
        array.append(value)
        if array.count > capacity { array.removeFirst(array.count - capacity) }
    }
}
