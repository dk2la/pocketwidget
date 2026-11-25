import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings: AppSettings
    private let services: ModuleServices
    private var statusItem: NSStatusItem?
    private var capsuleController: CapsuleWindowController?
    private var widgetController: WidgetWindowController?
    private var licensingTask: Task<Void, Never>?

    override init() {
        settings = AppSettings()
        services = ModuleServices(settings: settings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        registerHotkeys()
        capsuleController = CapsuleWindowController(settings: settings, services: services)

        // Modules, Settings and the welcome tour live in the edge widget.
        widgetController = WidgetWindowController(settings: settings, services: services)
        settings.addChangeHandler { [weak self] in
            self?.widgetController?.settingsDidChange()
        }

        // Module UI (e.g. the "+ new" playbook card) asks for a settings
        // page through this notification.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenSettings(_:)),
            name: .pocketOpenSettings,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openOnboarding),
            name: .pocketOpenOnboarding,
            object: nil
        )

        startLicensing()

        // A demo event is asked for from Settings, an open panel the pill
        // is skipped over — the widget closes it first, then shows the pill.
        services.demo.presentEvent = { [weak self] event in
            self?.widgetController?.presentEvent(event, closingPanel: true)
        }

        // `--demo`: scripted data in every module from the first frame.
        if CommandLine.arguments.contains("--demo") {
            services.demo.activate()
        }

        // Developer convenience: `open Pocket.app --args --settings`
        // wins over the tour; `--onboarding` forces the tour even when the
        // user switched it off.
        if CommandLine.arguments.contains("--settings") {
            services.beginProtectedAccess()
            showSettings(page: nil)
        } else if let tab = Self.launchTab() {
            // `--tab <module>`: open that module's panel, skip the tour —
            // for screenshots and promo recordings.
            services.beginProtectedAccess()
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                NotificationCenter.default.post(name: .pocketShowModule, object: nil, userInfo: ["tab": tab.rawValue])
            }
        } else if (settings.showOnboardingAtLaunch && !UITestMode.isActive)
            || CommandLine.arguments.contains("--onboarding") {
            // UI tests get the tour only when they ask for it.
            deferProtectedAccessUntilTourCloses()
            // A beat after launch, so the panel visibly opens instead of
            // appearing already open.
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                self?.widgetController?.openOnboarding()
            }
        } else {
            services.beginProtectedAccess()
        }
    }

    /// Refreshes the Access module at launch, every hour after that and on
    /// wake. The module itself decides what is due (the License key is
    /// re-validated once a day), so over-calling is harmless.
    private func startLicensing() {
        guard services.licensingEnforced else { return }
        let access = services.access
        licensingTask = Task {
            while !Task.isCancelled {
                await access.refresh()
                try? await Task.sleep(for: .seconds(3600))
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(refreshAccess),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func refreshAccess() {
        let access = services.access
        Task { await access.refresh() }
    }

    /// Module named by `--tab <name>` at launch, if any.
    private static func launchTab() -> ModuleTab? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--tab"), index + 1 < args.count else { return nil }
        return ModuleTab(rawValue: args[index + 1])
    }

    /// First launch: no access prompt may pile up on top of the tour. Its
    /// pages ask for the calendar and the notes folder one by one; the rest
    /// (clipboard, music players) starts once the tour closes.
    private func deferProtectedAccessUntilTourCloses() {
        guard !settings.onboardingCompleted else {
            services.beginProtectedAccess()
            return
        }
        widgetController?.onTourClosed = { [weak self] in
            guard let self else { return }
            self.widgetController?.onTourClosed = nil
            self.settings.onboardingCompleted = true
            self.services.beginProtectedAccess()
        }
    }

    /// Global shortcuts (Carbon — no permissions needed). H and P act on
    /// the widget; M opens or closes its Settings module.
    private func registerHotkeys() {
        let hotkeys = services.hotkeys
        hotkeys.register(.toggleWidgetHidden) { [weak self] in
            // The controller reconciles through settingsDidChange, so the
            // hotkey works even while the widget window is being rebuilt.
            self?.settings.widgetMinimized.toggle()
        }
        hotkeys.register(.togglePanelPin) { [weak self] in
            self?.settings.closeOnOutsideClick.toggle()
        }
        hotkeys.register(.toggleSettings) { [weak self] in
            self?.widgetController?.toggleSettings()
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "capsule.portrait.fill",
            accessibilityDescription: "Pocket"
        )

        let menu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        let tourItem = NSMenuItem(
            title: "Welcome Tour…",
            action: #selector(openOnboarding),
            keyEquivalent: ""
        )
        tourItem.target = self
        menu.addItem(tourItem)
        if services.updater.isAvailable {
            let updatesItem = NSMenuItem(
                title: "Check for Updates…",
                action: #selector(checkForUpdates),
                keyEquivalent: ""
            )
            updatesItem.target = self
            menu.addItem(updatesItem)
        }
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit Pocket",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        item.menu = menu

        statusItem = item
    }

    @objc private func openSettings() {
        showSettings(page: nil)
    }

    @objc private func checkForUpdates() {
        services.updater.checkForUpdates()
    }

    @objc private func openOnboarding() {
        widgetController?.openOnboarding()
    }

    @objc private func handleOpenSettings(_ notification: Notification) {
        let page = (notification.userInfo?["page"] as? String)
            .flatMap(SettingsView.Page.init(rawValue:))
        showSettings(page: page)
    }

    private func showSettings(page: SettingsView.Page?) {
        widgetController?.openSettings(page: page)
    }
}
