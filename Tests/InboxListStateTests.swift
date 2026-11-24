import XCTest

/// The inbox shows its empty screen (the mailbox device and a message) only
/// when there is nothing to list; a search, once it has run, decides alone.
final class InboxListStateTests: XCTestCase {
    private func message(_ uid: UInt32) -> EmailMessage {
        EmailMessage(
            uid: uid,
            subject: "Subject \(uid)",
            fromName: "Ann",
            fromAddress: "ann@example.com",
            date: Date(timeIntervalSince1970: 0),
            isUnread: false,
            references: []
        )
    }

    func testEmptyMailboxIsTheEmptyInbox() {
        XCTAssertEqual(InboxListState(messages: [], searchResults: nil), .emptyInbox)
    }

    func testMailboxMessagesAreListed() {
        let messages = [message(1), message(2)]
        XCTAssertEqual(InboxListState(messages: messages, searchResults: nil), .messages(messages))
    }

    func testSearchWithoutHitsIsEmptyEvenWhenTheMailboxHasMail() {
        XCTAssertEqual(InboxListState(messages: [message(1)], searchResults: []), .noSearchResults)
    }

    func testSearchHitsReplaceTheMailboxList() {
        let hits = [message(7)]
        XCTAssertEqual(InboxListState(messages: [message(1)], searchResults: hits), .messages(hits))
        XCTAssertEqual(InboxListState(messages: [], searchResults: hits), .messages(hits))
    }

    func testOnlyAListWithMessagesIsNotEmpty() {
        XCTAssertTrue(InboxListState.emptyInbox.isEmpty)
        XCTAssertTrue(InboxListState.noSearchResults.isEmpty)
        XCTAssertFalse(InboxListState.messages([message(1)]).isEmpty)
    }
}
