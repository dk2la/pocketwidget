import AppKit

/// Keeps the open panel from closing by itself while something of ours
/// lives outside it — a file picker, a system dialog. The cursor leaving
/// and clicks elsewhere are ignored for as long as a hold is active; the
/// close button, the tab buttons and the hotkeys still work.
///
/// Wrap the outside work in `during`, or pair `begin()` with `end()`:
///
///     let urls = await PanelHold.shared.during { await picker.begin() }
///
/// A *yield* is a hold that also drops Pocket's panels below other windows:
/// use it whenever Pocket raises a window that must show on top — our own
/// file pickers, a TCC consent dialog, System Settings. A yield always ends:
/// by its owner, or at its timeout if the owner never gets to (a consent
/// call that hangs).
///
///     let urls = await PanelHold.shared.yielding { await picker.begin() }
///
/// Both window controllers read `PanelHold.shared.isHeld`; every
/// `FloatingPanel` follows `yieldDidChange`. Once the last hold ends the
/// usual closing rules are back, and closing on leave waits for the cursor
/// to come over the panel again first.
@MainActor
final class PanelHold {
    static let shared = PanelHold()

    /// Posted (object: the hold) when `isYielding` flips.
    static let yieldDidChange = Notification.Name("PanelHold.yieldDidChange")

    /// Long enough for a user to read and answer any consent dialog.
    static let defaultYieldTimeout: Duration = .seconds(300)

    /// A begun yield; pass it back to `end(_:)`. Ending one twice is harmless.
    struct Yield: Hashable {
        fileprivate let id: Int
    }

    private var ledger = HoldLedger()
    private var expiryTask: Task<Void, Never>?

    var isHeld: Bool { ledger.isHeld }
    var isYielding: Bool { ledger.isYielding }

    /// The panels' level. `.screenSaver` puts them over the menu bar and
    /// fullscreen apps; while yielding they go down to `.normal`, the level
    /// of another app's windows. `.floating` would not do: it still covers
    /// System Settings, and consent alerts do not reliably sit above it.
    nonisolated static func level(yielding: Bool) -> NSWindow.Level {
        yielding ? .normal : .screenSaver
    }

    func begin() {
        ledger.beginKeepOpen()
    }

    func end() {
        ledger.endKeepOpen()
    }

    func during<T>(_ work: @MainActor () async -> T) async -> T {
        begin()
        defer { end() }
        return await work()
    }

    func beginYield(timeout: Duration = PanelHold.defaultYieldTimeout) -> Yield {
        Yield(id: update { $0.beginYield(now: .now, timeout: timeout) })
    }

    func end(_ yield: Yield) {
        update { $0.endYield(yield.id) }
    }

    func yielding<T>(
        timeout: Duration = PanelHold.defaultYieldTimeout,
        _ work: @MainActor () async -> T
    ) async -> T {
        let yield = beginYield(timeout: timeout)
        defer { end(yield) }
        return await work()
    }

    /// Applies a ledger change, announces a flip of `isYielding` and
    /// re-arms the timeout sweep.
    @discardableResult
    private func update<R>(_ change: (inout HoldLedger) -> R) -> R {
        let wasYielding = ledger.isYielding
        let result = change(&ledger)
        if ledger.isYielding != wasYielding {
            NotificationCenter.default.post(name: Self.yieldDidChange, object: self)
        }
        scheduleExpiry()
        return result
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        guard let deadline = ledger.nextDeadline else {
            expiryTask = nil
            return
        }
        expiryTask = Task { [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            guard !Task.isCancelled, let self else { return }
            self.update { $0.expire(now: .now) }
        }
    }
}

/// Bookkeeping behind `PanelHold`: keep-open holds nest by count (they
/// follow a view's lifetime), yields by identity with a deadline each.
struct HoldLedger {
    private var keepOpenDepth = 0
    private var yieldDeadlines: [Int: ContinuousClock.Instant] = [:]
    private var lastID = 0

    var isYielding: Bool { !yieldDeadlines.isEmpty }
    var isHeld: Bool { keepOpenDepth > 0 || isYielding }
    var nextDeadline: ContinuousClock.Instant? { yieldDeadlines.values.min() }

    mutating func beginKeepOpen() {
        keepOpenDepth += 1
    }

    mutating func endKeepOpen() {
        keepOpenDepth = max(keepOpenDepth - 1, 0)
    }

    mutating func beginYield(now: ContinuousClock.Instant, timeout: Duration) -> Int {
        lastID += 1
        yieldDeadlines[lastID] = now + timeout
        return lastID
    }

    mutating func endYield(_ id: Int) {
        yieldDeadlines[id] = nil
    }

    /// Drops yields whose deadline has come. True when any was dropped.
    @discardableResult
    mutating func expire(now: ContinuousClock.Instant) -> Bool {
        let before = yieldDeadlines.count
        yieldDeadlines = yieldDeadlines.filter { $0.value > now }
        return yieldDeadlines.count != before
    }
}
