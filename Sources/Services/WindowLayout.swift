import Foundation

/// Where a playbook puts its apps' windows once they are running. Only the
/// arrangements macOS itself offers under Window ▸ Move & Resize, so the
/// result matches the green button: the system owns the geometry, the
/// tile margins and the menu bar/Dock insets, and tiles never overlap.
enum WindowLayout: String, CaseIterable, Identifiable, Sendable {
    case none, leftRight, topBottom, leftAndQuarters, grid2x2, fullscreen

    var id: String { rawValue }

    private var spec: (icon: String, title: L10nKey) {
        switch self {
        case .none: ("rectangle", .playLayoutNone)
        case .leftRight: ("rectangle.split.2x1", .playLayoutLeftRight)
        case .topBottom: ("rectangle.split.1x2", .playLayoutTopBottom)
        case .leftAndQuarters: ("rectangle.lefthalf.inset.filled", .playLayoutLeftQuarters)
        case .grid2x2: ("rectangle.split.2x2", .playLayoutGrid2x2)
        case .fullscreen: ("rectangle.inset.filled", .playLayoutFullscreen)
        }
    }

    var icon: String { spec.icon }
    @MainActor var title: String { L10n.t(spec.title) }
}

extension WindowLayout: Codable {
    /// Earlier builds offered layouts macOS has no command for; they map to
    /// the closest system arrangement instead of failing the whole file.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "thirds": self = .leftAndQuarters
        case "mainAndSide": self = .leftRight
        default: self = WindowLayout(rawValue: raw) ?? .none
        }
    }
}
