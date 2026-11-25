import AppKit
import XCTest

/// Settings as a widget module, the tour and the event pill (#143).
///
/// Same ground rules as WidgetSmokeUITests: Pocket is an accessory app whose
/// windows are borderless panels, so everything is found by identifier
/// through `descendants(matching:)`, with generous waits for a slow runner.
final class SettingsModuleUITests: XCTestCase {
    private static let settingsPages = [
        "general", "license", "appearance", "modules", "accounts", "playbooks", "hotkeys",
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Pocket on a throwaway defaults suite (see UITestMode.swift), plus
    /// `extra` launch arguments.
    @MainActor
    private func launchPocket(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + extra
        app.launch()
        addTeardownBlock { @MainActor in app.terminate() }
        return app
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// Opens Settings from its strip icon and waits for the panel.
    @MainActor
    private func openSettings(in app: XCUIApplication) -> XCUIElement {
        let icon = element("strip.icon.settings", in: app)
        XCTAssertTrue(icon.waitForExistence(timeout: 20), "Settings icon did not appear")
        icon.click()
        let panel = element("panel.settings", in: app)
        XCTAssertTrue(panel.waitForExistence(timeout: 10), "Settings panel did not open")
        return panel
    }

    /// Waits until `element` is gone.
    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    // MARK: - Settings module

    @MainActor
    func testSettingsIconOpensAndClosesTheSettingsPanel() {
        let app = launchPocket()
        let panel = openSettings(in: app)
        for page in Self.settingsPages {
            XCTAssertTrue(
                element("settings.page.\(page)", in: app).waitForExistence(timeout: 5),
                "page button \(page) missing"
            )
        }

        element("strip.icon.settings", in: app).click()
        XCTAssertTrue(waitForDisappearance(of: panel, timeout: 10), "Settings panel did not close")
    }

    /// ⌃⌥M is a Carbon global hotkey. The key press goes to Finder, not to
    /// Pocket: an accessory app with no key window has no keyboard focus
    /// for XCUITest to type into, while a global hotkey fires whichever app
    /// is in front.
    @MainActor
    func testHotkeyOpensSettingsFromAMinimizedWidget() {
        let app = launchPocket(["--minimized"])
        XCTAssertTrue(element("widget.strip", in: app).waitForExistence(timeout: 20), "widget strip did not appear")
        // Minimized, the strip keeps only its first module button.
        XCTAssertTrue(
            waitForDisappearance(of: element("strip.icon.settings", in: app), timeout: 10),
            "widget did not start minimized"
        )

        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        finder.typeKey("m", modifierFlags: [.control, .option])

        XCTAssertTrue(element("panel.settings", in: app).waitForExistence(timeout: 10), "⌃⌥M did not open Settings")
        XCTAssertTrue(element("strip.icon.settings", in: app).exists, "the widget was not restored")
    }

    @MainActor
    func testModulesPageHasNoSwitchForSettings() {
        let app = launchPocket()
        _ = openSettings(in: app)
        element("settings.page.modules", in: app).click()

        XCTAssertTrue(
            element("settings.modules.toggle.calendar", in: app).waitForExistence(timeout: 10),
            "module switches did not appear"
        )
        XCTAssertFalse(element("settings.modules.toggle.settings", in: app).exists, "Settings has a switch")
    }

    /// The panel opens at 720 wide on a right-docked strip, so dragging the
    /// width grip (on its left edge) 300 to the right leaves it below 560.
    @MainActor
    func testNarrowSettingsPanelPutsThePagesOnTop() {
        let app = launchPocket()
        _ = openSettings(in: app)
        XCTAssertTrue(element("settings.pages.sidebar", in: app).waitForExistence(timeout: 5), "sidebar missing")

        let grip = element("panel.grip.width", in: app)
        XCTAssertTrue(grip.waitForExistence(timeout: 5), "width grip missing")
        let start = grip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.3, thenDragTo: start.withOffset(CGVector(dx: 300, dy: 0)))

        XCTAssertTrue(element("settings.pages.strip", in: app).waitForExistence(timeout: 10), "page strip did not appear")
    }

    // MARK: - Live events

    @MainActor
    func testDemoSampleEventShowsThePillThenHidesIt() {
        let app = launchPocket(["--demo"])
        let panel = openSettings(in: app)
        // General is the first page; the sample buttons close its section.
        let button = element("settings.demo.event.pwr", in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 10), "sample event buttons missing")
        for _ in 0..<6 where !button.isHittable {
            panel.scroll(byDeltaX: 0, deltaY: -300)
        }
        button.click()

        let pill = element("event.pill", in: app)
        XCTAssertTrue(pill.waitForExistence(timeout: 10), "event pill did not appear")
        // Shown for 2.5 s, then slides back in.
        XCTAssertTrue(waitForDisappearance(of: pill, timeout: 15), "event pill did not go away")
    }

    // MARK: - Tour and the capsule

    @MainActor
    func testOnboardingArgumentShowsTheTourInTheWidget() {
        let app = launchPocket(["--onboarding"])
        XCTAssertTrue(element("panel.tour", in: app).waitForExistence(timeout: 20), "tour did not open")
    }

    /// The capsule is gone: nothing of Pocket's hangs from the top centre
    /// of the main screen.
    @MainActor
    func testNoWindowAtTheTopCentreOfTheScreen() throws {
        let app = launchPocket()
        let strip = element("widget.strip", in: app)
        XCTAssertTrue(strip.waitForExistence(timeout: 20), "widget strip did not appear")
        // Room for anything a late window controller might put up.
        _ = XCTWaiter().wait(for: [XCTestExpectation(description: "settle")], timeout: 3)

        let screen = try XCTUnwrap(NSScreen.main?.frame)
        // XCUITest frames are top-left based; the capsule sat in a band of
        // about this size under the camera housing.
        let topCentre = CGRect(x: screen.midX - 150, y: 0, width: 300, height: 48)
        let surfaces = app.windows.allElementsBoundByIndex + [strip]
        for surface in surfaces where surface.exists {
            XCTAssertFalse(
                surface.frame.intersects(topCentre),
                "a Pocket surface sits at the top centre: \(surface.frame)"
            )
        }
    }
}
