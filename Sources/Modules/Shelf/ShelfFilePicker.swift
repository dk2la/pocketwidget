import AppKit

/// Adds files to the shelf through the standard macOS file picker — the
/// way in that does not depend on a drag reaching an open panel.
@MainActor
enum ShelfFilePicker {
    /// Asks the user for files; empty means cancelled.
    typealias Choose = @MainActor () async -> [URL]

    /// Shows the picker and puts what was chosen on the shelf, the same
    /// way dropped files land. The panel is held open meanwhile and drops
    /// below the picker (see `PanelHold`). Returns false when nothing was
    /// chosen.
    @discardableResult
    static func addFiles(
        to shelf: ShelfStore,
        hold: PanelHold = .shared,
        choose: Choose = chooseWithOpenPanel
    ) async -> Bool {
        let urls = await hold.yielding(choose)
        guard !urls.isEmpty else { return false }
        shelf.add(urls)
        return true
    }

    /// Any number of files and folders.
    static func chooseWithOpenPanel() async -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        // Pocket is an accessory app: without this the picker opens behind
        // whatever app is in front.
        NSApp.activate(ignoringOtherApps: true)
        return await panel.begin() == .OK ? panel.urls : []
    }
}
