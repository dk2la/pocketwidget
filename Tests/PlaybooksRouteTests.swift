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

/// The editor is one more destination: it knows where it was opened from
/// and goes back there, whether the user saved or cancelled.
final class PlaybooksEditorRouteTests: XCTestCase {
    private let first = UUID()
    private let second = UUID()

    func testAddingReturnsToTheList() {
        XCTAssertEqual(PlaybooksRoute.editor(nil).back, .list)
    }

    func testEditingReturnsToTheOpenedPlaybook() {
        XCTAssertEqual(PlaybooksRoute.editor(first).back, .playbook(first))
    }

    func testAnOpenedPlaybookGoesBackToTheList() {
        XCTAssertEqual(PlaybooksRoute.playbook(first).back, .list)
        XCTAssertEqual(PlaybooksRoute.list.back, .list)
    }

    func testEditorOfANewPlaybookNeedsNoExistingPlaybook() {
        XCTAssertEqual(PlaybooksRoute.editor(nil).resolved(existing: []), .editor(nil))
        XCTAssertEqual(PlaybooksRoute.editor(nil).resolved(existing: [first]), .editor(nil))
    }

    func testEditorStaysWhileItsPlaybookExists() {
        XCTAssertEqual(PlaybooksRoute.editor(second).resolved(existing: [first, second]), .editor(second))
    }

    func testEditorOfARemovedPlaybookFallsBackToList() {
        // Deleted in Settings while it was being edited in the widget.
        XCTAssertEqual(PlaybooksRoute.editor(second).resolved(existing: [first]), .list)
    }

    func testDeletingFromTheEditorLandsOnTheList() {
        // Back from the editor points at the playbook, which is gone.
        let afterDelete = PlaybooksRoute.editor(second).back.resolved(existing: [first])
        XCTAssertEqual(afterDelete, .list)
    }

    func testOnlyTheEditorIsEditing() {
        XCTAssertTrue(PlaybooksRoute.editor(nil).isEditor)
        XCTAssertTrue(PlaybooksRoute.editor(first).isEditor)
        XCTAssertFalse(PlaybooksRoute.list.isEditor)
        XCTAssertFalse(PlaybooksRoute.playbook(first).isEditor)
    }

    func testOpenedIDIsNotSetForTheEditor() {
        XCTAssertNil(PlaybooksRoute.editor(first).openedID)
        XCTAssertNil(PlaybooksRoute.editor(nil).openedID)
    }
}
