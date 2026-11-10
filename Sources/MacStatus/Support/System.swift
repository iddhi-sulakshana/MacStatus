import Darwin
import Foundation
import IOKit

// MARK: - sysctl

func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
    return String(cString: buffer)
}

func sysctlInt(_ name: String) -> Int? {
    var value: Int64 = 0
    var size = MemoryLayout<Int64>.size
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
    return Int(value)
}

func monotonicNanos() -> UInt64 {
    clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
}

// MARK: - IOKit

func ioProperty(_ entry: io_registry_entry_t, _ key: String) -> Any? {
    IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
}

func ioProperties(_ entry: io_registry_entry_t) -> [String: Any]? {
    var props: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let dict = props?.takeRetainedValue() else { return nil }
    return dict as? [String: Any]
}

/// Calls `body` for every registry entry of the given IOKit class. Entries are released afterwards.
func forEachService(named className: String, _ body: (io_registry_entry_t) -> Void) {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else { return }
    defer { IOObjectRelease(iterator) }
    while case let entry = IOIteratorNext(iterator), entry != 0 {
        body(entry)
        IOObjectRelease(entry)
    }
}

func asInt(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }
func asUInt64(_ value: Any?) -> UInt64? { (value as? NSNumber)?.uint64Value }
func asDouble(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }

/// IOKit stores negative amperages as 64-bit two's complement, exposed as a huge unsigned number.
func asSignedInt64(_ value: Any?) -> Int64? {
    (value as? NSNumber).map { Int64(bitPattern: $0.uint64Value) }
}

func asString(_ value: Any?) -> String? {
    if let string = value as? String { return string.trimmingCharacters(in: .whitespacesAndNewlines) }
    if let data = value as? Data {
        return String(decoding: data.filter { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return nil
}

// MARK: - Network interfaces

struct InterfaceCounters {
    var received: UInt64
    var sent: UInt64
    var baudRate: UInt64
}

/// 64-bit byte counters and link speed for every interface, by BSD name.
/// `getifaddrs` only has 32-bit counters, which wrap every 4 GB, so this reads `NET_RT_IFLIST2` instead.
func interfaceCounters() -> [String: InterfaceCounters] {
    var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
    var length = 0
    guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return [:] }
    var buffer = [UInt8](repeating: 0, count: length)
    guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else { return [:] }

    var result: [String: InterfaceCounters] = [:]
    buffer.withUnsafeBytes { raw in
        var offset = 0
        var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        while offset + MemoryLayout<if_msghdr>.size <= length {
            let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
            guard header.ifm_msglen > 0 else { break }
            if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                if if_indextoname(UInt32(message.ifm_index), &name) != nil {
                    let data = message.ifm_data
                    result[String(cString: name)] = InterfaceCounters(received: data.ifi_ibytes, sent: data.ifi_obytes,
                                                                      baudRate: data.ifi_baudrate)
                }
            }
            offset += Int(header.ifm_msglen)
        }
    }
    return result
}
