import AppKit

/// Draws the menu bar item: power and temperature stacked on the left,
/// upload (red dot) and download (blue dot) speeds stacked on the right.
///
///     18W   ● 2 KB/s
///     57°   ● 9 KB/s
///
/// Column widths are fixed (measured from the widest plausible text) so the item never jitters.
enum MenuBarRenderer {
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
    private static let height: CGFloat = 22
    private static let dotSize: CGFloat = 5
    private static let gap: CGFloat = 8

    private static func width(of text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static let leftWidth = max(width(of: "188W"), width(of: "88.8W"))
    private static let rightWidth = width(of: "888.8 MB/s")

    static func image(power: String, temperature: String, up: String, down: String) -> NSImage {
        let totalWidth = leftWidth + gap + dotSize + 3 + rightWidth + 2
        let image = NSImage(size: NSSize(width: totalWidth, height: height), flipped: false) { _ in
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]

            // Two rows, each centred on a quarter of the bar height. All text is digits/caps, so we
            // centre on cap height rather than the (taller) full line box, which would clip the bottom row.
            func centreY(row: Int) -> CGFloat { height * (row == 0 ? 0.75 : 0.25) }
            func textOrigin(row: Int) -> CGFloat { centreY(row: row) - font.capHeight / 2 + font.descender }

            (power as NSString).draw(at: NSPoint(x: 0, y: textOrigin(row: 0)), withAttributes: attributes)
            (temperature as NSString).draw(at: NSPoint(x: 0, y: textOrigin(row: 1)), withAttributes: attributes)

            // Dots hug the speed text (left-aligned); the column is fixed-width so the item never resizes.
            let dotX = leftWidth + gap
            let textX = dotX + dotSize + 3
            for (row, (text, color)) in [(up, NSColor.systemRed), (down, NSColor.systemBlue)].enumerated() {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: dotX, y: centreY(row: row) - dotSize / 2, width: dotSize, height: dotSize)).fill()
                (text as NSString).draw(at: NSPoint(x: textX, y: textOrigin(row: row)), withAttributes: attributes)
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    static func image(for snapshot: SystemSnapshot) -> NSImage {
        image(power: Fmt.compactWatts(snapshot.energy.systemWatts),
              temperature: Fmt.compactTemperature(snapshot.cpu.temperature),
              up: Fmt.speed(snapshot.network.upBytesPerSecond),
              down: Fmt.speed(snapshot.network.downBytesPerSecond))
    }
}
