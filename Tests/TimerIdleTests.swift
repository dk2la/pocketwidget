import XCTest

/// The Timer module shows its desk clock only while the timer is idle:
/// nothing counting down and nothing paused partway.
@MainActor
final class TimerIdleTests: XCTestCase {
    // MARK: - Rule

    func testFullCountdownNotRunningIsIdle() {
        XCTAssertTrue(TimerService.isIdle(isRunning: false, remaining: 1500, duration: 1500))
    }

    func testRunningIsNotIdle() {
        XCTAssertFalse(TimerService.isIdle(isRunning: true, remaining: 1500, duration: 1500))
        XCTAssertFalse(TimerService.isIdle(isRunning: true, remaining: 900, duration: 1500))
    }

    func testPausedPartwayIsNotIdle() {
        XCTAssertFalse(TimerService.isIdle(isRunning: false, remaining: 900, duration: 1500))
    }

    // MARK: - Service

    func testFreshTimerIsIdle() {
        XCTAssertTrue(TimerService().isIdle)
    }

    func testStartAndResetFlipIdle() {
        let timer = TimerService()
        timer.start()
        XCTAssertFalse(timer.isIdle)
        timer.reset()
        XCTAssertTrue(timer.isIdle)
    }

    func testAlarmIsNotIdleUntilReset() {
        let timer = TimerService()
        // The next full hour that is not this one: always minutes away.
        let hour = (Calendar.current.component(.hour, from: Date()) + 2) % 24
        timer.ring(atHour: hour, minute: 0)
        XCTAssertTrue(timer.isAlarm)
        XCTAssertFalse(timer.isIdle)
        timer.reset()
        XCTAssertTrue(timer.isIdle)
    }

    func testNewLengthIsIdle() {
        let timer = TimerService()
        timer.setDuration(600)
        XCTAssertTrue(timer.isIdle)
    }
}
