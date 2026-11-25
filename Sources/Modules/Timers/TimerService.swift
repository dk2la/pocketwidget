import AppKit
import Observation
import OSLog

/// Single countdown timer. Wall-clock based, so it stays correct through
/// display sleep and timer-tick coalescing.
@MainActor
@Observable
final class TimerService {
    private(set) var duration: TimeInterval = 25 * 60
    private(set) var remaining: TimeInterval = 25 * 60
    private(set) var isRunning = false
    /// The running countdown was set as an alarm for a clock time.
    private(set) var isAlarm = false

    /// The capsule flips between closed and compact on these.
    @ObservationIgnored var onRunningChanged: (() -> Void)?
    @ObservationIgnored var onFinished: (() -> Void)?

    @ObservationIgnored private var endDate: Date?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.dk2la.pocket", category: "timer")

    static let presets: [TimeInterval] = [5 * 60, 10 * 60, 25 * 60, 45 * 60, 60 * 60]

    /// Nothing to show yet: no countdown or alarm going, and none paused
    /// partway. The module shows its empty screen exactly then.
    var isIdle: Bool {
        Self.isIdle(isRunning: isRunning, remaining: remaining, duration: duration)
    }

    nonisolated static func isIdle(
        isRunning: Bool, remaining: TimeInterval, duration: TimeInterval
    ) -> Bool {
        !isRunning && remaining >= duration
    }

    func setDuration(_ newDuration: TimeInterval) {
        guard !isRunning else { return }
        duration = newDuration
        remaining = newDuration
    }

    /// Alarm: counts down to the next time the clock shows this hour and
    /// minute, replacing whatever was running.
    func ring(atHour hour: Int, minute: Int) {
        let components = DateComponents(hour: hour, minute: minute, second: 0)
        guard let target = Calendar.current.nextDate(
            after: Date(), matching: components, matchingPolicy: .nextTime
        ) else { return }
        pause()
        setDuration(target.timeIntervalSinceNow)
        start()
        isAlarm = true
    }

    func start() {
        guard !isRunning, remaining > 0 else { return }
        isRunning = true
        endDate = Date().addingTimeInterval(remaining)
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                self?.tick()
            }
        }
        log.info("started, \(Int(self.remaining), privacy: .public)s")
        onRunningChanged?()
    }

    func pause() {
        guard isRunning else { return }
        isRunning = false
        isAlarm = false
        tickTask?.cancel()
        endDate = nil
        onRunningChanged?()
    }

    func reset() {
        pause()
        remaining = duration
    }

    private func tick() {
        guard isRunning, let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0 {
            finish()
        }
    }

    private func finish() {
        isRunning = false
        isAlarm = false
        tickTask?.cancel()
        endDate = nil
        remaining = duration
        NSSound(named: "Glass")?.play()
        onFinished?()
        onRunningChanged?()
    }
}
