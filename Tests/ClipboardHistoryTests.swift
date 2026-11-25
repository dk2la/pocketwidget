import XCTest

/// Clipboard history keeps copied text, newest first — except text another
/// part of Pocket has claimed as a secret (the app password Mail setup
/// picks up), which must never be listed.
final class ClipboardHistoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 0)

    func testCopiedTextIsListedNewestFirst() {
        var history = ClipboardHistory()
        history.record("first", at: now)
        history.record("second", at: now)
        XCTAssertEqual(history.entries.map(\.text), ["second", "first"])
    }

    func testCopyingTheSameTextAgainMovesItToTheTop() {
        var history = ClipboardHistory()
        history.record("first", at: now)
        history.record("second", at: now)
        history.record("first", at: now)
        XCTAssertEqual(history.entries.map(\.text), ["first", "second"])
    }

    func testBlankTextIsNotListed() {
        var history = ClipboardHistory()
        history.record("  \n", at: now)
        XCTAssertTrue(history.entries.isEmpty)
    }

    func testHistoryKeepsOnlyTheLatestEntries() {
        var history = ClipboardHistory()
        for index in 0..<(ClipboardHistory.capacity + 5) {
            history.record("text \(index)", at: now)
        }
        XCTAssertEqual(history.entries.count, ClipboardHistory.capacity)
        XCTAssertEqual(history.entries.first?.text, "text \(ClipboardHistory.capacity + 4)")
    }

    func testWithheldTextIsNotListedWhenCopiedAfterwards() {
        var history = ClipboardHistory()
        history.withhold("abcd efgh ijkl mnop")
        history.record("abcd efgh ijkl mnop", at: now)
        XCTAssertTrue(history.entries.isEmpty)
    }

    func testWithholdingRemovesTextAlreadyListed() {
        var history = ClipboardHistory()
        history.record("kept", at: now)
        history.record("abcd efgh ijkl mnop", at: now)
        history.withhold("abcd efgh ijkl mnop")
        XCTAssertEqual(history.entries.map(\.text), ["kept"])
    }

    func testWithholdingIgnoresSurroundingWhitespace() {
        var history = ClipboardHistory()
        history.record("abcd-efgh-ijkl-mnop\n", at: now)
        history.withhold("  abcd-efgh-ijkl-mnop")
        XCTAssertTrue(history.entries.isEmpty)
        history.record(" abcd-efgh-ijkl-mnop ", at: now)
        XCTAssertTrue(history.entries.isEmpty)
    }

    func testOtherTextIsStillListedAfterWithholding() {
        var history = ClipboardHistory()
        history.withhold("abcdefghijklmnop")
        history.record("hello", at: now)
        XCTAssertEqual(history.entries.map(\.text), ["hello"])
    }
}
