import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let store: StatsStore
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    private var lastImageKey = ""

    init(store: StatsStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.autosaveName = "MacStatusItem"
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
        }

        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self

        store.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateImage(for: $0) }
            .store(in: &cancellables)
        updateImage(for: store.snapshot)
    }

    // MARK: Menu bar item

    private func updateImage(for snapshot: SystemSnapshot) {
        let power = Fmt.compactWatts(snapshot.energy.systemWatts)
        let temperature = Fmt.compactTemperature(snapshot.cpu.temperature)
        let up = Fmt.speed(snapshot.network.upBytesPerSecond)
        let down = Fmt.speed(snapshot.network.downBytesPerSecond)

        let key = [power, temperature, up, down].joined(separator: "|")
        guard key != lastImageKey else { return }
        lastImageKey = key
        statusItem.button?.image = MenuBarRenderer.image(power: power, temperature: temperature, up: up, down: down)
    }

    // MARK: Clicks

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }

    func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }

        // A fresh hosting controller per opening: nothing keeps re-rendering while the popup is closed.
        let host = NSHostingController(rootView: PopupView(store: store, onQuit: { NSApp.terminate(nil) }))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host

        store.setDetailed(true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate()
    }

    func popoverDidClose(_ notification: Notification) {
        store.setDetailed(false)
        popover.contentViewController = nil
    }

    // MARK: Right-click menu

    private func showContextMenu() {
        let menu = NSMenu()

        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(refresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit MacStatus", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // Attach just for this click, otherwise the menu would swallow left clicks too.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refresh() { store.refresh() }

    @objc private func toggleLaunchAtLogin() { LaunchAtLogin.toggle() }

    @objc private func quit() { NSApp.terminate(nil) }
}
