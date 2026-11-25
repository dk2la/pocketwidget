import XCTest

/// Where the Settings page list goes for a given panel width.
final class SettingsLayoutTests: XCTestCase {
    func testThresholdIs560() {
        XCTAssertEqual(SettingsLayout.sidebarMinWidth, 560)
    }

    func testJustBelowThresholdUsesTopStrip() {
        XCTAssertEqual(SettingsLayout.mode(forWidth: 559), .topStrip)
    }

    func testAtThresholdUsesSidebar() {
        XCTAssertEqual(SettingsLayout.mode(forWidth: 560), .sidebar)
    }

    func testMinimumPanelWidthUsesTopStrip() {
        XCTAssertEqual(SettingsLayout.mode(forWidth: 300), .topStrip)
    }

    func testWidePanelUsesSidebar() {
        XCTAssertEqual(SettingsLayout.mode(forWidth: 900), .sidebar)
    }
}
