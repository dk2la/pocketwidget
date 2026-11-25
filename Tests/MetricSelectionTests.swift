import XCTest

/// The System module remembers which metric was looked at last, and lays
/// its five small cards out in rows that never leave one stranded when
/// there is room to share.
final class MetricSelectionTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "MetricSelectionTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Selection

    func testFirstOpenSelectsCPU() {
        XCTAssertEqual(MetricSelection.load(from: defaults), .cpu)
    }

    func testLastChoiceIsRemembered() {
        for gauge in Gauge.allCases {
            MetricSelection.save(gauge, to: defaults)
            XCTAssertEqual(MetricSelection.load(from: defaults), gauge)
        }
    }

    func testUnknownStoredValueFallsBackToCPU() {
        defaults.set("fan", forKey: MetricSelection.key)
        XCTAssertEqual(MetricSelection.load(from: defaults), .cpu)
    }

    func testCardOrder() {
        XCTAssertEqual(Gauge.allCases, [.cpu, .memory, .network, .battery, .volume])
    }

    // MARK: - Card rows

    /// Width that holds exactly `columns` cards of the minimum width.
    private func width(for columns: Int) -> CGFloat {
        CGFloat(columns) * MetricGrid.minCardWidth + CGFloat(columns - 1) * MetricGrid.spacing
    }

    func testNarrowestPanelFitsTwoCardsARow() {
        let content = 300 - 2 * 14.0 // panel minimum width minus its insets
        XCTAssertEqual(MetricGrid.rows(width: content, count: 5), [2, 2, 1])
    }

    func testThreeFitThreeThenTwo() {
        XCTAssertEqual(MetricGrid.rows(width: width(for: 3), count: 5), [3, 2])
    }

    func testFourFitStillThreeThenTwo() {
        // 4 + 1 would strand the last card; the same two rows share evenly.
        XCTAssertEqual(MetricGrid.rows(width: width(for: 4), count: 5), [3, 2])
    }

    func testWidePanelPutsAllInOneRow() {
        XCTAssertEqual(MetricGrid.rows(width: width(for: 5), count: 5), [5])
        XCTAssertEqual(MetricGrid.rows(width: 900, count: 5), [5])
    }

    func testOnePixelShortDropsAColumn() {
        XCTAssertEqual(MetricGrid.rows(width: width(for: 5) - 1, count: 5), [3, 2])
        XCTAssertEqual(MetricGrid.rows(width: width(for: 3) - 1, count: 5), [2, 2, 1])
    }

    func testTooNarrowForTwoStacksCards() {
        XCTAssertEqual(MetricGrid.rows(width: 100, count: 5), [1, 1, 1, 1, 1])
        XCTAssertEqual(MetricGrid.rows(width: 0, count: 5), [1, 1, 1, 1, 1])
    }

    func testRowsAlwaysHoldEveryCard() {
        for width in stride(from: CGFloat(0), through: 1200, by: 7) {
            for count in 0...7 {
                let rows = MetricGrid.rows(width: width, count: count)
                XCTAssertEqual(rows.reduce(0, +), count)
                XCTAssertFalse(rows.contains(0))
            }
        }
    }

    // MARK: - Chart height

    func testChartHeightFollowsThePanelWithinLimits() {
        XCTAssertEqual(MetricGrid.chartHeight(available: 0), MetricGrid.chartHeightRange.lowerBound)
        XCTAssertEqual(MetricGrid.chartHeight(available: 5000), MetricGrid.chartHeightRange.upperBound)
        let middle = MetricGrid.chartHeight(available: 400)
        XCTAssertGreaterThan(middle, MetricGrid.chartHeightRange.lowerBound)
        XCTAssertLessThan(middle, MetricGrid.chartHeightRange.upperBound)
    }
}
