import AppKit
import SwiftUI

/// Developer aid: samples live data for a few seconds, then writes `popup.png` and `menubar.png`.
@MainActor
enum PreviewRenderer {
    static func run(store: StatsStore, outputDirectory: String) {
        store.setDetailed(true)
        store.start()

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let popup = PopupContent(snapshot: store.snapshot, history: store.history)
                .background(Theme.background)
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: popup)
            renderer.scale = 2
            if let image = renderer.nsImage { write(image, to: directory.appendingPathComponent("popup.png")) }

            write(menuBarPreview(for: store.snapshot), to: directory.appendingPathComponent("menubar.png"))
            write(energyStatesPreview(), to: directory.appendingPathComponent("energy-states.png"))
            print("snapshot: \(store.snapshot)")
            NSApp.terminate(nil)
        }
    }

    /// The energy card in all three power states with synthetic data, since a desk Mac can't be unplugged on demand.
    private static func energyStatesPreview() -> NSImage? {
        func energy(_ state: PowerState, battery: Double, charger: Double, percent: Int, minutes: Int?) -> EnergyStats {
            EnergyStats(systemWatts: 14.2, hasBattery: true, batteryPercent: percent, state: state,
                        batteryWatts: battery, adapterWatts: charger, adapterRatedWatts: 30,
                        adapterName: "30W USB-C Power Adapter", healthPercent: 94, cycleCount: 76,
                        batteryTemperature: 31, minutesRemaining: minutes)
        }
        let states = VStack(spacing: 10) {
            EnergyCard(energy: energy(.charging, battery: 11.8, charger: 26.1, percent: 54, minutes: 48))
            EnergyCard(energy: energy(.discharging, battery: -14.2, charger: 0, percent: 54, minutes: 215))
            EnergyCard(energy: energy(.pluggedIn, battery: 0, charger: 14.5, percent: 100, minutes: nil))
        }
        .padding(14)
        .frame(width: PopupMetrics.width)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: states)
        renderer.scale = 2
        return renderer.nsImage
    }

    /// The menu bar item composited on dark and light bars, 4x for legibility.
    private static func menuBarPreview(for snapshot: SystemSnapshot) -> NSImage {
        let item = MenuBarRenderer.image(for: snapshot)
        let scale: CGFloat = 4
        let size = NSSize(width: (item.size.width + 24) * scale, height: item.size.height * scale * 2 + 8)
        let output = NSImage(size: size)
        output.lockFocus()
        for (index, appearance) in [NSAppearance.Name.darkAqua, .aqua].enumerated() {
            let background: NSColor = index == 0 ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.93, alpha: 1)
            let rect = NSRect(x: 0, y: CGFloat(1 - index) * (item.size.height * scale + 8),
                              width: size.width, height: item.size.height * scale)
            background.setFill()
            rect.fill()
            NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
                item.draw(in: NSRect(x: 12 * scale, y: rect.minY, width: item.size.width * scale, height: rect.height))
            }
        }
        output.unlockFocus()
        return output
    }

    private static func write(_ image: NSImage?, to url: URL) {
        guard let image, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}
