import CoreGraphics

/// Where the Settings page list goes: beside the page while the panel is
/// wide enough for a 200pt sidebar, otherwise as a strip above it.
enum SettingsLayout: Equatable {
    case sidebar
    case topStrip

    /// Narrowest panel that still leaves the page usable next to the sidebar.
    static let sidebarMinWidth: CGFloat = 560

    static func mode(forWidth width: CGFloat) -> SettingsLayout {
        width >= sidebarMinWidth ? .sidebar : .topStrip
    }
}
