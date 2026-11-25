import SwiftUI

/// "Timer" module. On top, what is set: a quiet row for the alarm with the
/// time it rings at, and a hero card for a countdown — running or paused
/// partway — with the time left, a bar that drains with it, Pause / Start
/// and Reset. With neither, the empty screen.
/// Under it one card sets both, switched between Timer and Alarm: a dial to
/// drag, the usual lengths for the timer, and Start or Set.
struct TimerModuleView: View {
    var timer: TimerService

    /// What the card under the hero sets.
    private enum Mode { case timer, alarm }

    @State private var mode = Mode.timer
    /// The alarm's clock time, in five-minute steps from midnight.
    @State private var alarmStep = TimerModuleView.step(after: Date().addingTimeInterval(30 * 60))

    var body: some View {
        let isEmpty = timer.isIdle && timer.alarmDate == nil
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    if let alarmDate = timer.alarmDate {
                        alarmRow(alarmDate)
                            .transition(.opacity)
                    }
                    if !timer.isIdle {
                        hero
                            .transition(.opacity)
                    }
                }
                .animation(Theme.stateSpring, value: timer.alarmDate)
                .animation(Theme.stateSpring, value: timer.isIdle)
                .emptyScreen(when: isEmpty) {
                    ModuleEmptyScreen(label: L10n.t(.focusReady), sublabel: L10n.t(.timerDoneNote))
                }
                picker
            }
            if !isEmpty {
                ModuleFootnote(systemName: "bell", text: L10n.t(.timerDoneNote))
            }
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
                Spacer(minLength: 0)
                if let endsAt {
                    Text(endsAt)
                        .font(Theme.subFont)
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(TimeFormat.mmss(timer.remaining))
                    .font(Theme.timerFont)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
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
                ModuleButton(label: L10n.t(.timerReset)) {
                    timer.reset()
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

    /// "Ends at 17:42" while the countdown runs.
    private var endsAt: String? {
        guard timer.isRunning else { return nil }
        let end = Date().addingTimeInterval(timer.remaining)
        return L10n.f(.timerEndsAt, end.formatted(date: .omitted, time: .shortened))
    }

    // MARK: - Alarm

    private static let minutesPerStep = 5
    private static let stepsPerDay = 24 * 60 / minutesPerStep

    /// The first five-minute step at or after `date`.
    private static func step(after date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return min((minutes + minutesPerStep - 1) / minutesPerStep, stepsPerDay - 1)
    }

    private var alarmHour: Int { alarmStep * Self.minutesPerStep / 60 }
    private var alarmMinute: Int { alarmStep * Self.minutesPerStep % 60 }

    /// The picked time the way the system shows clock times.
    private var alarmLabel: String {
        let date = Calendar.current.date(
            bySettingHour: alarmHour, minute: alarmMinute, second: 0, of: Date()
        ) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// How long until `date`: "1 h 20 min".
    private static func until(_ date: Date) -> String {
        let minutes = max(1, Int((date.timeIntervalSinceNow / 60).rounded(.up)))
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return L10n.f(.ageMin, rest) }
        if rest == 0 { return L10n.f(.ageHour, hours) }
        return L10n.f(.ageHour, hours) + " " + L10n.f(.ageMin, rest)
    }

    /// The alarm that is set: nothing counts down here, it only says when
    /// it rings and how far off that is, and can be taken away.
    private func alarmRow(_ date: Date) -> some View {
        // Nothing else redraws the row while it waits.
        TimelineView(.periodic(from: .now, by: 20)) { _ in
            GroupedCard {
                HStack(alignment: .center, spacing: 12) {
                    IconTile(systemName: "alarm")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(date.formatted(date: .omitted, time: .shortened))
                            .font(Theme.bodyFont)
                            .fontWeight(.medium)
                            .monospacedDigit()
                            .lineLimit(1)
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(L10n.t(.timerAlarm)) · \(Self.until(date))")
                            .font(Theme.subFont)
                            .lineLimit(1)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer(minLength: 0)
                    CircleGlassButton(systemName: "xmark", size: 30, solid: false) {
                        timer.cancelAlarm()
                    }
                    .help(L10n.t(.timerReset))
                }
                .groupedRow(isLast: true)
            }
        }
    }

    // MARK: - Picker

    /// One card for both: the Timer / Alarm switch, the dial of the chosen
    /// one, and the value it shows beside Start or Set.
    private var picker: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.groupRadius, style: .continuous)
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                modeCell(.timer, label: L10n.t(.modTimer))
                modeCell(.alarm, label: L10n.t(.timerAlarm))
            }
            switch mode {
            case .timer: timerPicker
            case .alarm: alarmPicker
            }
        }
        .padding(4)
        .background(Theme.cardFill, in: shape)
        .overlay(shape.stroke(Theme.hairlineSoft, lineWidth: 1))
    }

    private func modeCell(_ cell: Mode, label: String) -> some View {
        Button {
            mode = cell
        } label: {
            Text(label)
                .lengthCell(isActive: mode == cell)
        }
        .buttonStyle(PressableStyle())
    }

    /// The dial for any length, the usual ones as one-click cells, and
    /// Start. Locked while the timer runs — the length belongs to the
    /// countdown already going.
    private var timerPicker: some View {
        VStack(spacing: 4) {
            RulerDial(
                value: Int(timer.duration / 60),
                range: 1...180,
                majorEvery: 5,
                label: { "\($0)" },
                onChange: { timer.setDuration(TimeInterval($0 * 60)) }
            )
            HStack(spacing: 4) {
                ForEach(TimerService.presets, id: \.self) { preset in
                    Button {
                        withAnimation(.snappy(duration: 0.3)) {
                            timer.setDuration(preset)
                        }
                    } label: {
                        Text("\(Int(preset / 60))")
                            .monospacedDigit()
                            .lengthCell(isActive: timer.duration == preset)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            actionRow(value: TimeFormat.mmss(timer.duration)) {
                ModuleButton(label: L10n.t(.timerStart), systemName: "play.fill", kind: .accent, height: 30) {
                    timer.start()
                }
            }
        }
        .opacity(timer.isRunning ? 0.35 : 1)
        .disabled(timer.isRunning)
    }

    /// The day's ruler in five-minute steps, and Set. Setting again moves
    /// the alarm.
    private var alarmPicker: some View {
        VStack(spacing: 4) {
            RulerDial(
                value: alarmStep,
                range: 0...(Self.stepsPerDay - 1),
                majorEvery: 60 / Self.minutesPerStep,
                label: { "\($0 * Self.minutesPerStep / 60):00" },
                onChange: { alarmStep = $0 }
            )
            actionRow(value: alarmLabel) {
                ModuleButton(label: L10n.t(.timerSet), systemName: "alarm", kind: .light, height: 30) {
                    timer.setAlarm(hour: alarmHour, minute: alarmMinute)
                }
            }
        }
    }

    /// The picked value, large, beside the one button that acts on it.
    private func actionRow(value: String, @ViewBuilder button: () -> some View) -> some View {
        HStack(spacing: 10) {
            Text(value)
                .font(Theme.heroFont)
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
            button()
        }
        .padding(.leading, 10)
        .padding(.trailing, 2)
        .padding(.vertical, 2)
    }
}

/// A ruler under a fixed pointer: drag it sideways to set the value. It
/// snaps to whole steps and ticks under the finger on each one. The timer
/// uses it twice: minutes of length, and five-minute steps of the day.
private struct RulerDial: View {
    /// The value now set.
    var value: Int
    let range: ClosedRange<Int>
    /// Every such step gets a taller tick and a label.
    let majorEvery: Int
    let label: (Int) -> String
    var onChange: (Int) -> Void

    private static let spacing: CGFloat = 9
    /// Room for the labels of the first and last tick.
    private static let inset: CGFloat = 24
    private static let height: CGFloat = 48

    /// Where the ruler sits while it is dragged, in fractional steps.
    @State private var dragPosition: Double?
    @State private var dragStart: Double?

    var body: some View {
        let position = dragPosition ?? Double(value)
        return GeometryReader { geometry in
            ruler
                .offset(x: geometry.size.width / 2 - Self.inset - CGFloat(position) * Self.spacing)
        }
        .frame(height: Self.height)
        .overlay(alignment: .bottom) {
            Capsule()
                .fill(Theme.accent)
                .frame(width: 2, height: 22)
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.2),
                    .init(color: .black, location: 0.8),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .contentShape(Rectangle())
        .gesture(drag)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { gesture in
                let start = dragStart ?? Double(value)
                dragStart = start
                let moved = start - Double(gesture.translation.width / Self.spacing)
                let position = min(max(moved, Double(range.lowerBound)), Double(range.upperBound))
                dragPosition = position
                let snapped = Int(position.rounded())
                if snapped != value {
                    onChange(snapped)
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
            }
            .onEnded { _ in
                dragStart = nil
                withAnimation(.snappy(duration: 0.2)) { dragPosition = nil }
            }
    }

    /// Every step as a tick, the major ones taller and labelled. Drawn once
    /// at full length and slid under the pointer.
    private var ruler: some View {
        Canvas { context, size in
            for step in 0...range.upperBound {
                let isMajor = step % majorEvery == 0
                let x = Self.inset + CGFloat(step) * Self.spacing
                let tickHeight: CGFloat = isMajor ? 14 : 8
                let tick = CGRect(x: x - 0.5, y: size.height - tickHeight, width: 1, height: tickHeight)
                context.fill(
                    Path(roundedRect: tick, cornerRadius: 0.5),
                    with: .color(isMajor ? Theme.textTertiary : Theme.textQuaternary.opacity(0.6))
                )
                if isMajor, step >= range.lowerBound {
                    context.draw(
                        Text(label(step))
                            .font(Theme.subFont)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textTertiary),
                        at: CGPoint(x: x, y: 12)
                    )
                }
            }
        }
        .frame(
            width: Self.inset * 2 + CGFloat(range.upperBound) * Self.spacing,
            height: Self.height
        )
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
