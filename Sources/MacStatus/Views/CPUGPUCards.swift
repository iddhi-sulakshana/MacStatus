import SwiftUI

/// Footer shared by the CPU and GPU cards: temperature on the left, a detail on the right.
private struct TemperatureFooter: View {
    let temperature: Double?
    let detail: String

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "thermometer.medium").font(.system(size: 10))
                Text(Fmt.temperature(temperature)).font(.value(11, weight: .semibold))
            }
            .foregroundStyle(Theme.secondaryText)
            Spacer()
            Text(detail).font(.system(size: 10)).foregroundStyle(Theme.secondaryText)
        }
    }
}

struct CPUCard: View {
    let cpu: CPUStats
    let history: [Double]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle(symbol: "cpu", title: "CPU", tint: Theme.cpu)
                Text(Fmt.percent(cpu.total))
                    .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                Sparkline(values: history, color: Theme.cpu).frame(height: 36)
                VStack(spacing: 4) {
                    LegendRow(color: Theme.cpu, label: "User", value: Fmt.percent(cpu.user))
                    LegendRow(color: Theme.system, label: "System", value: Fmt.percent(cpu.system))
                }
                TemperatureFooter(temperature: cpu.temperature, detail: coreDetail)
            }
        }
    }

    private var coreDetail: String {
        if cpu.performanceCores > 0, cpu.efficiencyCores > 0 { return "\(cpu.performanceCores)P + \(cpu.efficiencyCores)E" }
        return cpu.logicalCores > 0 ? "\(cpu.logicalCores) cores" : ""
    }
}

struct GPUCard: View {
    let gpu: GPUStats
    let history: [Double]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle(symbol: "display", title: "GPU", tint: Theme.gpu)
                Text(Fmt.percent(gpu.utilization))
                    .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                Sparkline(values: history, color: Theme.gpu).frame(height: 36)
                VStack(spacing: 4) {
                    LegendRow(color: Theme.gpu, label: "Memory", value: Fmt.memory(gpu.memoryUsed))
                    LegendRow(color: Theme.system, label: "Cores", value: gpu.coreCount > 0 ? "\(gpu.coreCount)" : "—")
                }
                TemperatureFooter(temperature: gpu.temperature, detail: "")
            }
        }
    }
}
