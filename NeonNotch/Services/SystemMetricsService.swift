import Darwin
import Foundation

@MainActor
final class SystemMetricsService: MetricsProvider {
    private var previousCPUTicks: (used: UInt64, total: UInt64)?
    private var previousNetwork: (down: UInt64, up: UInt64, date: Date)?

    func sample() async -> SystemMetricsSnapshot {
        let cpu = cpuPercent()
        let memory = memoryUsage()
        let disk = diskUsage()
        let network = networkRates()
        return SystemMetricsSnapshot(
            cpuPercent: cpu,
            memoryUsed: memory.used,
            memoryTotal: memory.total,
            diskUsed: disk.used,
            diskTotal: disk.total,
            networkDownPerSecond: network.down,
            networkUpPerSecond: network.up,
            timestamp: Date()
        )
    }

    private func cpuPercent() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        let used = user + system + nice
        let total = used + idle
        defer { previousCPUTicks = (used, total) }
        guard let previous = previousCPUTicks, total > previous.total else { return 0 }
        let usedDelta = used - previous.used
        let totalDelta = total - previous.total
        return totalDelta == 0 ? 0 : min(100, Double(usedDelta) / Double(totalDelta) * 100)
    }

    private func memoryUsage() -> (used: UInt64, total: UInt64) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, ProcessInfo.processInfo.physicalMemory) }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let total = ProcessInfo.processInfo.physicalMemory
        let freePages = UInt64(stats.free_count + stats.speculative_count)
        let free = freePages * UInt64(pageSize)
        return (total > free ? total - free : 0, total)
    }

    private func diskUsage() -> (used: UInt64, total: UInt64) {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        let total = UInt64(max(0, values?.volumeTotalCapacity ?? 0))
        let available = UInt64(max(0, values?.volumeAvailableCapacityForImportantUsage ?? 0))
        return (total > available ? total - available : 0, total)
    }

    private func networkRates() -> (down: UInt64, up: UInt64) {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return (0, 0) }
        defer { freeifaddrs(addresses) }
        var down: UInt64 = 0
        var up: UInt64 = 0
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let item = current.pointee
            if item.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
               (item.ifa_flags & UInt32(IFF_LOOPBACK)) == 0,
               let data = item.ifa_data?.assumingMemoryBound(to: if_data.self).pointee {
                down += UInt64(data.ifi_ibytes)
                up += UInt64(data.ifi_obytes)
            }
            pointer = item.ifa_next
        }
        let now = Date()
        defer { previousNetwork = (down, up, now) }
        guard let previous = previousNetwork else { return (0, 0) }
        let interval = max(0.2, now.timeIntervalSince(previous.date))
        return (
            UInt64(Double(down >= previous.down ? down - previous.down : 0) / interval),
            UInt64(Double(up >= previous.up ? up - previous.up : 0) / interval)
        )
    }
}

