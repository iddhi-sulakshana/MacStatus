import Foundation

final class NetworkMonitor {
    private var previous: [String: InterfaceCounters] = [:]
    private var previousTime: UInt64 = 0

    /// Throughput across physical interfaces (`en*`: Wi-Fi, Ethernet, Thunderbolt/USB NICs).
    /// Tunnels (`utun*`) are skipped so VPN traffic isn't counted twice.
    func sample() -> NetworkStats {
        let current = interfaceCounters().filter { $0.key.hasPrefix("en") }
        let now = monotonicNanos()
        defer { previous = current; previousTime = now }

        var stats = NetworkStats()
        for counters in current.values {
            stats.totalReceived += counters.received
            stats.totalSent += counters.sent
        }
        guard previousTime != 0, now > previousTime else { return stats }

        let seconds = Double(now - previousTime) / 1_000_000_000
        var received: UInt64 = 0, sent: UInt64 = 0
        for (name, counters) in current {
            // A counter that went backwards means the interface was reset (unplugged, reattached): skip it this round.
            guard let old = previous[name], counters.received >= old.received, counters.sent >= old.sent else { continue }
            received += counters.received - old.received
            sent += counters.sent - old.sent
        }
        stats.downBytesPerSecond = Double(received) / seconds
        stats.upBytesPerSecond = Double(sent) / seconds
        return stats
    }
}
