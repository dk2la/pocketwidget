/// One trip to System Settings that Pocket started (a privacy pane). Opening
/// it returns at once while the window stays up, so whether the widget
/// should still yield follows what the user does: it yields while Settings
/// is in front and comes back on top once they go elsewhere. The visit ends
/// when Settings quits, never shows up, or at the caller's timeout.
struct SettingsVisit {
    enum Event {
        case settingsActivated
        case otherAppActivated
        case settingsQuit
        /// Settings has had time to launch cold.
        case launchWindowPassed
        case timedOut
    }

    private(set) var yields = true
    private(set) var isOver = false
    private var sawSettings: Bool

    init(settingsFrontmost: Bool) {
        sawSettings = settingsFrontmost
    }

    mutating func handle(_ event: Event) {
        guard !isOver else { return }
        switch event {
        case .settingsActivated:
            sawSettings = true
            yields = true
        case .otherAppActivated:
            // Before Settings comes up, activations are its launch noise.
            if sawSettings { yields = false }
        case .settingsQuit, .timedOut:
            finish()
        case .launchWindowPassed:
            if !sawSettings { finish() }
        }
    }

    private mutating func finish() {
        isOver = true
        yields = false
    }
}
