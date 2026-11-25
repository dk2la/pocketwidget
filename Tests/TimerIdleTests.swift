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

    func testAlarmIsSetForTheNextSuchClockTime() throws {
        let timer = TimerService()
        // The next full hour that is not this one: always minutes away.
        let hour = (Calendar.current.component(.hour, from: Date()) + 2) % 24
        timer.setAlarm(hour: hour, minute: 0)
        let date = try XCTUnwrap(timer.alarmDate)
        XCTAssertGreaterThan(date, Date())
        XCTAssertLessThanOrEqual(date.timeIntervalSinceNow, 24 * 60 * 60)
        XCTAssertEqual(Calendar.current.component(.hour, from: date), hour)
        timer.cancelAlarm()
        XCTAssertNil(timer.alarmDate)
    }

    func testAlarmAndCountdownDoNotTouchEachOther() {
        let timer = TimerService()
        let hour = (Calendar.current.component(.hour, from: Date()) + 2) % 24
        timer.setAlarm(hour: hour, minute: 0)
        XCTAssertTrue(timer.isIdle, "an alarm does not start the countdown")
        timer.start()
        timer.reset()
        XCTAssertNotNil(timer.alarmDate, "resetting the countdown keeps the alarm")
        timer.cancelAlarm()
    }

    func testNewLengthIsIdle() {
        let timer = TimerService()
        timer.setDuration(600)
        XCTAssertTrue(timer.isIdle)
    }
}
