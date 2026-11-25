import CoreGraphics

/// What placement needs to know about one connected display. A value type,
/// so the choice of display is decided — and tested — without real screens.
struct DisplayInfo: Equatable, Sendable {
    /// Stable across relaunches and reconnects (the display's UUID), unlike
    /// its index or frame.
    let id: String
    /// Cocoa screen coordinates (y-up), like every rect in the geometry.
    let frame: CGRect
    let visibleFrame: CGRect
    let isBuiltIn: Bool
    let hasCameraHousing: Bool
}

/// Which display the strip is on. The panel size limits follow the same
/// display, so this is the one place that decides it.
enum StripDisplay {
    struct Choice: Equatable {
        let display: DisplayInfo
        /// What to keep as the saved display from now on. Differs from the
        /// id passed in only when that display is gone.
        let savedID: String?
    }

    /// - Saved display connected: the strip stays on it.
    /// - Saved display gone: the built-in screen (else the main one) takes
    ///   the strip, and becomes the saved choice — so the strip does not
    ///   jump back when the display returns.
    /// - Nothing saved (the strip was never dragged since displays are
    ///   remembered): the display with a camera housing, else the main one,
    ///   and nothing is saved.
    static func choose(savedID: String?, among displays: [DisplayInfo], mainID: String?) -> Choice? {
        let main = displays.first { $0.id == mainID } ?? displays.first
        guard let savedID else {
            return (displays.first(where: \.hasCameraHousing) ?? main)
                .map { Choice(display: $0, savedID: nil) }
        }
        if let saved = displays.first(where: { $0.id == savedID }) {
            return Choice(display: saved, savedID: savedID)
        }
        return (displays.first(where: \.isBuiltIn) ?? main)
            .map { Choice(display: $0, savedID: $0.id) }
    }
}
