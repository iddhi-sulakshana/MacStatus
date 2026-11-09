import Foundation
import IOKit

/// Battery state from `AppleSmartBattery`, live wattage from the SMC.
final class PowerMonitor {
    func sample(smc: SMC?) -> EnergyStats {
        var energy = EnergyStats()
        energy.systemWatts = smc?.systemPower()

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else {
            // Desktop Mac: no battery, only the wall.
            energy.adapterWatts = smc?.adapterPower() ?? energy.systemWatts ?? 0
            return energy
        }
        defer { IOObjectRelease(service) }
        guard let props = ioProperties(service) else { return energy }

        energy.hasBattery = (props["BatteryInstalled"] as? Bool) ?? true

        let isCharging = (props["IsCharging"] as? Bool) ?? false
        let isPlugged = (props["ExternalConnected"] as? Bool) ?? false
        energy.state = isCharging ? .charging : (isPlugged ? .pluggedIn : .discharging)

        // Apple Silicon reports percent directly; Intel reports mAh against MaxCapacity.
        let current = asInt(props["CurrentCapacity"]) ?? 0
        let maximum = asInt(props["MaxCapacity"]) ?? 100
        energy.batteryPercent = maximum > 100 ? current * 100 / maximum : current

        // Signed: positive while charging, negative while discharging.
        let millivolts = Double(asInt(props["Voltage"]) ?? 0)
        let milliamps = Double(asSignedInt64(props["InstantAmperage"]) ?? asSignedInt64(props["Amperage"]) ?? 0)
        energy.batteryWatts = millivolts * milliamps / 1_000_000

        if let design = asInt(props["DesignCapacity"]), design > 0,
           let full = asInt(props["NominalChargeCapacity"]) ?? asInt(props["AppleRawMaxCapacity"]) {
            energy.healthPercent = min(100, full * 100 / design)
        }
        energy.cycleCount = asInt(props["CycleCount"])
        energy.batteryTemperature = asDouble(props["Temperature"]).map { $0 / 100 }
        if let minutes = asInt(props["TimeRemaining"]), minutes > 0, minutes < 65535 {
            energy.minutesRemaining = minutes
        }

        let telemetry = props["PowerTelemetryData"] as? [String: Any]
        if isPlugged {
            let adapter = props["AdapterDetails"] as? [String: Any]
            energy.adapterRatedWatts = asInt(adapter?["Watts"])
            energy.adapterName = asString(adapter?["Name"])
            // PDTR is refreshed every second; the telemetry copy lags by many seconds.
            energy.adapterWatts = smc?.adapterPower() ?? asDouble(telemetry?["SystemPowerIn"]).map { $0 / 1000 } ?? 0
        }

        if energy.systemWatts == nil {
            energy.systemWatts = asDouble(telemetry?["SystemLoad"]).map { $0 / 1000 }
        }
        return energy
    }
}
