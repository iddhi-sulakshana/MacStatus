import Combine
import Foundation
import os

/// Owns every monitor. Not thread-safe: only ever touched from `StatsStore`'s sampling queue.
final class Sampler: @unchecked Sendable {
    private let cpu = CPUMonitor()
    private let gpu = GPUMonitor()
    private let memory = MemoryMonitor()
    private let network = NetworkMonitor()
    private let connection = ConnectionMonitor()
    private let publicIP = PublicIPMonitor()
    private let power = PowerMonitor()
    private let disks = DiskMonitor()
    private let processes = ProcessMonitor()
    private lazy var smc = SMC()
    private lazy var hid = HIDSensors()

    private var latest = SystemSnapshot()

    /// `detailed` adds the work that only matters while the popup is open (process list, connection details).
    /// `force` re-runs the public IP lookup, which is otherwise cached per network.
    func sample(detailed: Bool, force: Bool = false) -> SystemSnapshot {
        var snapshot = latest

        snapshot.cpu.chipName = cpu.chipName
        snapshot.cpu.logicalCores = cpu.logicalCores
        snapshot.cpu.performanceCores = cpu.performanceCores
        snapshot.cpu.efficiencyCores = cpu.efficiencyCores
        if let usage = cpu.sample() {
            snapshot.cpu.total = usage.total
            snapshot.cpu.user = usage.user
            snapshot.cpu.system = usage.system
            snapshot.cpu.idle = usage.idle
        }
        snapshot.cpu.temperature = smc?.cpuTemperature() ?? hid?.averageTemperature(matching: "PMU tdie")

        if let usage = gpu.sample() {
            snapshot.gpu.utilization = usage.utilization
            snapshot.gpu.memoryUsed = usage.memoryUsed
            snapshot.gpu.coreCount = usage.coreCount
            snapshot.gpu.name = usage.name
        }
        snapshot.gpu.temperature = smc?.gpuTemperature()

        snapshot.memory = memory.sample()
        snapshot.network = network.sample()
        snapshot.energy = power.sample(smc: smc)
        snapshot.disks = disks.sample(internalTemperature: hid?.averageTemperature(matching: "NAND"))

        if detailed {
            let result = processes.sample()
            snapshot.topCPU = result.cpu
            snapshot.topMemory = result.memory

            var details = connection.sample()
            details.publicIP = publicIP.lookup(networkKey: details.networkKey, wantsIPv6: details.localIPv6 != nil, force: force)
            snapshot.connection = details
        }

        latest = snapshot
        return snapshot
    }
}

@MainActor
final class StatsStore: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot()
    @Published private(set) var history = StatsHistory()

    private let sampler = Sampler()
    private let queue = DispatchQueue(label: "app.macstatus.sampler", qos: .utility)
    private let detailed = OSAllocatedUnfairLock(initialState: false)
    private let forceRequested = OSAllocatedUnfairLock(initialState: false)
    private var timer: DispatchSourceTimer?

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    /// The popup being open switches on the heavier samplers and forces an immediate refresh.
    func setDetailed(_ value: Bool) {
        detailed.withLock { $0 = value }
        if value { queue.async { [weak self] in self?.tick() } }
    }

    /// Samples right away and looks the public IP up again.
    func refresh() {
        forceRequested.withLock { $0 = true }
        queue.async { [weak self] in self?.tick() }
    }

    nonisolated private func tick() {
        let force = forceRequested.withLock { requested in
            defer { requested = false }
            return requested
        }
        let snapshot = sampler.sample(detailed: detailed.withLock { $0 }, force: force)
        Task { @MainActor [weak self] in self?.apply(snapshot) }
    }

    private func apply(_ snapshot: SystemSnapshot) {
        self.snapshot = snapshot
        history.record(snapshot)
    }
}
