import CoreGraphics
import Observation

/// What the expanded capsule hosts. The welcome tour moved to the widget.
enum CapsuleContent: Equatable {
    case settings
}

@MainActor
@Observable
final class CapsuleViewModel {
    private(set) var state: CapsuleState = .closed

    /// Currently visible live event, if any. Shown only while not expanded.
    var activeEvent: LiveEvent?

    /// The expanded capsule's content. Set by the controller, which also
    /// sizes the window for it.
    var content: CapsuleContent = .settings

    /// Which settings page the expanded capsule shows; module UI deep-links
    /// into it ("Set up account" → Accounts).
    let pageSelection = SettingsPageSelection()

    /// Fired by a click on the resting capsule — the controller expands it
    /// into the settings panel.
    @ObservationIgnored var onCapsuleTapped: (() -> Void)?

    /// Fired by the panel's close button.
    @ObservationIgnored var onClose: (() -> Void)?

    /// True while the user drags the panel's resize grip — outside-click
    /// collapse is suppressed for the duration.
    @ObservationIgnored var isResizingPanel = false

    func setState(_ newState: CapsuleState) {
        guard newState != state else { return }
        state = newState
    }

    /// Body size of the expanded capsule for `content` — the one place the
    /// window and the SwiftUI drop both take it from. User-sized.
    func panelSize(for content: CapsuleContent, settings: AppSettings) -> CGSize {
        switch content {
        case .settings: settings.expandedPanelSize
        }
    }
}
