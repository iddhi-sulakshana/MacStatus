import Foundation

enum Fmt {
    /// Network / disk throughput, decimal units: "0 B/s", "2 KB/s", "9.4 MB/s".
    static func speed(_ bytesPerSecond: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = max(0, bytesPerSecond)
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        if unit == 0 { return "\(Int(value)) \(units[0])" }
        return value >= 10 ? String(format: "%.0f %@", value, units[unit]) : String(format: "%.1f %@", value, units[unit])
    }

    /// Amounts of traffic, decimal: "340 MB", "12.3 GB".
    static func dataSize(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        if unit == 0 { return "\(bytes) B" }
        return value >= 100 ? String(format: "%.0f %@", value, units[unit]) : String(format: "%.1f %@", value, units[unit])
    }

    /// Link rates: "292 Mbps", "1 Gbps", "2.5 Gbps".
    static func bitRate(_ bitsPerSecond: Double) -> String {
        if bitsPerSecond >= 1_000_000_000 {
            let gbps = bitsPerSecond / 1_000_000_000
            return gbps.rounded() == gbps ? String(format: "%.0f Gbps", gbps) : String(format: "%.1f Gbps", gbps)
        }
        return String(format: "%.0f Mbps", bitsPerSecond / 1_000_000)
    }

    /// Memory sizes (binary, like Activity Monitor): "7.32 GB", "340 MB".
    static func memory(_ bytes: UInt64) -> String {
        let gib = Double(bytes) / 1_073_741_824
        if gib >= 1 { return String(format: "%.2f GB", gib) }
        let mib = Double(bytes) / 1_048_576
        if mib >= 1 { return String(format: "%.0f MB", mib) }
        return String(format: "%.0f KB", Double(bytes) / 1024)
    }

    /// Compact legend form: "7.32G".
    static func memoryShort(_ bytes: UInt64) -> String {
        let gib = Double(bytes) / 1_073_741_824
        return gib >= 1 ? String(format: "%.2fG", gib) : String(format: "%.0fM", Double(bytes) / 1_048_576)
    }

    /// Disk capacities (decimal, like Finder): "245 GB", "1 TB".
    static func capacity(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 1000 { return String(format: "%.1f TB", gb / 1000) }
        return String(format: "%.0f GB", gb)
    }

    static func percent(_ value: Double) -> String { String(format: "%.1f%%", value) }

    static func watts(_ value: Double) -> String { String(format: "%.1f W", value) }

    static func signedWatts(_ value: Double) -> String {
        let sign = value > 0.05 ? "+" : (value < -0.05 ? "−" : "")
        return sign + String(format: "%.1f W", abs(value))
    }

    /// Menu bar form: "18W", "5.9W".
    static func compactWatts(_ value: Double?) -> String {
        guard let value else { return "--W" }
        return value < 10 ? String(format: "%.1fW", value) : String(format: "%.0fW", value)
    }

    static func temperature(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f°C", value)
    }

    static func compactTemperature(_ value: Double?) -> String {
        guard let value else { return "--°" }
        return String(format: "%.0f°", value)
    }

    static func duration(minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}
