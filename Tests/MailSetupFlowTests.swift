import XCTest

/// Mail setup in the module: it watches the clipboard only while it waits
/// for a password, takes a copied app password by itself, and on Connect
/// either hands the account over or keeps everything typed with a reason.
@MainActor
final class MailSetupFlowTests: XCTestCase {
    private final class FakePasteboard: MailSetupPasteboard {
        private(set) var changeCount = 0
        private(set) var text: String?
        private(set) var readCount = 0

        func copy(_ newText: String) {
            changeCount += 1
            text = newText
        }

        func readText() -> String? {
            readCount += 1
            return text
        }
    }

    private var pasteboard = FakePasteboard()
    private var probeResult: Result<Void, Error> = .success(())
    private var probed: [(EmailAccountConfig, String)] = []
    private var saved: [(EmailAccountConfig, String)] = []
    private var saveSucceeds = true
    private var claimed: [String] = []
    /// Runs inside the probe, while the flow is connecting.
    private var duringProbe: (() -> Void)?

    private func makeFlow() -> MailSetupFlow {
        let flow = MailSetupFlow(pasteboard: pasteboard, pollInterval: nil) { [unowned self] config, password in
            probed.append((config, password))
            duringProbe?()
            return probeResult
        }
        flow.onConnected = { [unowned self] config, password in
            saved.append((config, password))
            return saveSucceeds
        }
        flow.onPasswordPickedUp = { [unowned self] in claimed.append($0) }
        return flow
    }

    // MARK: - The watch

    func testNothingIsWatchedBeforeSetupStarts() {
        let flow = makeFlow()
        XCTAssertFalse(flow.isActive)
        XCTAssertFalse(flow.isWatching)
        pasteboard.copy("abcd efgh ijkl mnop")
        flow.checkClipboard()
        XCTAssertEqual(flow.draft.password, "")
        XCTAssertEqual(pasteboard.readCount, 0)
    }

    func testStartingSetupStartsTheWatch() {
        let flow = makeFlow()
        flow.begin()
        XCTAssertTrue(flow.isActive)
        XCTAssertEqual(flow.draft.provider, .gmail)
        XCTAssertTrue(flow.isWatching)
    }

    func testProvidersWithoutAnAppPasswordPageAreNotWatched() {
        let flow = makeFlow()
        flow.begin()
        flow.select(.outlook)
        XCTAssertFalse(flow.isWatching)
        flow.select(.custom)
        XCTAssertFalse(flow.isWatching)
        flow.select(.icloud)
        XCTAssertTrue(flow.isWatching)
    }

    func testCopiedAppPasswordFillsTheField() {
        let flow = makeFlow()
        flow.begin()
        XCTAssertFalse(flow.passwordWasPickedUp)
        pasteboard.copy("abcd efgh ijkl mnop")
        flow.checkClipboard()
        XCTAssertEqual(flow.draft.password, "abcdefghijklmnop")
        XCTAssertTrue(flow.passwordWasPickedUp)
    }

    func testCopiedPasswordIsClaimedFromClipboardHistory() {
        let flow = makeFlow()
        flow.begin()
        pasteboard.copy("abcd efgh ijkl mnop")
        flow.checkClipboard()
        XCTAssertEqual(claimed, ["abcd efgh ijkl mnop"])
    }

    func testOtherCopiedTextIsIgnored() {
        let flow = makeFlow()
        flow.begin()
        flow.draft.password = "typed"
        pasteboard.copy("https://example.com/some/link")
        flow.checkClipboard()
        XCTAssertEqual(flow.draft.password, "typed")
        XCTAssertFalse(flow.passwordWasPickedUp)
        XCTAssertTrue(claimed.isEmpty)
    }

    func testAnotherProvidersFormatIsIgnored() {
        let flow = makeFlow()
        flow.begin()
        flow.select(.icloud)
        pasteboard.copy("abcd efgh ijkl mnop")
        flow.checkClipboard()
        XCTAssertEqual(flow.draft.password, "")
        pasteboard.copy("abcd-efgh-ijkl-mnop")
        flow.checkClipboard()
        XCTAssertEqual(flow.draft.password, "abcd-efgh-ijkl-mnop")
    }

    func testTextCopiedBeforeSetupStartedIsNotTaken() {
        let flow = makeFlow()
        pasteboard.copy("abcd efgh ijkl mnop")
        flow.begin()
        flow.checkClipboard()
        XCTAssertEqual(flow.draft.password, "")
    }

    func testTheWatchStopsOnceThePasswordIsFilled() {
        let flow = makeFlow()
        flow.begin()
        flow.draft.password = "typed by hand"
        XCTAssertFalse(flow.isWatching)
        pasteboard.copy("abcd efgh ijkl mnop")
        flow.checkClipboard()
        XCTAssertEqual(flow.draft.password, "typed by hand")
        flow.draft.password = ""
        XCTAssertTrue(flow.isWatching)
    }

    func testTypingOverAPickedUpPasswordDropsTheNotice() {
        let flow = makeFlow()
        flow.begin()
        pasteboard.copy("abcd efgh ijkl mnop")
        flow.checkClipboard()
        flow.draft.password = "typed by hand"
        XCTAssertFalse(flow.passwordWasPickedUp)
    }

    func testCancellingStopsTheWatchAndForgetsWhatWasTyped() {
        let flow = makeFlow()
        flow.begin()
        flow.draft.email = "ann@gmail.com"
        pasteboard.copy("abcd efgh ijkl mnop")
        flow.checkClipboard()
        flow.cancel()
        XCTAssertFalse(flow.isActive)
        XCTAssertFalse(flow.isWatching)
        XCTAssertEqual(flow.draft, MailSetupDraft())
        XCTAssertFalse(flow.passwordWasPickedUp)

        pasteboard.copy("qrst uvwx yzab cdef")
        flow.checkClipboard()
        XCTAssertEqual(flow.draft.password, "")
    }

    // MARK: - Connect

    func testConnectNeedsAnAddressAndAPassword() async {
        let flow = makeFlow()
        flow.begin()
        XCTAssertFalse(flow.canConnect)
        flow.draft.email = "ann@gmail.com"
        XCTAssertFalse(flow.canConnect)
        flow.draft.password = "abcdefghijklmnop"
        XCTAssertTrue(flow.canConnect)

        flow.draft.email = "  "
        await flow.connect()
        XCTAssertTrue(probed.isEmpty)
    }

    func testSuccessfulConnectHandsTheAccountOverAndEndsSetup() async {
        let flow = makeFlow()
        flow.begin()
        flow.draft.email = " ann@gmail.com "
        pasteboard.copy("abcd efgh ijkl mnop")
        flow.checkClipboard()

        await flow.connect()

        XCTAssertEqual(probed.count, 1)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.0.email, "ann@gmail.com")
        XCTAssertEqual(saved.first?.0.imapHost, "imap.gmail.com")
        XCTAssertEqual(saved.first?.0.presetID, "gmail")
        XCTAssertEqual(saved.first?.1, "abcdefghijklmnop")
        XCTAssertFalse(flow.isActive)
        XCTAssertFalse(flow.isWatching)
        XCTAssertEqual(flow.draft, MailSetupDraft())
    }

    func testTheWatchIsOffWhileConnecting() async {
        let flow = makeFlow()
        flow.begin()
        flow.draft.email = "ann@gmail.com"
        flow.draft.password = "abcdefghijklmnop"
        var watchedDuringProbe: Bool?
        var phaseDuringProbe: MailSetupFlow.Phase?
        duringProbe = {
            watchedDuringProbe = flow.isWatching
            phaseDuringProbe = flow.phase
        }
        await flow.connect()
        XCTAssertEqual(watchedDuringProbe, false)
        XCTAssertEqual(phaseDuringProbe, .connecting)
    }

    func testFailedConnectKeepsTheFieldsAndSaysWhy() async {
        let flow = makeFlow()
        flow.begin()
        flow.draft.email = "ann@gmail.com"
        flow.draft.password = "abcdefghijklmnop"
        probeResult = .failure(MailError.authFailed("[AUTHENTICATIONFAILED] Invalid credentials"))

        await flow.connect()

        XCTAssertTrue(saved.isEmpty)
        XCTAssertEqual(flow.phase, .failed(.rejected))
        XCTAssertTrue(flow.isActive)
        XCTAssertEqual(flow.draft.email, "ann@gmail.com")
        XCTAssertEqual(flow.draft.password, "abcdefghijklmnop")
        XCTAssertEqual(flow.draft.provider, .gmail)
        // Waiting for a better password again.
        XCTAssertTrue(flow.isWatching)
    }

    func testEditingAfterAFailureClearsTheReason() async {
        let flow = makeFlow()
        flow.begin()
        flow.draft.email = "ann@gmail.com"
        flow.draft.password = "abcdefghijklmnop"
        probeResult = .failure(MailError.timeout)
        await flow.connect()
        XCTAssertEqual(flow.phase, .failed(.unreachable))

        flow.draft.password = "qrstuvwxyzabcdef"
        XCTAssertEqual(flow.phase, .editing)
    }

    func testAccountThatCannotBeSavedIsAFailure() async {
        let flow = makeFlow()
        flow.begin()
        flow.draft.email = "ann@gmail.com"
        flow.draft.password = "abcdefghijklmnop"
        saveSucceeds = false
        await flow.connect()
        XCTAssertEqual(flow.phase, .failed(.notSaved))
        XCTAssertEqual(flow.draft.password, "abcdefghijklmnop")
    }

    func testCancellingWhileConnectingDropsTheResult() async {
        let flow = makeFlow()
        flow.begin()
        flow.draft.email = "ann@gmail.com"
        flow.draft.password = "abcdefghijklmnop"
        duringProbe = { flow.cancel() }
        await flow.connect()
        XCTAssertTrue(saved.isEmpty)
        XCTAssertFalse(flow.isActive)
    }

    // MARK: - Reasons

    func testFailureReasons() {
        XCTAssertEqual(MailSetupFailure(MailError.authFailed("no")), .rejected)
        XCTAssertEqual(MailSetupFailure(MailError.timeout), .unreachable)
        XCTAssertEqual(MailSetupFailure(MailError.connectionClosed), .unreachable)
        XCTAssertEqual(MailSetupFailure(MailError.tls("handshake")), .unreachable)
        XCTAssertEqual(MailSetupFailure(MailError.badResponse("NO mailbox")), .other("NO mailbox"))
    }

    // MARK: - The draft

    func testCustomProviderNeedsItsServers() {
        var draft = MailSetupDraft()
        draft.select(.custom)
        draft.email = "ann@example.com"
        draft.imapHost = ""
        draft.smtpHost = ""
        XCTAssertFalse(draft.isComplete)
        draft.imapHost = "imap.example.com"
        draft.smtpHost = "smtp.example.com"
        draft.smtpPort = "587"
        XCTAssertTrue(draft.isComplete)
        XCTAssertEqual(draft.config.imapHost, "imap.example.com")
        XCTAssertEqual(draft.config.smtpPort, 587)
        XCTAssertTrue(draft.config.smtpUsesSTARTTLS)
        XCTAssertEqual(draft.config.presetID, "custom")
    }

    func testDraftFromASavedAccountRoundTrips() {
        var draft = MailSetupDraft()
        draft.select(.icloud)
        draft.email = "ann@icloud.com"
        let config = draft.config
        XCTAssertEqual(MailSetupDraft(config: config).config, config)
        XCTAssertEqual(MailSetupDraft(config: config).provider, .icloud)
    }
}
