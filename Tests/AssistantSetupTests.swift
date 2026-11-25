import XCTest

/// What each provider card offers, given what is on the Mac.
final class AssistantSetupPlanTests: XCTestCase {
    private func facts(
        claude: String? = nil,
        codex: String? = nil,
        claudeApp: Bool = false,
        chatGPTApp: Bool = false,
        curl: Bool = true,
        node: Bool = false,
        homebrew: Bool = false
    ) -> AssistantSetupFacts {
        AssistantSetupFacts(
            claudePath: claude,
            codexPath: codex,
            hasClaudeApp: claudeApp,
            hasChatGPTApp: chatGPTApp,
            hasCurl: curl,
            hasNode: node,
            hasHomebrew: homebrew
        )
    }

    func testAFoundProgramConnectsWithOneClick() {
        let found = facts(claude: "/Users/me/.local/bin/claude")
        XCTAssertEqual(AssistantSetupPlan.presence(of: .claudeCode, facts: found), .found)
        XCTAssertEqual(AssistantSetupPlan.presence(of: .codex, facts: found), .missing)
    }

    func testDesktopAppWithoutTheProgramIsItsOwnCase() {
        let apps = facts(claudeApp: true, chatGPTApp: true)
        XCTAssertEqual(AssistantSetupPlan.presence(of: .claudeCode, facts: apps), .appOnly)
        XCTAssertEqual(AssistantSetupPlan.presence(of: .codex, facts: apps), .appOnly)
        // The program wins over the app.
        let both = facts(codex: "/opt/homebrew/bin/codex", chatGPTApp: true)
        XCTAssertEqual(AssistantSetupPlan.presence(of: .codex, facts: both), .found)
    }

    func testBothProgramsInstallWithoutNodeOrHomebrew() {
        let bare = facts()
        XCTAssertEqual(
            AssistantSetupPlan.installCommand(for: .claudeCode, facts: bare),
            "curl -fsSL https://claude.ai/install.sh | bash"
        )
        XCTAssertEqual(
            AssistantSetupPlan.installCommand(for: .codex, facts: bare),
            "curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh"
        )
    }

    func testWithoutCurlThePackageManagersAreUsed() {
        XCTAssertEqual(
            AssistantSetupPlan.installCommand(for: .codex, facts: facts(curl: false, node: true, homebrew: true)),
            "brew install --cask codex"
        )
        XCTAssertEqual(
            AssistantSetupPlan.installCommand(for: .codex, facts: facts(curl: false, node: true)),
            "npm install -g @openai/codex"
        )
        XCTAssertEqual(
            AssistantSetupPlan.installCommand(for: .claudeCode, facts: facts(curl: false, homebrew: true)),
            "brew install --cask claude-code"
        )
        XCTAssertEqual(
            AssistantSetupPlan.installCommand(for: .claudeCode, facts: facts(curl: false, node: true)),
            "npm install -g @anthropic-ai/claude-code"
        )
    }

    func testNoWayToInstallMeansStepsByHand() {
        let stranded = facts(curl: false)
        XCTAssertNil(AssistantSetupPlan.installCommand(for: .codex, facts: stranded))
        XCTAssertEqual(AssistantSetupPlan.presence(of: .codex, facts: stranded), .noInstaller)
        XCTAssertNil(AssistantTerminalScript.make(for: .codex, facts: stranded))
        XCTAssertEqual(AssistantSetupPlan.manualCommands(for: .codex), ["npm install -g @openai/codex", "codex login"])
        // With the desktop app it is still steps by hand.
        XCTAssertEqual(AssistantSetupPlan.presence(of: .codex, facts: facts(chatGPTApp: true, curl: false)), .noInstaller)
        // A program that is already there needs no installer.
        XCTAssertEqual(AssistantSetupPlan.presence(of: .codex, facts: facts(codex: "/x/codex", curl: false)), .found)
    }

    func testTheKeyProviderHasNoProgram() {
        XCTAssertNil(AssistantSetupPlan.installCommand(for: .api, facts: facts()))
        XCTAssertNil(AssistantTerminalScript.make(for: .api, facts: facts()))
    }

    // MARK: - The .command file

    func testScriptInstallsThenSignsInWhenTheProgramIsMissing() throws {
        let script = try XCTUnwrap(AssistantTerminalScript.make(for: .claudeCode, facts: facts()))
        XCTAssertTrue(script.hasPrefix("#!/bin/sh\n"))
        let install = try XCTUnwrap(script.range(of: "curl -fsSL https://claude.ai/install.sh | bash"))
        let signIn = try XCTUnwrap(script.range(of: "claude auth login"))
        XCTAssertLessThan(install.lowerBound, signIn.lowerBound)
        // The installers put the program where a fresh PATH may not reach.
        XCTAssertTrue(script.contains("export PATH=\"$HOME/.local/bin:"))
        // The file is temporary and cleans up after itself.
        XCTAssertTrue(script.contains("rm -f \"$0\""))
    }

    func testScriptOnlySignsInWhenTheProgramIsThere() throws {
        let script = try XCTUnwrap(
            AssistantTerminalScript.make(for: .codex, facts: facts(codex: "/Users/me/My Tools/codex"))
        )
        XCTAssertFalse(script.contains("install.sh"))
        XCTAssertFalse(script.contains("brew install"))
        XCTAssertFalse(script.contains("npm install"))
        // The program Pocket found, by its full path, quoted for the shell.
        XCTAssertTrue(script.contains("'/Users/me/My Tools/codex' login\n"))
    }

    func testScriptStopsWhenInstallFails() throws {
        let script = try XCTUnwrap(AssistantTerminalScript.make(for: .codex, facts: facts()))
        let install = try XCTUnwrap(script.range(of: "CODEX_NON_INTERACTIVE=1 sh"))
        let guardLine = try XCTUnwrap(script.range(of: "|| {"))
        let signIn = try XCTUnwrap(script.range(of: "codex login"))
        XCTAssertLessThan(install.lowerBound, guardLine.lowerBound)
        XCTAssertLessThan(guardLine.lowerBound, signIn.lowerBound)
        XCTAssertTrue(script.contains("exit 1"))
    }

    func testShellQuoting() {
        XCTAssertEqual(AssistantTerminalScript.quoted("/usr/bin/codex"), "'/usr/bin/codex'")
        XCTAssertEqual(AssistantTerminalScript.quoted("/it's/codex"), "'/it'\\''s/codex'")
    }

    func testScriptButtonSaysWhatItWillDo() {
        XCTAssertTrue(AssistantSetupPlan.needsInstall(.claudeCode, facts: facts()))
        XCTAssertFalse(AssistantSetupPlan.needsInstall(.claudeCode, facts: facts(claude: "/x/claude")))
    }
}

/// Reading the answer of the test request.
final class AssistantProbeOutcomeTests: XCTestCase {
    private func outcome(_ error: Error) -> AssistantProbeOutcome {
        AssistantProbeOutcome(.failure(error))
    }

    func testSuccessConnects() {
        XCTAssertEqual(AssistantProbeOutcome(.success(())), .connected)
    }

    func testSignedOutAnswersAreRecognised() {
        let messages = [
            "Not logged in · Please run /login",
            "Login expired · Please run /login",
            "OAuth token revoked · Please run /login",
            "Please run /login · API Error: 401 {\"type\":\"error\"}",
            "ERROR: unexpected status 401 Unauthorized: Missing bearer or basic authentication in header",
            "Not logged in",
        ]
        for message in messages {
            XCTAssertEqual(outcome(CLIAssistantClient.CLIError.failed(message)), .signedOut, message)
        }
        XCTAssertEqual(outcome(CLIAssistantClient.CLIError.notSignedIn), .signedOut)
    }

    func testOtherFailuresAreNotSignIn() {
        XCTAssertEqual(outcome(CLIAssistantClient.CLIError.failed("env: node: No such file or directory")), .failed(.other))
        XCTAssertEqual(outcome(CLIAssistantClient.CLIError.failed("You've hit your usage limit")), .failed(.other))
        XCTAssertEqual(outcome(CLIAssistantClient.CLIError.timedOut), .failed(.timedOut))
        XCTAssertEqual(outcome(CLIAssistantClient.CLIError.emptyOutput), .failed(.other))
        XCTAssertEqual(outcome(CLIAssistantClient.CLIError.notInstalled("codex")), .failed(.notInstalled))
        XCTAssertEqual(outcome(URLError(.timedOut)), .failed(.other))
    }
}

/// `claude` before 2.1.169 does not know `--safe-mode` and refuses to start.
final class ClaudeSafeModeTests: XCTestCase {
    func testSafeModeIsPassedByDefault() {
        let arguments = CLIAssistantClient.claudeArguments(system: "s", prompt: "p", model: "", safeMode: true)
        XCTAssertTrue(arguments.contains("--safe-mode"))
        XCTAssertEqual(Array(arguments.prefix(2)), ["-p", "p"])
    }

    func testOlderProgramsRunWithoutIt() {
        let arguments = CLIAssistantClient.claudeArguments(system: "s", prompt: "p", model: "opus", safeMode: false)
        XCTAssertFalse(arguments.contains("--safe-mode"))
        XCTAssertEqual(Array(arguments.suffix(2)), ["--model", "opus"])
    }

    func testUnknownFlagAnswerIsRecognised() {
        XCTAssertTrue(CLIAssistantClient.rejectsSafeMode(stderr: "error: unknown option '--safe-mode'\n"))
        XCTAssertFalse(CLIAssistantClient.rejectsSafeMode(stderr: "error: unknown option '--model'"))
        XCTAssertFalse(CLIAssistantClient.rejectsSafeMode(stderr: ""))
    }
}

/// The setup inside the module: chooser, test request, sign-in in Terminal,
/// waiting, connected.
@MainActor
final class AssistantSetupFlowTests: XCTestCase {
    private var facts = AssistantSetupFacts(claudePath: "/bin/claude", hasCurl: true)
    /// Answers of the test request, in order; the last one repeats.
    private var probeResults: [Result<Void, Error>] = [.success(())]
    private var probed: [(AssistantConfig, String)] = []
    private var scripts: [String] = []
    private var terminalOpens = true
    private var stored: AssistantConfig?
    private var storedKey = ""
    private var saved: [(AssistantConfig, String)] = []
    private var saveSucceeds = true
    private var slept: [Duration] = []
    /// Runs inside every wait of the polling loop, with its number from 1.
    private var duringSleep: ((Int) -> Void)?
    /// Runs inside the test request.
    private var duringProbe: (() -> Void)?

    private let signedOut: Result<Void, Error> = .failure(CLIAssistantClient.CLIError.failed("Not logged in · Please run /login"))

    private func makeFlow() -> AssistantSetupFlow {
        let flow = AssistantSetupFlow(ports: AssistantSetupFlow.Ports(
            detect: { [unowned self] in facts },
            probe: { [unowned self] config, key in
                probed.append((config, key))
                duringProbe?()
                let index = min(probed.count, probeResults.count) - 1
                return probeResults[index]
            },
            openTerminal: { [unowned self] script in
                scripts.append(script)
                return terminalOpens
            },
            sleep: { [unowned self] duration in
                slept.append(duration)
                duringSleep?(slept.count)
            },
            currentConfig: { [unowned self] in stored },
            storedKey: { [unowned self] in storedKey },
            save: { [unowned self] config, key in
                guard saveSucceeds else { return false }
                saved.append((config, key))
                stored = config
                return true
            }
        ))
        return flow
    }

    private func openedFlow() async -> AssistantSetupFlow {
        let flow = makeFlow()
        flow.setVisible(true)
        await flow.refresh()
        return flow
    }

    // MARK: - Chooser

    func testFirstOpenShowsTheChooser() {
        let flow = makeFlow()
        XCTAssertEqual(flow.phase, .chooser)
        XCTAssertTrue(flow.isOpen)
        XCTAssertFalse(flow.canClose, "with no provider there is nothing to go back to")
    }

    func testASavedProviderOpensTheChat() {
        stored = AssistantConfig(provider: .claudeCode)
        let flow = makeFlow()
        XCTAssertEqual(flow.phase, .closed)
        XCTAssertFalse(flow.isOpen)
        XCTAssertTrue(probed.isEmpty, "a saved setup is not tested again")
        XCTAssertTrue(saved.isEmpty)
    }

    func testCardsOfferNothingBeforeTheMacWasLookedAt() {
        facts = AssistantSetupFacts()
        let flow = makeFlow()
        XCTAssertEqual(flow.card(for: .claudeCode), AssistantProviderCard(status: .testing, action: nil))
        XCTAssertEqual(flow.card(for: .codex), AssistantProviderCard(status: .testing, action: nil))
    }

    func testNothingIsPickedSilently() async {
        // Both programs are on the Mac; still nobody is connected.
        facts = AssistantSetupFacts(claudePath: "/bin/claude", codexPath: "/bin/codex", hasCurl: true)
        let flow = await openedFlow()
        XCTAssertEqual(flow.phase, .chooser)
        XCTAssertTrue(probed.isEmpty)
        XCTAssertTrue(saved.isEmpty)
        XCTAssertEqual(flow.card(for: .claudeCode), AssistantProviderCard(status: .found, action: .connect))
        XCTAssertEqual(flow.card(for: .codex), AssistantProviderCard(status: .found, action: .connect))
    }

    func testCardsFollowWhatIsOnTheMac() async {
        facts = AssistantSetupFacts(hasChatGPTApp: true, hasCurl: true)
        let flow = await openedFlow()
        XCTAssertEqual(flow.card(for: .claudeCode), AssistantProviderCard(status: .missing, action: .installAndSignIn))
        XCTAssertEqual(flow.card(for: .codex), AssistantProviderCard(status: .appOnly, action: .installAndSignIn))
        facts = AssistantSetupFacts()
        await flow.refresh()
        XCTAssertEqual(flow.card(for: .codex), AssistantProviderCard(status: .noInstaller, action: nil))
    }

    func testOpeningTheChooserKeepsTheCurrentProvider() async {
        stored = AssistantConfig(provider: .claudeCode)
        let flow = await openedFlow()
        flow.open()
        XCTAssertEqual(flow.phase, .chooser)
        XCTAssertTrue(flow.canClose)
        XCTAssertEqual(flow.card(for: .claudeCode), AssistantProviderCard(status: .connected, action: nil))
        flow.close()
        XCTAssertEqual(flow.phase, .closed)
        XCTAssertEqual(stored?.provider, .claudeCode)
    }

    func testChooserCannotBeClosedWithoutAProvider() async {
        let flow = await openedFlow()
        flow.close()
        XCTAssertEqual(flow.phase, .chooser)
    }

    // MARK: - One click

    func testOneClickTestsAndConnects() async {
        let flow = await openedFlow()
        duringProbe = { XCTAssertEqual(flow.phase, .testing(.claudeCode)) }
        await flow.connect(.claudeCode)
        XCTAssertEqual(probed.count, 1)
        XCTAssertEqual(probed.first?.0, AssistantConfig(provider: .claudeCode))
        XCTAssertEqual(saved.first?.0, AssistantConfig(provider: .claudeCode))
        XCTAssertEqual(flow.phase, .closed)
    }

    func testTestingCardShowsProgress() async {
        let flow = await openedFlow()
        var seen: AssistantProviderCard?
        duringProbe = { seen = flow.card(for: .claudeCode) }
        await flow.connect(.claudeCode)
        XCTAssertEqual(seen, AssistantProviderCard(status: .testing, action: nil))
    }

    func testNotSignedInLeadsToTheSignInStep() async {
        probeResults = [signedOut]
        let flow = await openedFlow()
        await flow.connect(.claudeCode)
        XCTAssertEqual(flow.phase, .chooser)
        XCTAssertTrue(saved.isEmpty)
        XCTAssertEqual(flow.card(for: .claudeCode), AssistantProviderCard(status: .signedOut, action: .signIn))
    }

    func testOtherFailureStaysOnTheCardWithoutRawText() async {
        probeResults = [.failure(CLIAssistantClient.CLIError.failed("env: node: No such file or directory"))]
        let flow = await openedFlow()
        await flow.connect(.claudeCode)
        XCTAssertEqual(flow.phase, .chooser)
        XCTAssertEqual(
            flow.card(for: .claudeCode),
            AssistantProviderCard(status: .found, action: .connect, failure: .other)
        )
    }

    func testAnswerAfterLeavingIsDropped() async {
        stored = AssistantConfig(provider: .codex)
        let flow = await openedFlow()
        flow.open()
        duringProbe = { flow.close() }
        await flow.connect(.claudeCode)
        XCTAssertEqual(flow.phase, .closed)
        XCTAssertTrue(saved.isEmpty)
        XCTAssertEqual(stored?.provider, .codex)
    }

    func testModelNamesDoNotCarryAcrossProviders() async {
        stored = AssistantConfig(provider: .claudeCode, model: "opus")
        facts.codexPath = "/bin/codex"
        let flow = await openedFlow()
        flow.open()
        await flow.connect(.codex)
        XCTAssertEqual(saved.last?.0, AssistantConfig(provider: .codex))
    }

    func testSigningInAgainKeepsTheModel() async {
        stored = AssistantConfig(provider: .claudeCode, model: "opus")
        let flow = await openedFlow()
        flow.noteSignedOut(.claudeCode)
        flow.open()
        flow.startSignIn(.claudeCode)
        await flow.pollingEnded()
        XCTAssertEqual(saved.last?.0, AssistantConfig(provider: .claudeCode, model: "opus"))
    }

    func testAFailedSaveIsReported() async {
        saveSucceeds = false
        let flow = await openedFlow()
        await flow.connect(.claudeCode)
        XCTAssertEqual(flow.phase, .chooser)
        XCTAssertEqual(flow.card(for: .claudeCode).failure, .notSaved)
    }

    // MARK: - Sign-in in Terminal

    func testSignInOpensTerminalAndWaits() async {
        probeResults = [signedOut]
        let flow = await openedFlow()
        await flow.connect(.claudeCode)
        flow.startSignIn(.claudeCode)
        XCTAssertEqual(scripts.count, 1)
        XCTAssertTrue(scripts[0].contains("'/bin/claude' auth login"))
        XCTAssertFalse(scripts[0].contains("install.sh"))
        XCTAssertEqual(flow.phase, .waiting(.claudeCode))
        XCTAssertEqual(flow.card(for: .claudeCode), AssistantProviderCard(status: .waiting, action: .cancel))
        flow.cancelWaiting()
    }

    func testInstallAndSignInRunsBoth() async {
        facts = AssistantSetupFacts(hasCurl: true)
        let flow = await openedFlow()
        flow.startSignIn(.codex)
        XCTAssertTrue(scripts[0].contains("https://chatgpt.com/codex/install.sh"))
        XCTAssertTrue(scripts[0].contains("codex login"))
        XCTAssertEqual(flow.phase, .waiting(.codex))
        flow.cancelWaiting()
    }

    func testTerminalThatDoesNotOpenIsAFailure() async {
        terminalOpens = false
        facts = AssistantSetupFacts(hasCurl: true)
        let flow = await openedFlow()
        flow.startSignIn(.codex)
        XCTAssertEqual(flow.phase, .chooser)
        XCTAssertEqual(flow.card(for: .codex).failure, .terminal)
        XCTAssertFalse(flow.isPolling)
    }

    func testNoInstallerMeansNoTerminal() async {
        facts = AssistantSetupFacts()
        let flow = await openedFlow()
        flow.startSignIn(.codex)
        XCTAssertTrue(scripts.isEmpty)
        XCTAssertEqual(flow.phase, .chooser)
    }

    // MARK: - Waiting

    func testWaitingChecksEveryCoupleOfSecondsUntilTheTestPasses() async {
        probeResults = [signedOut, signedOut, signedOut, .success(())]
        let flow = await openedFlow()
        await flow.connect(.claudeCode)
        flow.startSignIn(.claudeCode)
        XCTAssertTrue(flow.isPolling)
        await flow.pollingEnded()
        XCTAssertEqual(slept, [.seconds(2), .seconds(2), .seconds(2)])
        XCTAssertEqual(probed.count, 4)
        XCTAssertEqual(saved.first?.0, AssistantConfig(provider: .claudeCode))
        XCTAssertEqual(flow.phase, .closed)
        XCTAssertFalse(flow.isPolling)
    }

    func testWaitingDoesNotTestBeforeTheProgramIsInstalled() async {
        facts = AssistantSetupFacts(hasCurl: true)
        let flow = await openedFlow()
        // The installer finishes during the third wait.
        duringSleep = { [unowned self] count in
            if count == 3 { facts.codexPath = "/Users/me/.local/bin/codex" }
        }
        flow.startSignIn(.codex)
        await flow.pollingEnded()
        XCTAssertEqual(slept.count, 3)
        XCTAssertEqual(probed.count, 1)
        XCTAssertEqual(flow.phase, .closed)
    }

    func testPollingStopsWhenTheModuleCloses() async {
        probeResults = [signedOut]
        let flow = await openedFlow()
        await flow.connect(.claudeCode)
        duringSleep = { count in
            if count == 2 { flow.setVisible(false) }
        }
        flow.startSignIn(.claudeCode)
        await flow.pollingEnded()
        XCTAssertEqual(slept.count, 2)
        XCTAssertEqual(probed.count, 2, "one click, one check, none after the module closed")
        XCTAssertFalse(flow.isPolling)
        // The card is still waiting; it picks up where it left off.
        XCTAssertEqual(flow.phase, .waiting(.claudeCode))
        probeResults = [.success(())]
        duringSleep = nil
        flow.setVisible(true)
        XCTAssertTrue(flow.isPolling)
        await flow.pollingEnded()
        XCTAssertEqual(flow.phase, .closed)
    }

    func testPollingStopsWhenTheProviderChanges() async {
        probeResults = [signedOut]
        facts = AssistantSetupFacts(claudePath: "/bin/claude", codexPath: "/bin/codex", hasCurl: true)
        let flow = await openedFlow()
        await flow.connect(.claudeCode)
        duringSleep = { count in
            if count == 1 { flow.openKeyForm() }
        }
        flow.startSignIn(.claudeCode)
        await flow.pollingEnded()
        XCTAssertEqual(probed.count, 1)
        XCTAssertEqual(flow.phase, .ownKey)
        XCTAssertFalse(flow.isPolling)
    }

    func testCancelWaitingReturnsToTheChooser() async {
        probeResults = [signedOut]
        let flow = await openedFlow()
        await flow.connect(.claudeCode)
        flow.startSignIn(.claudeCode)
        flow.cancelWaiting()
        XCTAssertEqual(flow.phase, .chooser)
        XCTAssertFalse(flow.isPolling)
        await flow.pollingEnded()
        XCTAssertEqual(probed.count, 1)
    }

    func testNoPollingOutsideWaiting() async {
        let flow = await openedFlow()
        XCTAssertFalse(flow.isPolling)
        XCTAssertTrue(slept.isEmpty)
    }

    // MARK: - Own key

    func testKeyFormStartsFromAPreset() async {
        let flow = await openedFlow()
        flow.openKeyForm()
        XCTAssertEqual(flow.phase, .ownKey)
        XCTAssertEqual(flow.draft.baseURL, AssistantAPIPreset.openai.baseURL)
        XCTAssertEqual(flow.draft.model, AssistantAPIPreset.openai.sampleModel)
        XCTAssertEqual(flow.draft.key, "")
        flow.applyPreset(.ollama)
        XCTAssertEqual(flow.draft.baseURL, AssistantAPIPreset.ollama.baseURL)
        XCTAssertTrue(flow.canConnectKey, "a local Ollama needs no key")
    }

    func testKeyFormLoadsTheSavedSetup() async {
        stored = AssistantConfig(provider: .api, baseURL: "https://openrouter.ai/api/v1", model: "x/y")
        storedKey = "sk-1"
        let flow = await openedFlow()
        flow.open()
        flow.openKeyForm()
        XCTAssertEqual(flow.draft, AssistantKeyDraft(baseURL: "https://openrouter.ai/api/v1", model: "x/y", key: "sk-1"))
    }

    func testKeyFormTestsThenSaves() async {
        let flow = await openedFlow()
        flow.openKeyForm()
        flow.draft = AssistantKeyDraft(baseURL: " https://api.openai.com/v1 ", model: " gpt-5-mini ", key: "sk-2")
        await flow.connectKey()
        let expected = AssistantConfig(provider: .api, baseURL: "https://api.openai.com/v1", model: "gpt-5-mini")
        XCTAssertEqual(probed.first?.0, expected)
        XCTAssertEqual(probed.first?.1, "sk-2")
        XCTAssertEqual(saved.first?.0, expected)
        XCTAssertEqual(saved.first?.1, "sk-2")
        XCTAssertEqual(flow.phase, .closed)
    }

    func testKeyFormKeepsWhatWasTypedOnFailure() async {
        probeResults = [.failure(URLError(.userAuthenticationRequired))]
        let flow = await openedFlow()
        flow.openKeyForm()
        flow.draft.key = "sk-bad"
        await flow.connectKey()
        XCTAssertEqual(flow.phase, .ownKey)
        XCTAssertEqual(flow.keyFailure, .refused(URLError(.userAuthenticationRequired).localizedDescription))
        XCTAssertEqual(flow.draft.key, "sk-bad")
        XCTAssertTrue(saved.isEmpty)
        // An edit makes the reason stale.
        flow.draft.key = "sk-good"
        XCTAssertNil(flow.keyFailure)
    }

    func testIncompleteKeyFormCannotConnect() async {
        let flow = await openedFlow()
        flow.openKeyForm()
        flow.draft.model = "  "
        XCTAssertFalse(flow.canConnectKey)
        await flow.connectKey()
        XCTAssertTrue(probed.isEmpty)
    }

    func testBackFromTheKeyFormReturnsToTheChooser() async {
        let flow = await openedFlow()
        flow.openKeyForm()
        flow.back()
        XCTAssertEqual(flow.phase, .chooser)
    }

    // MARK: - From the chat

    func testASignedOutChatMarksTheCard() async {
        stored = AssistantConfig(provider: .claudeCode)
        let flow = await openedFlow()
        flow.noteSignedOut(.claudeCode)
        XCTAssertEqual(flow.phase, .closed, "the conversation stays on screen")
        flow.open()
        XCTAssertEqual(flow.card(for: .claudeCode), AssistantProviderCard(status: .signedOut, action: .signIn))
    }

    func testDisconnectingReturnsToTheChooser() async {
        stored = AssistantConfig(provider: .claudeCode)
        let flow = await openedFlow()
        stored = nil
        flow.providerRemoved()
        XCTAssertEqual(flow.phase, .chooser)
        XCTAssertFalse(flow.canClose)
    }
}

/// The four questions offered in an empty chat.
@MainActor
final class AssistantSuggestionTests: XCTestCase {
    func testFourSuggestionsInEveryLanguage() {
        XCTAssertEqual(AssistantSuggestion.allCases.count, 4)
        let saved = L10n.shared.language
        defer { L10n.shared.language = saved }
        for language in AppLanguage.allCases {
            L10n.shared.language = language
            let texts = AssistantSuggestion.allCases.map(\.text)
            XCTAssertEqual(Set(texts).count, 4, "\(language)")
            XCTAssertTrue(texts.allSatisfy { !$0.isEmpty }, "\(language)")
        }
        L10n.shared.language = .en
        XCTAssertEqual(AssistantSuggestion.allCases.map(\.text), [
            "What's on my calendar today?",
            "Any unread email?",
            "Set a 25-minute timer",
            "What's playing?",
        ])
    }

    func testSuggestionsShowOnlyInAnEmptyChat() {
        XCTAssertTrue(AssistantSuggestion.isOffered(transcriptIsEmpty: true, isThinking: false))
        XCTAssertFalse(AssistantSuggestion.isOffered(transcriptIsEmpty: false, isThinking: false))
        XCTAssertFalse(AssistantSuggestion.isOffered(transcriptIsEmpty: true, isThinking: true))
    }
}
