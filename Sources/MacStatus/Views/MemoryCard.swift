import SwiftUI

struct MemoryCard: View {
    let memory: MemoryStats

    private let wiredColor = Theme.cpu
    private let compressedColor = Color(red: 1.0, green: 0.45, blue: 0.85)
    private let cachedColor = Color(red: 0.30, green: 0.61, blue: 1.00).opacity(0.55)

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    CardTitle(symbol: "memorychip", title: "Memory", tint: Theme.memory)
                    pressurePill
                    Spacer()
                    Text("\(Fmt.memory(memory.used)) / \(Fmt.memory(memory.total))")
                        .font(.value(11)).foregroundStyle(Theme.secondaryText)
                    Text(String(format: "%.0f%%", memory.usedFraction * 100))
                        .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                }

                SegmentedBar(segments: [
                    Segment(fraction: fraction(memory.app), color: Theme.memory),
                    Segment(fraction: fraction(memory.wired), color: wiredColor),
                    Segment(fraction: fraction(memory.compressed), color: compressedColor),
                    Segment(fraction: fraction(memory.cached), color: cachedColor),
                ])

                HStack(spacing: 10) {
                    legend("App", memory.app, Theme.memory)
                    legend("Wired", memory.wired, wiredColor)
                    legend("Comp.", memory.compressed, compressedColor)
                    legend("Cache", memory.cached, cachedColor)
                }
            }
        }
    }

    private func fraction(_ bytes: UInt64) -> Double {
        memory.total == 0 ? 0 : Double(bytes) / Double(memory.total)
    }

    private func legend(_ label: String, _ bytes: UInt64, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.secondaryText)
            Text(Fmt.memoryShort(bytes)).font(.value(10, weight: .semibold)).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pressurePill: some View {
        switch memory.pressure {
        case .normal: Pill(text: "Nominal", color: Theme.memory)
        case .warning: Pill(text: "Warning", color: Theme.system)
        case .critical: Pill(text: "Critical", color: Theme.upload)
        }
    }
}
