import CoreWLAN
import Darwin
import Foundation
import SystemConfiguration

/// The primary connection: which interface carries the default route, its addresses, router, DNS and,
/// on Wi-Fi, the radio details. Read from the SystemConfiguration dynamic store, which needs no privileges.
final class ConnectionMonitor {
    private let store = SCDynamicStoreCreate(nil, "MacStatus" as CFString, nil, nil)
    /// BSD name -> (SystemConfiguration interface type, display name). Rebuilt when an unknown adapter shows up.
    private var adapters: [String: (type: String, name: String)] = [:]

    func sample() -> ConnectionInfo {
        var info = ConnectionInfo()
        let global = value("State:/Network/Global/IPv4") ?? value("State:/Network/Global/IPv6")
        guard let interface = global?["PrimaryInterface"] as? String else { return info }

        info.interface = interface
        info.router = global?["Router"] as? String
        info.dns = value("State:/Network/Global/DNS")?["ServerAddresses"] as? [String] ?? []

        if let ipv4 = value("State:/Network/Interface/\(interface)/IPv4") {
            info.localIPv4 = (ipv4["Addresses"] as? [String])?.first
            info.prefixLength = ((ipv4["SubnetMasks"] as? [String])?.first).flatMap(Self.prefixLength(ofMask:))
        }
        if let ipv6 = value("State:/Network/Interface/\(interface)/IPv6"),
           let addresses = ipv6["Addresses"] as? [String] {
            info.localIPv6 = addresses.first(where: Self.isGlobalIPv6)
        }
        info.macAddress = Self.macAddress(of: interface)

        let adapter = adapter(named: interface)
        info.adapterName = adapter?.name
        if Self.isTunnel(interface) {
            info.kind = .vpn
            info.adapterName = "VPN"
        } else if adapter?.type == (kSCNetworkInterfaceTypeIEEE80211 as String) {
            info.kind = .wifi
            info.wifi = Self.wifi(named: interface)
        } else if adapter?.type == (kSCNetworkInterfaceTypeEthernet as String) {
            info.kind = .ethernet
            info.linkSpeed = interfaceCounters()[interface].map(\.baudRate).flatMap { $0 > 0 ? $0 : nil }
        } else {
            info.kind = .other
        }
        return info
    }

    // MARK: Helpers

    private func value(_ key: String) -> [String: Any]? {
        guard let store else { return nil }
        return SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any]
    }

    private func adapter(named bsdName: String) -> (type: String, name: String)? {
        if let known = adapters[bsdName] { return known }
        var all: [String: (type: String, name: String)] = [:]
        for interface in SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? [] {
            guard let name = SCNetworkInterfaceGetBSDName(interface) as String? else { continue }
            all[name] = (SCNetworkInterfaceGetInterfaceType(interface) as String? ?? "",
                         SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? ?? name)
        }
        adapters = all
        return all[bsdName]
    }

    private static func isTunnel(_ name: String) -> Bool {
        ["utun", "ipsec", "ppp", "tun", "tap", "wg"].contains { name.hasPrefix($0) }
    }

    /// Global unicast only: link-local (fe80::/10) and unique-local (fc00::/7) addresses aren't reachable from outside.
    private static func isGlobalIPv6(_ address: String) -> Bool {
        let lower = address.lowercased()
        return !(lower.hasPrefix("fe8") || lower.hasPrefix("fe9") || lower.hasPrefix("fea") || lower.hasPrefix("feb")
            || lower.hasPrefix("fc") || lower.hasPrefix("fd") || lower == "::1")
    }

    private static func prefixLength(ofMask mask: String) -> Int? {
        var address = in_addr()
        guard inet_pton(AF_INET, mask, &address) == 1 else { return nil }
        return UInt32(bigEndian: address.s_addr).nonzeroBitCount
    }

    private static func macAddress(of interface: String) -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }

        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  String(cString: entry.pointee.ifa_name) == interface else { continue }
            return address.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { link -> String? in
                let length = Int(link.pointee.sdl_alen)
                guard length == 6, let dataOffset = MemoryLayout<sockaddr_dl>.offset(of: \.sdl_data) else { return nil }
                // The address follows the interface name inside `sdl_data`, which can run past the declared array.
                let bytes = UnsafeRawPointer(link) + dataOffset + Int(link.pointee.sdl_nlen)
                return (0..<length).map { String(format: "%02x", bytes.load(fromByteOffset: $0, as: UInt8.self)) }
                    .joined(separator: ":")
            }
        }
        return nil
    }

    private static func wifi(named name: String) -> WiFiInfo? {
        guard let radio = CWWiFiClient.shared().interface(withName: name), radio.powerOn() else { return nil }
        var info = WiFiInfo()
        info.ssid = radio.ssid()
        info.rssi = radio.rssiValue()
        info.noise = radio.noiseMeasurement()
        info.transmitRate = radio.transmitRate()
        if let channel = radio.wlanChannel() {
            info.channel = channel.channelNumber
            switch channel.channelBand {
            case .band2GHz: info.band = "2.4 GHz"
            case .band5GHz: info.band = "5 GHz"
            case .band6GHz: info.band = "6 GHz"
            default: info.band = nil
            }
        }
        return info
    }
}
