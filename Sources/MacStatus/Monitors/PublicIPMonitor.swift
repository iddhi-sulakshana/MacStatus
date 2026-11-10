import Foundation
import os

/// Looks up the public address, ISP and rough location. The address can't be read locally (it belongs to the
/// router), so this asks ipinfo.io, falling back to Cloudflare's trace page, which only knows the IP and country.
///
/// Called on every sample while the popup is open, but only goes to the network when the Mac has moved to another
/// network, the answer is 10 minutes old, or Refresh was pressed. Nothing is sent except the request itself.
final class PublicIPMonitor: @unchecked Sendable {
    private struct State {
        var lookup: PublicIPLookup = .pending
        var networkKey: String?
        var fetchedAt = Date.distantPast
        var inFlight = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 10
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    /// The latest answer for `networkKey` (nil = offline). Starts a lookup in the background when one is due.
    func lookup(networkKey: String?, wantsIPv6: Bool, force: Bool) -> PublicIPLookup {
        guard let networkKey else {
            state.withLock { $0 = State() }
            return .pending
        }

        let start = state.withLock { state -> Bool in
            if state.networkKey != networkKey {
                state = State(networkKey: networkKey)
            }
            let age = Date().timeIntervalSince(state.fetchedAt)
            let due: Bool
            switch state.lookup {
            case .pending: due = true
            case .failed: due = age > 30 || force
            case .found: due = age > 600 || (force && age > 5)
            }
            guard due, !state.inFlight else { return false }
            state.inFlight = true
            return true
        }
        if start {
            Task.detached(priority: .utility) { [self] in
                let result = await fetch(wantsIPv6: wantsIPv6)
                state.withLock { state in
                    guard state.networkKey == networkKey else { return } // moved networks meanwhile: drop it
                    state.inFlight = false
                    state.fetchedAt = Date()
                    // A failed refresh keeps the answer we already had for this network.
                    if case .failed = result, case .found = state.lookup { return }
                    state.lookup = result
                }
            }
        }
        return state.withLock { $0.lookup }
    }

    // MARK: Requests

    private struct IPInfoResponse: Decodable {
        let ip: String
        let city: String?
        let country: String?
        let org: String?     // "AS9329 Sri Lanka Telecom Internet"
    }

    private func fetch(wantsIPv6: Bool) async -> PublicIPLookup {
        // ipinfo.io and 1.1.1.1 only answer over IPv4; the IPv6 address needs an IPv6-only endpoint.
        async let ipv6 = wantsIPv6 ? text("https://api6.ipify.org") : nil
        var info = await ipinfo()
        if info == nil { info = await cloudflare() }
        if let address = await ipv6, address.contains(":"), Self.isAddress(address) {
            info = info ?? PublicIPInfo()
            info?.ipv6 = address
        }
        return info.map(PublicIPLookup.found) ?? .failed
    }

    private func ipinfo() async -> PublicIPInfo? {
        guard let data = await data("https://ipinfo.io/json"),
              let response = try? JSONDecoder().decode(IPInfoResponse.self, from: data),
              Self.isAddress(response.ip) else { return nil }

        var info = PublicIPInfo(ipv4: response.ip)
        if let org = response.org?.trimmingCharacters(in: .whitespaces), !org.isEmpty {
            let parts = org.split(separator: " ", maxSplits: 1).map(String.init)
            if parts.count == 2, parts[0].hasPrefix("AS") {
                info.asn = parts[0]
                info.isp = parts[1]
            } else {
                info.isp = org
            }
        }
        let country = response.country.map { Locale.current.localizedString(forRegionCode: $0) ?? $0 }
        let place = [response.city, country].compactMap { $0 }.filter { !$0.isEmpty }
        info.location = place.isEmpty ? nil : place.joined(separator: ", ")
        return info
    }

    private func cloudflare() async -> PublicIPInfo? {
        guard let body = await text("https://1.1.1.1/cdn-cgi/trace") else { return nil }
        var fields: [String: String] = [:]
        for line in body.split(separator: "\n") {
            let pair = line.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { fields[pair[0]] = pair[1] }
        }
        guard let ip = fields["ip"], Self.isAddress(ip) else { return nil }
        let country = fields["loc"].map { Locale.current.localizedString(forRegionCode: $0) ?? $0 }
        return PublicIPInfo(ipv4: ip, location: country)
    }

    private func data(_ address: String) async -> Data? {
        guard let url = URL(string: address),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    private func text(_ address: String) async -> String? {
        guard let data = await data(address) else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Never display whatever a server sent back unless it parses as an IP address.
    private static func isAddress(_ text: String) -> Bool {
        var v4 = in_addr(), v6 = in6_addr()
        return inet_pton(AF_INET, text, &v4) == 1 || inet_pton(AF_INET6, text, &v6) == 1
    }
}
