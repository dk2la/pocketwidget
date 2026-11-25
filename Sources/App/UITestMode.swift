import Foundation

/// `--ui-testing`: the launch the PocketUITests target drives. Pocket starts
/// as on a fresh install without touching the user's data: a throwaway
/// defaults suite, no welcome tour (unless `--onboarding` is passed too), no
/// licensing in debug builds and nothing that makes macOS ask for access —
/// a system prompt would block the test run.
enum UITestMode {
    static let argument = "--ui-testing"
    static let isActive = CommandLine.arguments.contains(argument)
    /// `--minimized` with `--ui-testing`: the widget starts rolled up. The
    /// defaults suite is wiped at every launch, so a test cannot store it.
    static let startsMinimized = isActive && CommandLine.arguments.contains("--minimized")
    /// Not the bundle ID: UserDefaults refuses a suite named after the app.
    static let defaultsSuite = "com.dk2la.pocket.ui-testing"
}

extension UserDefaults {
    /// The defaults Pocket reads and writes: the standard domain, or under
    /// `--ui-testing` a suite wiped at every launch, so each test starts
    /// clean and the user's settings stay untouched. UserDefaults is
    /// thread-safe; the SDK just does not mark it Sendable.
    nonisolated(unsafe) static let app: UserDefaults = {
        guard UITestMode.isActive,
              let suite = UserDefaults(suiteName: UITestMode.defaultsSuite)
        else { return .standard }
        suite.removePersistentDomain(forName: UITestMode.defaultsSuite)
        return suite
    }()
}
