import XCTest

/// The editor works on a draft: nothing reaches the store until Save, and
/// Save writes exactly one playbook — a new one or the edited one.
@MainActor
final class PlaybookDraftTests: XCTestCase {
    private var folder: URL!
    private var fileURL: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("playbook-tests-\(UUID().uuidString)")
        fileURL = folder.appendingPathComponent("playbooks.json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A store with exactly these playbooks, backed by a file of its own.
    private func makeStore(_ playbooks: [Playbook]) throws -> PlaybookStore {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(playbooks).write(to: fileURL)
        return PlaybookStore(fileURL: fileURL)
    }

    private func work() -> Playbook {
        Playbook(
            name: "Work",
            icon: "hammer.fill",
            steps: [
                .openApps(id: UUID(), bundleIDs: ["com.apple.Safari"], layout: .leftRight),
                .startTimer(id: UUID(), minutes: 25),
            ]
        )
    }

    // MARK: - Adding

    func testNewDraftStartsEmptyAndCannotBeSaved() {
        let draft = PlaybookDraft(editing: nil)
        XCTAssertTrue(draft.isNew)
        XCTAssertEqual(draft.playbook.name, "")
        XCTAssertTrue(draft.playbook.steps.isEmpty)
        XCTAssertFalse(draft.canSave)
        XCTAssertFalse(draft.isChanged)
    }

    func testSavingANewDraftAddsOnePlaybook() throws {
        let existing = work()
        let store = try makeStore([existing])
        var draft = PlaybookDraft(editing: nil)
        draft.playbook.name = "Evening"
        draft.playbook.icon = "moon.zzz.fill"
        draft.playbook.steps = [.closeOtherApps(id: UUID())]

        XCTAssertTrue(draft.save(to: store))

        XCTAssertEqual(store.playbooks.count, 2)
        XCTAssertEqual(store.playbooks.first, existing)
        XCTAssertEqual(store.playbooks.last, draft.playbook)
        // And it is on disk: a fresh store reads the same list.
        XCTAssertEqual(PlaybookStore(fileURL: fileURL).playbooks, store.playbooks)
    }

    func testANamelessDraftIsNotSaved() throws {
        let store = try makeStore([])
        var draft = PlaybookDraft(editing: nil)
        draft.playbook.name = "   "
        draft.playbook.steps = [.closeOtherApps(id: UUID())]

        XCTAssertFalse(draft.canSave)
        XCTAssertFalse(draft.save(to: store))
        XCTAssertTrue(store.playbooks.isEmpty)
    }

    // MARK: - Editing

    func testDraftOfAnExistingPlaybookIsFilledWithIt() {
        let existing = work()
        let draft = PlaybookDraft(editing: existing)
        XCTAssertFalse(draft.isNew)
        XCTAssertEqual(draft.playbook, existing)
        XCTAssertTrue(draft.canSave)
        XCTAssertFalse(draft.isChanged)
    }

    func testSavingAnEditReplacesThatPlaybookInPlace() throws {
        let first = work()
        let second = Playbook(name: "Clear", steps: [.closeOtherApps(id: UUID())])
        let store = try makeStore([first, second])
        var draft = PlaybookDraft(editing: first)
        draft.playbook.name = "Deep work"
        draft.playbook.steps.append(.openURLs(id: UUID(), urls: ["https://example.com"]))

        XCTAssertTrue(draft.isChanged)
        XCTAssertTrue(draft.save(to: store))

        XCTAssertEqual(store.playbooks.count, 2)
        XCTAssertEqual(store.playbooks[0].id, first.id)
        XCTAssertEqual(store.playbooks[0].name, "Deep work")
        XCTAssertEqual(store.playbooks[0].steps.count, 3)
        XCTAssertEqual(store.playbooks[1], second)
    }

    func testAbandonedDraftLeavesTheStoreUntouched() throws {
        // Cancel, Back, or the panel closed by hand: the draft is dropped.
        let existing = work()
        let store = try makeStore([existing])
        let onDisk = try Data(contentsOf: fileURL)

        var edit = PlaybookDraft(editing: existing)
        edit.playbook.name = "Half-typed"
        edit.playbook.steps.removeAll()
        var new = PlaybookDraft(editing: nil)
        new.playbook.name = "Half-made"

        XCTAssertTrue(edit.isChanged)
        XCTAssertTrue(new.isChanged)
        XCTAssertEqual(store.playbooks, [existing])
        XCTAssertEqual(try Data(contentsOf: fileURL), onDisk)
    }

    func testSavingAnEditOfAPlaybookRemovedMeanwhileDoesNotBringItBack() throws {
        let existing = work()
        let store = try makeStore([existing])
        var draft = PlaybookDraft(editing: existing)
        draft.playbook.name = "Renamed"
        store.remove(existing)

        draft.save(to: store)

        XCTAssertTrue(store.playbooks.isEmpty)
    }

    // MARK: - Clean-up on save

    func testSaveTrimsWhatTheUserTyped() throws {
        let store = try makeStore([])
        var draft = PlaybookDraft(editing: nil)
        draft.playbook.name = "  Morning "
        draft.playbook.steps = [
            .runShortcut(id: UUID(), name: " Lights on "),
            .setFocus(id: UUID(), shortcutName: " Work focus"),
            .openURLs(id: UUID(), urls: [" https://a.example ", "", "   ", "https://b.example"]),
        ]

        draft.save(to: store)

        let saved = try XCTUnwrap(store.playbooks.first)
        XCTAssertEqual(saved.name, "Morning")
        guard case .runShortcut(_, let shortcut) = saved.steps[0],
              case .setFocus(_, let focus) = saved.steps[1],
              case .openURLs(_, let urls) = saved.steps[2]
        else { return XCTFail("step kinds changed on save") }
        XCTAssertEqual(shortcut, "Lights on")
        XCTAssertEqual(focus, "Work focus")
        XCTAssertEqual(urls, ["https://a.example", "https://b.example"])
    }

    func testEveryStepKindSurvivesSaveAndReload() throws {
        let store = try makeStore([])
        var draft = PlaybookDraft(editing: nil)
        draft.playbook.name = "All"
        draft.playbook.steps = PlaybookStep.Kind.allCases.map { $0.makeStep() }

        draft.save(to: store)

        let reloaded = PlaybookStore(fileURL: fileURL).playbooks
        XCTAssertEqual(reloaded.first?.steps.map(\.kind), PlaybookStep.Kind.allCases)
    }

    // MARK: - Steps

    func testStepsMoveWithinBounds() {
        var draft = PlaybookDraft(editing: work())
        let ids = draft.playbook.steps.map(\.id)

        draft.moveStep(ids[0], by: -1)
        XCTAssertEqual(draft.playbook.steps.map(\.id), ids)
        draft.moveStep(ids[0], by: 1)
        XCTAssertEqual(draft.playbook.steps.map(\.id), [ids[1], ids[0]])
        draft.moveStep(ids[0], by: 1)
        XCTAssertEqual(draft.playbook.steps.map(\.id), [ids[1], ids[0]])
    }

    // MARK: - Deleting

    func testDeletingRemovesOnlyThatPlaybook() throws {
        let first = work()
        let second = Playbook(name: "Clear", steps: [.closeOtherApps(id: UUID())])
        let store = try makeStore([first, second])

        PlaybookDraft(editing: first).delete(from: store)

        XCTAssertEqual(store.playbooks, [second])
        XCTAssertEqual(PlaybookStore(fileURL: fileURL).playbooks, [second])
    }

    func testDeletingANewDraftDoesNothing() throws {
        let existing = work()
        let store = try makeStore([existing])

        PlaybookDraft(editing: nil).delete(from: store)

        XCTAssertEqual(store.playbooks, [existing])
    }
}
