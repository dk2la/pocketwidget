import XCTest

/// Launches Pocket in its UI-test state and finds the widget strip.
///
/// Pocket is an accessory app (LSUIElement): no Dock icon, no main window,
/// and the widget is a borderless NSPanel. Such panels do not always show
/// up under `app.windows`, so queries go through `descendants(matching:)`
/// by identifier, with generous waits: a fresh CI runner is slow to bring
/// the panel up.
final class WidgetSmokeUITests: XCTestCase {
    /// Modules enabled on a fresh install (`ModuleTab.defaultTabs`). The
    /// test bundle cannot see app types, so the list is repeated here.
    private static let defaultModules = [
        "playbooks", "calendar", "email", "clipboard", "notes", "assistant", "hotkeys", "settings",
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Pocket on a throwaway defaults suite: no tour, no licensing, no
    /// access prompts. See UITestMode.swift.
    @MainActor
    private func launchPocket() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        addTeardownBlock { @MainActor in app.terminate() }
        return app
    }

    @MainActor
    func testStripShowsDefaultModules() {
        let app = launchPocket()
        let strip = app.descendants(matching: .any)["widget.strip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 20), "widget strip did not appear")

        for module in Self.defaultModules {
            let icon = app.descendants(matching: .any)["strip.icon.\(module)"]
            XCTAssertTrue(icon.waitForExistence(timeout: 5), "strip icon \(module) missing")
        }
    }
}
