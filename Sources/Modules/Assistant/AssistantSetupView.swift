import AppKit
import SwiftUI

/// Choosing who answers, inside the Assistant module: one card each for
/// Claude, ChatGPT and an own key. Every decision is made by
/// `AssistantSetupFlow`; this view draws its cards and passes on clicks.
struct AssistantSetupView: View {
    var flow: AssistantSetupFlow
    /// Removes the saved provider.
    let onDisconnect: () -> Void
    /// Sign-in happens in Terminal and the browser. The panel stays open
    /// meanwhile, so the waiting card is still there to connect and open
    /// the chat when the person comes back.
    @State private var holdsPanel = false

    private var isWaiting: Bool {
        if case .waiting = flow.phase { true } else { false }
    }

    private func holdPanel(_ hold: Bool) {
        guard hold != holdsPanel else { return }
        holdsPanel = hold
        if hold {
            PanelHold.shared.begin()
        } else {
            PanelHold.shared.end()
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if flow.phase == .ownKey {
                AssistantKeyForm(flow: flow)
            } else {
                chooser
            }
        }
        .animation(Theme.stateSpring, value: flow.phase)
        .animation(Theme.stateSpring, value: flow.facts)
        .onAppear {
            flow.setVisible(true)
            holdPanel(isWaiting)
            Task { await flow.refresh() }
        }
        .onDisappear {
            flow.setVisible(false)
            holdPanel(false)
        }
        .onChange(of: isWaiting) { _, waiting in holdPanel(waiting) }
        // Back from Terminal or the browser: something may be installed now.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await flow.refresh() }
        }
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: L10n.t(.asstChoose))
            ForEach([AssistantProvider.claudeCode, .codex]) { provider in
                AssistantProviderCardView(provider: provider, card: flow.card(for: provider)) { action in
                    perform(action, on: provider)
                }
            }
            keyCard
            if flow.canClose {
                HStack {
                    Spacer(minLength: 0)
                    ModuleButton(label: L10n.t(.asstDisconnect), tint: Theme.critical, action: onDisconnect)
                }
            }
        }
    }

    private var keyCard: some View {
        let connected = flow.card(for: .api).status == .connected
        return SetupCard {
            SetupCardHeading(
                title: L10n.t(.asstOwnKey),
                status: connected ? L10n.t(.mailCheckOk) : nil,
                highlighted: connected
            )
            SetupCardNote(text: L10n.t(.asstProviderAPI))
            SetupCardActions {
                ModuleButton(label: L10n.t(connected ? .calEdit : .asstSetUp)) {
                    flow.openKeyForm()
                }
            }
        }
    }

    private func perform(_ action: AssistantProviderCard.Action, on provider: AssistantProvider) {
        switch action {
        case .connect: Task { await flow.connect(provider) }
        case .signIn, .installAndSignIn: flow.startSignIn(provider)
        case .cancel: flow.cancelWaiting()
        }
    }
}

/// One command-line provider: what was found and the one thing to do.
private struct AssistantProviderCardView: View {
    let provider: AssistantProvider
    let card: AssistantProviderCard
    let onAction: (AssistantProviderCard.Action) -> Void

    var body: some View {
        SetupCard {
            SetupCardHeading(title: provider.title, status: status, highlighted: isHighlighted, busy: isBusy)
            SetupCardNote(text: note)
            if card.status == .noInstaller {
                manualSteps
            }
            if let failure = card.failure {
                SetupCardNote(text: Self.text(for: failure), color: Theme.critical)
            }
            if let action = card.action {
                SetupCardActions {
                    ModuleButton(label: Self.label(for: action), kind: action == .cancel ? .ghost : .light) {
                        onAction(action)
                    }
                }
            }
        }
    }

    private var status: String? {
        switch card.status {
        case .connected: L10n.t(.mailCheckOk)
        case .found: L10n.t(.asstFound)
        case .signedOut: L10n.t(.asstSignedOut)
        case .missing: L10n.t(.asstMissing)
        case .testing: L10n.t(.mailChecking)
        case .waiting: L10n.t(.asstWaiting)
        case .appOnly, .noInstaller: nil
        }
    }

    private var isHighlighted: Bool {
        card.status == .connected || card.status == .found
    }

    private var isBusy: Bool {
        card.status == .testing || card.status == .waiting
    }

    private var note: String {
        switch card.status {
        case .appOnly: L10n.f(.asstAppFound, provider.title)
        case .waiting: L10n.t(.asstWaitingSub)
        case .noInstaller: L10n.t(.asstManualIntro)
        default: subscriptionNote
        }
    }

    private var subscriptionNote: String {
        L10n.t(provider == .claudeCode ? .asstProviderClaude : .asstProviderCodex)
    }

    /// Nothing on this Mac can install the program: the steps, to be done
    /// by hand. Pocket does not install Node for the person.
    private var manualSteps: some View {
        let steps = [L10n.t(.asstManualNode)]
            + AssistantSetupPlan.manualCommands(for: provider).map { L10n.f(.asstManualRun, $0) }
            + [L10n.t(.asstManualDone)]
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(index + 1).")
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                    Text(step)
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(Theme.subFont)
            }
        }
    }

    private static func label(for action: AssistantProviderCard.Action) -> String {
        switch action {
        case .connect: L10n.t(.mailConnect)
        case .signIn: L10n.t(.asstSignIn)
        case .installAndSignIn: L10n.t(.asstInstallSignIn)
        case .cancel: L10n.t(.mailCancel)
        }
    }

    private static func text(for failure: AssistantSetupFailure) -> String {
        switch failure {
        case .timedOut: L10n.t(.asstTimedOut)
        case .terminal: L10n.t(.asstTerminalFailed)
        case .notSaved: L10n.t(.mailErrorNotSaved)
        case .notInstalled, .other: L10n.t(.asstFailed)
        }
    }
}

/// The own-key form: presets, base URL, model, API key.
private struct AssistantKeyForm: View {
    var flow: AssistantSetupFlow

    var body: some View {
        let draft = Bindable(flow).draft
        let card = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: L10n.t(.asstOwnKey))
            presetRow
            VStack(spacing: 0) {
                field { TextField(L10n.t(.asstBaseURL), text: draft.baseURL) }
                Hairline()
                field { TextField(L10n.t(.asstModel), text: draft.model) }
                Hairline()
                field { SecureField(L10n.t(.asstKey), text: draft.key) }
            }
            .background(Theme.cardFill, in: card)
            SetupCardNote(text: L10n.t(.asstKeyHint))
                .padding(.horizontal, 4)
            if let failure = flow.keyFailure {
                SetupCardNote(text: Self.text(for: failure), color: Theme.critical)
                    .padding(.horizontal, 4)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                ModuleButton(label: L10n.t(.mailCancel)) {
                    flow.back()
                }
                ModuleButton(
                    label: flow.isTestingKey ? L10n.t(.mailChecking) : L10n.t(.mailConnect),
                    kind: .light,
                    enabled: flow.canConnectKey
                ) {
                    Task { await flow.connectKey() }
                }
            }
        }
        .animation(Theme.stateSpring, value: flow.keyFailure)
    }

    private var presetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(AssistantAPIPreset.allCases) { preset in
                    let selected = AssistantAPIPreset.matching(flow.draft.baseURL) == preset
                    let shape = RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    Button {
                        flow.applyPreset(preset)
                    } label: {
                        Text(preset.title)
                            .font(Theme.subFont)
                            .fontWeight(selected ? .semibold : .medium)
                            .lineLimit(1)
                            .foregroundStyle(selected ? Theme.inkOnAccent : Theme.textSecondary)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(shape.fill(selected ? Theme.lightFill : Theme.cardFill))
                            .overlay(shape.stroke(Theme.hairlineSoft, lineWidth: selected ? 0 : 1))
                            .contentShape(shape)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private func field<Field: View>(@ViewBuilder _ content: () -> Field) -> some View {
        content()
            .textFieldStyle(.plain)
            .font(Theme.bodyFont)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
    }

    private static func text(for failure: AssistantSetupFlow.KeyFailure) -> String {
        switch failure {
        case .refused(let message): message
        case .notSaved: L10n.t(.mailErrorNotSaved)
        }
    }
}

// MARK: - Card pieces

/// The card every provider sits on: the grouped-list card of the other
/// modules.
private struct SetupCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.groupRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardFill, in: shape)
        .overlay(shape.stroke(Theme.hairlineSoft, lineWidth: 1))
    }
}

/// Provider name on the left, its state on the right.
private struct SetupCardHeading: View {
    let title: String
    var status: String?
    /// The state is good news: found, connected.
    var highlighted = false
    /// Something is in progress: testing, waiting.
    var busy = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(Theme.headlineFont)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let status {
                HStack(spacing: 6) {
                    if busy {
                        BlinkingDot(color: Theme.accent, size: 5)
                    } else if highlighted {
                        StatusDot()
                    }
                    Text(status)
                        .font(Theme.subFont)
                        .lineLimit(1)
                        .foregroundStyle(highlighted ? Theme.textSecondary : Theme.textTertiary)
                }
            }
        }
    }
}

private struct SetupCardNote: View {
    let text: String
    var color: Color = Theme.textTertiary

    var body: some View {
        Text(text)
            .font(Theme.subFont)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The card's button, at its trailing edge.
private struct SetupCardActions<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            content
        }
    }
}
