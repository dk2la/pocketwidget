import SwiftUI

/// Hosting view for a FloatingPanel (widget, event pill, permission guide).
///
/// The panel is key only while text input needs it (see
/// FloatingPanel.allowsKeyFocus) — the rest of the time it stays non-key so it
/// does not steal focus from the app the user is working in. AppKit
/// swallows the first click into a non-key window by default, which would
/// make every button in the panel require two clicks. Accepting the first
/// mouse restores single-click behaviour.
final class PanelHostingView<Content: View>: NSHostingView<Content> {
    /// The controllers own the window frame and set it with `setFrame`.
    /// The default `.standardBounds` sizing would make the hosting view
    /// install min/intrinsic/max constraints on top of that; the content is
    /// always laid out at the window's size, so SwiftUI has nothing to add.
    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = []
    }

    /// The view to install as the panel's `contentView`.
    ///
    /// Never the hosting view itself: as a window's content view
    /// `NSHostingView` animates the window frame to follow its content
    /// (`updateAnimatedWindowSize`, from `windowDidLayout`) regardless of
    /// `sizingOptions`. That races the controller's own `setFrame` — every
    /// window resize invalidates the safe area, which requests another
    /// update-constraints pass from inside the layout pass, and AppKit
    /// throws once the loop exceeds its budget (crashes on ⌃⌥H and on tab
    /// switches mid-animation). Behind a plain container the hosting view
    /// is an ordinary subview that just fills the window.
    func makeWindowContentView() -> NSView {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.backgroundColor = .clear
        frame = container.bounds
        autoresizingMask = [.width, .height]
        container.addSubview(self)
        return container
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("unused")
    }

    private var hoverArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Mouse moves reach SwiftUI's hover effects even though the app is an
    /// agent and never the active app.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea {
            removeTrackingArea(hoverArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {}

    override func mouseExited(with event: NSEvent) {}
}
