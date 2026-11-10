import SwiftUI

enum Theme {
    static let backgroundTop = Color(red: 0.05, green: 0.06, blue: 0.17)
    static let backgroundBottom = Color(red: 0.11, green: 0.07, blue: 0.27)
    static let card = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.10)
    static let secondaryText = Color.white.opacity(0.55)

    static let cpu = Color(red: 0.23, green: 0.84, blue: 0.94)
    static let gpu = Color(red: 0.76, green: 0.46, blue: 1.00)
    static let memory = Color(red: 0.20, green: 0.88, blue: 0.54)
    static let system = Color(red: 1.00, green: 0.72, blue: 0.28)
    static let disk = Color(red: 1.00, green: 0.62, blue: 0.30)
    static let network = Color(red: 0.51, green: 0.56, blue: 1.00)

    // Network (also used for the menu bar dots): upload red, download blue.
    static let upload = Color(red: 1.00, green: 0.35, blue: 0.37)
    static let download = Color(red: 0.30, green: 0.61, blue: 1.00)

    // Power state: charging green, discharging red, plugged-in blue.
    static let charging = Color(red: 0.20, green: 0.88, blue: 0.54)
    static let discharging = Color(red: 1.00, green: 0.35, blue: 0.37)
    static let pluggedIn = Color(red: 0.30, green: 0.61, blue: 1.00)

    static func color(for state: PowerState) -> Color {
        switch state {
        case .charging: charging
        case .discharging: discharging
        case .pluggedIn: pluggedIn
        }
    }

    static var background: some View {
        LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Containers

struct Card<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.cardStroke, lineWidth: 1))
    }
}

struct CardTitle: View {
    let symbol: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
            Text(title).font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(tint)
    }
}

struct Pill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(color.opacity(0.14)))
    }
}

// MARK: - Text helpers

extension Font {
    static func value(_ size: CGFloat = 11, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

/// "● Label        value"
struct LegendRow: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 4)
            Text(value).font(.value()).foregroundStyle(.white)
        }
    }
}

/// Small caption above a value.
struct StatColumn: View {
    let label: String
    let value: String
    var valueColor: Color = .white
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.secondaryText)
            Text(value).font(.value(15, weight: .semibold)).foregroundStyle(valueColor)
            if let detail {
                Text(detail).font(.system(size: 10)).foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Charts

struct Sparkline: View {
    let values: [Double]
    let color: Color
    var maximum: Double = 100

    var body: some View {
        GeometryReader { geometry in
            let points = points(in: geometry.size)
            ZStack {
                // Faint baseline so the chart reads as a chart before the history fills in.
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geometry.size.height - 0.5))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height - 0.5))
                }
                .stroke(Color.white.opacity(0.10), lineWidth: 1)

                Path { path in
                    guard points.count > 1, let first = points.first, let last = points.last else { return }
                    path.move(to: CGPoint(x: first.x, y: geometry.size.height))
                    points.forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: last.x, y: geometry.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.32), color.opacity(0)], startPoint: .top, endPoint: .bottom))

                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        let capacity = CGFloat(StatsHistory.capacity - 1)
        let offset = CGFloat(StatsHistory.capacity - values.count)
        return values.enumerated().map { index, value in
            let x = (CGFloat(index) + offset) / capacity * size.width
            let y = size.height - CGFloat(min(max(value / maximum, 0), 1)) * (size.height - 2) - 1
            return CGPoint(x: x, y: y)
        }
    }
}

struct Segment: Identifiable {
    let id = UUID()
    let fraction: Double
    let color: Color
}

struct SegmentedBar: View {
    let segments: [Segment]
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1.5) {
                ForEach(segments) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: max(0, geometry.size.width * segment.fraction))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
        .frame(height: height)
    }
}
