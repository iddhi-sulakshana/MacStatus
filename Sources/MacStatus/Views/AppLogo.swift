import AppKit
import SwiftUI

/// The MacStatus logo: a chip with a pulse running through it, on the popup's navy.
/// Drawn in SwiftUI so the popup header and the app icon (`MacStatus --icon`) come from the same source.
struct AppLogo: View {
    var size: CGFloat
    /// For icons of 32 px and less: drops the pins and thickens the pulse so it still reads.
    var simplified = false

    private static let navyTop = Color(red: 0.14, green: 0.19, blue: 0.43)
    private static let navyBottom = Color(red: 0.04, green: 0.06, blue: 0.17)
    private static let chipTop = Color(red: 0.13, green: 0.17, blue: 0.38)
    private static let chipBottom = Color(red: 0.07, green: 0.09, blue: 0.22)
    private static let blue = Color(red: 0.31, green: 0.61, blue: 1.00)
    private static let pulse = [Color(red: 0.13, green: 0.83, blue: 0.93), blue, Color(red: 0.75, green: 0.52, blue: 0.99)]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        let chip = size * (simplified ? 0.66 : 0.54)
        let pulseWidth = max(1.2, size * (simplified ? 0.085 : 0.05))

        ZStack {
            shape.fill(LinearGradient(colors: [Self.navyTop, Self.navyBottom], startPoint: .top, endPoint: .bottom))
            shape.fill(RadialGradient(colors: [Self.blue.opacity(0.38), .clear], center: UnitPoint(x: 0.82, y: 0.08),
                                      startRadius: 0, endRadius: size * 0.8))
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom),
                               lineWidth: max(0.5, size * 0.008))

            if !simplified {
                // Pins run under the chip so they read as attached to it.
                ChipPins(count: 3, pinLength: size * 0.11, pinWidth: max(1, size * 0.034))
                    .fill(Self.blue.opacity(0.55))
                    .frame(width: chip + size * 0.14, height: chip + size * 0.14)
            }

            RoundedRectangle(cornerRadius: chip * 0.2, style: .continuous)
                .fill(LinearGradient(colors: [Self.chipTop, Self.chipBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: chip * 0.2, style: .continuous)
                    .strokeBorder(Self.blue.opacity(0.7), lineWidth: max(0.75, size * 0.012)))
                .frame(width: chip, height: chip)

            Pulse()
                .stroke(LinearGradient(colors: Self.pulse, startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: pulseWidth, lineCap: .round, lineJoin: .round))
                .frame(width: chip * 0.78, height: chip * 0.62)
                .shadow(color: Self.blue.opacity(0.9), radius: size * 0.035)
        }
        .frame(width: size, height: size)
    }
}

/// The heartbeat from the README banner's mark: flat, a dip, a tall spike, settling slightly higher.
private struct Pulse: Shape {
    func path(in rect: CGRect) -> Path {
        // Banner coordinates: M5 17 H11 L14 9 L18.5 24 L21.5 15 H27 (x 5...27, y 9...24).
        let points: [CGPoint] = [(5, 17), (11, 17), (14, 9), (18.5, 24), (21.5, 15), (27, 15)].map {
            CGPoint(x: rect.minX + ($0.0 - 5) / 22 * rect.width, y: rect.minY + ($0.1 - 9) / 15 * rect.height)
        }
        var path = Path()
        path.addLines(points)
        return path
    }
}

/// `count` pins on each side of a square, centred, reaching in from its edges.
private struct ChipPins: Shape {
    let count: Int
    let pinLength: CGFloat
    let pinWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing = rect.width * 0.2
        let offsets = (0..<count).map { (CGFloat($0) - CGFloat(count - 1) / 2) * spacing }
        for offset in offsets {
            let x = rect.midX + offset, y = rect.midY + offset
            let pins = [
                CGRect(x: x - pinWidth / 2, y: rect.minY, width: pinWidth, height: pinLength),                 // top
                CGRect(x: x - pinWidth / 2, y: rect.maxY - pinLength, width: pinWidth, height: pinLength),     // bottom
                CGRect(x: rect.minX, y: y - pinWidth / 2, width: pinLength, height: pinWidth),                 // left
                CGRect(x: rect.maxX - pinLength, y: y - pinWidth / 2, width: pinLength, height: pinWidth),     // right
            ]
            for pin in pins { path.addRoundedRect(in: pin, cornerSize: CGSize(width: pinWidth / 2, height: pinWidth / 2)) }
        }
        return path
    }
}

/// Writes the macOS iconset (16 pt to 512 pt @2x) for `iconutil`. Used by `Scripts/build-app.sh`.
@MainActor
enum IconRenderer {
    static func run(outputDirectory: String) {
        let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var written = 0
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                // Apple's grid: the rounded square is 824 of 1024, leaving room for the drop shadow.
                let pixels = CGFloat(points * scale)
                let icon = AppLogo(size: pixels * 824 / 1024, simplified: pixels <= 32)
                    .shadow(color: .black.opacity(0.35), radius: pixels * 14 / 1024, y: pixels * 10 / 1024)
                    .frame(width: pixels, height: pixels)
                let renderer = ImageRenderer(content: icon)
                renderer.scale = 1
                guard let image = renderer.cgImage,
                      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { continue }
                let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
                if (try? png.write(to: directory.appendingPathComponent(name))) != nil { written += 1 }
            }
        }
        print("wrote \(written) icon images to \(directory.path)")
        exit(written == 10 ? 0 : 1)
    }
}
