import Darwin
import Foundation
import IOKit

/// Per-physical-drive throughput from `IOBlockStorageDriver` statistics.
///
/// Each driver owns a tree of `IOMedia` nodes: the physical disk plus, for APFS, the synthesized
/// container disks stacked on top of it. A mounted volume (`/dev/disk3s1s1`) is attributed to the
/// drive whose tree contains its whole-disk name (`disk3`).
final class DiskMonitor {
    private struct Drive {
        var id: UInt64
        var model: String
        var interconnect: String
        var isInternal: Bool
        var capacity: UInt64
        var wholeDisks: Set<String>
        /// Registry entry exposing the NVMe SMART plug-in (external NVMe drives).
        var smartEntryID: UInt64?
    }

    private struct Counters { var read: UInt64; var write: UInt64; var time: UInt64 }

    private struct Volume {
        var device: String
        var mountPoint: String
        var name: String
        var total: UInt64
        var available: UInt64
    }

    private var drives: [UInt64: Drive] = [:]
    private var ignored: Set<UInt64> = []
    private var counters: [UInt64: Counters] = [:]
    private var volumes: [Volume] = []
    private var lastVolumeRefresh: UInt64 = 0
    /// SMART reads are admin commands to the drive, so they are cached and refreshed every 10 s.
    private var smartTemperatures: [UInt64: (time: UInt64, value: Double?)] = [:]

    func sample(internalTemperature: Double?) -> [DiskStats] {
        let now = monotonicNanos()
        var seen: [UInt64: (read: UInt64, write: UInt64)] = [:]
        var topologyChanged = false

        forEachService(named: "IOBlockStorageDriver") { entry in
            var id: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(entry, &id)
            guard !ignored.contains(id),
                  let stats = ioProperty(entry, "Statistics") as? [String: Any] else { return }
            if drives[id] == nil {
                if let drive = describe(entry, id: id) {
                    drives[id] = drive
                    topologyChanged = true
                } else {
                    ignored.insert(id)
                    return
                }
            }
            seen[id] = (asUInt64(stats["Bytes (Read)"]) ?? 0, asUInt64(stats["Bytes (Write)"]) ?? 0)
        }

        for id in drives.keys where seen[id] == nil {
            drives[id] = nil
            counters[id] = nil
            topologyChanged = true
        }
        if topologyChanged || now &- lastVolumeRefresh > 5_000_000_000 {
            volumes = readVolumes()
            lastVolumeRefresh = now
        }

        var result: [DiskStats] = []
        for (id, drive) in drives {
            guard let current = seen[id] else { continue }
            var readRate = 0.0, writeRate = 0.0
            if let old = counters[id], now > old.time {
                let seconds = Double(now - old.time) / 1_000_000_000
                readRate = Double(current.read >= old.read ? current.read - old.read : 0) / seconds
                writeRate = Double(current.write >= old.write ? current.write - old.write : 0) / seconds
            }
            counters[id] = Counters(read: current.read, write: current.write, time: now)

            let mine = volumes.filter { volume in
                wholeDisk(of: volume.device).map(drive.wholeDisks.contains) ?? false
            }
            let primary = mine.first { $0.mountPoint == "/" }
                ?? mine.first { !$0.mountPoint.hasPrefix("/System/") }
                ?? mine.first

            result.append(DiskStats(
                id: id,
                name: primary?.name ?? drive.model,
                model: drive.model,
                interconnect: drive.interconnect,
                isInternal: drive.isInternal,
                capacity: primary?.total ?? drive.capacity,
                used: primary.map { $0.total > $0.available ? $0.total - $0.available : 0 },
                readBytesPerSecond: readRate,
                writeBytesPerSecond: writeRate,
                temperature: (drive.isInternal ? internalTemperature : nil) ?? smartTemperature(of: drive, now: now)
            ))
        }
        return result.sorted { ($0.isInternal ? 0 : 1, $0.name) < ($1.isInternal ? 0 : 1, $1.name) }
    }

    private func smartTemperature(of drive: Drive, now: UInt64) -> Double? {
        guard let entryID = drive.smartEntryID else { return nil }
        if let cached = smartTemperatures[drive.id], now &- cached.time < 10_000_000_000 { return cached.value }
        let value = NVMeSMART.temperature(entryID: entryID)
        smartTemperatures[drive.id] = (now, value)
        return value
    }

    // MARK: Topology

    private func describe(_ driver: io_registry_entry_t, id: UInt64) -> Drive? {
        var wholeDisks: Set<String> = []
        var capacity: UInt64 = 0

        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(driver, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let child = IOIteratorNext(iterator), child != 0 {
            defer { IOObjectRelease(child) }
            guard IOObjectConformsTo(child, "IOMedia") != 0,
                  (ioProperty(child, "Whole") as? Bool) == true,
                  let name = ioProperty(child, "BSD Name") as? String else { continue }
            if wholeDisks.isEmpty { capacity = asUInt64(ioProperty(child, "Size")) ?? 0 }
            wholeDisks.insert(name)
        }
        guard !wholeDisks.isEmpty else { return nil } // card readers with nothing inserted

        var model = "", interconnect = "", location = ""
        var current: io_registry_entry_t = 0
        if IORegistryEntryGetParentEntry(driver, kIOServicePlane, &current) == KERN_SUCCESS {
            var depth = 0
            while current != 0, depth < 10 {
                if let device = ioProperty(current, "Device Characteristics") as? [String: Any], model.isEmpty {
                    model = asString(device["Product Name"]) ?? ""
                }
                if let proto = ioProperty(current, "Protocol Characteristics") as? [String: Any], interconnect.isEmpty {
                    interconnect = asString(proto["Physical Interconnect"]) ?? ""
                    location = asString(proto["Physical Interconnect Location"]) ?? ""
                }
                var next: io_registry_entry_t = 0
                IORegistryEntryGetParentEntry(current, kIOServicePlane, &next)
                IOObjectRelease(current)
                current = next
                depth += 1
            }
            if current != 0 { IOObjectRelease(current) }
        }

        // Disk images and other virtual devices aren't "connected disks".
        if interconnect == "Virtual Interface" || location == "File" { return nil }

        return Drive(id: id,
                     model: model.isEmpty ? "Disk" : model,
                     interconnect: Self.prettyInterconnect(interconnect, location: location),
                     isInternal: location == "Internal",
                     capacity: capacity,
                     wholeDisks: wholeDisks,
                     smartEntryID: NVMeSMART.capableEntryID(above: driver))
    }

    private static func prettyInterconnect(_ interconnect: String, location: String) -> String {
        if location == "Internal" { return "Internal" }
        switch interconnect {
        case "PCI-Express": return "PCIe"
        case "": return "External"
        default: return interconnect
        }
    }

    // MARK: Volumes

    private func readVolumes() -> [Volume] {
        var list: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&list, MNT_NOWAIT)
        guard count > 0, let list else { return [] }

        var result: [Volume] = []
        for index in 0..<Int(count) {
            var fs = list[index]
            let device = withUnsafePointer(to: &fs.f_mntfromname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            guard device.hasPrefix("/dev/disk") else { continue }
            let mountPoint = withUnsafePointer(to: &fs.f_mntonname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            let url = URL(fileURLWithPath: mountPoint)
            let name = (try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? url.lastPathComponent
            let blockSize = UInt64(fs.f_bsize)
            result.append(Volume(device: device,
                                 mountPoint: mountPoint,
                                 name: name,
                                 total: UInt64(fs.f_blocks) * blockSize,
                                 available: UInt64(fs.f_bavail) * blockSize))
        }
        return result
    }

    /// "/dev/disk3s1s1" -> "disk3"
    private func wholeDisk(of device: String) -> String? {
        let name = device.dropFirst("/dev/".count)
        guard name.hasPrefix("disk") else { return nil }
        let digits = name.dropFirst(4).prefix { $0.isNumber }
        return digits.isEmpty ? nil : "disk" + digits
    }
}
