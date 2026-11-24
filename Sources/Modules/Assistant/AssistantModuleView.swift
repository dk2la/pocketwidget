import SwiftUI

/// "Assistant" module: chat transcript over the widget's modules. User turns
/// sit right on raised glass, assistant turns as plain text on the left,
/// tool calls as small chips with a check ("✓ set_timer(25)").
struct AssistantModuleView: View {
    var assistant: AssistantService
    var speech: SpeechCaptureService
    var voice: SpeechSynthesisService

    @FocusState private var composerFocused: Bool

    var body: some View {
        if assistant.config == nil {
            setupPrompt
        } else {
            chat
        }
    }

    private var setupPrompt: some View {
        ModuleSetupPrompt(title: L10n.t(.asstSetupTitle), sublabel: L10n.t(.asstSetupSub))
    }

    private var chat: some View {
        VStack(spacing: 10) {
            // The robot is the empty chat only: once there is a turn, the
            // transcript has the panel to itself.
            transcript.emptyScreen(when: assistant.transcript.isEmpty) {
                ModuleEmptyScreen(
                    label: L10n.t(.asstEmptyTitle),
                    sublabel: assistant.isVoiceMode ? L10n.t(.asstVoiceHint) : L10n.t(.asstHint)
                ) {
                    IsoAssistantView(mode: robotMode)
                }
            }
            // A playbook closes apps, so the model only gets to ask.
            if let playbook = assistant.pendingPlaybook {
                playbookConfirmation(playbook)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            // Same live dictation line the Notes module shows: the words
            // appear as they are recognised, before the turn is sent.
            SpeechStatusRow(speech: speech)
            composer
        }
        .animation(Theme.stateSpring, value: speech.isRecording)
        .animation(Theme.stateSpring, value: assistant.pendingPlaybook)
        // Answers are spoken from here, not from the service, so the audio
        // follows the view that is actually on screen.
        .onChange(of: assistant.pendingSpeech) { _, pending in
            guard pending != nil, let text = assistant.consumePendingSpeech() else { return }
            voice.speak(text, locale: L10n.shared.language.speechLocale)
        }
        .onDisappear { voice.stop() }
    }

    /// What the robot of the empty chat is doing.
    private var robotMode: IsoAssistantView.Mode {
        if speech.isRecording { return .listening }
        return assistant.isThinking ? .thinking : .idle
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(assistant.transcript) { message in
                        row(message)
                    }
                    if assistant.isThinking {
                        HStack(spacing: 6) {
                            BlinkingDot(color: Theme.accent, size: 5)
                            Text(L10n.t(.asstThinking))
                                .font(Theme.subFont)
                                .foregroundStyle(Theme.textTertiary)
                            Spacer(minLength: 0)
                        }
                        .id("thinking")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
            }
            .onChange(of: assistant.transcript.count) {
                withAnimation(Theme.stateSpring) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onAppear {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func row(_ message: AssistantMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .font(Theme.bodyFont)
                    .lineSpacing(2)
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 14,
                            bottomLeadingRadius: 14,
                            bottomTrailingRadius: 4,
                            topTrailingRadius: 14,
                            style: .continuous
                        )
                        .fill(Theme.raisedFill)
                    )
            }
        case .assistant:
            HStack {
                Text(message.text)
                    .font(Theme.bodyFont)
                    .lineSpacing(3)
                    .foregroundStyle(message.isError ? Theme.critical : Theme.textSecondary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 2)
                Spacer(minLength: 32)
            }
        case .tool:
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: message.isError ? "exclamationmark.triangle" : "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(message.isError ? Theme.critical : Theme.accent)
                    Text(message.toolLabel ?? "")
                        .font(Theme.subFont)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Theme.hairlineSoft, lineWidth: 1)
                )
                Spacer(minLength: 0)
            }
        }
    }

    /// A playbook closes apps, so the model only asks — this card runs it.
    private func playbookConfirmation(_ playbook: Playbook) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.groupRadius, style: .continuous)
        return VStack(alignment: .trailing, spacing: 12) {
            HStack(spacing: 12) {
                IconTile(systemName: playbook.icon)
                Text(L10n.f(.asstPlaybookConfirm, playbook.name))
                    .font(Theme.bodyFont)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                ModuleButton(label: L10n.t(.mailCancel)) {
                    assistant.cancelPendingPlaybook()
                }
                ModuleButton(label: L10n.t(.asstPlaybookRun), systemName: "play.fill", kind: .accent) {
                    assistant.confirmPendingPlaybook()
                }
            }
        }
        .padding(14)
        .background(Theme.cardFill, in: shape)
        .overlay(shape.stroke(Theme.hairlineSoft, lineWidth: 1))
    }

    private var composer: some View {
        ComposerBar {
            SpeechMicControl(speech: speech, size: 30) { text in
                voice.stop() // barge-in: speaking over the answer replaces it
                assistant.acceptDictation(text)
            }
            TextField(L10n.t(.asstPlaceholder), text: Bindable(assistant).draft)
                .textFieldStyle(.plain)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textPrimary)
                .focused($composerFocused)
                .onSubmit { assistant.send() }
            // Voice-mode toggle and transcript clearing live in the panel
            // header; only the in-the-moment mute belongs down here.
            if voice.isSpeaking {
                ModuleButton(systemName: "speaker.slash", height: 30) {
                    voice.stop()
                }
                .transition(.opacity)
            }
            if !assistant.draft.isEmpty, !assistant.isThinking {
                ModuleButton(systemName: "arrow.up", kind: .light, height: 30) {
                    assistant.send()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .animation(Theme.stateSpring, value: assistant.draft.isEmpty)
        .animation(Theme.stateSpring, value: voice.isSpeaking)
    }
}
