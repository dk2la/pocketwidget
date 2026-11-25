import XCTest

/// The event pill sits beside the strip on the side facing the screen
/// centre (8 pt gap), centred on the strip, and never leaves the visible
/// frame.
final class LiveEventPillGeometryTests: XCTestCase {
    private let visible = NSRect(x: 0, y: 0, width: 1440, height: 875)
    private let pill = CGSize(width: 200, height: 36)

    private func frame(_ strip: NSRect, _ edge: WidgetEdge, on screen: NSRect? = nil) -> NSRect {
        WidgetGeometry.eventPillFrame(strip: strip, edge: edge, pillSize: pill, visibleFrame: screen ?? visible)
    }

    func testLeftDockPutsPillToTheRight() {
        let strip = NSRect(x: 6, y: 300, width: 44, height: 260)
        XCTAssertEqual(frame(strip, .left), NSRect(x: 58, y: 412, width: 200, height: 36))
    }

    func testRightDockPutsPillToTheLeft() {
        let strip = NSRect(x: 1390, y: 300, width: 44, height: 260)
        XCTAssertEqual(frame(strip, .right), NSRect(x: 1182, y: 412, width: 200, height: 36))
    }

    func testTopDockPutsPillBelow() {
        let strip = NSRect(x: 500, y: 825, width: 300, height: 44)
        XCTAssertEqual(frame(strip, .top), NSRect(x: 550, y: 781, width: 200, height: 36))
    }

    func testBottomDockPutsPillAbove() {
        let strip = NSRect(x: 500, y: 6, width: 300, height: 44)
        XCTAssertEqual(frame(strip, .bottom), NSRect(x: 550, y: 58, width: 200, height: 36))
    }

    func testMinimizedStripCentresOnTheShortStrip() {
        // Minimized side strip: grip plus one button.
        let left = NSRect(x: 6, y: 600, width: 44, height: 76)
        XCTAssertEqual(frame(left, .left), NSRect(x: 58, y: 620, width: 200, height: 36))
        // Minimized bottom strip: narrower than the pill, which overhangs
        // both ends evenly.
        let bottom = NSRect(x: 700, y: 6, width: 76, height: 44)
        XCTAssertEqual(frame(bottom, .bottom), NSRect(x: 638, y: 58, width: 200, height: 36))
    }

    func testClampedAtCorners() {
        let bottomLeft = NSRect(x: 0, y: 6, width: 76, height: 44)
        XCTAssertEqual(frame(bottomLeft, .bottom), NSRect(x: 0, y: 58, width: 200, height: 36))
        let topRight = NSRect(x: 1364, y: 825, width: 76, height: 44)
        XCTAssertEqual(frame(topRight, .top), NSRect(x: 1240, y: 781, width: 200, height: 36))
        let leftTop = NSRect(x: 6, y: 860, width: 44, height: 15)
        XCTAssertEqual(frame(leftTop, .left), NSRect(x: 58, y: 839, width: 200, height: 36))
        let rightBottom = NSRect(x: 1390, y: 0, width: 44, height: 20)
        XCTAssertEqual(frame(rightBottom, .right), NSRect(x: 1182, y: 0, width: 200, height: 36))
    }

    func testClampedOnASecondScreen() {
        // A display to the right of the main one: clamping uses its frame,
        // not the origin.
        let second = NSRect(x: 1440, y: 0, width: 1920, height: 1055)
        let strip = NSRect(x: 1440, y: 6, width: 76, height: 44)
        XCTAssertEqual(frame(strip, .bottom, on: second), NSRect(x: 1440, y: 58, width: 200, height: 36))
    }
}
