import AppKit
import Observation
import SwiftUI

/// The live event pill: a small glass window that slides out of the widget
/// strip towards the screen centre for a moment. A window of its own, so
/// the strip's window never resizes and the strip never moves. Purely
/// informational — it lets every click through.
@MainActor
final class LiveEventPillController {
    static let pillSize = CGSize(width: 208, height: 36)
    static let displayDuration: Duration = .milliseconds(2500)
    /// Room around the pill inside its window for the slide, so the
    /// moving pill is never clipped by the window edge.
    fileprivate static let slideDistance: CGFloat = 14
    private static let hideDuration: Duration = .milliseconds(450)

    private let panel = FloatingPanel()
    private let model = LiveEventPillModel()
    private var showTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?

    init(settings: AppSettings) {
        panel.ignoresMouseEvents = true
        let hostingView = PanelHostingView(rootView: LiveEventPillView(model: model, settings: settings))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        panel.contentView = hostingView.makeWindowContentView()
    }

    /// Shows `event` beside `strip` (Cocoa screen coordinates). A pill
    /// already on screen takes the new content in place and restarts its
    /// timer — a volume sweep updates, it does not flicker.
    func present(_ event: LiveEvent, strip: NSRect, edge: WidgetEdge, visibleFrame: NSRect) {
        showTask?.cancel()
        dismissTask?.cancel()
        let pill = WidgetGeometry.eventPillFrame(
            strip: strip, edge: edge, pillSize: Self.pillSize, visibleFrame: visibleFrame
        )
        panel.setFrame(pill.insetBy(dx: -Self.slideDistance, dy: -Self.slideDistance), display: true)
        if model.event == nil {
            // Size and order the window first; the slide runs on the next
            // tick, in a stable coordinate space.
            model.edge = edge
            panel.orderFrontRegardless()
            showTask = Task { [weak self] in
                guard !Task.isCancelled else { return }
                withAnimation(Theme.eventSpring) { self?.model.event = event }
            }
        } else {
            model.event = event
        }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.displayDuration)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    /// Gone at once — a panel opening or a drag starting owns the space.
    func dismiss() {
        showTask?.cancel()
        dismissTask?.cancel()
        withInstantTransaction { model.event = nil }
        panel.orderOut(nil)
    }

    private func hide() {
        withAnimation(Theme.stateSpring) { model.event = nil }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: Self.hideDuration)
            guard !Task.isCancelled else { return }
            self?.panel.orderOut(nil)
        }
    }

    private func withInstantTransaction(_ body: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, body)
    }
}

@MainActor
@Observable
private final class LiveEventPillModel {
    var event: LiveEvent?
    /// Dock edge at show time — the pill slides out from that side.
    var edge: WidgetEdge = .left
}

private struct LiveEventPillView: View {
    var model: LiveEventPillModel
    var settings: AppSettings

    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: WidgetMetrics.radius, style: .continuous)
    }

    var body: some View {
        ZStack {
            if let event = model.event {
                LiveEventView(event: event)
                    .frame(width: LiveEventPillController.pillSize.width, height: LiveEventPillController.pillSize.height)
                    .background(GlassSurface(shape: shape, dark: settings.glassAppearance.resolvedDark(for: colorScheme)))
                    .clipShape(shape)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("event.pill")
                    .transition(transition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Out of the strip towards the centre; Reduce Motion keeps the fade
    /// and drops the movement.
    private var transition: AnyTransition {
        guard !Theme.reduceMotion else { return .opacity }
        let distance = LiveEventPillController.slideDistance
        let offset: CGSize = switch model.edge {
        case .left: CGSize(width: -distance, height: 0)
        case .right: CGSize(width: distance, height: 0)
        case .top: CGSize(width: 0, height: -distance)
        case .bottom: CGSize(width: 0, height: distance)
        }
        return .opacity.combined(with: .offset(offset))
    }
}
