import SwiftUI

/// Connected drives, two per row.
struct DisksCard: View {
    let disks: [DiskStats]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    CardTitle(symbol: "internaldrive", title: "Disks", tint: Theme.disk)
                    Spacer()
                    Text("\(disks.count) connected").font(.system(size: 10)).foregroundStyle(Theme.secondaryText)
                }
                if disks.isEmpty {
                    Text("No disks found").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
                }
                ForEach(Array(stride(from: 0, to: disks.count, by: 2)), id: \.self) { start in
                    HStack(alignment: .top, spacing: 8) {
                        DiskTile(disk: disks[start])
                        if start + 1 < disks.count {
                            DiskTile(disk: disks[start + 1])
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }
}

private struct DiskTile: View {
    let disk: DiskStats

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: disk.isInternal ? "internaldrive.fill" : "externaldrive.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.disk)
                VStack(alignment: .leading, spacing: 1) {
                    Text(disk.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(disk.model).font(.system(size: 9)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 3) {
                SegmentedBar(segments: [Segment(fraction: usedFraction, color: Theme.disk)], height: 4)
                HStack {
                    Text(capacityLabel)
                    Spacer(minLength: 4)
                    Text(disk.interconnect)
                }
                .font(.system(size: 9))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
            }

            HStack(spacing: 6) {
                rate(symbol: "arrow.down", label: "Read", speed: disk.readBytesPerSecond, color: Theme.download)
                rate(symbol: "arrow.up", label: "Write", speed: disk.writeBytesPerSecond, color: Theme.upload)
            }

            HStack(spacing: 4) {
                Image(systemName: "thermometer.medium").font(.system(size: 10))
                Text(Fmt.temperature(disk.temperature)).font(.value(11, weight: .semibold))
                if disk.temperature == nil {
                    Text("unavailable").font(.system(size: 9))
                }
            }
            .foregroundStyle(Theme.secondaryText)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private var usedFraction: Double {
        guard let used = disk.used, disk.capacity > 0 else { return 0 }
        return min(1, Double(used) / Double(disk.capacity))
    }

    private var capacityLabel: String {
        guard let used = disk.used else { return Fmt.capacity(disk.capacity) }
        return "\(Fmt.capacity(used)) of \(Fmt.capacity(disk.capacity))"
    }

    private func rate(symbol: String, label: String, speed: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 8, weight: .bold))
                Text(label).font(.system(size: 9))
            }
            .foregroundStyle(color)
            Text(Fmt.speed(speed)).font(.value(11, weight: .semibold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
