import XCTest

/// Which icons the strip shows and in what order. Settings is a module like
/// the others, except that it can never be switched off.
final class StripLineupTests: XCTestCase {
    /// Every module 0.3.0 knew, in a user-arranged order.
    private let oldOrder: [ModuleTab] = [
        .notes, .playbooks, .calendar, .email, .clipboard, .assistant,
        .hotkeys, .chats, .media, .timer, .shelf, .metrics,
    ]

    // MARK: - Order

    func testFreshInstallHasSettingsAtTheEndOfTheDefaultOrder() {
        let order = StripLineup.loadedOrder(stored: [])
        XCTAssertEqual(order.last, .settings)
        XCTAssertEqual(Set(order), Set(ModuleTab.allCases))
        XCTAssertEqual(order.count, ModuleTab.allCases.count, "no module twice")
    }

    func testUpgradeAppendsSettingsToTheStoredOrder() {
        XCTAssertEqual(StripLineup.loadedOrder(stored: oldOrder), oldOrder + [.settings])
    }

    func testSettingsKeepsTheSpotTheUserDraggedItTo() {
        var stored = oldOrder
        stored.insert(.settings, at: 2)
        XCTAssertEqual(StripLineup.loadedOrder(stored: stored), stored)
    }

    func testOtherMissingModulesStillArriveBeforeSettings() {
        let stored: [ModuleTab] = [.notes, .email]
        let order = StripLineup.loadedOrder(stored: stored)
        XCTAssertEqual(Array(order.prefix(2)), stored)
        XCTAssertEqual(order.last, .settings)
        XCTAssertEqual(order.count, ModuleTab.allCases.count)
    }

    // MARK: - Enabled set

    func testLoadingStoredModulesAlwaysAddsSettings() {
        XCTAssertEqual(StripLineup.loadedEnabled([.notes, .email]), [.notes, .email, .settings])
    }

    func testSettingsCannotBeSwitchedOff() {
        let enabled: Set<ModuleTab> = [.notes, .email, .settings]
        XCTAssertFalse(StripLineup.canToggle(.settings, enabled: enabled))
        XCTAssertEqual(StripLineup.toggled(.settings, in: enabled), enabled)
    }

    func testModulesSwitchOnAndOff() {
        let enabled: Set<ModuleTab> = [.notes, .email, .settings]
        XCTAssertEqual(StripLineup.toggled(.email, in: enabled), [.notes, .settings])
        XCTAssertEqual(StripLineup.toggled(.timer, in: enabled), [.notes, .email, .timer, .settings])
    }

    func testLastModuleRuleIgnoresSettings() {
        // Settings alone is not module content: the last real module stays.
        let enabled: Set<ModuleTab> = [.notes, .settings]
        XCTAssertFalse(StripLineup.canToggle(.notes, enabled: enabled))
        XCTAssertEqual(StripLineup.toggled(.notes, in: enabled), enabled)
        XCTAssertTrue(StripLineup.canToggle(.email, enabled: enabled), "switching one on is always fine")
    }

    // MARK: - Visible icons

    func testVisibleIconsFollowTheOrderAndSkipDisabledModules() {
        let order: [ModuleTab] = [.timer, .notes, .settings, .email, .media]
        let enabled: Set<ModuleTab> = [.notes, .email, .settings]
        XCTAssertEqual(StripLineup.visible(order: order, enabled: enabled), [.notes, .settings, .email])
    }
}
