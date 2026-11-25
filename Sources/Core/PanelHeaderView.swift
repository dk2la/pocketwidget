import SwiftUI

/// The one header every module panel gets: `[back?] TITLE …… [actions] [✕]`.
/// Modules draw no chrome of their own — their navigation state lives in the
/// services and this view reads it, so every tab speaks the same grammar:
/// chevron to go up, module title, the module's few actions on the right.
/// The capsule's expanded panel embeds the same back/actions pieces next to
/// its tab row.
struct PanelHeaderView: View {
    let tab: ModuleTab
    var services: ModuleServices
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ModuleBackButton(tab: tab, services: services)
            Text(tab.title)
                .font(Theme.titleFont)
                .lineLimit(1)
                .foregroundStyle(Theme.textPrimary)
                .padding(.leading, 4)
            if tab == .email, let badge = services.emailService.unreadBadge {
                UnreadBadge(text: badge)
                    .padding(.leading, 4)
            }
            if tab == .calendar, showsCalendarDate {
                // The agenda's date; the week view carries its own range.
                Text(Self.dateFormatter.string(from: Date()))
                    .font(Theme.bodyFont)
                    .lineLimit(1)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.leading, 6)
            }
            Spacer(minLength: 0)
            ModuleAccessoriesView(tab: tab, services: services)
            HeaderIconButton("xmark", action: onClose)
        }
        .padding(.horizontal, Theme.panelInset - 4)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    private var showsCalendarDate: Bool {
        let calendar = services.calendarService
        return calendar.displayMode == .listOnly && calendar.selectedEvent == nil
            && !calendar.isCreating && calendar.editingEvent == nil && !calendar.showingPicker
    }

    private static let dateFormatter = DateFormatter(template: "EEE d MMM")
}

/// Red count capsule after the mail title.
struct UnreadBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.captionFont)
            .fontWeight(.semibold)
            .monospacedDigit()
            .foregroundStyle(Color.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(Theme.critical, in: Capsule())
    }
}

/// Chevron shown whenever the module is one level deep; always returns to
/// the module's root.
struct ModuleBackButton: View {
    let tab: ModuleTab
    var services: ModuleServices

    var body: some View {
        if let back = backAction {
            HeaderIconButton("chevron.left", action: back)
        }
    }

    private var backAction: (() -> Void)? {
        switch tab {
        case .email:
            if services.emailService.isComposeOpen {
                { services.emailService.closeCompose() }
            } else if services.emailService.openMessage != nil {
                { services.emailService.closeMessage() }
            } else if services.emailService.needsSetup, services.emailService.setup.isActive {
                { services.emailService.setup.cancel() }
            } else {
                nil
            }
        case .notes:
            services.notesStore.openNote != nil
                ? {
                    services.notesStore.commitTitle()
                    services.notesStore.closeEditor()
                }
                : nil
        case .calendar:
            calendarBackAction
        case .assistant:
            assistantBackAction
        default:
            nil
        }
    }

    /// Form → chooser → chat. The chooser has no way back while there is
    /// no provider to chat with.
    private var assistantBackAction: (() -> Void)? {
        let assistant = services.assistantService
        guard !assistant.isDemo else { return nil }
        let setup = assistant.setup
        switch setup.phase {
        case .closed: return nil
        case .chooser: return setup.canClose ? { setup.back() } : nil
        case .ownKey, .testing, .waiting: return { setup.back() }
        }
    }

    /// Form → card → list, one level per chevron.
    private var calendarBackAction: (() -> Void)? {
        let calendar = services.calendarService
        if calendar.editingEvent != nil {
            return { calendar.cancelEditing() }
        } else if calendar.isCreating {
            return { calendar.cancelCreating() }
        } else if calendar.selectedEvent != nil {
            return { calendar.closeEvent() }
        } else if calendar.showingPicker {
            return { calendar.showingPicker = false }
        }
        return nil
    }
}

/// The module's few header actions — the same set on the widget panel and
/// the capsule.
struct ModuleAccessoriesView: View {
    let tab: ModuleTab
    var services: ModuleServices

    var body: some View {
        switch tab {
        case .email:
            emailAccessories
        case .calendar:
            calendarAccessories
        case .assistant:
            assistantAccessories
        case .notes:
            // An open note carries its own Delete, in the editor.
            if services.notesStore.openNote == nil {
                HeaderIconButton("plus", help: L10n.t(.notesNew)) {
                    services.notesStore.create()
                }
            }
        case .clipboard:
            if !services.clipboardStore.entries.isEmpty {
                HeaderIconButton("trash", help: L10n.t(.clipClear)) {
                    services.clipboardStore.clear()
                }
            }
        case .shelf:
            if !services.shelfStore.items.isEmpty {
                HeaderIconButton("trash", help: L10n.t(.clipClear)) {
                    services.shelfStore.clear()
                }
            }
        case .playbooks:
            HeaderIconButton("plus", help: L10n.t(.playAdd)) {
                requestSettings()
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var emailAccessories: some View {
        let service = services.emailService
        if !service.needsSetup, !service.isComposeOpen {
            if let message = service.openMessage {
                // Sent and Spam mail is not in the inbox — nothing to archive.
                if service.canArchive(message) {
                    HeaderIconButton("archivebox", help: L10n.t(.mailArchive)) {
                        service.archive(message)
                    }
                }
                HeaderIconButton("arrow.up.forward.app", help: L10n.t(.mailOpenInApp)) {
                    service.openInMailApp()
                }
            } else {
                HeaderIconButton("square.and.pencil", help: L10n.t(.mailNewMessage)) {
                    service.startNewMail()
                }
                HeaderIconButton(
                    "magnifyingglass",
                    help: L10n.t(.mailSearch),
                    active: service.isSearchOpen
                ) {
                    service.toggleSearch()
                }
                HeaderIconButton("arrow.clockwise", help: L10n.t(.mailRefresh)) {
                    service.refresh()
                }
            }
        }
    }

    @ViewBuilder
    private var calendarAccessories: some View {
        let service = services.calendarService
        // The detail card and the form carry their own actions; the header
        // only adds to the list.
        if service.access == .granted, !service.showingPicker,
           service.selectedEvent == nil, !service.isCreating, service.editingEvent == nil {
            if !service.writableCalendars.isEmpty {
                HeaderIconButton("plus", help: L10n.t(.calNewEvent)) {
                    service.startCreating(on: service.selectedDay)
                }
            }
            ForEach(CalendarDisplayMode.allCases) { mode in
                HeaderIconButton(mode.icon, active: service.displayMode == mode) {
                    service.setDisplayMode(mode)
                }
            }
            HeaderIconButton("line.3.horizontal.decrease") {
                service.showingPicker = true
            }
        }
    }

    @ViewBuilder
    private var assistantAccessories: some View {
        let assistant = services.assistantService
        if let config = assistant.config, assistant.isDemo || !assistant.setup.isOpen {
            // Who answers; opens the chooser over the conversation.
            HeaderTextButton(Self.providerLabel(config), help: L10n.t(.asstChangeProvider)) {
                services.speechSynthesis.stop()
                if !assistant.isDemo {
                    assistant.setup.open()
                }
            }
            HeaderIconButton("waveform", active: assistant.isVoiceMode) {
                let enabled = !assistant.isVoiceMode
                assistant.setVoiceMode(enabled)
                if !enabled {
                    services.speechSynthesis.stop()
                }
            }
            if !assistant.transcript.isEmpty {
                HeaderIconButton("trash") {
                    services.speechSynthesis.stop()
                    assistant.clearTranscript()
                }
            }
        }
    }
}

extension ModuleAccessoriesView {
    /// "Claude", "ChatGPT", or the service behind an own key.
    static func providerLabel(_ config: AssistantConfig) -> String {
        guard !config.provider.isCLI else { return config.provider.title }
        return AssistantAPIPreset.matching(config.baseURL)?.title ?? L10n.t(.asstOwnKey)
    }
}

/// A header action that has to be read, not guessed from a glyph: the
/// assistant's provider. Same hover and height as `HeaderIconButton`.
struct HeaderTextButton: View {
    let label: String
    var help: String?
    let action: () -> Void

    @State private var hovered = false

    init(_ label: String, help: String? = nil, action: @escaping () -> Void) {
        self.label = label
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(Theme.subFont)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(hovered ? Theme.textSecondary : Theme.textTertiary)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovered ? Theme.raisedFill : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
        .help(help ?? "")
    }
}

struct HeaderIconButton: View {
    let systemName: String
    var help: String?
    var active = false
    let action: () -> Void

    @State private var hovered = false

    init(
        _ systemName: String,
        help: String? = nil,
        active: Bool = false,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.help = help
        self.active = active
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? Theme.accent : hovered ? Theme.textSecondary : Theme.textTertiary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hovered ? Theme.raisedFill : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
        .help(help ?? "")
    }
}
