import XCTest

/// The minimized strip must stay the same shape and keep exactly one module
/// button — the roll-up reads as the widget folding into itself.
final class WidgetGeometryTests: XCTestCase {
    func testMinimizedKeepsGripPlusOneButton() {
        let full = WidgetGeometry.stripLength(iconCount: 8)
        let mini = WidgetGeometry.stripLength(iconCount: 8, minimized: true)
        let oneIcon = WidgetGeometry.stripLength(iconCount: 1)
        XCTAssertEqual(mini, oneIcon, "minimized shows the first button, nothing else")
        XCTAssertLessThan(mini, full)
    }

    func testMinimizedKeepsFullThickness() {
        // Same width on a side dock: the pill must not get thinner, only
        // shorter, or the collapse reads as a shape change.
        for edge in [WidgetEdge.left, .right] {
            let full = WidgetGeometry.stripSize(iconCount: 6, edge: edge)
            let mini = WidgetGeometry.stripSize(iconCount: 6, edge: edge, minimized: true)
            XCTAssertEqual(mini.width, full.width)
            XCTAssertLessThan(mini.height, full.height)
        }
        for edge in [WidgetEdge.top, .bottom] {
            let full = WidgetGeometry.stripSize(iconCount: 6, edge: edge)
            let mini = WidgetGeometry.stripSize(iconCount: 6, edge: edge, minimized: true)
            XCTAssertEqual(mini.height, full.height)
            XCTAssertLessThan(mini.width, full.width)
        }
    }

    func testSingleTabWidgetDoesNotChangeSize() {
        // Nothing to fold away — the frame must stay put rather than jump.
        XCTAssertEqual(
            WidgetGeometry.stripLength(iconCount: 1, minimized: true),
            WidgetGeometry.stripLength(iconCount: 1)
        )
    }

    // MARK: - Settings panel

    /// A 14" MacBook's visible frame (menu bar taken off the top).
    private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 944)
    private let settingsSize = CGSize(width: 720, height: 520)

    private func settingsLayout(_ edge: WidgetEdge, in visibleFrame: CGRect) -> WidgetGeometry.ExpandedLayout {
        WidgetGeometry.expandedLayout(
            edge: edge,
            offset: 0.5,
            iconCount: 9,
            panelSize: WidgetGeometry.clampedPanelSize(
                WidgetMetrics.settingsPanelDefaultSize,
                screenFrame: visibleFrame,
                visibleFrame: visibleFrame
            ),
            in: visibleFrame
        )
    }

    func testSettingsPanelOpensAt720x520() {
        XCTAssertEqual(WidgetMetrics.settingsPanelDefaultSize, settingsSize)
        for edge in [WidgetEdge.left, .right, .top, .bottom] {
            XCTAssertEqual(settingsLayout(edge, in: laptop).panelLocal.size, settingsSize, "\(edge)")
        }
    }

    func testSettingsPanelOpensInwardFromTheStripOnEveryEdge() {
        let gap = WidgetMetrics.panelGap
        // Window-local coordinates are y-down.
        let left = settingsLayout(.left, in: laptop)
        XCTAssertEqual(left.panelLocal.minX, left.stripLocal.maxX + gap)
        let right = settingsLayout(.right, in: laptop)
        XCTAssertEqual(right.panelLocal.maxX + gap, right.stripLocal.minX)
        let top = settingsLayout(.top, in: laptop)
        XCTAssertEqual(top.panelLocal.minY, top.stripLocal.maxY + gap)
        let bottom = settingsLayout(.bottom, in: laptop)
        XCTAssertEqual(bottom.panelLocal.maxY + gap, bottom.stripLocal.minY)
        for layout in [left, right, top, bottom] {
            XCTAssertTrue(laptop.contains(layout.window))
        }
    }

    func testSettingsPanelIsClampedOnASmallScreen() {
        let small = CGRect(x: 0, y: 0, width: 640, height: 480)
        for edge in [WidgetEdge.left, .right, .top, .bottom] {
            let layout = settingsLayout(edge, in: small)
            XCTAssertTrue(small.contains(layout.window), "\(edge) panel stays on screen")
            XCTAssertLessThan(layout.panelLocal.width, settingsSize.width, "\(edge)")
            XCTAssertLessThan(layout.panelLocal.height, settingsSize.height, "\(edge)")
        }
    }

    func testSettingsPanelMayBeNarrowerThanTheSideListLayout() {
        // A later layout moves the page list to the top below 560, so the
        // stored size must be allowed under it.
        let size = WidgetGeometry.clampedPanelSize(
            CGSize(width: 400, height: 400),
            screenFrame: laptop,
            visibleFrame: laptop
        )
        XCTAssertEqual(size, CGSize(width: 400, height: 400))
        let tiny = WidgetGeometry.clampedPanelSize(.zero, screenFrame: laptop, visibleFrame: laptop)
        XCTAssertEqual(tiny, CGSize(width: WidgetMetrics.panelMinWidth, height: WidgetMetrics.panelMinHeight))
    }
}
