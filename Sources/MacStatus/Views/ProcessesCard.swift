import SwiftUI

struct ProcessesCard: View {
    let topCPU: [ProcessUsage]
    let topMemory: [ProcessUsage]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                CardTitle(symbol: "list.number", title: "Top Processes", tint: .white.opacity(0.9))
                HStack(alignment: .top, spacing: 16) {
                    column(title: "CPU", tint: Theme.cpu, rows: topCPU) { Fmt.percent($0.cpu) } fraction: { $0.cpu }
                    column(title: "Memory", tint: Theme.memory, rows: topMemory) { Fmt.memory($0.memory) } fraction: { Double($0.memory) }
                }
            }
        }
    }

    private func column(title: String, tint: Color, rows: [ProcessUsage],
                        value: @escaping (ProcessUsage) -> String,
                        fraction: @escaping (ProcessUsage) -> Double) -> some View {
        let peak = rows.map(fraction).max() ?? 1
        return VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(tint)
            if rows.isEmpty {
                Text("Sampling…").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
            }
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(row.name).font(.system(size: 11)).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 2)
                        Text(value(row)).font(.value(10, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                    }
                    GeometryReader { geometry in
                        Capsule().fill(tint.opacity(0.75))
                            .frame(width: geometry.size.width * CGFloat(peak > 0 ? fraction(row) / peak : 0))
                    }
                    .frame(height: 2.5)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
