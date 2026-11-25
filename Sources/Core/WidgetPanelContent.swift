import Foundation

/// What the open widget panel shows. The welcome tour has no strip icon of
/// its own: it rides the Settings slot (and so the Settings panel size),
/// which also makes a detour into a settings page an in-place switch.
enum WidgetPanelContent: Equatable {
    case lockScreen
    case tour
    case settings
    case module(ModuleTab)

    /// Locked, every slot is the lock screen — the tour and Settings
    /// included, so neither is a way around it.
    static func resolve(selectedTab: ModuleTab?, showsTour: Bool, locked: Bool) -> WidgetPanelContent? {
        guard let selectedTab else { return nil }
        if locked { return .lockScreen }
        if selectedTab == .settings { return showsTour ? .tour : .settings }
        return .module(selectedTab)
    }

    /// The strip icon drawn as active. The tour is not Settings, and the
    /// lock screen has only the lock button, which never lights.
    var highlightedTab: ModuleTab? {
        switch self {
        case .settings: .settings
        case .module(let tab): tab
        case .tour, .lockScreen: nil
        }
    }

    /// The tour is read, not glanced at: it closes only on ✕, Start, Esc or
    /// the hotkey — granting access means clicking in System Settings and
    /// consent dialogs, which must not end it.
    func autoCloses(closeOnOutsideClick: Bool) -> Bool {
        self == .tour ? false : closeOnOutsideClick
    }

    /// ⌃⌥M closes what it opens (Settings, or the lock screen when locked)
    /// and the tour; over a module or nothing, it opens Settings.
    static func hotkeyCloses(_ content: WidgetPanelContent?) -> Bool {
        switch content {
        case .settings, .tour, .lockScreen: true
        case .module, nil: false
        }
    }

    /// The tab Settings opens in. Locked, that is the slot the lock button
    /// uses (the first module), so the lock button and ⌃⌥M toggle the same
    /// panel.
    static func settingsSlot(locked: Bool, firstTab: ModuleTab?) -> ModuleTab {
        locked ? firstTab ?? .settings : .settings
    }
}
