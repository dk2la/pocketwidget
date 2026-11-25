import AppKit

extension NSScreen {
    private var displayNumber: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }

    /// Stable across relaunches and reconnects, unlike the screen's index
    /// or frame: the display's UUID. Nil only for a screen macOS gives no
    /// display number for.
    var stableID: String? {
        guard let displayNumber else { return nil }
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayNumber)?.takeRetainedValue() else {
            // No UUID (possible for a virtual display): the number at least
            // holds for as long as the display stays connected.
            return "display-\(displayNumber)"
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    var hasCameraHousing: Bool { safeAreaInsets.top > 0 }

    var isBuiltIn: Bool {
        displayNumber.map { CGDisplayIsBuiltin($0) != 0 } ?? false
    }

    var displayInfo: DisplayInfo? {
        stableID.map {
            DisplayInfo(
                id: $0,
                frame: frame,
                visibleFrame: visibleFrame,
                isBuiltIn: isBuiltIn,
                hasCameraHousing: hasCameraHousing
            )
        }
    }
}

/// The connected screens run through `StripDisplay.choose` — the bridge
/// between the pure choice and AppKit.
@MainActor
enum StripScreen {
    struct Resolved {
        let screen: NSScreen
        /// See `StripDisplay.Choice.savedID`.
        let savedID: String?
    }

    static func resolve(savedID: String?) -> Resolved? {
        let screens = NSScreen.screens
        let choice = StripDisplay.choose(
            savedID: savedID,
            among: screens.compactMap(\.displayInfo),
            mainID: NSScreen.main?.stableID
        )
        guard let choice, let screen = screens.first(where: { $0.stableID == choice.display.id }) else {
            // Screens without a display number cannot be told apart; fall
            // back to the rule from before displays were remembered.
            return (screens.first(where: \.hasCameraHousing) ?? NSScreen.main)
                .map { Resolved(screen: $0, savedID: savedID) }
        }
        return Resolved(screen: screen, savedID: choice.savedID)
    }
}
