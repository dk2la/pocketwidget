import XCTest

/// Files picked through the "Add file" row land on the shelf like dropped
/// ones, and the panel is held open for exactly as long as the picker is up.
@MainActor
final class ShelfAddFileTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var folder: URL!

    override func setUp() async throws {
        suiteName = "shelf-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeFile(_ name: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        return url
    }

    // MARK: - Store

    func testAddedFilesLandNewestFirst() throws {
        let shelf = ShelfStore(defaults: defaults)
        let old = try makeFile("old.txt")
        let a = try makeFile("a.txt")
        let b = try makeFile("b.txt")
        shelf.add([old])
        shelf.add([a, b])
        XCTAssertEqual(shelf.items.map(\.url), [b, a, old])
    }

    func testFoldersAreAccepted() throws {
        let shelf = ShelfStore(defaults: defaults)
        let sub = folder.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        shelf.add([sub])
        XCTAssertEqual(shelf.items.map(\.url), [sub])
    }

    func testDuplicatesAndNonFilesAreSkipped() throws {
        let shelf = ShelfStore(defaults: defaults)
        let a = try makeFile("a.txt")
        let b = try makeFile("b.txt")
        shelf.add([a])
        shelf.add([b, a, URL(string: "https://example.com/c.txt")!])
        XCTAssertEqual(shelf.items.map(\.url), [b, a])
    }

    func testAddedFilesSurviveRelaunch() throws {
        let a = try makeFile("a.txt")
        ShelfStore(defaults: defaults).add([a])
        XCTAssertEqual(ShelfStore(defaults: defaults).items.map(\.url.path), [a.path])
    }

    // MARK: - Picker

    func testPickedFilesLandOnTheShelf() async throws {
        let shelf = ShelfStore(defaults: defaults)
        let a = try makeFile("a.txt")
        let b = try makeFile("b.txt")
        let added = await ShelfFilePicker.addFiles(to: shelf, hold: PanelHold()) { return [a, b] }
        XCTAssertTrue(added)
        XCTAssertEqual(shelf.items.map(\.url), [b, a])
    }

    func testCancelChangesNothing() async throws {
        let shelf = ShelfStore(defaults: defaults)
        let a = try makeFile("a.txt")
        shelf.add([a])
        let before = shelf.items
        let added = await ShelfFilePicker.addFiles(to: shelf, hold: PanelHold()) { return [] }
        XCTAssertFalse(added)
        XCTAssertEqual(shelf.items, before)
    }

    func testPanelIsHeldOnlyWhileThePickerIsOpen() async {
        let shelf = ShelfStore(defaults: defaults)
        let hold = PanelHold()
        var heldDuringPick = false
        var yieldedDuringPick = false
        await ShelfFilePicker.addFiles(to: shelf, hold: hold) {
            heldDuringPick = hold.isHeld
            yieldedDuringPick = hold.isYielding
            return []
        }
        XCTAssertTrue(heldDuringPick)
        XCTAssertTrue(yieldedDuringPick, "the picker must show above the widget")
        XCTAssertFalse(hold.isHeld)
        XCTAssertFalse(hold.isYielding)
    }

    // MARK: - Hold

    func testHoldsNest() {
        let hold = PanelHold()
        XCTAssertFalse(hold.isHeld)
        hold.begin()
        hold.begin()
        hold.end()
        XCTAssertTrue(hold.isHeld, "the outer picker is still open")
        hold.end()
        XCTAssertFalse(hold.isHeld)
    }

    func testExtraEndDoesNotUnbalanceLaterHolds() {
        let hold = PanelHold()
        hold.end()
        hold.begin()
        XCTAssertTrue(hold.isHeld)
    }
}
