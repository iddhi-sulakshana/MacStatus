import SwiftUI

struct HeaderView: View {
    let cpu: CPUStats
    let energy: EnergyStats
    let thermalState: ProcessInfo.ThermalState
    let onRefresh: () -> Void
    let onQuit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            AppLogo(size: 38)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    Pill(text: thermal.label, color: thermal.color)
                }
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.secondaryText).lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.85))
            .help("Refresh")

            Button(action: onQuit) {
                HStack(spacing: 4) {
                    Image(systemName: "power").font(.system(size: 10, weight: .bold))
                    Text("Quit").font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(Theme.upload.opacity(0.16)))
                .overlay(Capsule().strokeBorder(Theme.upload.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.upload)
        }
    }

    private var title: String {
        cpu.logicalCores > 0 ? "\(cpu.chipName) · \(cpu.logicalCores) Cores" : cpu.chipName
    }

    private var subtitle: String {
        if let name = energy.adapterName { return name }
        switch energy.state {
        case .discharging where energy.hasBattery: return "On battery · \(energy.batteryPercent)%"
        default: return energy.hasBattery ? "Power adapter connected" : "AC power"
        }
    }

    private var thermal: (label: String, color: Color) {
        switch thermalState {
        case .nominal: ("Nominal", Theme.memory)
        case .fair: ("Fair", Theme.system)
        case .serious: ("Serious", Theme.disk)
        case .critical: ("Critical", Theme.upload)
        @unknown default: ("Unknown", Theme.secondaryText)
        }
    }
}
