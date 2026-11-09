import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = StatsStore()
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `MacStatus --preview <dir>` renders the popup and menu bar item to PNGs and exits.
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--preview"), arguments.indices.contains(flag + 1) {
            PreviewRenderer.run(store: store, outputDirectory: arguments[flag + 1])
            return
        }

        statusController = StatusItemController(store: store)
        store.start()

        // `MacStatus --show-popup` opens the popup right after launch (handy for screenshots and debugging).
        if arguments.contains("--show-popup") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                self?.statusController?.showPopover()
            }
        }
    }
}
