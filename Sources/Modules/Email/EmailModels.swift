import Foundation

/// Mail account configuration. Non-secret parts live in UserDefaults; the
/// password lives in the Keychain under the account's email address.
struct EmailAccountConfig: Codable, Equatable {
    var email: String
    var imapHost: String
    var imapPort: UInt16
    var smtpHost: String
    var smtpPort: UInt16
    var smtpUsesSTARTTLS: Bool
    var presetID: String

    static let defaultsKey = "email.account.v1"
    static let keychainService = "com.dk2la.pocket.email"
}

/// Provider presets — prefill hosts/ports and carry the auth hint.
enum EmailProvider: String, CaseIterable, Identifiable {
    case gmail
    case icloud
    case yandex
    case outlook
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gmail: "Gmail"
        case .icloud: "iCloud"
        case .yandex: "Yandex"
        case .outlook: "Outlook"
        case .custom: "Custom"
        }
    }

    /// (imapHost, imapPort, smtpHost, smtpPort, startTLS)
    var preset: (String, UInt16, String, UInt16, Bool)? {
        switch self {
        case .gmail: ("imap.gmail.com", 993, "smtp.gmail.com", 465, false)
        case .icloud: ("imap.mail.me.com", 993, "smtp.mail.me.com", 587, true)
        case .yandex: ("imap.yandex.com", 993, "smtp.yandex.com", 465, false)
        case .outlook: ("outlook.office365.com", 993, "smtp-mail.outlook.com", 587, true)
        case .custom: nil
        }
    }

    /// Personal Outlook killed password auth for IMAP — warn up front.
    var isPasswordAuthUnreliable: Bool { self == .outlook }

    /// The provider's page for creating an app password; nil where there is
    /// no such page to send the user to.
    var appPasswordURL: URL? {
        switch self {
        case .gmail: URL(string: "https://myaccount.google.com/apppasswords")
        // "App-Specific Passwords" sits in the Sign-In and Security section.
        case .icloud: URL(string: "https://account.apple.com/account/manage")
        case .yandex: URL(string: "https://id.yandex.com/security/app-passwords")
        case .outlook, .custom: nil
        }
    }

    /// The app password in `copied`, when the whole text has the shape this
    /// provider issues them in; nil for anything else. Mail setup uses it to
    /// tell a freshly copied password from ordinary clipboard text.
    ///
    /// - Gmail: 16 lowercase letters, shown as four groups of four with
    ///   spaces between; returned without the spaces.
    /// - iCloud: `xxxx-xxxx-xxxx-xxxx`, lowercase letters, hyphens kept.
    /// - Yandex: 16 lowercase letters.
    func appPassword(in copied: String) -> String? {
        let text = copied.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
        case .gmail:
            let groups = text.split(omittingEmptySubsequences: false) { $0 == " " || $0 == "\u{00A0}" }
            if groups.count == 1 {
                return Self.isLowercaseLetters(text, count: 16) ? text : nil
            }
            guard groups.count == 4, groups.allSatisfy({ Self.isLowercaseLetters($0, count: 4) }) else {
                return nil
            }
            return groups.joined()
        case .icloud:
            let groups = text.split(separator: "-", omittingEmptySubsequences: false)
            guard groups.count == 4, groups.allSatisfy({ Self.isLowercaseLetters($0, count: 4) }) else {
                return nil
            }
            return text
        case .yandex:
            return Self.isLowercaseLetters(text, count: 16) ? text : nil
        case .outlook, .custom:
            return nil
        }
    }

    private static func isLowercaseLetters(_ text: some StringProtocol, count: Int) -> Bool {
        text.count == count && text.allSatisfy { $0.isASCII && $0.isLowercase }
    }
}

/// Gmail-like inbox sections. Each one is a message list of its own; the
/// IMAP folder (or search) behind it depends on the server — see
/// `EmailService` for the mapping.
enum Mailbox: String, CaseIterable, Sendable, Codable {
    /// INBOX; on Gmail, the Primary category of it.
    case primary
    /// Flagged (starred) messages in INBOX.
    case starred
    /// Gmail's Important label; hidden elsewhere.
    case important
    case sent
    case spam

    static let defaultsKey = "email.mailbox.v1"
}

/// UIDs are only unique inside one IMAP folder: the same number names a
/// different message in INBOX and in Sent. Everything that caches or looks
/// up a message keys by folder + UID.
struct MessageKey: Hashable, Sendable, Codable {
    var mailbox: String
    var uid: UInt32
}

/// What the inbox's list area shows. A search that has run decides alone:
/// its hits replace the mailbox list, and no hits is an empty screen even
/// when the mailbox has mail.
enum InboxListState: Equatable {
    /// The selected mailbox has no messages.
    case emptyInbox
    /// A search ran and found nothing.
    case noSearchResults
    case messages([EmailMessage])

    init(messages: [EmailMessage], searchResults: [EmailMessage]?) {
        if let searchResults {
            self = searchResults.isEmpty ? .noSearchResults : .messages(searchResults)
        } else {
            self = messages.isEmpty ? .emptyInbox : .messages(messages)
        }
    }

    /// True when the list area is the empty screen.
    var isEmpty: Bool {
        if case .messages = self { return false }
        return true
    }
}

/// One inbox message. `bodyPlain` is filled lazily on open.
struct EmailMessage: Identifiable, Equatable, Sendable, Codable {
    let uid: UInt32
    /// The IMAP folder the UID belongs to.
    var mailbox: String = "INBOX"
    var subject: String
    var fromName: String
    var fromAddress: String
    /// Plain addresses from the envelope: where replies are asked to go,
    /// and who else was on the message (for Reply all).
    var replyTo: String?
    var to: [String] = []
    /// Display name of the first To recipient, when the envelope had one.
    var toName: String?
    var cc: [String] = []
    var date: Date
    var isUnread: Bool
    var messageID: String?
    var references: [String]
    var bodyPlain: String?
    /// Raw HTML of the body when the message is HTML — rendered richly in
    /// the reader; `bodyPlain` stays as the flattened fallback/preview.
    var bodyHTML: String?
    /// Where the readable part lives and how it is encoded.
    var textPart: TextPartInfo?

    var key: MessageKey { MessageKey(mailbox: mailbox, uid: uid) }
    var id: MessageKey { key }

    /// Who the message went to, for lists of outgoing mail: the first
    /// recipient's name, else their address.
    var recipientDisplay: String {
        if let toName, !toName.isEmpty { return toName }
        return to.first ?? ""
    }

    struct TextPartInfo: Equatable, Sendable, Codable {
        var section: String
        var encoding: String
        var charset: String
        /// text/html parts are flattened to text after decoding.
        var isHTML: Bool = false
    }
}

/// What one body fetch brings back: the readable text plus the threading
/// chain, which ENVELOPE does not carry.
struct MessageBody: Sendable {
    var text: String
    var references: [String]
    /// Present when the readable part was HTML.
    var html: String?
}

/// How a compose form was seeded from an open message; nil means new mail.
enum ReplyMode: Equatable, Sendable {
    case reply
    case replyAll
    case forward
}

/// A reply ready for the wire.
struct OutgoingMail: Sendable {
    var from: String
    var to: String
    var cc: [String] = []
    var subject: String
    var body: String
    var inReplyTo: String?
    var references: [String]
}

enum MailConnectionState: Equatable {
    case offline
    case connecting
    case online
    case failed(String)
}

enum MailError: Error, LocalizedError {
    case timeout
    case connectionClosed
    case badResponse(String)
    case authFailed(String)
    case tls(String)

    var errorDescription: String? {
        switch self {
        case .timeout: "Connection timed out"
        case .connectionClosed: "Connection closed"
        case .badResponse(let s): s
        case .authFailed(let s): s
        case .tls(let s): s
        }
    }

    /// Errors where the socket, not the request, is the suspect — the only
    /// ones a session may transparently retry on a fresh connection.
    var isTransportFailure: Bool {
        switch self {
        case .timeout, .connectionClosed, .tls: true
        case .badResponse, .authFailed: false
        }
    }
}
