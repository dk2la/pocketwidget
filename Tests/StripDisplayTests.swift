import XCTest

/// Which display the strip goes to, decided over fake screens: a MacBook
/// with a camera housing and an external monitor to its right.
final class StripDisplayTests: XCTestCase {
    private let laptop = DisplayInfo(
        id: "laptop",
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
        isBuiltIn: true,
        hasCameraHousing: true
    )
    private let monitor = DisplayInfo(
        id: "monitor",
        frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1415),
        isBuiltIn: false,
        hasCameraHousing: false
    )
    private let secondMonitor = DisplayInfo(
        id: "second",
        frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1055),
        isBuiltIn: false,
        hasCameraHousing: false
    )

    // MARK: - Saved display present

    func testSavedDisplayIsUsedWhileConnected() {
        let choice = StripDisplay.choose(savedID: "monitor", among: [laptop, monitor], mainID: "laptop")
        XCTAssertEqual(choice?.display, monitor)
        XCTAssertEqual(choice?.savedID, "monitor", "the saved choice is left alone")
    }

    func testSavedDisplayWinsOverTheMainAndTheBuiltInOne() {
        let choice = StripDisplay.choose(
            savedID: "second",
            among: [laptop, monitor, secondMonitor],
            mainID: "monitor"
        )
        XCTAssertEqual(choice?.display, secondMonitor)
    }

    func testSavedBuiltInDisplayStaysWhenAMonitorIsTheMainOne() {
        let choice = StripDisplay.choose(savedID: "laptop", among: [laptop, monitor], mainID: "monitor")
        XCTAssertEqual(choice?.display, laptop)
        XCTAssertEqual(choice?.savedID, "laptop")
    }

    // MARK: - Saved display gone

    func testGoneDisplayFallsBackToTheBuiltInScreen() {
        let choice = StripDisplay.choose(savedID: "monitor", among: [laptop], mainID: "laptop")
        XCTAssertEqual(choice?.display, laptop)
    }

    func testBuiltInScreenIsPreferredOverTheMainOne() {
        let choice = StripDisplay.choose(
            savedID: "monitor",
            among: [secondMonitor, laptop],
            mainID: "second"
        )
        XCTAssertEqual(choice?.display, laptop)
    }

    func testWithoutABuiltInScreenTheMainOneIsUsed() {
        // A desktop Mac, or a MacBook with its lid closed.
        let choice = StripDisplay.choose(
            savedID: "gone",
            among: [monitor, secondMonitor],
            mainID: "second"
        )
        XCTAssertEqual(choice?.display, secondMonitor)
        XCTAssertEqual(choice?.savedID, "second")
    }

    func testWithoutAMainScreenTheFirstOneIsUsed() {
        let choice = StripDisplay.choose(savedID: "gone", among: [monitor, secondMonitor], mainID: nil)
        XCTAssertEqual(choice?.display, monitor)
    }

    func testFallbackRewritesTheSavedChoice() {
        let choice = StripDisplay.choose(savedID: "monitor", among: [laptop], mainID: "laptop")
        XCTAssertEqual(choice?.savedID, "laptop")
    }

    func testStripDoesNotJumpBackWhenTheDisplayReturns() {
        // Unplug: the strip moves to the laptop and the choice is rewritten.
        let unplugged = StripDisplay.choose(savedID: "monitor", among: [laptop], mainID: "laptop")
        // Plug back in: the rewritten choice keeps it on the laptop.
        let replugged = StripDisplay.choose(
            savedID: unplugged?.savedID,
            among: [laptop, monitor],
            mainID: "monitor"
        )
        XCTAssertEqual(replugged?.display, laptop)
        XCTAssertEqual(replugged?.savedID, "laptop")
    }

    // MARK: - Nothing saved (installs from before 0.3.0)

    func testNothingSavedUsesTheDisplayWithACameraHousing() {
        let choice = StripDisplay.choose(savedID: nil, among: [monitor, laptop], mainID: "monitor")
        XCTAssertEqual(choice?.display, laptop)
    }

    func testNothingSavedWithoutACameraHousingUsesTheMainDisplay() {
        let choice = StripDisplay.choose(savedID: nil, among: [monitor, secondMonitor], mainID: "second")
        XCTAssertEqual(choice?.display, secondMonitor)
    }

    func testNothingSavedStaysUnsaved() {
        // Until the strip is dragged it keeps following the old rule, so a
        // screen change alone must not pin it anywhere.
        let choice = StripDisplay.choose(savedID: nil, among: [laptop, monitor], mainID: "monitor")
        XCTAssertNil(choice?.savedID)
    }

    // MARK: - No displays

    func testNoDisplaysGivesNoChoice() {
        XCTAssertNil(StripDisplay.choose(savedID: "monitor", among: [], mainID: nil))
        XCTAssertNil(StripDisplay.choose(savedID: nil, among: [], mainID: nil))
    }

    // MARK: - Same edge and offset on the fallback display

    func testFallbackKeepsTheEdgeAndOffset() throws {
        let edge = WidgetEdge.right
        let offset = 0.25
        let before = WidgetGeometry.stripFrame(edge: edge, offset: offset, iconCount: 5, in: monitor.visibleFrame)
        XCTAssertTrue(monitor.visibleFrame.contains(before))

        let fallback = try XCTUnwrap(StripDisplay.choose(savedID: "monitor", among: [laptop], mainID: "laptop"))
        let after = WidgetGeometry.stripFrame(
            edge: edge,
            offset: offset,
            iconCount: 5,
            in: fallback.display.visibleFrame
        )
        XCTAssertTrue(laptop.visibleFrame.contains(after), "the strip lands fully on the built-in screen")

        let placement = WidgetGeometry.nearestPlacement(for: after, in: laptop.visibleFrame)
        XCTAssertEqual(placement.edge, edge)
        XCTAssertEqual(placement.offset, offset, accuracy: 0.001)
    }

    // MARK: - Panel size limits

    func testPanelLimitsComeFromTheStripDisplay() {
        // A wide panel fits the monitor but not the laptop.
        XCTAssertEqual(WidgetGeometry.clampedPanelWidth(900, screenFrame: monitor.frame), 900)
        XCTAssertEqual(
            WidgetGeometry.clampedPanelWidth(900, screenFrame: CGRect(x: 0, y: 0, width: 800, height: 600)),
            720
        )
        XCTAssertEqual(WidgetGeometry.clampedPanelHeight(1200, visibleFrame: monitor.visibleFrame), 1200)
        XCTAssertEqual(
            WidgetGeometry.clampedPanelHeight(1200, visibleFrame: laptop.visibleFrame),
            laptop.visibleFrame.height - 2 * WidgetMetrics.edgeInset
        )
    }

    func testPanelLimitsKeepTheMinimumAndTheFixedMaximum() {
        XCTAssertEqual(WidgetGeometry.clampedPanelWidth(10, screenFrame: monitor.frame), WidgetMetrics.panelMinWidth)
        XCTAssertEqual(WidgetGeometry.clampedPanelWidth(5000, screenFrame: monitor.frame), WidgetMetrics.panelMaxWidth)
        XCTAssertEqual(
            WidgetGeometry.clampedPanelHeight(10, visibleFrame: monitor.visibleFrame),
            WidgetMetrics.panelMinHeight
        )
        XCTAssertEqual(
            WidgetGeometry.clampedPanelHeight(5000, visibleFrame: monitor.visibleFrame),
            WidgetMetrics.panelMaxHeight
        )
        // No display known: only the fixed limits apply.
        XCTAssertEqual(WidgetGeometry.clampedPanelWidth(5000, screenFrame: nil), WidgetMetrics.panelMaxWidth)
        XCTAssertEqual(WidgetGeometry.clampedPanelHeight(5000, visibleFrame: nil), WidgetMetrics.panelMaxHeight)
    }

    func testOpenPanelStaysOnTheStripDisplay() {
        for edge in [WidgetEdge.left, .right, .top, .bottom] {
            let layout = WidgetGeometry.expandedLayout(
                edge: edge,
                offset: 0.9,
                iconCount: 6,
                panelSize: CGSize(width: 900, height: 1200),
                in: monitor.visibleFrame
            )
            XCTAssertTrue(
                monitor.visibleFrame.contains(layout.window),
                "\(edge) panel must not spill onto the neighbouring display"
            )
        }
    }
}
