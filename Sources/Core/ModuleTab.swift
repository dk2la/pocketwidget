/// Modules of the panel — V3 set. Only the core set (`defaultTabs`) ships
/// enabled; all are toggleable and reorderable in settings. Only Chats is
/// still a placeholder without a backing service.
enum ModuleTab: String, CaseIterable, Identifiable {
    case playbooks
    case calendar
    case email
    case clipboard
    case notes
    case assistant
    case hotkeys
    case chats
    case media
    case timer
    case shelf
    case metrics
    /// The app's settings. Always on — see StripLineup.
    case settings

    var id: String { rawValue }

    /// Core module set: enabled on a fresh install and tagged "default" in
    /// the settings module list. Music, Timer, Shelf and System are opt-in.
    static let defaultTabs: [ModuleTab] = [.playbooks, .calendar, .email, .clipboard, .notes, .assistant, .hotkeys]
    /// No backing service yet — shown as "soon", excluded from defaults.
    static let comingSoon: Set<ModuleTab> = [.chats]

    var isComingSoon: Bool { Self.comingSoon.contains(self) }

    private var spec: (title: L10nKey, icon: String) {
        switch self {
        case .playbooks: (.modPlaybooks, "bolt.fill")
        case .calendar: (.modCalendar, "calendar")
        case .email: (.modEmail, "envelope")
        case .clipboard: (.modClipboard, "doc.on.clipboard")
        case .notes: (.modNotes, "note.text")
        case .assistant: (.modAssistant, "sparkles")
        case .hotkeys: (.modKeys, "keyboard")
        case .chats: (.modChats, "bubble.left")
        case .media: (.modMusic, "music.note")
        case .timer: (.modTimer, "timer")
        case .shelf: (.modShelf, "tray")
        case .metrics: (.modSystem, "gauge")
        case .settings: (.setTitle, "gearshape")
        }
    }

    /// Full localized name for headers and the settings window.
    @MainActor var title: String { L10n.t(spec.title) }
    var icon: String { spec.icon }
}
