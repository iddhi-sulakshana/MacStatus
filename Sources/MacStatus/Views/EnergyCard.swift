import SwiftUI

/// Charging = green, discharging = red, plugged in (not charging) = blue.
struct EnergyCard: View {
    let energy: EnergyStats

    private var stateColor: Color { Theme.color(for: energy.state) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    CardTitle(symbol: "bolt.fill", title: "Energy & Power", tint: stateColor)
                    Pill(text: stateLabel, color: stateColor)
                    Spacer()
                    if energy.hasBattery {
                        Text("\(energy.batteryPercent)%")
                            .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(stateColor)
                    }
                }

                if energy.hasBattery {
                    SegmentedBar(segments: [Segment(fraction: Double(energy.batteryPercent) / 100, color: stateColor)], height: 8)
                }

                HStack(alignment: .top, spacing: 8) {
                    if energy.hasBattery {
                        StatColumn(label: "Battery", value: Fmt.signedWatts(energy.batteryWatts),
                                   valueColor: batteryFlowColor, detail: batteryDetail)
                    }
                    StatColumn(label: "Charger", value: energy.adapterWatts > 0.05 ? Fmt.watts(energy.adapterWatts) : "—",
                               valueColor: Theme.pluggedIn, detail: chargerDetail)
                    StatColumn(label: "System", value: energy.systemWatts.map(Fmt.watts) ?? "—", detail: "total draw")
                }

                if energy.hasBattery {
                    Divider().overlay(Color.white.opacity(0.08))
                    HStack {
                        footer("Health", energy.healthPercent.map { "\($0)%" } ?? "—")
                        footer("Cycles", energy.cycleCount.map(String.init) ?? "—")
                        footer("Temp", Fmt.temperature(energy.batteryTemperature))
                        footer(energy.state == .charging ? "To full" : "Remaining",
                               energy.minutesRemaining.map(Fmt.duration(minutes:)) ?? "—")
                    }
                }
            }
        }
    }

    private var stateLabel: String {
        switch energy.state {
        case .charging: "Charging"
        case .discharging: "Discharging"
        case .pluggedIn: energy.hasBattery ? "Plugged In" : "AC Power"
        }
    }

    /// Sign of the actual battery current, so a plugged-in Mac that is still leaning on the battery shows red.
    private var batteryFlowColor: Color {
        if energy.batteryWatts > 0.05 { return Theme.charging }
        if energy.batteryWatts < -0.05 { return Theme.discharging }
        return Theme.pluggedIn
    }

    private var batteryDetail: String {
        if energy.batteryWatts > 0.05 { return "charging" }
        if energy.batteryWatts < -0.05 { return "discharging" }
        return "idle"
    }

    private var chargerDetail: String {
        if let rated = energy.adapterRatedWatts { return "of \(rated) W" }
        return energy.adapterWatts > 0.05 ? "connected" : "unplugged"
    }

    private func footer(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.secondaryText)
            Text(value).font(.value(12, weight: .semibold)).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
