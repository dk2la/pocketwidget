import Foundation
import Observation

// Assistant setup inside the module, as logic only: what each provider card
// offers given what is on the Mac, how the answer of the test request is
// read, what the Terminal file contains, and the steps from the chooser to a
// connected provider. Nothing here touches the disk, the network or AppKit;
// all of that comes in through `AssistantSetupFlow.Ports`.

/// What Pocket found on this Mac. Only presence is looked at: Pocket never
/// reads another program's sign-in from the Keychain or from its files.
struct AssistantSetupFacts: Equatable, Sendable {
    /// Full path of the `claude` program, when it is installed.
    var claudePath: String?
    /// Full path of the `codex` program, when it is installed.
    var codexPath: String?
    var hasClaudeApp = false
    var hasChatGPTApp = false
    var hasCurl = false
    /// `npm` is there, which is what installing through Node takes.
    var hasNode = false
    var hasHomebrew = false

    func programPath(for provider: AssistantProvider) -> String? {
        switch provider {
        case .claudeCode: claudePath
        case .codex: codexPath
        case .api: nil
        }
    }

    func hasDesktopApp(for provider: AssistantProvider) -> Bool {
        switch provider {
        case .claudeCode: hasClaudeApp
        case .codex: hasChatGPTApp
        case .api: false
        }
    }
}

/// Decisions that follow from the facts alone.
enum AssistantSetupPlan {
    enum Presence: Equatable {
        /// The command-line program is installed.
        case found
        /// Only the desktop app is installed; the program can be added.
        case appOnly
        /// Neither is installed; the program can be added.
        case missing
        /// The program is missing and nothing on this Mac can install it.
        case noInstaller
    }

    static func presence(of provider: AssistantProvider, facts: AssistantSetupFacts) -> Presence {
        if facts.programPath(for: provider) != nil { return .found }
        guard installCommand(for: provider, facts: facts) != nil else { return .noInstaller }
        return facts.hasDesktopApp(for: provider) ? .appOnly : .missing
    }

    static func needsInstall(_ provider: AssistantProvider, facts: AssistantSetupFacts) -> Bool {
        facts.programPath(for: provider) == nil
    }

    /// The command that installs a provider's program, or `nil` when this
    /// Mac has nothing to install it with.
    ///
    /// Both vendors publish an installer that needs only `curl`, which macOS
    /// ships, so that is the normal case. Homebrew and npm are there for a
    /// Mac where `curl` is somehow gone. Pocket does not install Node or
    /// Homebrew for the person.
    ///
    /// Commands as documented on 2026-11-25:
    /// https://code.claude.com/docs/en/setup and
    /// https://developers.openai.com/codex/cli
    static func installCommand(for provider: AssistantProvider, facts: AssistantSetupFacts) -> String? {
        let commands: (curl: String, brew: String, npm: String)
        switch provider {
        case .claudeCode:
            commands = (
                "curl -fsSL https://claude.ai/install.sh | bash",
                "brew install --cask claude-code",
                "npm install -g @anthropic-ai/claude-code"
            )
        case .codex:
            commands = (
                // Without the variable the installer stops to ask whether
                // to start Codex right away.
                "curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh",
                "brew install --cask codex",
                "npm install -g @openai/codex"
            )
        case .api:
            return nil
        }
        if facts.hasCurl { return commands.curl }
        if facts.hasHomebrew { return commands.brew }
        if facts.hasNode { return commands.npm }
        return nil
    }

    /// What the person runs by hand, once Node is there, on a Mac where
    /// Pocket has nothing to install the program with.
    static func manualCommands(for provider: AssistantProvider) -> [String] {
        guard let name = provider.executableName, let signIn = signInArguments(for: provider) else { return [] }
        let package = provider == .claudeCode ? "@anthropic-ai/claude-code" : "@openai/codex"
        return ["npm install -g \(package)", "\(name) \(signIn)"]
    }

    /// What signs the person in, after the program's name or path.
    static func signInArguments(for provider: AssistantProvider) -> String? {
        switch provider {
        case .claudeCode: "auth login"
        case .codex: "login"
        case .api: nil
        }
    }
}

/// The text of the temporary `.command` file Terminal runs: install when
/// the program is missing, then sign-in.
enum AssistantTerminalScript {
    static func make(for provider: AssistantProvider, facts: AssistantSetupFacts) -> String? {
        guard let name = provider.executableName,
              let signIn = AssistantSetupPlan.signInArguments(for: provider)
        else { return nil }
        var lines = [
            "#!/bin/sh",
            "# Written by Pocket to connect \(provider.title). It removes itself.",
            "rm -f \"$0\"",
            // The installers put the program in ~/.local/bin, which the
            // shell's PATH may not include yet.
            "export PATH=\"$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH\"",
            "clear",
        ]
        let program: String
        if let path = facts.programPath(for: provider) {
            program = quoted(path)
        } else {
            guard let install = AssistantSetupPlan.installCommand(for: provider, facts: facts) else { return nil }
            program = name
            lines += [
                "echo 'Pocket: installing \(name)'",
                "\(install) || {",
                "  echo",
                "  echo 'Pocket: the install did not finish. Close this window and try again.'",
                "  exit 1",
                "}",
                "echo",
            ]
        }
        lines += [
            "echo 'Pocket: sign in to \(provider.title)'",
            "\(program) \(signIn)",
            "echo",
            "echo 'Pocket: you can close this window.'",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    /// One shell word, whatever the text holds.
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Why a provider did not connect, in terms a card can say in plain words.
/// The program's own error text is logged, never shown.
enum AssistantSetupFailure: Equatable, Sendable {
    case notInstalled
    case timedOut
    /// Terminal could not be opened.
    case terminal
    /// The test passed but the setup could not be stored.
    case notSaved
    case other
}

/// The answer of the test request, read.
enum AssistantProbeOutcome: Equatable, Sendable {
    case connected
    /// Nobody is signed in to the program.
    case signedOut
    case failed(AssistantSetupFailure)

    init(_ result: Result<Void, Error>) {
        switch result {
        case .success: self = .connected
        case .failure(let error): self = Self.reading(error)
        }
    }

    private static func reading(_ error: Error) -> AssistantProbeOutcome {
        guard let error = error as? CLIAssistantClient.CLIError else { return .failed(.other) }
        switch error {
        case .notSignedIn: return .signedOut
        case .notInstalled: return .failed(.notInstalled)
        case .timedOut: return .failed(.timedOut)
        case .emptyOutput: return .failed(.other)
        case .failed(let message): return saysSignedOut(message) ? .signedOut : .failed(.other)
        }
    }

    /// The ways `claude` and `codex` say that nobody is signed in:
    /// "Not logged in · Please run /login", "Login expired · Please run
    /// /login", "OAuth token revoked · …", "unexpected status 401
    /// Unauthorized: Missing bearer or basic authentication in header".
    static func saysSignedOut(_ message: String) -> Bool {
        let text = message.lowercased()
        return ["not logged in", "/login", "login expired", "401 unauthorized", "authentication_failed"]
            .contains { text.contains($0) }
    }
}

/// What a provider card shows and the one thing it offers.
struct AssistantProviderCard: Equatable {
    enum Status: Equatable {
        /// This provider answers the chat now.
        case connected
        /// "Found on this Mac".
        case found
        /// The test request said nobody is signed in.
        case signedOut
        case appOnly
        case missing
        /// Steps to follow by hand.
        case noInstaller
        /// The test request is on its way.
        case testing
        /// Terminal is open: "Waiting for sign-in…".
        case waiting
    }

    enum Action: Equatable {
        case connect
        case signIn
        case installAndSignIn
        case cancel
    }

    var status: Status
    var action: Action?
    /// The last try on this card failed for a reason other than sign-in.
    var failure: AssistantSetupFailure?
}

/// The own-key form: any OpenAI-compatible service.
struct AssistantKeyDraft: Equatable {
    var baseURL = AssistantAPIPreset.openai.baseURL
    var model = AssistantAPIPreset.openai.sampleModel
    var key = ""

    var config: AssistantConfig {
        AssistantConfig(
            provider: .api,
            baseURL: baseURL.trimmingCharacters(in: .whitespaces),
            model: model.trimmingCharacters(in: .whitespaces)
        )
    }

    /// The key may be empty: a local Ollama takes none.
    var isComplete: Bool {
        let config = config
        return !config.baseURL.isEmpty && !config.model.isEmpty
    }
}

/// Assistant setup inside the module, from the chooser to a connected
/// provider. It lives with the assistant service, not in a view, so a
/// half-done setup survives the panel closing while the person signs in.
///
/// Pocket never connects a provider by itself: every path to `save` starts
/// with a click on a card.
@MainActor
@Observable
final class AssistantSetupFlow {
    enum Phase: Equatable {
        /// Setup is not open; the chat is.
        case closed
        case chooser
        /// A found program was clicked; the test request is on its way.
        case testing(AssistantProvider)
        /// Terminal is open for install and sign-in.
        case waiting(AssistantProvider)
        case ownKey
    }

    /// Everything the flow needs from outside.
    struct Ports {
        /// Looks at what is installed.
        var detect: @MainActor () async -> AssistantSetupFacts
        /// The test request: one tiny round-trip through the provider.
        var probe: @MainActor (AssistantConfig, String) async -> Result<Void, Error>
        /// Runs a script in Terminal; false when Terminal did not open.
        var openTerminal: @MainActor (String) -> Bool
        /// The clock of the waiting card.
        var sleep: @MainActor (Duration) async -> Void
        var currentConfig: @MainActor () -> AssistantConfig?
        /// The API key as stored, for the form of a saved own-key setup.
        var storedKey: @MainActor () -> String
        /// Stores a tested setup; false when it could not be stored.
        var save: @MainActor (AssistantConfig, String) -> Bool
    }

    static let pollInterval: Duration = .seconds(2)

    private(set) var phase: Phase {
        didSet { syncPolling() }
    }

    private(set) var facts = AssistantSetupFacts()
    /// False until the Mac has been looked at once. The first look can take
    /// seconds, and until it is done a card must not offer to install a
    /// program that may well be there.
    private(set) var hasLooked = false

    var draft = AssistantKeyDraft() {
        didSet {
            // The reason belongs to what was tested; an edit makes it stale.
            if draft != oldValue { keyFailure = nil }
        }
    }

    enum KeyFailure: Equatable {
        /// The service refused or was not reached; its own words.
        case refused(String)
        /// The test passed but the setup could not be stored.
        case notSaved
    }

    private(set) var keyFailure: KeyFailure?
    private(set) var isTestingKey = false

    private var signedOut: Set<AssistantProvider> = []
    private var failures: [AssistantProvider: AssistantSetupFailure] = [:]

    @ObservationIgnored private let ports: Ports
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    /// Bumped whenever polling stops, so a loop that is mid-wait notices.
    @ObservationIgnored private var pollGeneration = 0
    @ObservationIgnored private var polledProvider: AssistantProvider?
    private(set) var isPolling = false

    init(ports: Ports) {
        self.ports = ports
        phase = ports.currentConfig() == nil ? .chooser : .closed
    }

    // MARK: - Reading

    var isOpen: Bool { phase != .closed }

    /// There is a chat to go back to.
    var canClose: Bool { ports.currentConfig() != nil }

    var canConnectKey: Bool { phase == .ownKey && draft.isComplete && !isTestingKey }

    func card(for provider: AssistantProvider) -> AssistantProviderCard {
        let isCurrent = ports.currentConfig()?.provider == provider
        // The own-key card has no program behind it: it opens the form.
        guard provider.isCLI else {
            return AssistantProviderCard(status: isCurrent ? .connected : .found, action: .connect)
        }
        switch phase {
        case .testing(provider):
            return AssistantProviderCard(status: .testing, action: nil)
        case .waiting(provider):
            return AssistantProviderCard(status: .waiting, action: .cancel)
        default:
            break
        }
        guard hasLooked else {
            return AssistantProviderCard(status: .testing, action: nil)
        }
        let failure = failures[provider]
        if signedOut.contains(provider), facts.programPath(for: provider) != nil {
            return AssistantProviderCard(status: .signedOut, action: .signIn, failure: failure)
        }
        if isCurrent {
            return AssistantProviderCard(status: .connected, action: nil, failure: failure)
        }
        switch AssistantSetupPlan.presence(of: provider, facts: facts) {
        case .found: return AssistantProviderCard(status: .found, action: .connect, failure: failure)
        case .appOnly: return AssistantProviderCard(status: .appOnly, action: .installAndSignIn, failure: failure)
        case .missing: return AssistantProviderCard(status: .missing, action: .installAndSignIn, failure: failure)
        case .noInstaller: return AssistantProviderCard(status: .noInstaller, action: nil, failure: failure)
        }
    }

    // MARK: - Steps

    /// The module panel came on screen or left it. The waiting card only
    /// checks while it can be seen.
    func setVisible(_ visible: Bool) {
        isVisible = visible
        syncPolling()
    }

    /// Looks again at what is installed.
    func refresh() async {
        facts = await ports.detect()
        hasLooked = true
    }

    /// Opens the chooser over the chat; the conversation is untouched.
    func open() {
        guard phase == .closed else { return }
        phase = .chooser
    }

    /// Back to the chat, when there is a provider to chat with.
    func close() {
        guard canClose else { return }
        phase = .closed
    }

    /// One level up: the form and the waiting card lead to the chooser,
    /// the chooser to the chat.
    func back() {
        switch phase {
        case .ownKey, .waiting, .testing: phase = .chooser
        case .chooser: close()
        case .closed: break
        }
    }

    /// One click on a found program: test it, then connect.
    func connect(_ provider: AssistantProvider) async {
        guard provider.isCLI, facts.programPath(for: provider) != nil, canStartStep else { return }
        failures[provider] = nil
        phase = .testing(provider)
        let config = config(for: provider)
        let result = await ports.probe(config, "")
        // Left or changed in the meantime.
        guard phase == .testing(provider) else { return }
        switch AssistantProbeOutcome(result) {
        case .connected:
            finish(config, key: "")
        case .signedOut:
            signedOut.insert(provider)
            phase = .chooser
        case .failed(let failure):
            failures[provider] = failure
            phase = .chooser
        }
    }

    /// "Install and sign in" / "Sign in": Terminal runs the commands and
    /// the card waits.
    func startSignIn(_ provider: AssistantProvider) {
        guard canStartStep, let script = AssistantTerminalScript.make(for: provider, facts: facts) else { return }
        failures[provider] = nil
        guard ports.openTerminal(script) else {
            failures[provider] = .terminal
            phase = .chooser
            return
        }
        phase = .waiting(provider)
    }

    func cancelWaiting() {
        guard case .waiting = phase else { return }
        phase = .chooser
    }

    func openKeyForm() {
        guard isOpen else { return }
        if let config = ports.currentConfig(), !config.provider.isCLI {
            draft = AssistantKeyDraft(baseURL: config.baseURL, model: config.model, key: ports.storedKey())
        }
        keyFailure = nil
        phase = .ownKey
    }

    func applyPreset(_ preset: AssistantAPIPreset) {
        draft.baseURL = preset.baseURL
        draft.model = preset.sampleModel
    }

    /// Tests the own-key setup. Success stores it; failure keeps the form.
    func connectKey() async {
        guard canConnectKey else { return }
        let config = draft.config
        let key = draft.key
        isTestingKey = true
        let result = await ports.probe(config, key)
        isTestingKey = false
        guard phase == .ownKey else { return }
        switch result {
        case .success:
            if !finish(config, key: key) { keyFailure = .notSaved }
        case .failure(let error):
            keyFailure = .refused(error.localizedDescription)
        }
    }

    /// A chat turn came back "not signed in": the card offers sign-in the
    /// next time the chooser is opened.
    func noteSignedOut(_ provider: AssistantProvider) {
        signedOut.insert(provider)
    }

    /// The saved provider was removed: there is no chat to show.
    func providerRemoved() {
        signedOut = []
        failures = [:]
        draft = AssistantKeyDraft()
        phase = .chooser
    }

    // MARK: - Inside

    /// A new step may start from the chooser, or replace a waiting card.
    private var canStartStep: Bool {
        switch phase {
        case .chooser, .waiting: true
        case .closed, .testing, .ownKey: false
        }
    }

    /// Model names do not carry across providers.
    private func config(for provider: AssistantProvider) -> AssistantConfig {
        if let current = ports.currentConfig(), current.provider == provider { return current }
        return AssistantConfig(provider: provider)
    }

    @discardableResult
    private func finish(_ config: AssistantConfig, key: String) -> Bool {
        guard ports.save(config, key) else {
            failures[config.provider] = .notSaved
            if phase != .ownKey { phase = .chooser }
            return false
        }
        signedOut.remove(config.provider)
        failures = [:]
        draft = AssistantKeyDraft()
        phase = .closed
        return true
    }

    // MARK: - Waiting for sign-in

    private var waitingProvider: AssistantProvider? {
        if case .waiting(let provider) = phase { return provider }
        return nil
    }

    private func syncPolling() {
        let wanted = isVisible ? waitingProvider : nil
        guard wanted != polledProvider else { return }
        pollGeneration += 1
        polledProvider = wanted
        isPolling = wanted != nil
        guard let provider = wanted else { return }
        let generation = pollGeneration
        let previous = pollTask
        pollTask = Task { [weak self] in
            await previous?.value
            await self?.poll(provider, generation: generation)
        }
    }

    /// Every couple of seconds: is the program there yet, and does the test
    /// request pass? The first pass connects the provider.
    private func poll(_ provider: AssistantProvider, generation: Int) async {
        while generation == pollGeneration {
            await ports.sleep(Self.pollInterval)
            guard generation == pollGeneration else { return }
            let found = await ports.detect()
            guard generation == pollGeneration else { return }
            facts = found
            hasLooked = true
            // The installer is still running.
            guard found.programPath(for: provider) != nil else { continue }
            let config = config(for: provider)
            let result = await ports.probe(config, "")
            guard generation == pollGeneration else { return }
            if case .connected = AssistantProbeOutcome(result) {
                finish(config, key: "")
                return
            }
        }
    }

    /// Returns once no check is running. For tests.
    func pollingEnded() async {
        await pollTask?.value
    }
}

/// The questions offered in an empty chat. All four are always shown: when
/// something is not connected the assistant answers by asking for access.
enum AssistantSuggestion: CaseIterable, Identifiable {
    case calendar, mail, timer, playing

    var id: Self { self }

    @MainActor var text: String {
        switch self {
        case .calendar: L10n.t(.asstSuggestCalendar)
        case .mail: L10n.t(.asstSuggestMail)
        case .timer: L10n.t(.asstSuggestTimer)
        case .playing: L10n.t(.asstSuggestPlaying)
        }
    }

    /// Offered until the first message is sent.
    static func isOffered(transcriptIsEmpty: Bool, isThinking: Bool) -> Bool {
        transcriptIsEmpty && !isThinking
    }
}
