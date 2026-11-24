import AppKit
import Observation

/// Text clipboard history. Kept in memory only — persisting clipboard
/// contents to disk would be a privacy hazard.
@MainActor
@Observable
final class ClipboardStore {
    typealias Entry = ClipboardHistory.Entry

    private var history = ClipboardHistory()
    var entries: [Entry] { history.entries }

    @ObservationIgnored private var lastChangeCount = NSPasteboard.general.changeCount
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    /// Password managers mark secrets with this type — never record them.
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// Reading another app's copy may raise macOS's paste-access prompt, so
    /// watching starts only once the welcome tour is out of the way.
    func startWatching() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - Demo mode

    /// Scripted history; the pasteboard is not watched while it is shown,
    /// so a stray copy during recording never lands in the list.
    private(set) var isDemo = false
    @ObservationIgnored private var parkedEntries: [Entry] = []

    func enterDemo(entries demoEntries: [Entry]) {
        guard !isDemo else { return }
        isDemo = true
        parkedEntries = entries
        history.entries = demoEntries
    }

    func exitDemo() {
        guard isDemo else { return }
        isDemo = false
        history.entries = parkedEntries
        parkedEntries = []
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func poll() {
        guard !isDemo else { return }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        let types = pasteboard.types ?? []
        guard !types.contains(Self.concealedType), !types.contains(Self.transientType),
              let text = pasteboard.string(forType: .string)
        else { return }
        history.record(text, at: Date())
    }

    /// Keeps a secret another module took from the clipboard out of the
    /// history — the app password Mail setup picks up. Whichever of the two
    /// sees the copy first, the text does not stay listed.
    func withhold(_ text: String) {
        history.withhold(text)
        // History parked under demo mode must not bring it back either.
        parkedEntries.removeAll { $0.text == text }
    }

    /// Puts an entry back onto the pasteboard and moves it to the top.
    func copy(_ entry: Entry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
        // Our own write must not be re-captured as a new entry.
        lastChangeCount = pasteboard.changeCount
        history.entries.removeAll { $0.id == entry.id }
        history.entries.insert(entry, at: 0)
    }

    func clear() {
        history.entries.removeAll()
    }
}
