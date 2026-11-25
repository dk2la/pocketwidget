import AppKit
import Observation
import OSLog
import ServiceManagement

extension Notification.Name {
    /// Posted by UI that wants the Settings module opened; the
    /// AppDelegate observes it.
    static let pocketOpenSettings = Notification.Name("pocketOpenSettings")
    /// Posted with `userInfo["tab"]` (a ModuleTab raw value) to open that
    /// module in the widget — e.g. the assistant handing a form to the
    /// calendar.
    static let pocketShowModule = Notification.Name("pocketShowModule")
    /// Posted by UI that wants the welcome tour in the widget (settings,
    /// context menus); the AppDelegate observes it.
    static let pocketOpenOnboarding = Notification.Name("pocketOpenOnboarding")
}

/// Asks the AppDelegate for the Settings module, optionally on a page.
@MainActor
func requestSettings(page: SettingsView.Page? = nil) {
    NotificationCenter.default.post(
        name: .pocketOpenSettings,
        object: nil,
        userInfo: page.map { ["page": $0.rawValue] }
    )
}

/// Asks the AppDelegate for the welcome tour, from its first page.
@MainActor
func requestOnboarding() {
    NotificationCenter.default.post(name: .pocketOpenOnboarding, object: nil)
}

/// User preferences, persisted to UserDefaults.
@MainActor
@Observable
final class AppSettings {
    /// Widget glass appearance.
    var glassAppearance: GlassAppearance {
        didSet { persist(glassAppearance.rawValue, Self.glassAppearanceKey, log: "glassAppearance") }
    }

    /// Interface language — translates the widget and settings.
    var language: AppLanguage {
        didSet {
            L10n.shared.language = language
            persist(language.rawValue, Self.languageKey, log: "language")
        }
    }

    /// Stable id (`NSScreen.stableID`) of the display the strip was last
    /// put on. Nil until the strip is first dragged: it then follows the
    /// display with a camera housing, as it did before displays were saved.
    private(set) var widgetDisplayID: String? {
        didSet {
            guard widgetDisplayID != oldValue else { return }
            if let widgetDisplayID {
                persist(widgetDisplayID, Self.widgetDisplayKey, log: "widgetDisplay")
            } else {
                defaults.removeObject(forKey: Self.widgetDisplayKey)
                notifyChange()
            }
        }
    }

    /// The display the strip is on — the one source of truth. The panels
    /// take their size limits from it. See `StripDisplay.choose` for the rule. Resolved at launch, on
    /// every screen change (`refreshStripDisplay`) and when a drag ends,
    /// rather than on each read: it is read on every mouse move.
    @ObservationIgnored private(set) var stripScreen: NSScreen?

    /// Edge the widget strip is docked to.
    private(set) var widgetEdge: WidgetEdge {
        didSet { persist(widgetEdge.rawValue, Self.widgetEdgeKey) }
    }

    /// Normalized 0…1 position of the strip's center along its edge.
    private(set) var widgetOffset: Double {
        didSet { persist(widgetOffset, Self.widgetOffsetKey) }
    }

    /// Clicking anywhere outside the widget, or the cursor leaving it,
    /// closes the open panel. Off = the panel stays pinned until closed
    /// explicitly. ⌃⌥P flips it.
    var closeOnOutsideClick: Bool {
        didSet { persist(closeOnOutsideClick, Self.outsideClickKey, log: "closeOnOutsideClick") }
    }

    /// Widget rolled up to its grip plus the first module button (⌃⌥H).
    /// Persisted so a restart brings the widget back the way it was left.
    var widgetMinimized: Bool {
        didSet { persist(widgetMinimized, Self.widgetMinimizedKey, log: "widgetMinimized") }
    }

    /// The welcome tour opens in the widget at every launch until switched
    /// off — from the tour's own footer or Settings → General.
    var showOnboardingAtLaunch: Bool {
        didSet { persist(showOnboardingAtLaunch, Self.onboardingAtLaunchKey, log: "showOnboardingAtLaunch") }
    }

    /// The first welcome tour has been closed. Until then nothing asks
    /// macOS for access on its own — the tour asks, page by page.
    var onboardingCompleted: Bool {
        didSet { persist(onboardingCompleted, Self.onboardingCompletedKey, log: "onboardingCompleted") }
    }

    /// The metric on the System module's large chart: CPU until another is
    /// chosen. Written straight to defaults: no window reacts to it.
    var systemMetric: Gauge {
        didSet { MetricSelection.save(systemMetric, to: defaults) }
    }

    /// Size of the widget's module panel, each axis dragged by its own grip.
    private(set) var widgetPanelWidth: CGFloat {
        didSet { persist(Double(widgetPanelWidth), Self.widgetPanelWidthKey) }
    }

    private(set) var widgetPanelHeight: CGFloat {
        didSet { persist(Double(widgetPanelHeight), Self.widgetPanelHeightKey) }
    }

    /// Size of the Settings module's panel, dragged by the same grips as
    /// the module panel but stored apart from it (720×520 at first).
    private(set) var settingsPanelSize: CGSize {
        didSet {
            defaults.set(Double(settingsPanelSize.width), forKey: Self.settingsPanelWidthKey)
            persist(Double(settingsPanelSize.height), Self.settingsPanelHeightKey)
        }
    }

    private(set) var enabledTabs: Set<ModuleTab> {
        didSet { persist(enabledTabs.map(\.rawValue).sorted(), Self.tabsKey) }
    }

    /// User-arranged channel order (Settings → Modules).
    private(set) var tabOrder: [ModuleTab] {
        didSet { persist(tabOrder.map(\.rawValue), Self.tabOrderKey) }
    }

    /// Launch-at-login through SMAppService; mirrored here for observation.
    private(set) var launchAtLogin: Bool

    /// Channels in user order, disabled ones filtered out.
    var orderedEnabledTabs: [ModuleTab] {
        StripLineup.visible(order: tabOrder, enabled: enabledTabs)
    }

    /// Window controllers react to changes — the widget re-derives its
    /// layout. Handlers are append-only.
    @ObservationIgnored private var changeHandlers: [() -> Void] = []

    func addChangeHandler(_ handler: @escaping () -> Void) {
        changeHandlers.append(handler)
    }

    /// The one write path of every persisted property.
    private func persist(_ value: Any, _ key: String, log name: String? = nil) {
        defaults.set(value, forKey: key)
        if let name {
            log.info("\(name, privacy: .public) -> \(String(describing: value), privacy: .public)")
        }
        notifyChange()
    }

    /// Held back while several properties change as one (see
    /// `setWidgetPlacement`), so nobody lays out a half-written placement.
    private func notifyChange() {
        guard !isBatchingChanges else { return }
        for handler in changeHandlers {
            handler()
        }
    }

    @ObservationIgnored private var isBatchingChanges = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let log = Logger(subsystem: "com.dk2la.pocket", category: "settings")
    // v6: bumped when the hotkeys tab shipped (v5 = assistant, v4 = email,
    // v3 = notes, v2 = playbooks) — a stored older set would silently hide
    // new tabs, since "missing" is indistinguishable from "disabled by the user".
    @ObservationIgnored private static let tabsKey = "settings.enabledTabs.v6"
    /// (legacy key, tabs to surface when migrating from it)
    @ObservationIgnored private static let legacyTabsKeys: [(String, Set<ModuleTab>)] = [
        ("settings.enabledTabs.v5", [.hotkeys]),
        ("settings.enabledTabs.v4", [.assistant, .hotkeys]),
        ("settings.enabledTabs.v3", [.email, .assistant, .hotkeys]),
        ("settings.enabledTabs.v2", [.notes, .email, .assistant, .hotkeys]),
    ]
    @ObservationIgnored private static let tabOrderKey = "settings.tabOrder"
    @ObservationIgnored private static let glassAppearanceKey = "settings.glassAppearance"
    @ObservationIgnored private static let languageKey = "settings.language"
    @ObservationIgnored private static let widgetEdgeKey = "settings.widgetEdge"
    @ObservationIgnored private static let widgetOffsetKey = "settings.widgetOffset"
    @ObservationIgnored private static let widgetDisplayKey = "settings.widgetDisplay"
    @ObservationIgnored private static let displayGoneGrace: Duration = .seconds(10)
    @ObservationIgnored private var displayGoneTask: Task<Void, Never>?
    @ObservationIgnored private static let outsideClickKey = "settings.closeOnOutsideClick"
    @ObservationIgnored private static let widgetMinimizedKey = "settings.widgetMinimized"
    @ObservationIgnored private static let onboardingAtLaunchKey = "settings.showOnboardingAtLaunch"
    @ObservationIgnored private static let onboardingCompletedKey = "settings.onboardingCompleted"
    @ObservationIgnored private static let widgetPanelWidthKey = "settings.widgetPanelWidth"
    @ObservationIgnored private static let widgetPanelHeightKey = "settings.widgetPanelHeight"
    @ObservationIgnored private static let settingsPanelWidthKey = "settings.settingsPanelWidth"
    @ObservationIgnored private static let settingsPanelHeightKey = "settings.settingsPanelHeight"

    init(defaults: UserDefaults = .app) {
        self.defaults = defaults
        // Resolved before anything else: the panel size limits below come
        // from the strip's display. A saved display that is gone is
        // replaced here, at launch, the same way as on a screen change.
        let storedDisplay = defaults.string(forKey: Self.widgetDisplayKey)
        let display = StripScreen.resolve(savedID: storedDisplay)
        let screen = display?.screen
        stripScreen = screen
        // A saved display that is missing is given a moment to appear
        // before it is given up (see `forgetGoneDisplayAfterGrace`).
        widgetDisplayID = storedDisplay
        let displayIsGone = display.map { $0.savedID != storedDisplay } ?? false
        let storedPanelWidth = defaults.double(forKey: Self.widgetPanelWidthKey)
        widgetPanelWidth = WidgetGeometry.clampedPanelWidth(
            storedPanelWidth > 0 ? storedPanelWidth : WidgetMetrics.panelDefaultWidth,
            screenFrame: screen?.frame
        )
        let storedPanelHeight = defaults.double(forKey: Self.widgetPanelHeightKey)
        widgetPanelHeight = WidgetGeometry.clampedPanelHeight(
            storedPanelHeight > 0 ? storedPanelHeight : WidgetMetrics.panelDefaultHeight,
            visibleFrame: screen?.visibleFrame
        )
        let storedSettingsWidth = defaults.double(forKey: Self.settingsPanelWidthKey)
        let storedSettingsHeight = defaults.double(forKey: Self.settingsPanelHeightKey)
        settingsPanelSize = WidgetGeometry.clampedPanelSize(
            CGSize(
                width: storedSettingsWidth > 0 ? storedSettingsWidth : WidgetMetrics.settingsPanelDefaultSize.width,
                height: storedSettingsHeight > 0 ? storedSettingsHeight : WidgetMetrics.settingsPanelDefaultSize.height
            ),
            screenFrame: screen?.frame,
            visibleFrame: screen?.visibleFrame
        )
        glassAppearance = defaults.string(forKey: Self.glassAppearanceKey)
            .flatMap(GlassAppearance.init(rawValue:)) ?? .dark
        language = defaults.string(forKey: Self.languageKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
        widgetEdge = defaults.string(forKey: Self.widgetEdgeKey)
            .flatMap(WidgetEdge.init(rawValue:)) ?? .right
        let storedOffset = defaults.object(forKey: Self.widgetOffsetKey) as? Double
        widgetOffset = min(max(storedOffset ?? 0.5, 0), 1)
        // Absent key = default ON: auto-close is the expected light behaviour.
        closeOnOutsideClick = (defaults.object(forKey: Self.outsideClickKey) as? Bool) ?? true
        widgetMinimized = defaults.bool(forKey: Self.widgetMinimizedKey)
        // Absent key = on: the tour shows until the user turns it off.
        showOnboardingAtLaunch = (defaults.object(forKey: Self.onboardingAtLaunchKey) as? Bool) ?? true
        onboardingCompleted = defaults.bool(forKey: Self.onboardingCompletedKey)
        systemMetric = MetricSelection.load(from: defaults)
        // A fresh install starts with the core modules only; the rest are
        // switched on in Settings → Modules.
        let defaultEnabled = Set(ModuleTab.defaultTabs)
        if let stored = defaults.stringArray(forKey: Self.tabsKey) {
            let tabs = Set(stored.compactMap(ModuleTab.init(rawValue:)))
            enabledTabs = StripLineup.loadedEnabled(tabs.isEmpty ? defaultEnabled : tabs)
        } else if let (legacy, extras) = Self.legacyTabsKeys
            .compactMap({ key, extras in
                defaults.stringArray(forKey: key).map { ($0, extras) }
            })
            .first {
            // Migration: keep the user's choices, surface freshly shipped
            // tabs they could not have known about.
            let tabs = Set(legacy.compactMap(ModuleTab.init(rawValue:))).union(extras)
            enabledTabs = StripLineup.loadedEnabled(tabs.isEmpty ? defaultEnabled : tabs)
        } else {
            enabledTabs = StripLineup.loadedEnabled(defaultEnabled)
        }
        // Stored order, with any newly introduced tabs appended at the end.
        tabOrder = StripLineup.loadedOrder(
            stored: (defaults.stringArray(forKey: Self.tabOrderKey) ?? []).compactMap(ModuleTab.init(rawValue:))
        )
        launchAtLogin = SMAppService.mainApp.status == .enabled
        L10n.shared.language = language
        if displayIsGone {
            forgetGoneDisplayAfterGrace()
        }
        log.info("loaded tabs=\(self.enabledTabs.count, privacy: .public)")
    }

    /// Where a drag left the strip: the display it was dropped on, the
    /// nearest edge and the offset along it. Written as one change.
    func setWidgetPlacement(screen: NSScreen, edge: WidgetEdge, offset: Double) {
        let clamped = min(max(offset, 0), 1)
        let displayID = screen.stableID
        let displayChanged = screen !== stripScreen || displayID != widgetDisplayID
        guard displayChanged || edge != widgetEdge || clamped != widgetOffset else { return }
        log.info("""
        widget placement -> \(edge.rawValue, privacy: .public) @ \(clamped, privacy: .public) \
        display=\(displayID ?? "-", privacy: .public)
        """)
        isBatchingChanges = true
        stripScreen = screen
        widgetDisplayID = displayID
        widgetEdge = edge
        widgetOffset = clamped
        isBatchingChanges = false
        notifyChange()
        if displayChanged {
            revalidatePanelSize()
        }
    }

    /// Call on every screen change. When the saved display is gone the
    /// strip moves to the display it falls back to at once, and after a
    /// grace period that display becomes the saved one, so the strip stays
    /// there when the old display returns; the panel sizes are re-clamped
    /// to the display the strip is on now. Idempotent — both window
    /// controllers call it, in whichever order the notification arrives.
    func refreshStripDisplay() {
        let resolved = StripScreen.resolve(savedID: widgetDisplayID)
        stripScreen = resolved?.screen
        if let resolved, resolved.savedID != widgetDisplayID {
            forgetGoneDisplayAfterGrace()
        } else {
            displayGoneTask?.cancel()
            displayGoneTask = nil
        }
        revalidatePanelSize()
    }

    /// macOS can report an external display as missing for a moment on
    /// wake or at login. Giving the saved display up at once would move the
    /// strip to the built-in screen for good, so the choice is rewritten
    /// only if the display is still gone after the grace period.
    private func forgetGoneDisplayAfterGrace() {
        guard displayGoneTask == nil else { return }
        displayGoneTask = Task { [weak self] in
            try? await Task.sleep(for: Self.displayGoneGrace)
            guard let self, !Task.isCancelled else { return }
            displayGoneTask = nil
            let resolved = StripScreen.resolve(savedID: widgetDisplayID)
            if let resolved, resolved.savedID != widgetDisplayID {
                log.info("widget display gone")
                widgetDisplayID = resolved.savedID
            }
        }
    }

    func setWidgetPanelWidth(_ raw: CGFloat) {
        let clamped = WidgetGeometry.clampedPanelWidth(raw, screenFrame: stripScreen?.frame)
        guard clamped != widgetPanelWidth else { return }
        widgetPanelWidth = clamped
    }

    func setWidgetPanelHeight(_ raw: CGFloat) {
        let clamped = WidgetGeometry.clampedPanelHeight(raw, visibleFrame: stripScreen?.visibleFrame)
        guard clamped != widgetPanelHeight else { return }
        widgetPanelHeight = clamped
    }

    func setSettingsPanelWidth(_ raw: CGFloat) {
        let width = WidgetGeometry.clampedPanelWidth(raw, screenFrame: stripScreen?.frame)
        guard width != settingsPanelSize.width else { return }
        settingsPanelSize.width = width
    }

    func setSettingsPanelHeight(_ raw: CGFloat) {
        let height = WidgetGeometry.clampedPanelHeight(raw, visibleFrame: stripScreen?.visibleFrame)
        guard height != settingsPanelSize.height else { return }
        settingsPanelSize.height = height
    }

    /// The size `tab`'s widget panel opens at: Settings has its own, every
    /// other module shares one.
    func panelSize(for tab: ModuleTab?) -> CGSize {
        tab == .settings
            ? settingsPanelSize
            : CGSize(width: widgetPanelWidth, height: widgetPanelHeight)
    }

    /// Writes the size `panelSize(for:)` reads for `tab`.
    func setPanelWidth(_ width: CGFloat, for tab: ModuleTab?) {
        if tab == .settings {
            setSettingsPanelWidth(width)
        } else {
            setWidgetPanelWidth(width)
        }
    }

    func setPanelHeight(_ height: CGFloat, for tab: ModuleTab?) {
        if tab == .settings {
            setSettingsPanelHeight(height)
        } else {
            setWidgetPanelHeight(height)
        }
    }

    /// Re-clamp every panel size to the strip's display — after a display
    /// change, or once the strip moved to another display (a smaller
    /// screen may no longer fit the stored size).
    func revalidatePanelSize() {
        setWidgetPanelWidth(widgetPanelWidth)
        setWidgetPanelHeight(widgetPanelHeight)
        setSettingsPanelWidth(settingsPanelSize.width)
        setSettingsPanelHeight(settingsPanelSize.height)
    }

    func moveTabs(fromOffsets source: IndexSet, toOffset destination: Int) {
        tabOrder.move(fromOffsets: source, toOffset: destination)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            log.error("launch-at-login toggle failed: \(error, privacy: .public)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    func isEnabled(_ tab: ModuleTab) -> Bool {
        enabledTabs.contains(tab)
    }

    /// False for Settings and for the last enabled module (see StripLineup).
    func canToggle(_ tab: ModuleTab) -> Bool {
        StripLineup.canToggle(tab, enabled: enabledTabs)
    }

    /// A refused toggle is a no-op (see `canToggle`).
    func toggle(_ tab: ModuleTab) {
        let toggled = StripLineup.toggled(tab, in: enabledTabs)
        guard toggled != enabledTabs else { return }
        enabledTabs = toggled
    }
}
