import Darwin
import Foundation

final class NetworkMonitor {
    private struct Counters { var received: UInt32; var sent: UInt32 }

    private var previous: [String: Counters] = [:]
    private var previousTime: UInt64 = 0

    /// Throughput across physical interfaces (`en*`: Wi-Fi, Ethernet, Thunderbolt/USB NICs).
    /// Tunnels (`utun*`) are skipped so VPN traffic isn't counted twice.
    func sample() -> NetworkStats {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return NetworkStats() }
        defer { freeifaddrs(list) }

        var current: [String: Counters] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = cursor {
            defer { cursor = interface.pointee.ifa_next }
            guard let address = interface.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  let data = interface.pointee.ifa_data,
                  interface.pointee.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
            let name = String(cString: interface.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }
            let counters = data.assumingMemoryBound(to: if_data.self).pointee
            current[name] = Counters(received: counters.ifi_ibytes, sent: counters.ifi_obytes)
        }

        let now = monotonicNanos()
        defer { previous = current; previousTime = now }
        guard previousTime != 0, now > previousTime else { return NetworkStats() }

        let seconds = Double(now - previousTime) / 1_000_000_000
        var received = 0.0, sent = 0.0
        for (name, counters) in current {
            guard let old = previous[name] else { continue }
            // `if_data` counters are 32-bit and wrap; wrapping subtraction handles that.
            received += Double(counters.received &- old.received)
            sent += Double(counters.sent &- old.sent)
        }
        return NetworkStats(upBytesPerSecond: sent / seconds, downBytesPerSecond: received / seconds)
    }
}
