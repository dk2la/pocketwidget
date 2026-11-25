import Foundation

/// One libproc pass over every readable process. Times are nanoseconds,
/// already converted from Mach ticks.
struct ProcessSnapshot: Sendable {
    struct Entry: Sendable {
        let pid: Int32
        let name: String
        /// User + system CPU time since the process started.
        let cpuTime: UInt64
        /// Resident memory, bytes.
        let resident: UInt64
    }

    /// Monotonic clock at the moment of the pass.
    let takenAt: UInt64
    let processes: [Entry]
}

/// What the top-processes list ranks by. Follows the large chart when it
/// shows CPU or memory; every other metric falls back to CPU, since
/// per-process network, battery or volume figures are not available
/// without private APIs or root, and CPU is what "loading the Mac" means first.
enum ProcessSortKey: Equatable {
    case cpu, memory

    init(gauge: Gauge) {
        self = gauge == .memory ? .memory : .cpu
    }
}

/// One process's load between two snapshots.
struct ProcessLoad: Equatable, Identifiable, Sendable {
    let pid: Int32
    let name: String
    /// Share of one core, as Activity Monitor counts it: 1.5 is 150 %.
    let cpu: Double
    /// Bytes.
    let resident: UInt64

    var id: Int32 { pid }

    /// Loads of the processes alive in `current`. A process with no
    /// baseline (new, or the first pass) or whose counter went backwards
    /// (a reused pid) reads as 0 % until the next pass.
    static func loads(previous: ProcessSnapshot?, current: ProcessSnapshot) -> [ProcessLoad] {
        var baseline: [Int32: UInt64] = [:]
        var elapsed: Double = 0
        if let previous, current.takenAt > previous.takenAt {
            elapsed = Double(current.takenAt - previous.takenAt)
            for entry in previous.processes {
                baseline[entry.pid] = entry.cpuTime
            }
        }
        return current.processes.map { entry in
            var cpu: Double = 0
            if elapsed > 0, let before = baseline[entry.pid], entry.cpuTime >= before {
                cpu = Double(entry.cpuTime - before) / elapsed
            }
            return ProcessLoad(pid: entry.pid, name: entry.name, cpu: cpu, resident: entry.resident)
        }
    }

    /// The `count` heaviest by `key`; ties fall to the other value, then
    /// the lower pid, so the order does not flicker between passes.
    static func top(_ loads: [ProcessLoad], by key: ProcessSortKey, count: Int) -> [ProcessLoad] {
        guard count > 0 else { return [] }
        let sorted = loads.sorted { lhs, rhs in
            let primary = key == .cpu
                ? compare(lhs.cpu, rhs.cpu)
                : compare(lhs.resident, rhs.resident)
            if primary != .orderedSame { return primary == .orderedDescending }
            let secondary = key == .cpu
                ? compare(lhs.resident, rhs.resident)
                : compare(lhs.cpu, rhs.cpu)
            if secondary != .orderedSame { return secondary == .orderedDescending }
            return lhs.pid < rhs.pid
        }
        return Array(sorted.prefix(count))
    }

    private static func compare<T: Comparable>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        lhs < rhs ? .orderedAscending : (lhs > rhs ? .orderedDescending : .orderedSame)
    }

    // MARK: - Formatting

    /// "0%", "1.2%", "46%", "250%".
    static func formatCPU(_ value: Double) -> String {
        let percent = max(value, 0) * 100
        if percent < 0.05 { return "0%" }
        if percent < 9.95 { return String(format: "%.1f%%", percent) }
        return String(format: "%.0f%%", percent)
    }

    /// Binary units, as Activity Monitor shows them: "5.4 MB", "512 MB", "1.2 GB".
    static func formatMemory(_ bytes: UInt64) -> String {
        if bytes == 0 { return "0 MB" }
        let gigabytes = Double(bytes) / 1_073_741_824
        if gigabytes >= 1 { return String(format: "%.1f GB", gigabytes) }
        let megabytes = Double(bytes) / 1_048_576
        if megabytes < 9.95 { return String(format: "%.1f MB", megabytes) }
        return String(format: "%.0f MB", megabytes)
    }
}

/// Mach absolute time → nanoseconds. On Intel the timebase is 1/1; on
/// Apple silicon one tick is 125/3 ns, and libproc's task times are in ticks.
enum MachTime {
    static func nanoseconds(_ ticks: UInt64, numer: UInt32, denom: UInt32) -> UInt64 {
        guard numer != denom, denom != 0 else { return ticks }
        let product = ticks.multipliedFullWidth(by: UInt64(numer))
        // Saturate rather than trap when the result would not fit.
        guard product.high < UInt64(denom) else { return .max }
        return UInt64(denom).dividingFullWidth(product).quotient
    }
}
