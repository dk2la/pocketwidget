import Foundation
import Observation

/// State of the edge widget that SwiftUI animates on. Frames are set by the
/// controller in window-local SwiftUI coordinates, in the same runloop tick
/// as the window frame — the two must never disagree (see the two-phase
/// open in WidgetWindowController.openPanel).
@MainActor
@Observable
final class WidgetViewModel {
    /// Open module panel; nil = collapsed to the icon strip.
    private(set) var selectedTab: ModuleTab?
    /// Widget rolled up to its grip plus the first module button (⌃⌥H);
    /// no panel. See WidgetGeometry.stripLength.
    var isMinimized = false

    /// Pocket is locked: the strip is one lock button and the panel is the
    /// lock screen.
    var isLocked = false

    /// Page shown by the Settings module; deep links set it before opening.
    let settingsPage = SettingsPageSelection()
    /// Settings was opened from the welcome tour: its page list then leads
    /// with "‹ Back" to the tour page it left (`onResumeOnboarding`).
    var cameFromOnboarding = false
    /// The Settings slot shows the welcome tour instead of Settings (see
    /// WidgetPanelContent).
    var showsTour = false
    /// The tour's page. Kept here rather than in the view so a detour into
    /// Settings (connecting an account) comes back to the same page.
    var onboardingStep: OnboardingStep = .welcome

    /// What the open panel shows; nil while collapsed.
    var panelContent: WidgetPanelContent? {
        WidgetPanelContent.resolve(selectedTab: selectedTab, showsTour: showsTour, locked: isLocked)
    }

    var edge: WidgetEdge = .right
    var stripFrame: CGRect = .zero
    var panelFrame: CGRect = .zero

    @ObservationIgnored var onTabTapped: ((ModuleTab) -> Void)?
    @ObservationIgnored var onClose: (() -> Void)?
    @ObservationIgnored var onRestore: (() -> Void)?
    /// Back from a settings detour to the tour (see `cameFromOnboarding`).
    @ObservationIgnored var onResumeOnboarding: (() -> Void)?
    /// Drag reads the global cursor itself (NSEvent.mouseLocation) — the
    /// window moves mid-drag, so gesture-local coordinates would feed back.
    @ObservationIgnored var onDragChanged: (() -> Void)?
    @ObservationIgnored var onDragEnded: (() -> Void)?
    /// Resize grips (width on the panel's outer edge, height on the bottom).
    /// They read the global cursor for the same feedback reason as the drag.
    @ObservationIgnored var onResizeChanged: (() -> Void)?
    @ObservationIgnored var onResizeEnded: (() -> Void)?
    @ObservationIgnored var onHeightResizeChanged: (() -> Void)?
    @ObservationIgnored var onHeightResizeEnded: (() -> Void)?

    func setSelectedTab(_ tab: ModuleTab?) {
        guard tab != selectedTab else { return }
        selectedTab = tab
    }
}
