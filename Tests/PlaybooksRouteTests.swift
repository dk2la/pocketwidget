import XCTest

/// Where the Playbooks module is: the list, or one opened playbook. The
/// route must never point at a playbook that no longer exists.
final class PlaybooksRouteTests: XCTestCase {
    private let first = UUID()
    private let second = UUID()

    func testListStaysList() {
        XCTAssertEqual(PlaybooksRoute.list.resolved(existing: [first, second]), .list)
        XCTAssertEqual(PlaybooksRoute.list.resolved(existing: []), .list)
    }

    func testOpenedPlaybookStaysOpenWhileItExists() {
        let route = PlaybooksRoute.playbook(second)
        XCTAssertEqual(route.resolved(existing: [first, second]), .playbook(second))
    }

    func testRemovedPlaybookFallsBackToList() {
        // Deleted in Settings while it was open in the widget.
        let route = PlaybooksRoute.playbook(second)
        XCTAssertEqual(route.resolved(existing: [first]), .list)
        XCTAssertEqual(route.resolved(existing: []), .list)
    }

    func testOpenedIDIsOnlySetForAnOpenedPlaybook() {
        XCTAssertNil(PlaybooksRoute.list.openedID)
        XCTAssertEqual(PlaybooksRoute.playbook(first).openedID, first)
    }
}
