import Foundation
import ServiceManagement

/// MacStatus starts at login by default once it is installed in an Applications folder.
/// Turning it off from the right-click menu is remembered, so a later launch doesn't turn it back on.
@MainActor
enum LaunchAtLogin {
    private static let optOutKey = "launchAtLoginOptOut"

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Called on every launch. Registering again is also what repairs the login item after a reinstall.
    static func applyDefault() {
        guard isInstalled, !UserDefaults.standard.bool(forKey: optOutKey), !isEnabled else { return }
        register(true)
    }

    static func toggle() {
        let enable = !isEnabled
        UserDefaults.standard.set(!enable, forKey: optOutKey)
        register(enable)
    }

    /// Dev builds run from `build/`: registering those would leave a login item pointing into the repo.
    private static var isInstalled: Bool {
        Bundle.main.bundleURL.deletingLastPathComponent().lastPathComponent == "Applications"
    }

    private static func register(_ enable: Bool) {
        do {
            if enable { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("MacStatus: launch at login \(enable ? "on" : "off") failed: \(error.localizedDescription)")
        }
    }
}
