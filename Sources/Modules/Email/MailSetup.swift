import AppKit
import Observation

/// What a mail setup form holds while the user fills it: the provider, the
/// address, the password and — for a custom provider — its servers. Shared
/// by the setup in the Mail module and the one in Settings.
struct MailSetupDraft: Equatable {
    private(set) var provider: EmailProvider = .gmail
    var email = ""
    var password = ""
    var imapHost = ""
    var imapPort = "993"
    var smtpHost = ""
    var smtpPort = "465"

    init() {
        select(.gmail)
    }

    /// The form for an account that is already saved; the password stays in
    /// the Keychain and is not shown.
    init(config: EmailAccountConfig) {
        provider = EmailProvider(rawValue: config.presetID) ?? .custom
        email = config.email
        imapHost = config.imapHost
        imapPort = String(config.imapPort)
        smtpHost = config.smtpHost
        smtpPort = String(config.smtpPort)
    }

    /// Switches the provider; a preset fills in its servers.
    mutating func select(_ newProvider: EmailProvider) {
        provider = newProvider
        if let preset = newProvider.preset {
            imapHost = preset.0
            imapPort = String(preset.1)
            smtpHost = preset.2
            smtpPort = String(preset.3)
        }
    }

    /// Everything but the password is there.
    var isComplete: Bool {
        let config = config
        return !config.email.isEmpty && !config.imapHost.isEmpty && !config.smtpHost.isEmpty
    }

    var config: EmailAccountConfig {
        let address = email.trimmingCharacters(in: .whitespaces)
        if let preset = provider.preset {
            return EmailAccountConfig(
                email: address,
                imapHost: preset.0,
                imapPort: preset.1,
                smtpHost: preset.2,
                smtpPort: preset.3,
                smtpUsesSTARTTLS: preset.4,
                presetID: provider.rawValue
            )
        }
        let smtp = UInt16(smtpPort) ?? 465
        return EmailAccountConfig(
            email: address,
            imapHost: imapHost.trimmingCharacters(in: .whitespaces),
            imapPort: UInt16(imapPort) ?? 993,
            smtpHost: smtpHost.trimmingCharacters(in: .whitespaces),
            smtpPort: smtp,
            smtpUsesSTARTTLS: smtp == 587,
            presetID: provider.rawValue
        )
    }
}

/// Why Connect did not connect, in terms the form can say in plain words.
enum MailSetupFailure: Equatable {
    /// The server answered and refused the address and password.
    case rejected
    /// The server could not be reached at all.
    case unreachable
    /// The account checked out but the password could not be stored.
    case notSaved
    /// Anything else, in the server's own words.
    case other(String)

    init(_ error: Error) {
        switch error {
        case MailError.authFailed: self = .rejected
        case MailError.badResponse(let message): self = .other(message)
        // Timeouts, dropped sockets, TLS and whatever the network layer
        // throws: the conversation with the server never got going.
        default: self = .unreachable
        }
    }
}

/// The clipboard as mail setup sees it.
@MainActor
protocol MailSetupPasteboard: AnyObject {
    /// Changes whenever something new is copied.
    var changeCount: Int { get }
    func readText() -> String?
}

@MainActor
final class SystemMailSetupPasteboard: MailSetupPasteboard {
    var changeCount: Int { NSPasteboard.general.changeCount }
    func readText() -> String? { NSPasteboard.general.string(forType: .string) }
}

/// Mail setup inside the Mail module, from "Add mail" to a connected
/// account. It outlives the panel — the user leaves for the browser to get
/// an app password and comes back to the same step — so it lives with the
/// mail service, not in a view. Nothing here is written to disk: the
/// password reaches the Keychain only through `onConnected`.
///
/// While setup waits for a password it watches the clipboard and takes a
/// copied app password by itself (see `EmailProvider.appPassword(in:)`).
/// The watch is on only in that state: not before `begin()`, not while
/// connecting, not after connecting or `cancel()`, and never for a
/// provider without an app-password format.
@MainActor
@Observable
final class MailSetupFlow {
    enum Phase: Equatable {
        /// Setup is not open.
        case idle
        case editing
        case connecting
        /// Connect failed; the form is editable and keeps what was typed.
        case failed(MailSetupFailure)
    }

    typealias Probe = @MainActor (EmailAccountConfig, String) async -> Result<Void, Error>

    private(set) var phase: Phase = .idle {
        didSet { syncWatch() }
    }

    var draft = MailSetupDraft() {
        didSet {
            guard draft != oldValue else { return }
            // The reason belongs to what was checked; an edit makes it stale.
            if case .failed = phase { phase = .editing }
            syncWatch()
        }
    }

    /// The clipboard is being watched for an app password right now.
    private(set) var isWatching = false

    /// Stores the checked account; false when it could not be stored.
    @ObservationIgnored var onConnected: ((EmailAccountConfig, String) -> Bool)?
    /// Called with the copied text a password was taken from, so Clipboard
    /// history can leave it out.
    @ObservationIgnored var onPasswordPickedUp: ((String) -> Void)?

    @ObservationIgnored private let pasteboard: MailSetupPasteboard
    @ObservationIgnored private let pollInterval: Duration?
    @ObservationIgnored private let probe: Probe
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var lastChangeCount = 0
    /// The password the clipboard gave, while the field still holds it.
    private var pickedUpPassword: String?

    /// `pollInterval` nil leaves the watch to explicit `checkClipboard()`
    /// calls (tests).
    init(
        pasteboard: MailSetupPasteboard,
        pollInterval: Duration? = .milliseconds(500),
        probe: @escaping Probe
    ) {
        self.pasteboard = pasteboard
        self.pollInterval = pollInterval
        self.probe = probe
    }

    var isActive: Bool { phase != .idle }

    var canConnect: Bool {
        switch phase {
        case .editing, .failed: draft.isComplete && !draft.password.isEmpty
        case .idle, .connecting: false
        }
    }

    /// The password in the field came from the clipboard, not from typing.
    var passwordWasPickedUp: Bool {
        pickedUpPassword != nil && pickedUpPassword == draft.password
    }

    // MARK: - Steps

    func begin() {
        guard phase == .idle else { return }
        phase = .editing
    }

    func select(_ provider: EmailProvider) {
        draft.select(provider)
    }

    /// Closes setup and forgets everything typed, the password included.
    func cancel() {
        phase = .idle
        draft = MailSetupDraft()
        pickedUpPassword = nil
    }

    /// Checks the account with the server. Success stores it and ends
    /// setup; failure keeps the form as it is and says why.
    func connect() async {
        guard canConnect else { return }
        let config = draft.config
        let password = draft.password
        phase = .connecting
        let result = await probe(config, password)
        // Cancelled (or connected from Settings) in the meantime.
        guard phase == .connecting else { return }
        switch result {
        case .success:
            if onConnected?(config, password) ?? false {
                cancel()
            } else {
                phase = .failed(.notSaved)
            }
        case .failure(let error):
            phase = .failed(MailSetupFailure(error))
        }
    }

    // MARK: - Clipboard watch

    private var isWaitingForPassword: Bool {
        switch phase {
        case .editing, .failed: draft.provider.appPasswordURL != nil
        case .idle, .connecting: false
        }
    }

    private func syncWatch() {
        let shouldWatch = isWaitingForPassword
        guard shouldWatch != isWatching else { return }
        isWatching = shouldWatch
        watchTask?.cancel()
        watchTask = nil
        guard shouldWatch else { return }
        // Only what is copied from now on counts.
        lastChangeCount = pasteboard.changeCount
        guard let pollInterval else { return }
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: pollInterval)
                guard !Task.isCancelled else { return }
                self?.checkClipboard()
            }
        }
    }

    /// One look at the clipboard: a newly copied app password of the chosen
    /// provider goes into the password field, anything else is left alone.
    func checkClipboard() {
        guard isWatching else { return }
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        guard let copied = pasteboard.readText(),
              let password = draft.provider.appPassword(in: copied)
        else { return }
        pickedUpPassword = password
        draft.password = password
        onPasswordPickedUp?(copied)
    }
}
