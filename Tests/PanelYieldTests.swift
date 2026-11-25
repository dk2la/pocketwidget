import AppKit
import XCTest

/// While a window Pocket raised (a file picker, a consent dialog, System
/// Settings) is up, the widget yields: it drops below that window and
/// stays open. A yield always ends — by its owner or by its timeout.
@MainActor
final class PanelYieldTests: XCTestCase {
    private let start = ContinuousClock.now

    // MARK: - Ledger

    func testYieldHoldsThePanelAndLowersIt() {
        var ledger = HoldLedger()
        let id = ledger.beginYield(now: start, timeout: .seconds(60))
        XCTAssertTrue(ledger.isYielding)
        XCTAssertTrue(ledger.isHeld, "the panel stays open while a system window is up")
        ledger.endYield(id)
        XCTAssertFalse(ledger.isYielding)
        XCTAssertFalse(ledger.isHeld)
    }

    func testKeepOpenHoldDoesNotLowerThePanel() {
        var ledger = HoldLedger()
        ledger.beginKeepOpen()
        XCTAssertTrue(ledger.isHeld)
        XCTAssertFalse(ledger.isYielding, "an open editor is no reason to drop below other windows")
    }

    func testYieldsNestByIdentity() {
        var ledger = HoldLedger()
        let first = ledger.beginYield(now: start, timeout: .seconds(60))
        let second = ledger.beginYield(now: start, timeout: .seconds(60))
        ledger.endYield(first)
        ledger.endYield(first)
        XCTAssertTrue(ledger.isYielding, "ending one twice must not end the other")
        ledger.endYield(second)
        XCTAssertFalse(ledger.isYielding)
    }

    func testForgottenYieldExpiresAtItsTimeout() {
        var ledger = HoldLedger()
        _ = ledger.beginYield(now: start, timeout: .seconds(60))
        XCTAssertFalse(ledger.expire(now: start + .seconds(59)))
        XCTAssertTrue(ledger.isYielding)
        XCTAssertTrue(ledger.expire(now: start + .seconds(60)), "a stuck dialog call must not hold forever")
        XCTAssertFalse(ledger.isYielding)
        XCTAssertFalse(ledger.isHeld)
    }

    func testNextDeadlineIsTheEarliestOpenYield() {
        var ledger = HoldLedger()
        XCTAssertNil(ledger.nextDeadline)
        _ = ledger.beginYield(now: start, timeout: .seconds(300))
        let short = ledger.beginYield(now: start, timeout: .seconds(30))
        XCTAssertEqual(ledger.nextDeadline, start + .seconds(30))
        ledger.endYield(short)
        XCTAssertEqual(ledger.nextDeadline, start + .seconds(300))
    }

    // MARK: - Level

    func testLevelDropsToNormalOnlyWhileYielding() {
        XCTAssertEqual(PanelHold.level(yielding: false), .screenSaver)
        XCTAssertEqual(PanelHold.level(yielding: true), .normal)
    }

    // MARK: - Shared hold

    func testYieldingWorkLowersThePanelForItsDuration() async {
        let hold = PanelHold()
        var during = false
        await hold.yielding { during = hold.isYielding && hold.isHeld }
        XCTAssertTrue(during)
        XCTAssertFalse(hold.isYielding)
        XCTAssertFalse(hold.isHeld)
    }

    func testYieldChangesAreAnnounced() {
        let hold = PanelHold()
        var announced = 0
        let observer = NotificationCenter.default.addObserver(
            forName: PanelHold.yieldDidChange, object: hold, queue: nil
        ) { _ in announced += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        let yield = hold.beginYield()
        hold.end(yield)
        hold.end(yield)
        XCTAssertEqual(announced, 2, "once down, once up; a repeated end is silent")
    }

    // MARK: - System Settings visit

    func testVisitYieldsAtOnceAndUntilTheUserLeavesSettings() {
        var visit = SettingsVisit(settingsFrontmost: false)
        XCTAssertTrue(visit.yields, "the pane is on its way up")
        visit.handle(.otherAppActivated)
        XCTAssertTrue(visit.yields, "an app activating before Settings shows up is not the user leaving")
        visit.handle(.settingsActivated)
        XCTAssertTrue(visit.yields)
        visit.handle(.otherAppActivated)
        XCTAssertFalse(visit.yields, "the user went elsewhere: the widget comes back on top")
        XCTAssertFalse(visit.isOver)
        visit.handle(.settingsActivated)
        XCTAssertTrue(visit.yields, "back in Settings: drop below it again")
    }

    func testVisitEndsWhenSettingsQuits() {
        var visit = SettingsVisit(settingsFrontmost: true)
        visit.handle(.settingsQuit)
        XCTAssertTrue(visit.isOver)
        XCTAssertFalse(visit.yields)
    }

    func testVisitEndsIfSettingsNeverShowsUp() {
        var visit = SettingsVisit(settingsFrontmost: false)
        visit.handle(.launchWindowPassed)
        XCTAssertTrue(visit.isOver)
        XCTAssertFalse(visit.yields)
    }

    func testVisitToAlreadyFrontSettingsOutlastsTheLaunchWindow() {
        var visit = SettingsVisit(settingsFrontmost: true)
        visit.handle(.launchWindowPassed)
        XCTAssertFalse(visit.isOver)
        XCTAssertTrue(visit.yields)
    }

    func testVisitEndsAtItsTimeout() {
        var visit = SettingsVisit(settingsFrontmost: true)
        visit.handle(.timedOut)
        XCTAssertTrue(visit.isOver)
        XCTAssertFalse(visit.yields)
        visit.handle(.settingsActivated)
        XCTAssertFalse(visit.yields, "an ended visit stays ended")
    }
}
