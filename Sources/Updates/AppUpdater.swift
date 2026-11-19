import Sparkle

/// Updates through Sparkle. Pocket checks the feed (`SUFeedURL` in
/// Info.plist) once a day and asks before installing; the status-bar menu can
/// check on demand. Settings for both live in `project.yml`.
///
/// Debug builds have no updater: an update would replace the build under
/// development with the released one.
@MainActor
final class AppUpdater {
    #if DEBUG
    /// Whether this build can update itself.
    let isAvailable = false

    func checkForUpdates() {}
    #else
    let isAvailable = true

    private let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    /// Asks the feed now and shows the answer, also when there is no update.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
    #endif
}
