import XCTest

/// What the widget panel shows, which strip icon it lights, and the rules
/// the welcome tour and the Settings hotkey hang on.
final class WidgetPanelContentTests: XCTestCase {
    // MARK: - Content

    func testNoSelectedTabMeansNoPanel() {
        XCTAssertNil(WidgetPanelContent.resolve(selectedTab: nil, showsTour: false, locked: false))
        XCTAssertNil(WidgetPanelContent.resolve(selectedTab: nil, showsTour: true, locked: true))
    }

    func testModuleAndSettings() {
        XCTAssertEqual(WidgetPanelContent.resolve(selectedTab: .notes, showsTour: false, locked: false), .module(.notes))
        XCTAssertEqual(WidgetPanelContent.resolve(selectedTab: .settings, showsTour: false, locked: false), .settings)
    }

    func testTourRidesTheSettingsSlot() {
        XCTAssertEqual(WidgetPanelContent.resolve(selectedTab: .settings, showsTour: true, locked: false), .tour)
    }

    func testLockScreenWinsOverEverything() {
        for tab in [ModuleTab.notes, .settings] {
            for tour in [false, true] {
                XCTAssertEqual(WidgetPanelContent.resolve(selectedTab: tab, showsTour: tour, locked: true), .lockScreen)
            }
        }
    }

    // MARK: - Strip highlight

    func testTourAndLockScreenLightNoIcon() {
        XCTAssertNil(WidgetPanelContent.tour.highlightedTab)
        XCTAssertNil(WidgetPanelContent.lockScreen.highlightedTab)
        XCTAssertEqual(WidgetPanelContent.settings.highlightedTab, .settings)
        XCTAssertEqual(WidgetPanelContent.module(.timer).highlightedTab, .timer)
    }

    // MARK: - Auto-close

    func testTourNeverClosesOnOutsideClickOrLeave() {
        XCTAssertFalse(WidgetPanelContent.tour.autoCloses(closeOnOutsideClick: true))
    }

    func testOtherContentFollowsTheSetting() {
        for content in [WidgetPanelContent.settings, .module(.notes), .lockScreen] {
            XCTAssertTrue(content.autoCloses(closeOnOutsideClick: true))
            XCTAssertFalse(content.autoCloses(closeOnOutsideClick: false))
        }
    }

    // MARK: - Settings hotkey (⌃⌥M)

    func testHotkeyClosesSettingsTourAndLockScreen() {
        XCTAssertTrue(WidgetPanelContent.hotkeyCloses(.settings))
        XCTAssertTrue(WidgetPanelContent.hotkeyCloses(.tour))
        XCTAssertTrue(WidgetPanelContent.hotkeyCloses(.lockScreen))
    }

    func testHotkeyOpensSettingsOverAModuleOrNothing() {
        XCTAssertFalse(WidgetPanelContent.hotkeyCloses(.module(.notes)))
        XCTAssertFalse(WidgetPanelContent.hotkeyCloses(nil))
    }

    // MARK: - Settings slot

    func testUnlockedSettingsOpensInItsOwnSlot() {
        XCTAssertEqual(WidgetPanelContent.settingsSlot(locked: false, firstTab: .notes), .settings)
    }

    func testLockedSettingsOpensTheLockScreenWhereTheLockButtonDoes() {
        XCTAssertEqual(WidgetPanelContent.settingsSlot(locked: true, firstTab: .notes), .notes)
        XCTAssertEqual(WidgetPanelContent.settingsSlot(locked: true, firstTab: nil), .settings)
    }
}
