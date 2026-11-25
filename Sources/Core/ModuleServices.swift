/// Single shared instances of every module service. Every surface (the
/// widget, Settings, the tour) renders from these — separate copies would
/// diverge (two clipboard histories) or double the work (two media pollers).
@MainActor
final class ModuleServices {
    /// Persisted preferences, for modules that remember a choice.
    let settings: AppSettings
    /// Sparkle. Shared so the status-bar menu and the settings sidebar ask
    /// the same updater.
    let updater = AppUpdater()
    let powerMonitor = PowerSourceMonitor()
    let audioMonitor = AudioSystemMonitor()
    let mediaCenter = MediaCenter()
    let calendarService = CalendarService()
    let statsService = SystemStatsService()
    let shelfStore = ShelfStore(defaults: .app)
    let clipboardStore = ClipboardStore()
    let timerService = TimerService()
    let notesStore = NotesStore()
    let speechCapture = SpeechCaptureService()
    let speechSynthesis = SpeechSynthesisService()
    let emailService = EmailService()
    let senderAvatars = SenderAvatarStore()
    let assistantService = AssistantService()
    let playbookStore = PlaybookStore()
    let playbookRunner: PlaybookRunner
    let appShortcuts = AppShortcutsService()
    /// Scripted data in every module, for promo recordings.
    let demo = DemoMode()
    /// Global shortcuts — the AppDelegate binds their actions, Settings →
    /// Hotkeys rebinds their keys.
    let hotkeys = HotkeyService()
    /// Trial / License gate. `licensingEnforced` is false in debug builds,
    /// where the gate exists but never locks anything.
    let access: Access
    let licensingEnforced = LicensingConfig.isEnforced

    /// Pocket is locked: surfaces show the lock screen instead of modules.
    var isLocked: Bool {
        licensingEnforced && access.state.isLocked
    }

    init(settings: AppSettings) {
        self.settings = settings
        access = Access.live(enforced: licensingEnforced)
        playbookRunner = PlaybookRunner(timer: timerService)
        // The toolbox needs the fully built container, so it attaches last.
        assistantService.attachToolbox(services: self)
        demo.attach(services: self)
        // An app password Mail setup takes from the clipboard is a secret:
        // Clipboard history must not list it.
        emailService.setup.onPasswordPickedUp = { [clipboardStore] in clipboardStore.withhold($0) }
    }

    /// Starts everything that makes macOS ask for access on its own: the
    /// notes folder (Documents by default), the clipboard, scripting the
    /// music players. On first launch the welcome tour calls it once it is
    /// closed — its pages ask for the calendar and the notes folder first.
    func beginProtectedAccess() {
        // UI tests: a system access prompt would block the run.
        guard !UITestMode.isActive else { return }
        notesStore.activate()
        clipboardStore.startWatching()
        mediaCenter.allowPlayerScripts()
    }
}
