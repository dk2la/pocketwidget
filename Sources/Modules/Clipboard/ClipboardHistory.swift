import Foundation

/// The list behind Clipboard history: copied text, newest first, capped.
/// Text that another part of Pocket claims as a secret — the app password
/// Mail setup picks up from the clipboard — is withheld: it is dropped from
/// the list if already there and never listed afterwards.
struct ClipboardHistory {
    struct Entry: Identifiable, Equatable {
        let id: UUID
        let text: String
        let copiedAt: Date
    }

    static let capacity = 25
    private static let maxLength = 10_000

    var entries: [Entry] = []
    /// Kept in memory only, like the history itself.
    private var withheld: Set<String> = []

    /// Lists newly copied text at the top; blank and withheld text is not
    /// listed.
    mutating func record(_ copied: String, at date: Date) {
        let text = Self.normalized(copied)
        guard !text.isEmpty, !withheld.contains(text), text != entries.first?.text else { return }
        entries.removeAll { $0.text == text }
        entries.insert(Entry(id: UUID(), text: String(text.prefix(Self.maxLength)), copiedAt: date), at: 0)
        if entries.count > Self.capacity {
            entries.removeLast(entries.count - Self.capacity)
        }
    }

    /// Keeps `copied` out of the history, whether it was listed already or
    /// is copied again later.
    mutating func withhold(_ copied: String) {
        let text = Self.normalized(copied)
        guard !text.isEmpty else { return }
        withheld.insert(text)
        entries.removeAll { $0.text == text }
    }

    private static func normalized(_ copied: String) -> String {
        copied.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
