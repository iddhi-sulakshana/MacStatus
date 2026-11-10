import AppKit
import SwiftUI

/// Live traffic, the primary connection, and its public and local addresses. Click an address to copy it.
struct NetworkCard: View {
    let network: NetworkStats
    let connection: ConnectionInfo
    let uploadHistory: [Double]
    let downloadHistory: [Double]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    CardTitle(symbol: symbol, title: "Network", tint: Theme.network)
                    Pill(text: kindLabel, color: kindColor)
                    Spacer()
                    Text(adapterLabel).font(.system(size: 10)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }

                HStack(alignment: .top, spacing: 8) {
                    StatColumn(label: "Download", value: Fmt.speed(network.downBytesPerSecond), valueColor: Theme.download,
                               detail: "\(Fmt.dataSize(network.totalReceived)) total")
                    StatColumn(label: "Upload", value: Fmt.speed(network.upBytesPerSecond), valueColor: Theme.upload,
                               detail: "\(Fmt.dataSize(network.totalSent)) total")
                }

                ZStack {
                    Sparkline(values: downloadHistory, color: Theme.download, maximum: chartMaximum)
                    Sparkline(values: uploadHistory, color: Theme.upload, maximum: chartMaximum)
                }
                .frame(height: 30)

                if let wifi = connection.wifi {
                    Divider().overlay(Color.white.opacity(0.08))
                    WiFiRow(wifi: wifi)
                } else if connection.kind == .ethernet {
                    Divider().overlay(Color.white.opacity(0.08))
                    HStack {
                        Footer(label: "Adapter", value: connection.adapterName ?? "Ethernet")
                        Footer(label: "Link speed", value: connection.linkSpeed.map { Fmt.bitRate(Double($0)) } ?? "—")
                    }
                }

                Divider().overlay(Color.white.opacity(0.08))
                if connection.kind == .offline {
                    Text("Not connected").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                } else {
                    addresses
                }
            }
        }
    }

    // MARK: Addresses

    private var addresses: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 16) {
                AddressColumn(title: "Public", tint: Theme.network) { publicRows }
                AddressColumn(title: "Local", tint: Theme.memory) {
                    AddressRow(label: "IP", value: localAddress)
                    AddressRow(label: "Router", value: connection.router)
                    AddressRow(label: "DNS", value: connection.dns.first, help: connection.dns.joined(separator: ", "),
                               suffix: connection.dns.count > 1 ? " +\(connection.dns.count - 1)" : nil)
                    AddressRow(label: "MAC", value: connection.macAddress)
                }
            }
            if let ipv6 = publicInfo?.ipv6 ?? connection.localIPv6 {
                AddressRow(label: "IPv6", value: ipv6)
            }
        }
    }

    @ViewBuilder private var publicRows: some View {
        switch connection.publicIP {
        case .found(let info):
            AddressRow(label: "IP", value: info.ipv4)
            AddressRow(label: "ISP", value: info.isp, copyable: false)
            AddressRow(label: "ASN", value: info.asn, copyable: false)
            AddressRow(label: "Location", value: info.location, copyable: false)
        case .pending:
            Text("Looking up…").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
        case .failed:
            Text("Couldn't reach the lookup service").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var publicInfo: PublicIPInfo? {
        if case .found(let info) = connection.publicIP { return info }
        return nil
    }

    private var localAddress: String? {
        guard let address = connection.localIPv4 else { return nil }
        return connection.prefixLength.map { "\(address)/\($0)" } ?? address
    }

    // MARK: Header

    private var symbol: String {
        switch connection.kind {
        case .wifi: "wifi"
        case .ethernet: "cable.connector.horizontal"
        case .vpn: "lock.shield"
        case .other: "network"
        case .offline: "wifi.slash"
        }
    }

    private var kindLabel: String {
        switch connection.kind {
        case .wifi: "Wi-Fi"
        case .ethernet: "Ethernet"
        case .vpn: "VPN"
        case .other: "Connected"
        case .offline: "Offline"
        }
    }

    private var kindColor: Color {
        switch connection.kind {
        case .wifi, .ethernet, .other: Theme.memory
        case .vpn: Theme.gpu
        case .offline: Theme.upload
        }
    }

    /// "AX88179B · en5". The adapter name is left out when it just repeats the pill ("Wi-Fi").
    private var adapterLabel: String {
        var parts: [String] = []
        if let name = connection.adapterName, name != kindLabel { parts.append(name) }
        if let interface = connection.interface { parts.append(interface) }
        return parts.joined(separator: " · ")
    }

    /// Both lines share one scale so upload and download can be compared; 1 KB/s floor keeps idle noise flat.
    private var chartMaximum: Double {
        max(1_000, (uploadHistory + downloadHistory).max() ?? 0) * 1.1
    }
}

// MARK: - Wi-Fi

private struct WiFiRow: View {
    let wifi: WiFiInfo

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Network").font(.system(size: 10)).foregroundStyle(Theme.secondaryText)
                networkName
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Footer(label: "Signal", value: "\(wifi.rssi) dBm", valueColor: signalColor)
            Footer(label: "Channel", value: channel)
            Footer(label: "Rate", value: wifi.transmitRate > 0 ? Fmt.bitRate(wifi.transmitRate * 1_000_000) : "—")
        }
    }

    @ViewBuilder private var networkName: some View {
        if let ssid = wifi.ssid {
            Text(ssid).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1).help(ssid)
        } else {
            switch LocationAccess.status {
            case .notDetermined:
                Button("Show name") { LocationAccess.request() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.network)
                    .help("macOS only shows the Wi-Fi name to apps allowed to use Location Services. MacStatus doesn't read your location.")
            case .denied, .restricted:
                Text("Hidden").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                    .help("Allow MacStatus under System Settings › Privacy & Security › Location Services to show the Wi-Fi name.")
            default:
                Text("—").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            }
        }
    }

    private var channel: String {
        switch (wifi.channel, wifi.band) {
        case let (channel?, band?): "\(channel) · \(band)"
        case let (channel?, nil): "\(channel)"
        default: "—"
        }
    }

    /// Roughly how macOS's Wi-Fi menu grades it: above −67 dBm is good, below −75 is weak.
    private var signalColor: Color {
        if wifi.rssi >= -67 { return Theme.memory }
        if wifi.rssi >= -75 { return Theme.system }
        return Theme.upload
    }
}

// MARK: - Building blocks

/// Label above a value, like the energy card's footer.
private struct Footer: View {
    let label: String
    let value: String
    var valueColor: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.secondaryText)
            Text(value).font(.value(12, weight: .semibold)).foregroundStyle(valueColor).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AddressColumn<Rows: View>: View {
    let title: String
    let tint: Color
    @ViewBuilder let rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(tint)
            rows
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// "Label ........ value". Addresses copy to the clipboard on click.
private struct AddressRow: View {
    let label: String
    let value: String?
    var copyable = true
    var help: String?
    var suffix: String?

    @State private var copied = false

    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 4)
            if let value, copyable {
                Button { copy(value) } label: { text(value) }
                    .buttonStyle(.plain)
                    .help(help ?? "Click to copy")
            } else {
                text(value ?? "—").help(help ?? value ?? "")
            }
        }
    }

    private func text(_ value: String) -> some View {
        Text(copied ? "Copied" : value + (suffix ?? ""))
            .font(.value(11))
            .foregroundStyle(copied ? Theme.memory : .white)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }
}
