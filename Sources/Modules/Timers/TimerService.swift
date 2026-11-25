import AppKit
import Observation
import OSLog

/// One countdown timer and one alarm, independent of each other. Both are
/// wall-clock based, so they stay correct through display sleep and
/// timer-tick coalescing.
@MainActor
@Observable
final class TimerService {
    private(set) var duration: TimeInterval = 25 * 60
    private(set) var remaining: TimeInterval = 25 * 60
    private(set) var isRunning = false
    /// When the alarm rings; `nil` while none is set.
    private(set) var alarmDate: Date?

    /// The widget shows a "timer finished" event on this.
    @ObservationIgnored var onFinished: (() -> Void)?

    @ObservationIgnored private var endDate: Date?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var alarmTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.dk2la.pocket", category: "timer")

    static let presets: [TimeInterval] = [5 * 60, 10 * 60, 25 * 60, 45 * 60, 60 * 60]

    /// The countdown has nothing to show yet: not going, and not paused
    /// partway. The alarm is separate — see `alarmDate`.
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

    /// Sets the alarm for the next time the clock shows this hour and
    /// minute, replacing an earlier one. The countdown is left alone.
    func setAlarm(hour: Int, minute: Int) {
        let components = DateComponents(hour: hour, minute: minute, second: 0)
        guard let target = Calendar.current.nextDate(
            after: Date(), matching: components, matchingPolicy: .nextTime
        ) else { return }
        alarmTask?.cancel()
        alarmDate = target
        alarmTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.checkAlarm()
            }
        }
        log.info("alarm set")
    }

    func cancelAlarm() {
        alarmTask?.cancel()
        alarmTask = nil
        alarmDate = nil
    }

    private func checkAlarm() {
        guard let alarmDate, alarmDate <= Date() else { return }
        cancelAlarm()
        NSSound(named: "Glass")?.play()
        onFinished?()
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
    }

    func pause() {
        guard isRunning else { return }
        isRunning = false
        tickTask?.cancel()
        endDate = nil
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
        tickTask?.cancel()
        endDate = nil
        remaining = duration
        NSSound(named: "Glass")?.play()
        onFinished?()
    }
}
