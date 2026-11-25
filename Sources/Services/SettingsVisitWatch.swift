import AppKit

/// Makes the widget yield to System Settings that Pocket just opened (see
/// `SettingsVisit` for the rules). One visit at a time: opening another
/// pane starts over. Every path ends the yield — Settings quitting, never
/// showing up, or the timeout.
@MainActor
final class SettingsVisitWatch {
    static let shared = SettingsVisitWatch()

    private nonisolated static let settingsBundleID = "com.apple.systempreferences"
    /// System Settings may take a while to come up cold.
    private static let launchWindow: Duration = .seconds(15)
    /// Same as the permission guide's lifetime.
    private static let timeout: Duration = .seconds(600)

    private var visit: SettingsVisit?
    private var yield: PanelHold.Yield?
    private var observers: [NSObjectProtocol] = []
    private var timers: [Task<Void, Never>] = []

    private init() {}

    func start() {
        stop()
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.settingsBundleID
        visit = SettingsVisit(settingsFrontmost: frontmost)

        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { note in
                let isSettings = Self.bundleID(of: note) == Self.settingsBundleID
                MainActor.assumeIsolated {
                    self.handle(isSettings ? .settingsActivated : .otherAppActivated)
                }
            },
            center.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
            ) { note in
                guard Self.bundleID(of: note) == Self.settingsBundleID else { return }
                MainActor.assumeIsolated { self.handle(.settingsQuit) }
            },
        ]
        timers = [
            after(Self.launchWindow, .launchWindowPassed),
            after(Self.timeout, .timedOut),
        ]
        apply()
    }

    private nonisolated static func bundleID(of note: Notification) -> String? {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
    }

    private func after(_ delay: Duration, _ event: SettingsVisit.Event) -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.handle(event)
        }
    }

    private func handle(_ event: SettingsVisit.Event) {
        guard visit != nil else { return }
        visit?.handle(event)
        if visit?.isOver == true {
            stop()
        } else {
            apply()
        }
    }

    /// Mirrors the visit's verdict into one yield of the shared hold.
    private func apply() {
        let yields = visit?.yields ?? false
        if yields, yield == nil {
            // The backstop outlives the visit's own timeout by a little.
            yield = PanelHold.shared.beginYield(timeout: Self.timeout + .seconds(5))
        } else if !yields, let current = yield {
            PanelHold.shared.end(current)
            yield = nil
        }
    }

    private func stop() {
        visit = nil
        apply()
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
        timers.forEach { $0.cancel() }
        timers.removeAll()
    }
}
