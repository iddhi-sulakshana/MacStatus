import Foundation
import IOKit

/// Reads the composite temperature of an NVMe drive through Apple's `NVMeSMARTLib` CFPlugIn,
/// the same interface smartmontools uses. Works for third-party NVMe drives in Thunderbolt/USB4
/// enclosures. Apple's internal SSD isn't exposed this way (its temperature comes from the HID sensors).
///
/// Layouts below mirror `IOKit/storage/nvme/NVMeSMARTLibExternal.h`.
enum NVMeSMART {
    /// `IONVMeSMARTInterface`: IUNKNOWN_C_GUTS, version/revision, then the function table.
    private struct Interface {
        var reserved: UnsafeMutableRawPointer?
        var queryInterface: UnsafeMutableRawPointer?
        var addRef: (@convention(c) (UnsafeMutableRawPointer?) -> UInt32)?
        var release: (@convention(c) (UnsafeMutableRawPointer?) -> UInt32)?
        var version: UInt16
        var revision: UInt16
        var smartReadData: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> IOReturn)?
    }

    private static let plugInInterfaceID = CFUUIDGetConstantUUIDWithBytes(
        nil, 0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4, 0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F)
    private static let userClientType = CFUUIDGetConstantUUIDWithBytes(
        nil, 0xAA, 0x0F, 0xA6, 0xF9, 0xC2, 0xD6, 0x45, 0x7F, 0xB1, 0x0B, 0x59, 0xA1, 0x32, 0x53, 0x29, 0x2F)
    private static let smartInterfaceID = CFUUIDGetConstantUUIDWithBytes(
        nil, 0xCC, 0xD1, 0xDB, 0x19, 0xFD, 0x9A, 0x4D, 0xAF, 0xBF, 0x95, 0x12, 0x45, 0x4B, 0x23, 0x0A, 0xB6)

    /// Registry-entry ID of the nearest ancestor that advertises NVMe SMART support.
    static func capableEntryID(above entry: io_registry_entry_t) -> UInt64? {
        var current: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &current) == KERN_SUCCESS else { return nil }
        var depth = 0
        while current != 0, depth < 10 {
            if (ioProperty(current, "NVMe SMART Capable") as? Bool) == true {
                var id: UInt64 = 0
                IORegistryEntryGetRegistryEntryID(current, &id)
                IOObjectRelease(current)
                return id
            }
            var next: io_registry_entry_t = 0
            IORegistryEntryGetParentEntry(current, kIOServicePlane, &next)
            IOObjectRelease(current)
            current = next
            depth += 1
        }
        if current != 0 { IOObjectRelease(current) }
        return nil
    }

    /// Composite temperature in °C for the NVMe device with the given registry-entry ID.
    static func temperature(entryID: UInt64) -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(entryID))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var plugIn: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0
        guard IOCreatePlugInInterfaceForService(service, userClientType, plugInInterfaceID, &plugIn, &score) == KERN_SUCCESS,
              let plugIn, let vtable = plugIn.pointee else { return nil }
        defer { IODestroyPlugInInterface(plugIn) }

        var raw: LPVOID?
        guard vtable.pointee.QueryInterface(plugIn, CFUUIDGetUUIDBytes(smartInterfaceID), &raw) == S_OK,
              let raw else { return nil }
        let interface = raw.assumingMemoryBound(to: UnsafeMutablePointer<Interface>.self)
        defer { _ = interface.pointee.pointee.release?(raw) }

        var log = [UInt8](repeating: 0, count: 512)
        guard let read = interface.pointee.pointee.smartReadData,
              read(raw, &log) == kIOReturnSuccess else { return nil }

        // Byte 0: critical warning. Bytes 1-2: composite temperature, little-endian Kelvin.
        let kelvin = Int(log[1]) | Int(log[2]) << 8
        let celsius = Double(kelvin) - 273.15
        return celsius > 0 && celsius < 150 ? celsius : nil
    }
}
