import SwiftUI

/// "Timer" module: the countdown as a hero card — large digits, a thin bar
/// that drains with the time left, Start / Pause and Reset — and one row of
/// lengths underneath.
struct TimerModuleView: View {
    var timer: TimerService

    @State private var customMinutes = ""
    @FocusState private var customFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(
                            title: L10n.t(.timerLength),
                            trailing: L10n.t(.timerCustomPlaceholder)
                        )
                        lengthPicker
                    }
                }
            }
            ModuleFootnote(systemName: "bell", text: L10n.t(.timerDoneNote))
        }
    }

    // MARK: - Hero

    private var hero: some View {
        let isPartway = timer.remaining < timer.duration
        let state = L10n.t(timer.isRunning ? .focusRunning : .focusReady)
        return HeroCard {
            HStack(spacing: 7) {
                StatusDot(color: timer.isRunning ? Theme.accent : Theme.segmentOff)
                // Stored lower case ("focus · running"); reads as a sentence.
                Text(state.prefix(1).uppercased() + state.dropFirst())
                    .heroCaption()
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(TimeFormat.mmss(timer.remaining))
                    .font(Theme.timerFont)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                if isPartway {
                    Text(L10n.f(.timerLeftOf, Int(timer.duration / 60)))
                        .font(Theme.subFont)
                        .lineLimit(1)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            // The bar holds what is LEFT and drains — values jump per tick.
            GlassProgressBar(
                fraction: timer.duration > 0 ? timer.remaining / timer.duration : 0,
                fillColor: Theme.segmentOn
            )
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if isPartway {
                    ModuleButton(label: L10n.t(.timerReset)) {
                        timer.reset()
                    }
                }
                if timer.isRunning {
                    ModuleButton(label: L10n.t(.timerPause), systemName: "pause.fill", kind: .light) {
                        timer.pause()
                    }
                } else {
                    ModuleButton(label: L10n.t(.timerStart), systemName: "play.fill", kind: .accent) {
                        timer.start()
                    }
                }
            }
        }
    }

    // MARK: - Length

    /// Presets plus a free field in one segmented row. Locked while the
    /// timer runs — the length belongs to the countdown already going.
    private var lengthPicker: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.groupRadius, style: .continuous)
        return HStack(spacing: 4) {
            ForEach(TimerService.presets, id: \.self) { preset in
                Button {
                    timer.setDuration(preset)
                } label: {
                    Text("\(Int(preset / 60))")
                        .monospacedDigit()
                        .lengthCell(isActive: timer.duration == preset)
                }
                .buttonStyle(PressableStyle())
            }
            customCell
        }
        .padding(4)
        .background(Theme.cardFill, in: shape)
        .overlay(shape.stroke(Theme.hairlineSoft, lineWidth: 1))
        .opacity(timer.isRunning ? 0.35 : 1)
        .disabled(timer.isRunning)
    }

    /// Last cell of the row: type any minute count, Enter arms it. Lights
    /// up like an active preset while a non-preset length is set.
    private var customCell: some View {
        TextField("…", text: $customMinutes)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .focused($customFocused)
            .onSubmit(applyCustomMinutes)
            .onChange(of: customMinutes) { _, value in
                let digits = String(value.filter(\.isNumber).prefix(3))
                if digits != value { customMinutes = digits }
            }
            .lengthCell(isActive: !TimerService.presets.contains(timer.duration))
    }

    private func applyCustomMinutes() {
        guard let minutes = Int(customMinutes), minutes >= 1 else { return }
        timer.setDuration(TimeInterval(min(minutes, 999) * 60))
        customFocused = false
    }
}

private extension View {
    /// One cell of the length row.
    func lengthCell(isActive: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return font(Theme.subFont)
            .fontWeight(.medium)
            .foregroundStyle(isActive ? Theme.textPrimary : Theme.textTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(shape.fill(isActive ? Theme.raisedFill : .clear))
            .contentShape(shape)
    }
}

/// Closed-capsule indicator while the timer runs: blinking dot, countdown.
struct CompactTimerView: View {
    var timer: TimerService

    var body: some View {
        HStack {
            BlinkingDot(size: 6)
            Spacer(minLength: 0)
            Text(TimeFormat.mmss(timer.remaining))
                .font(Theme.smallValueFont)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 14)
    }
}
