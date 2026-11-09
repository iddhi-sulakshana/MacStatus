import Foundation
import IOKit

/// Reads Apple Silicon thermal sensors through the IOHID event system (no root needed).
/// The functions are private SPI, so they are resolved with `dlsym` and the monitor degrades
/// to "no data" if any of them disappears in a future macOS release.
final class HIDSensors {
    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias SetMatchingFn = @convention(c) (CFTypeRef, CFDictionary) -> Int32
    private typealias CopyServicesFn = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias CopyEventFn = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
    private typealias FloatValueFn = @convention(c) (CFTypeRef, Int32) -> Double
    private typealias CopyPropertyFn = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?

    private static let temperatureEventType: Int64 = 15
    private static let temperatureField: Int32 = 15 << 16

    private let copyEvent: CopyEventFn
    private let floatValue: FloatValueFn
    private let client: CFTypeRef
    private var sensors: [(name: String, service: CFTypeRef)] = []

    init?() {
        guard let handle = dlopen(nil, RTLD_NOW),
              let create = dlsym(handle, "IOHIDEventSystemClientCreate"),
              let setMatching = dlsym(handle, "IOHIDEventSystemClientSetMatching"),
              let copyServices = dlsym(handle, "IOHIDEventSystemClientCopyServices"),
              let copyEvent = dlsym(handle, "IOHIDServiceClientCopyEvent"),
              let floatValue = dlsym(handle, "IOHIDEventGetFloatValue"),
              let copyProperty = dlsym(handle, "IOHIDServiceClientCopyProperty") else { return nil }

        self.copyEvent = unsafeBitCast(copyEvent, to: CopyEventFn.self)
        self.floatValue = unsafeBitCast(floatValue, to: FloatValueFn.self)

        guard let client = unsafeBitCast(create, to: CreateFn.self)(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }
        self.client = client

        // Vendor usage page 0xff00, usage 5 = temperature sensors.
        _ = unsafeBitCast(setMatching, to: SetMatchingFn.self)(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        guard let services = unsafeBitCast(copyServices, to: CopyServicesFn.self)(client)?.takeRetainedValue() as? [CFTypeRef] else { return nil }

        let property = unsafeBitCast(copyProperty, to: CopyPropertyFn.self)
        sensors = services.map { service in
            let name = (property(service, "Product" as CFString)?.takeRetainedValue() as? String) ?? "?"
            return (name, service)
        }
    }

    /// Average temperature of all sensors whose name contains `fragment`.
    func averageTemperature(matching fragment: String) -> Double? {
        let values = sensors
            .filter { $0.name.contains(fragment) }
            .compactMap { temperature(of: $0.service) }
            .filter { $0 > 10 && $0 < 130 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func temperature(of service: CFTypeRef) -> Double? {
        guard let event = copyEvent(service, Self.temperatureEventType, 0, 0)?.takeRetainedValue() else { return nil }
        return floatValue(event, Self.temperatureField)
    }
}
