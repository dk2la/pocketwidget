import Foundation

/// Show/skip rule for live events on the widget. An open module panel is
/// the user's work — the pill must not cover it; locked, the widget shows
/// nothing but the lock. A minimized strip still shows events, and which
/// modules are enabled never matters ("timer finished" shows with the
/// Timer module off).
enum LiveEventGate {
    static func shouldShow(_ event: LiveEvent, panelOpen: Bool, locked: Bool, minimized: Bool) -> Bool {
        !panelOpen && !locked
    }
}
