import Foundation

/// What the Hotkeys list area shows. The keyboard device belongs to the
/// two states with nothing to list for the app in front; a search that
/// finds nothing keeps its plain message, and a list still on its way
/// leaves the word to the hero card.
enum ShortcutListState: Equatable {
    /// No app in front to read shortcuts from.
    case noApp
    /// Nothing to list yet and no verdict either: the menus are still being
    /// read, or there is no access to read them. The hero card says which.
    case pending
    /// The app has no shortcuts.
    case noShortcuts
    /// The query matches none of the app's shortcuts.
    case noSearchResults
    case shortcuts

    /// - Parameters:
    ///   - shownCount: shortcuts left after the query filter.
    ///   - isSettled: the app's menus were read, or it works from a key
    ///     preset — an empty list is then final.
    init(hasApp: Bool, shownCount: Int, query: String, isSettled: Bool) {
        if !hasApp {
            self = .noApp
        } else if shownCount > 0 {
            self = .shortcuts
        } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            self = .noSearchResults
        } else {
            self = isSettled ? .noShortcuts : .pending
        }
    }

    /// True when the list area is the empty screen with the device.
    var showsDevice: Bool {
        self == .noApp || self == .noShortcuts
    }
}
