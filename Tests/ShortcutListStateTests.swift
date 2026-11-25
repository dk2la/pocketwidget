import XCTest

/// Hotkeys shows its empty screen only when
/// there is nothing to list for the app in front; a search that finds
/// nothing keeps its plain message, and a list still on its way shows
/// neither.
final class ShortcutListStateTests: XCTestCase {
    func testNoAppInFrontIsTheEmptyScreen() {
        let state = ShortcutListState(hasApp: false, shownCount: 0, query: "", isSettled: false)
        XCTAssertEqual(state, .noApp)
        XCTAssertTrue(state.showsEmptyScreen)
    }

    func testNoAppWinsOverEverythingElse() {
        XCTAssertEqual(ShortcutListState(hasApp: false, shownCount: 3, query: "copy", isSettled: true), .noApp)
    }

    func testAppWithoutShortcutsIsTheEmptyScreen() {
        let state = ShortcutListState(hasApp: true, shownCount: 0, query: "", isSettled: true)
        XCTAssertEqual(state, .noShortcuts)
        XCTAssertTrue(state.showsEmptyScreen)
    }

    func testShortcutsAreTheListNotTheEmptyScreen() {
        let state = ShortcutListState(hasApp: true, shownCount: 12, query: "", isSettled: true)
        XCTAssertEqual(state, .shortcuts)
        XCTAssertFalse(state.showsEmptyScreen)
    }

    func testSearchThatFindsNothingIsNotTheEmptyScreen() {
        let state = ShortcutListState(hasApp: true, shownCount: 0, query: "zzz", isSettled: true)
        XCTAssertEqual(state, .noSearchResults)
        XCTAssertFalse(state.showsEmptyScreen)
    }

    func testSearchHitsAreTheList() {
        XCTAssertEqual(ShortcutListState(hasApp: true, shownCount: 2, query: "copy", isSettled: true), .shortcuts)
    }

    func testBlankQueryIsNotASearch() {
        XCTAssertEqual(ShortcutListState(hasApp: true, shownCount: 0, query: "   ", isSettled: true), .noShortcuts)
    }

    func testListStillOnItsWayIsNotTheEmptyScreen() {
        // Menus not read yet, or no Accessibility access: the hero card
        // says so, and the empty screen must not flash in meanwhile.
        let state = ShortcutListState(hasApp: true, shownCount: 0, query: "", isSettled: false)
        XCTAssertEqual(state, .pending)
        XCTAssertFalse(state.showsEmptyScreen)
    }

    func testSearchDecidesEvenBeforeTheListIsSettled() {
        XCTAssertEqual(
            ShortcutListState(hasApp: true, shownCount: 0, query: "copy", isSettled: false),
            .noSearchResults
        )
    }

    func testCustomShortcutsShowBeforeTheMenusAreRead() {
        XCTAssertEqual(ShortcutListState(hasApp: true, shownCount: 1, query: "", isSettled: false), .shortcuts)
    }
}
