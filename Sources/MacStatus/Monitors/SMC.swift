import Foundation
import IOKit

/// Minimal, read-only client for the AppleSMC user client. Works without root.
///
/// The kernel struct (`SMCParamStruct`) is 80 bytes. It is built by hand with explicit
/// offsets because Swift's struct layout packs nested structs differently from C.
///
///   0  key (UInt32, FourCC)         28 keyInfo.dataSize     40 result
///  28  keyInfo (12 bytes)           32 keyInfo.dataType     42 data8 (command)
///  48  bytes[32] (payload)          36 keyInfo.attributes   44 data32 (index)
final class SMC {
    private enum Command: UInt8 {
        case readKey = 5
        case keyFromIndex = 8
        case keyInfo = 9
    }

    private struct KeyInfo {
        var size: UInt32
        var type: UInt32
    }

    private static let structSize = 80
    private static let fourCCFloat = SMC.fourCC("flt ")

    private var connection: io_connect_t = 0
    private var infoCache: [UInt32: KeyInfo] = [:]

    private(set) var cpuTemperatureKeys: [UInt32] = []
    private(set) var gpuTemperatureKeys: [UInt32] = []

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
        discoverTemperatureKeys()
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    // MARK: Public reads

    /// Total system power draw in watts.
    func systemPower() -> Double? { readFloat("PSTR").map { max(0, $0) } }

    /// Power drawn from the DC input (the charger) in watts.
    func adapterPower() -> Double? { readFloat("PDTR").map { max(0, $0) } }

    func cpuTemperature() -> Double? { average(of: cpuTemperatureKeys) }
    func gpuTemperature() -> Double? { average(of: gpuTemperatureKeys) }

    func readFloat(_ key: String) -> Double? { readFloat(key: SMC.fourCC(key)) }

    // MARK: Sensor discovery

    /// Apple Silicon names: `Tp*` performance cores, `Te*` efficiency cores, `Tg*` GPU.
    /// Enumerating by prefix keeps this working across M1...M4 where the exact keys differ.
    private func discoverTemperatureKeys() {
        guard let countBytes = readBytes(key: SMC.fourCC("#KEY")) else { return }
        let count = countBytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        for index in 0..<count {
            guard let key = key(at: index) else { continue }
            let name = SMC.string(from: key)
            guard name.hasPrefix("Tp") || name.hasPrefix("Te") || name.hasPrefix("Tg") else { continue }
            guard let value = readFloat(key: key), Self.plausible(value) else { continue }
            if name.hasPrefix("Tg") { gpuTemperatureKeys.append(key) } else { cpuTemperatureKeys.append(key) }
        }
    }

    private static func plausible(_ celsius: Double) -> Bool { celsius > 10 && celsius < 130 }

    private func average(of keys: [UInt32]) -> Double? {
        let values = keys.compactMap { readFloat(key: $0) }.filter(Self.plausible)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: Raw access

    private func readFloat(key: UInt32) -> Double? {
        guard let info = keyInfo(key), info.type == SMC.fourCCFloat, info.size == 4,
              let bytes = readBytes(key: key), bytes.count == 4 else { return nil }
        let raw = bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        return Double(Float(bitPattern: raw))
    }

    private func keyInfo(_ key: UInt32) -> KeyInfo? {
        if let cached = infoCache[key] { return cached }
        var input = [UInt8](repeating: 0, count: SMC.structSize)
        input.withUnsafeMutableBytes { $0.storeBytes(of: key, toByteOffset: 0, as: UInt32.self) }
        input[42] = Command.keyInfo.rawValue
        guard let output = call(input) else { return nil }
        let info = output.withUnsafeBytes {
            KeyInfo(size: $0.loadUnaligned(fromByteOffset: 28, as: UInt32.self),
                    type: $0.loadUnaligned(fromByteOffset: 32, as: UInt32.self))
        }
        infoCache[key] = info
        return info
    }

    private func readBytes(key: UInt32) -> [UInt8]? {
        guard let info = keyInfo(key), info.size > 0, info.size <= 32 else { return nil }
        var input = [UInt8](repeating: 0, count: SMC.structSize)
        input.withUnsafeMutableBytes {
            $0.storeBytes(of: key, toByteOffset: 0, as: UInt32.self)
            $0.storeBytes(of: info.size, toByteOffset: 28, as: UInt32.self)
        }
        input[42] = Command.readKey.rawValue
        guard let output = call(input) else { return nil }
        return Array(output[48..<(48 + Int(info.size))])
    }

    private func key(at index: UInt32) -> UInt32? {
        var input = [UInt8](repeating: 0, count: SMC.structSize)
        input[42] = Command.keyFromIndex.rawValue
        input.withUnsafeMutableBytes { $0.storeBytes(of: index, toByteOffset: 44, as: UInt32.self) }
        guard let output = call(input) else { return nil }
        return output.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    }

    private func call(_ input: [UInt8]) -> [UInt8]? {
        var output = [UInt8](repeating: 0, count: SMC.structSize)
        var outputSize = SMC.structSize
        let status = input.withUnsafeBytes { inBuf in
            output.withUnsafeMutableBytes { outBuf in
                IOConnectCallStructMethod(connection, 2, inBuf.baseAddress, SMC.structSize, outBuf.baseAddress, &outputSize)
            }
        }
        guard status == KERN_SUCCESS, output[40] == 0 else { return nil }
        return output
    }

    private static func fourCC(_ string: String) -> UInt32 {
        string.utf8.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private static func string(from fourCC: UInt32) -> String {
        String(decoding: [24, 16, 8, 0].map { UInt8((fourCC >> UInt32($0)) & 0xff) }, as: UTF8.self)
    }
}
