import AppKit
import OSLog
import SwiftUI

/// Owns the capsule panel: positions it at the top center of the strip's
/// display (on the camera housing, where there is one), resizes the window in
/// step with the state machine, and survives display configuration changes.
/// Resting, the capsule shows live events and compact indicators; expanded,
/// it hosts the app's settings (click the capsule). Everything else opens
/// in the widget.
@MainActor
final class CapsuleWindowController: NSObject {
    private let panel = CapsulePanel()
    private let viewModel = CapsuleViewModel()
    private var closedSize: CGSize = CapsuleMetrics.fallbackClosedSize
    /// Target state — the controller's source of truth. May be one tick
    /// ahead of viewModel.state (see requestState).
    private var targetState: CapsuleState = .closed
    private var collapseTask: Task<Void, Never>?
    private var expandTask: Task<Void, Never>?
    private var hoverOpenTask: Task<Void, Never>?
    private var eventShowTask: Task<Void, Never>?
    private var eventDismissTask: Task<Void, Never>?
    /// Set synchronously in `present` — guards the window frame against
    /// idle-state churn during the one tick before `activeEvent` lands and
    /// for as long as the event is on screen.
    private var eventOwnsWindow = false
    private let clickMonitors = OutsideClickMonitors()
    /// Opened deliberately (hotkey, menu, deep link) rather than by hover:
    /// the panel then stays until the hotkey again, ✕, or a click outside —
    /// moving the mouse away must not close what the user asked for.
    private var settingsPinned = false
    private let services: ModuleServices
    private let settings: AppSettings
    /// The screen the capsule was last built on — the strip's display.
    private weak var attachedScreen: NSScreen?
    /// Fired when the expanded capsule (settings or tour) closes.
    var onCollapse: (() -> Void)?
    private let log = Logger(subsystem: "com.dk2la.pocket", category: "window")

    init(settings: AppSettings, services: ModuleServices) {
        self.settings = settings
        self.services = services
        super.init()

        settings.addChangeHandler { [weak self] in
            guard let self else { return }
            // The strip was dragged to another display, or its display went
            // away: the capsule and its hover zone go where the strip is.
            if self.settings.stripScreen !== self.attachedScreen {
                // What was opened deliberately (the settings, the welcome
                // tour) comes along open; a hover glance does not.
                let reopen = self.targetState == .expanded && self.settingsPinned
                self.moveToStripScreen()
                if reopen {
                    self.settingsPinned = true
                    self.requestState(.expanded)
                }
                return
            }
            self.refreshIdleState()
            // Live window resize while the user drags the panel grip.
            if self.targetState == .expanded, let screen = settings.stripScreen {
                self.collapseTask?.cancel()
                self.panel.setFrame(self.frame(for: .expanded, on: screen), display: true)
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        attachToScreen()
        setUpLiveEvents()
        viewModel.onCapsuleTapped = { [weak self] in
            self?.openSettings(page: nil, pinned: true)
        }
        viewModel.onClose = { [weak self] in
            self?.closeSettings()
        }
    }

    // MARK: - Settings capsule

    /// Expands the capsule onto the settings, optionally on a given page.
    /// `pinned` keeps it open regardless of the cursor (see `settingsPinned`).
    func openSettings(page: SettingsView.Page?, pinned: Bool = true) {
        if let page {
            viewModel.pageSelection.page = page
        }
        settingsPinned = pinned
        viewModel.content = .settings
        if targetState != .expanded {
            requestState(.expanded)
        }
    }

    func closeSettings() {
        settingsPinned = false
        guard targetState == .expanded else { return }
        requestState(idleState)
        onCollapse?()
    }

    /// ⌃⌥M: open pinned, or close if already open.
    func toggleSettings() {
        if targetState == .expanded {
            closeSettings()
        } else {
            openSettings(page: nil, pinned: true)
        }
    }

    /// While expanded, a click anywhere outside the capsule closes it — the
    /// same grammar as the widget panel. Installed on expand, removed on
    /// collapse so the monitors never outlive the panel.
    private func installOutsideClickMonitors() {
        clickMonitors.install(isOutside: { [weak self] event in
            // Only a click in another of our windows (the widget) counts as
            // outside — a sheet, popover or menu belonging to the panel
            // does not.
            guard let self, let window = event.window else { return false }
            return window !== self.panel && window.parent !== self.panel && window.sheetParent !== self.panel
        }, onClick: { [weak self] in
            self?.handleOutsideClick(at: NSEvent.mouseLocation)
        })
    }

    /// Expanded, the capsule is a drop: through the menu-bar band only the
    /// neck (the housing's width) is ours; below it the whole body is.
    private func capsuleOwns(viewPoint point: NSPoint, in bounds: NSRect) -> Bool {
        guard targetState == .expanded else { return true }
        let inNeckBand = point.y > bounds.maxY - closedSize.height
        guard inNeckBand else { return true }
        let housingWidth = closedSize.width - 2 * CapsuleMetrics.closedTopRadius
        return abs(point.x - bounds.midX) <= housingWidth / 2
    }

    /// Same test in screen coordinates.
    private func expandedContains(_ location: NSPoint, on screen: NSScreen) -> Bool {
        let frame = frame(for: .expanded, on: screen)
        guard frame.contains(location) else { return false }
        let local = NSPoint(x: location.x - frame.minX, y: location.y - frame.minY)
        return capsuleOwns(viewPoint: local, in: NSRect(origin: .zero, size: frame.size))
    }

    /// The settings do not close while the permission guide is up.
    private func handleOutsideClick(at location: NSPoint) {
        guard targetState == .expanded,
              !PermissionGuide.shared.isShowing, !viewModel.isResizingPanel,
              !PanelHold.shared.isHeld,
              panel.attachedSheet == nil, !panel.hasOwnPopupWindow,
              let screen = settings.stripScreen else { return }
        if !expandedContains(location, on: screen) {
            closeSettings()
        }
    }

    /// Live events moved to the widget's event pill; the capsule only
    /// follows playback and the timer for its compact idle state.
    private func setUpLiveEvents() {
        services.mediaCenter.onPlaybackChanged = { [weak self] in
            self?.refreshIdleState()
        }
        services.timerService.onRunningChanged = { [weak self] in
            self?.refreshIdleState()
        }
    }

    /// The capsule's resting state: compact while a timer runs or something
    /// is playing, fully closed otherwise. "Invisible" idle mode always
    /// closes fully.
    private var idleState: CapsuleState {
        // Locked, the capsule shows nothing of the modules.
        guard settings.idleMode == .compact, !services.isLocked else { return .closed }
        if services.timerService.isRunning || services.mediaCenter.track?.isPlaying == true {
            return .compact
        }
        return .closed
    }

    private func refreshIdleState() {
        guard targetState != .expanded else { return }
        // A live event owns the window frame — the dismiss task restores
        // the idle state itself.
        guard !eventOwnsWindow else { return }
        requestState(idleState)
    }

    /// Shows a transient live event on the closed capsule. Repeated events
    /// (e.g. a volume sweep) update the content in place and restart the
    /// dismiss timer.
    func present(_ event: LiveEvent) {
        guard targetState != .expanded, !services.isLocked,
              let screen = settings.stripScreen else { return }
        log.info("event \(String(describing: event), privacy: .public)")
        collapseTask?.cancel()
        eventShowTask?.cancel()
        eventDismissTask?.cancel()

        // The flag goes up synchronously: callbacks that fire right after
        // (e.g. the timer's onRunningChanged) must not reshape the window
        // during the tick before `activeEvent` lands.
        eventOwnsWindow = true

        // Same two-step as expansion: size the window silently first, run the
        // grow animation on the next tick in a stable coordinate space — the
        // bulge then grows symmetrically out of the camera housing.
        panel.setFrame(eventFrame(on: screen), display: true)
        eventShowTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            self?.viewModel.activeEvent = event
        }

        eventDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(CapsuleMetrics.eventDisplayMilliseconds))
            guard !Task.isCancelled, let self else { return }
            self.viewModel.activeEvent = nil
            try? await Task.sleep(for: .milliseconds(CapsuleMetrics.windowCollapseDelayMilliseconds))
            guard !Task.isCancelled, let screen = settings.stripScreen else { return }
            self.eventOwnsWindow = false
            guard self.targetState != .expanded else { return }
            // Settle into the current idle state — the state machine was
            // frozen while the event was on screen.
            let idle = self.idleState
            self.targetState = idle
            self.viewModel.setState(idle)
            self.panel.setFrame(self.frame(for: idle, on: screen), display: true)
        }
    }

    private func eventFrame(on screen: NSScreen) -> NSRect {
        CapsuleGeometry.topCentered(CapsuleGeometry.capsule(closedSize, side: CapsuleMetrics.eventSideWidth), on: screen)
    }

    /// Hover enters through the hosting view's tracking area. Resting on
    /// the capsule (or a live-event bulge) opens the settings unpinned;
    /// leaving the expanded panel closes them unless they are pinned.
    private func hoverEntered() {
        expandIfOverRestingCapsule()
    }

    /// Leaving closes at once — no grace period. Menus, sheets and the
    /// resize grip are still respected by `collapseIfCursorLeft`.
    private func hoverExited() {
        cancelHoverOpen()
        collapseIfCursorLeft()
    }

    /// Moves inside the window. Expanded, the menu-bar band beside the neck
    /// is window but not capsule: crossing into it is leaving. Resting, the
    /// window may still be the size of a drop that is closing; only the
    /// capsule itself opens it again.
    private func hoverMoved(viewPoint point: NSPoint, in bounds: NSRect) {
        if targetState == .expanded {
            if !capsuleOwns(viewPoint: point, in: bounds) {
                collapseIfCursorLeft()
            }
        } else {
            expandIfOverRestingCapsule()
        }
    }

    /// Hover opens the settings only from the resting capsule (or a live
    /// event's bulge). The window outlives the close animation by a beat,
    /// and without this the cursor crossing the space a closing drop is
    /// still vacating would throw it straight back open.
    ///
    /// The cursor has to rest there for `hoverOpenDelayMilliseconds` first:
    /// one countdown per visit, dropped as soon as the cursor moves off.
    private func expandIfOverRestingCapsule() {
        guard isCursorOverRestingCapsule else {
            cancelHoverOpen()
            return
        }
        guard hoverOpenTask == nil else { return }
        hoverOpenTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(CapsuleMetrics.hoverOpenDelayMilliseconds))
            guard !Task.isCancelled, let self else { return }
            self.hoverOpenTask = nil
            guard self.isCursorOverRestingCapsule else { return }
            self.viewModel.content = .settings
            self.requestState(.expanded)
        }
    }

    private var isCursorOverRestingCapsule: Bool {
        guard targetState != .expanded, let screen = settings.stripScreen else { return false }
        let resting = eventOwnsWindow ? eventFrame(on: screen) : frame(for: targetState, on: screen)
        // One point of slack: the cursor parks on the screen's very edge.
        return resting.insetBy(dx: -1, dy: -1).contains(NSEvent.mouseLocation)
    }

    private func cancelHoverOpen() {
        hoverOpenTask?.cancel()
        hoverOpenTask = nil
    }

    /// Collapses only when the cursor really is away from the panel and
    /// nothing of ours (a menu, a popover, a sheet) is up in front of it.
    private func collapseIfCursorLeft() {
        guard targetState == .expanded, !settingsPinned, !viewModel.isResizingPanel else { return }
        guard !PanelHold.shared.isHeld else { return }
        guard panel.attachedSheet == nil, !panel.hasOwnPopupWindow else { return }
        guard let screen = settings.stripScreen else { return }
        if expandedContains(NSEvent.mouseLocation, on: screen) { return }
        requestState(idleState)
    }

    /// A SwiftUI Menu or picker opens its own window on top of the panel;
    /// while one is visible the cursor is "inside" as far as the user is
    /// concerned.

    /// Single entry point for state changes: prepare the window frame first,
    /// then run the animation.
    private func requestState(_ newState: CapsuleState) {
        guard newState != targetState else { return }
        log.info("state -> \(String(describing: newState), privacy: .public) mouse=\(NSStringFromPoint(NSEvent.mouseLocation), privacy: .public)")
        targetState = newState
        cancelHoverOpen()
        collapseTask?.cancel()
        expandTask?.cancel()
        guard let screen = settings.stripScreen else { return }

        switch newState {
        case .expanded:
            // Expansion takes over: a visible live event is dismissed.
            eventShowTask?.cancel()
            eventDismissTask?.cancel()
            eventOwnsWindow = false
            viewModel.activeEvent = nil
            // Settings host text input — let the panel take key status
            // without activating the app.
            panel.allowsKeyFocus = true
            installOutsideClickMonitors()
            // Grow the window silently first: the capsule is pinned to the top
            // center and does not visually move. The animation starts on the
            // next tick, once the window's coordinate space is stable —
            // otherwise the growth starts from shifted coordinates and looks
            // like a widget sliding onto the camera housing from the side.
            panel.setFrame(frame(for: .expanded, on: screen), display: true)
            expandTask = Task { [weak self] in
                guard !Task.isCancelled else { return }
                self?.viewModel.setState(.expanded)
            }
        case .closed, .compact:
            settingsPinned = false
            clickMonitors.remove()
            panel.allowsKeyFocus = false
            if panel.isKeyWindow {
                panel.resignKey()
            }
            // While a live event is on screen it owns the window frame; only
            // the logical state advances — the dismiss task settles the rest.
            guard !eventOwnsWindow else {
                viewModel.setState(newState)
                return
            }
            let target = frame(for: newState, on: screen)
            if target.width > panel.frame.width {
                // Growing (closed → compact): widen the window silently
                // first, animate on the next tick in a stable coordinate
                // space — mirrors the expansion two-step.
                panel.setFrame(target, display: true)
                expandTask = Task { [weak self] in
                    guard !Task.isCancelled else { return }
                    self?.viewModel.setState(newState)
                }
            } else {
                viewModel.setState(newState)
                // Shrink the window only after SwiftUI has finished the close
                // animation, otherwise it would clip the capsule mid-flight.
                collapseTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(CapsuleMetrics.windowCollapseDelayMilliseconds))
                    guard !Task.isCancelled, let self,
                          let screen = settings.stripScreen else { return }
                    self.panel.setFrame(self.frame(for: newState, on: screen), display: true)
                }
            }
        }
    }

    private func attachToScreen() {
        guard let screen = settings.stripScreen else { return }
        attachedScreen = screen
        // The housing's own size, or the fallback on a display without one.
        closedSize = CapsuleGeometry.closedSize(on: screen)

        let rootView = CapsuleRootView(
            viewModel: viewModel,
            services: services,
            settings: settings,
            closedSize: closedSize
        )
        let hostingView = CapsuleHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        hostingView.onMouseEntered = { [weak self] in self?.hoverEntered() }
        hostingView.onMouseExited = { [weak self] in self?.hoverExited() }
        hostingView.onMouseMoved = { [weak self] point, bounds in
            self?.hoverMoved(viewPoint: point, in: bounds)
        }
        hostingView.ownsPoint = { [weak self] point in
            self?.capsuleOwns(viewPoint: point, in: hostingView.bounds) ?? true
        }
        panel.contentView = hostingView.makeWindowContentView()

        panel.setFrame(frame(for: viewModel.state, on: screen), display: true)
        panel.orderFrontRegardless()
    }

    /// `content` defaults to what the capsule shows now.
    private func frame(
        for state: CapsuleState,
        content: CapsuleContent? = nil,
        on screen: NSScreen
    ) -> NSRect {
        let size: CGSize = switch state {
        case .expanded:
            // The view model is the one source of the body size — the window
            // and the SwiftUI capsule must always agree on it. The panel sits
            // below the menu bar; the neck through it adds the housing's
            // height.
            expandedSize(viewModel.panelSize(for: content ?? viewModel.content, settings: settings))
        case .compact:
            CapsuleGeometry.capsule(closedSize, side: CapsuleMetrics.compactSideWidth)
        case .closed:
            closedSize
        }
        return CapsuleGeometry.topCentered(size, on: screen)
    }

    private func expandedSize(_ panel: CGSize) -> CGSize {
        CGSize(width: panel.width, height: panel.height + closedSize.height + CapsuleMetrics.dropFillet)
    }

    @objc private func screenParametersDidChange() {
        // Settles which display the strip is on now and re-clamps the panel
        // sizes to it.
        settings.refreshStripDisplay()
        moveToStripScreen()
    }

    /// Rebuilds the capsule, closed, at the top center of the strip's
    /// display — after a screen change, or once the strip changed display.
    private func moveToStripScreen() {
        // The capsule rebuilds from scratch on the (possibly new) screen, so
        // every in-flight transition and the live-event ownership must go
        // with it — otherwise `targetState` would still say "expanded" for a
        // window that is now closed, and hover could never reopen it.
        collapseTask?.cancel()
        expandTask?.cancel()
        eventShowTask?.cancel()
        eventDismissTask?.cancel()
        eventOwnsWindow = false
        viewModel.activeEvent = nil
        clickMonitors.remove()
        panel.allowsKeyFocus = false
        targetState = .closed
        viewModel.setState(.closed)
        settingsPinned = false
        cancelHoverOpen()
        attachToScreen()
    }
}
