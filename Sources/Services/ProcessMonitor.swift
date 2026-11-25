import Darwin
import Foundation
import Observation

/// Thin libproc reader: one pass over every process this user may inspect.
/// Others' processes (and the kernel) fail `proc_pidinfo` without root and
/// are skipped silently.
enum ProcessReader {
    static func snapshot() -> ProcessSnapshot {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let nanos = { (ticks: UInt64) in
            MachTime.nanoseconds(ticks, numer: timebase.numer, denom: timebase.denom)
        }

        // The count can grow between the two calls; leave headroom.
        let estimate = max(Int(proc_listallpids(nil, 0)), 0) + 64
        var pids = [pid_t](repeating: 0, count: estimate)
        let listed = pids.withUnsafeMutableBytes { buffer in
            Int(proc_listallpids(buffer.baseAddress, Int32(buffer.count)))
        }

        var entries: [ProcessSnapshot.Entry] = []
        entries.reserveCapacity(max(listed, 0))
        let infoSize = Int32(MemoryLayout<proc_taskinfo>.size)
        for pid in pids.prefix(max(listed, 0)) where pid > 0 {
            var info = proc_taskinfo()
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, infoSize) == infoSize else { continue }
            entries.append(ProcessSnapshot.Entry(
                pid: pid,
                name: name(of: pid),
                cpuTime: nanos(info.pti_total_user &+ info.pti_total_system),
                resident: info.pti_resident_size
            ))
        }
        return ProcessSnapshot(takenAt: nanos(mach_absolute_time()), processes: entries)
    }

    private static func name(of pid: pid_t) -> String {
        var short = [CChar](repeating: 0, count: Int(MAXCOMLEN) * 2 + 1)
        let shortName = proc_name(pid, &short, UInt32(short.count)) > 0 ? string(short) : "\(pid)"
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let pathName = proc_pidpath(pid, &path, UInt32(path.count)) > 0 ? string(path) : nil
        return ProcessName.display(path: pathName, shortName: shortName)
    }

    private static func string(_ buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }
}

/// Per-process CPU and memory for the System module's top list. Polls only
/// while an observer is registered, like `SystemStatsService`.
@MainActor
@Observable
final class ProcessMonitor {
    /// Every readable process at the last pass.
    private(set) var loads: [ProcessLoad] = []

    @ObservationIgnored private(set) var observerCount = 0
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var previous: ProcessSnapshot?

    func beginObserving() {
        observerCount += 1
        guard observerCount == 1, pollTask == nil else { return }
        pollTask = Task { [weak self] in
            // The first pass is only a baseline, so the second follows quickly.
            var interval: Duration = .milliseconds(500)
            while !Task.isCancelled {
                await self?.sample()
                try? await Task.sleep(for: interval)
                interval = .seconds(2)
            }
        }
    }

    /// The baseline is dropped: after a pause, old CPU times would average
    /// the whole gap into one reading.
    func endObserving() {
        observerCount = max(0, observerCount - 1)
        guard observerCount == 0 else { return }
        pollTask?.cancel()
        pollTask = nil
        previous = nil
    }

    private func sample() async {
        // Several hundred syscalls: off the main thread.
        let current = await Task.detached(priority: .utility) { ProcessReader.snapshot() }.value
        guard pollTask != nil else { return }
        // A baseline-only pass reads 0 % everywhere; keep the last list
        // on screen rather than flash a memory-ordered one.
        if previous != nil || loads.isEmpty {
            loads = ProcessLoad.loads(previous: previous, current: current)
        }
        previous = current
    }
}
