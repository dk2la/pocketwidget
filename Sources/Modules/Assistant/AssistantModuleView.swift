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
        // The demo's scripted provider is not a real one to set up.
        if !assistant.isDemo, assistant.setup.isOpen {
            AssistantSetupView(flow: assistant.setup) {
                voice.stop()
                assistant.removeConfig()
            }
        } else {
            chat
        }
    }

    private var chat: some View {
        VStack(spacing: 10) {
            transcript.emptyScreen(when: assistant.transcript.isEmpty) {
                ModuleEmptyScreen(
                    label: L10n.t(.asstEmptyTitle),
                    sublabel: assistant.isVoiceMode ? L10n.t(.asstVoiceHint) : L10n.t(.asstHint)
                )
            }
            // A playbook closes apps, so the model only gets to ask.
            if let playbook = assistant.pendingPlaybook {
                playbookConfirmation(playbook)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            // Same live dictation line the Notes module shows: the words
            // appear as they are recognised, before the turn is sent.
            SpeechStatusRow(speech: speech)
            if showsSuggestions {
                suggestions
                    .transition(.opacity)
            }
            composer
        }
        .animation(Theme.stateSpring, value: speech.isRecording)
        .animation(Theme.stateSpring, value: assistant.pendingPlaybook)
        .animation(Theme.stateSpring, value: showsSuggestions)
        // Answers are spoken from here, not from the service, so the audio
        // follows the view that is actually on screen.
        .onChange(of: assistant.pendingSpeech) { _, pending in
            guard pending != nil, let text = assistant.consumePendingSpeech() else { return }
            voice.speak(text, locale: L10n.shared.language.speechLocale)
        }
        .onDisappear { voice.stop() }
    }

    private var showsSuggestions: Bool {
        AssistantSuggestion.isOffered(
            transcriptIsEmpty: assistant.transcript.isEmpty,
            isThinking: assistant.isThinking
        )
    }

    /// Four questions to start from, in one row that scrolls sideways. A
    /// click sends the question at once; the row is gone after the first
    /// message.
    private var suggestions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(AssistantSuggestion.allCases) { suggestion in
                    let shape = RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    Button {
                        voice.stop()
                        assistant.send(suggestion.text)
                    } label: {
                        Text(suggestion.text)
                            .font(Theme.subFont)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background(shape.fill(Theme.cardFill))
                            .overlay(shape.stroke(Theme.hairlineSoft, lineWidth: 1))
                            .contentShape(shape)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
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
