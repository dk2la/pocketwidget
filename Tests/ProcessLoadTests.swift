import XCTest

/// The System module's "top processes" list: CPU % from two libproc
/// snapshots, the ranking, and how the values read.
final class ProcessLoadTests: XCTestCase {
    private func snapshot(at seconds: Double, _ entries: [(Int32, Double, UInt64)]) -> ProcessSnapshot {
        ProcessSnapshot(
            takenAt: UInt64(seconds * 1e9),
            processes: entries.map {
                ProcessSnapshot.Entry(pid: $0.0, name: "p\($0.0)", cpuTime: UInt64($0.1 * 1e9), resident: $0.2)
            }
        )
    }

    // MARK: - CPU from two samples

    func testCPUIsTimeDeltaOverWallTime() {
        let old = snapshot(at: 10, [(1, 5, 0), (2, 1, 0)])
        let new = snapshot(at: 12, [(1, 6, 100), (2, 4, 200)])
        let loads = ProcessLoad.loads(previous: old, current: new)
        let byPid = Dictionary(uniqueKeysWithValues: loads.map { ($0.pid, $0) })
        XCTAssertEqual(byPid[1]?.cpu ?? -1, 0.5, accuracy: 1e-9)
        // More than one core: 3 s of CPU in 2 s of wall time.
        XCTAssertEqual(byPid[2]?.cpu ?? -1, 1.5, accuracy: 1e-9)
        XCTAssertEqual(byPid[2]?.resident, 200)
        XCTAssertEqual(byPid[2]?.name, "p2")
    }

    func testNewProcessHasNoCPUYetButKeepsMemory() {
        let old = snapshot(at: 0, [(1, 1, 0)])
        let new = snapshot(at: 2, [(1, 1, 0), (7, 30, 512)])
        let load = ProcessLoad.loads(previous: old, current: new).first { $0.pid == 7 }
        XCTAssertEqual(load?.cpu, 0)
        XCTAssertEqual(load?.resident, 512)
    }

    func testVanishedProcessIsDropped() {
        let old = snapshot(at: 0, [(1, 1, 0), (2, 1, 0)])
        let new = snapshot(at: 2, [(1, 2, 0)])
        XCTAssertEqual(ProcessLoad.loads(previous: old, current: new).map(\.pid), [1])
    }

    func testCounterGoingBackwardsReadsAsZero() {
        // A reused pid restarts its CPU time from zero.
        let old = snapshot(at: 0, [(3, 50, 0)])
        let new = snapshot(at: 2, [(3, 1, 0)])
        XCTAssertEqual(ProcessLoad.loads(previous: old, current: new).first?.cpu, 0)
    }

    func testNoBaselineOrNoElapsedTimeReadsAsZero() {
        let new = snapshot(at: 2, [(1, 9, 64)])
        XCTAssertEqual(ProcessLoad.loads(previous: nil, current: new).first?.cpu, 0)
        XCTAssertEqual(ProcessLoad.loads(previous: new, current: new).first?.cpu, 0)
        let earlier = snapshot(at: 1, [(1, 10, 64)])
        XCTAssertEqual(ProcessLoad.loads(previous: new, current: earlier).first?.cpu, 0)
    }

    func testMachTicksConvertWithTheTimebase() {
        // Apple silicon: 125/3 ns per tick.
        XCTAssertEqual(MachTime.nanoseconds(24_000_000, numer: 125, denom: 3), 1_000_000_000)
        XCTAssertEqual(MachTime.nanoseconds(42, numer: 1, denom: 1), 42)
        XCTAssertEqual(MachTime.nanoseconds(42, numer: 1, denom: 0), 42)
        // No overflow on large counters.
        XCTAssertEqual(MachTime.nanoseconds(UInt64.max / 2, numer: 125, denom: 125), UInt64.max / 2)
    }

    // MARK: - Ranking

    private func load(_ pid: Int32, cpu: Double, mem: UInt64) -> ProcessLoad {
        ProcessLoad(pid: pid, name: "p\(pid)", cpu: cpu, resident: mem)
    }

    func testTopByCPU() {
        let loads = [load(1, cpu: 0.1, mem: 900), load(2, cpu: 0.9, mem: 10), load(3, cpu: 0.5, mem: 50)]
        XCTAssertEqual(ProcessLoad.top(loads, by: .cpu, count: 2).map(\.pid), [2, 3])
    }

    func testTopByMemory() {
        let loads = [load(1, cpu: 0.1, mem: 900), load(2, cpu: 0.9, mem: 10), load(3, cpu: 0.5, mem: 50)]
        XCTAssertEqual(ProcessLoad.top(loads, by: .memory, count: 5).map(\.pid), [1, 3, 2])
    }

    func testTiesBreakOnTheOtherValueThenPid() {
        let loads = [load(9, cpu: 0, mem: 10), load(4, cpu: 0, mem: 30), load(2, cpu: 0, mem: 10)]
        XCTAssertEqual(ProcessLoad.top(loads, by: .cpu, count: 3).map(\.pid), [4, 2, 9])
        let same = [load(5, cpu: 0.2, mem: 1), load(3, cpu: 0.2, mem: 1)]
        XCTAssertEqual(ProcessLoad.top(same, by: .memory, count: 2).map(\.pid), [3, 5])
    }

    func testTopHandlesShortAndEmptyLists() {
        XCTAssertTrue(ProcessLoad.top([], by: .cpu, count: 5).isEmpty)
        XCTAssertEqual(ProcessLoad.top([load(1, cpu: 0, mem: 0)], by: .cpu, count: 5).count, 1)
        XCTAssertTrue(ProcessLoad.top([load(1, cpu: 0, mem: 0)], by: .cpu, count: 0).isEmpty)
    }

    func testSortKeyFollowsTheLargeChart() {
        XCTAssertEqual(ProcessSortKey(gauge: .cpu), .cpu)
        XCTAssertEqual(ProcessSortKey(gauge: .memory), .memory)
        for gauge in [Gauge.network, .battery, .volume] {
            XCTAssertEqual(ProcessSortKey(gauge: gauge), .cpu)
        }
    }

    // MARK: - Formatting

    func testCPUFormatting() {
        XCTAssertEqual(ProcessLoad.formatCPU(0), "0%")
        XCTAssertEqual(ProcessLoad.formatCPU(0.0004), "0%")
        XCTAssertEqual(ProcessLoad.formatCPU(0.0123), "1.2%")
        XCTAssertEqual(ProcessLoad.formatCPU(0.0996), "10%")
        XCTAssertEqual(ProcessLoad.formatCPU(0.456), "46%")
        XCTAssertEqual(ProcessLoad.formatCPU(2.5), "250%")
        XCTAssertEqual(ProcessLoad.formatCPU(-1), "0%")
    }

    func testMemoryFormatting() {
        XCTAssertEqual(ProcessLoad.formatMemory(0), "0 MB")
        XCTAssertEqual(ProcessLoad.formatMemory(300 * 1024), "0.3 MB")
        XCTAssertEqual(ProcessLoad.formatMemory(5 * 1_048_576 + 400_000), "5.4 MB")
        XCTAssertEqual(ProcessLoad.formatMemory(512 * 1_048_576), "512 MB")
        XCTAssertEqual(ProcessLoad.formatMemory(1_023 * 1_048_576), "1023 MB")
        XCTAssertEqual(ProcessLoad.formatMemory(1_288_490_189), "1.2 GB")
        XCTAssertEqual(ProcessLoad.formatMemory(20 * 1_073_741_824), "20.0 GB")
    }
}
