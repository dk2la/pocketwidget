/// Keeps the open panel from closing by itself while something of ours
/// lives outside it — a file picker, a system dialog. The cursor leaving
/// and clicks elsewhere are ignored for as long as a hold is active; the
/// close button, the tab buttons and the hotkeys still work.
///
/// Wrap the outside work in `during`, or pair `begin()` with `end()`:
///
///     let urls = await PanelHold.shared.during { await picker.begin() }
///
/// Both window controllers read `PanelHold.shared.isHeld`. Once the last
/// hold ends the usual closing rules are back, and closing on leave waits
/// for the cursor to come over the panel again first.
@MainActor
final class PanelHold {
    static let shared = PanelHold()

    /// Holds nest: two pickers open at once keep the panel until both end.
    private var count = 0

    var isHeld: Bool { count > 0 }

    func begin() {
        count += 1
    }

    func end() {
        count = max(count - 1, 0)
    }

    func during<T>(_ work: @MainActor () async -> T) async -> T {
        begin()
        defer { end() }
        return await work()
    }
}
