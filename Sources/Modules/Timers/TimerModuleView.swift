import SwiftUI

/// "Timer" module. With nothing going it is the empty screen: the ready
/// message with the picked length, over Start. A countdown or an alarm —
/// running or paused partway — shows a hero card instead, with the time
/// left, a bar that drains with it, Pause / Start and Reset.
/// Under either sit the same two blocks: the length — a dial to drag and a
/// row of usual lengths — and an alarm that counts down to a clock time.
struct TimerModuleView: View {
    var timer: TimerService

    /// The alarm block's clock time; only hour and minute are used.
    @State private var alarmTime = Date().addingTimeInterval(30 * 60)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 18) {
                hero.emptyScreen(when: timer.isIdle) {
                    // The sublabel is the picked length: a custom one shows
                    // nowhere else once its field is cleared.
                    ModuleEmptyScreen(
                        label: L10n.t(.focusReady),
                        sublabel: TimeFormat.mmss(timer.remaining)
                    ) {
                        ModuleButton(label: L10n.t(.timerStart), systemName: "play.fill", kind: .accent) {
                            timer.start()
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(
                        title: L10n.t(.timerLength),
                        trailing: L10n.f(.ageMin, Int(timer.duration / 60))
                    )
                    lengthPicker
                }
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: L10n.t(.timerRingAt))
                    alarmBlock
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
                if timer.isAlarm {
                    Image(systemName: "alarm")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                } else {
                    StatusDot(color: timer.isRunning ? Theme.accent : Theme.segmentOff)
                }
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
                // An alarm has no round length to count from.
                if isPartway, !timer.isAlarm {
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

    /// Pick a clock time; Set starts a countdown that ends exactly then.
    private var alarmBlock: some View {
        GroupedCard {
            HStack(spacing: 12) {
                IconTile(systemName: "alarm")
                DatePicker("", selection: $alarmTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .fixedSize()
                Spacer(minLength: 0)
                ModuleButton(label: L10n.t(.timerSet), kind: .light) {
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
                    timer.ring(atHour: parts.hour ?? 0, minute: parts.minute ?? 0)
                }
            }
            .groupedRow(isLast: true)
        }
    }

    // MARK: - Length

    /// The dial for any length, over the usual ones as one-click cells.
    /// Locked while the timer runs — the length belongs to the countdown
    /// already going.
    private var lengthPicker: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.groupRadius, style: .continuous)
        return VStack(spacing: 4) {
            LengthDial(minutes: Int(timer.duration / 60)) { minutes in
                timer.setDuration(TimeInterval(minutes * 60))
            }
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
        }
        .padding(4)
        .background(Theme.cardFill, in: shape)
        .overlay(shape.stroke(Theme.hairlineSoft, lineWidth: 1))
        .opacity(timer.isRunning ? 0.35 : 1)
        .disabled(timer.isRunning)
    }
}

/// A ruler of minutes under a fixed pointer: drag it sideways to set the
/// length. It snaps to whole minutes and ticks under the finger on each one.
private struct LengthDial: View {
    /// The length now set, in minutes.
    var minutes: Int
    var onChange: (Int) -> Void

    static let range = 1...180
    private static let spacing: CGFloat = 9
    /// Room for the labels of the first and last tick.
    private static let inset: CGFloat = 16
    private static let height: CGFloat = 48

    /// Where the ruler sits while it is dragged, in fractional minutes.
    @State private var dragPosition: Double?
    @State private var dragStart: Double?

    var body: some View {
        let position = dragPosition ?? Double(minutes)
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
            .onChanged { value in
                let start = dragStart ?? Double(minutes)
                dragStart = start
                let moved = start - Double(value.translation.width / Self.spacing)
                let position = min(max(moved, Double(Self.range.lowerBound)), Double(Self.range.upperBound))
                dragPosition = position
                let snapped = Int(position.rounded())
                if snapped != minutes {
                    onChange(snapped)
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
            }
            .onEnded { _ in
                dragStart = nil
                withAnimation(.snappy(duration: 0.2)) { dragPosition = nil }
            }
    }

    /// Every minute as a tick, every fifth one taller and numbered. Drawn
    /// once at full length and slid under the pointer.
    private var ruler: some View {
        Canvas { context, size in
            for minute in 0...Self.range.upperBound {
                let isMajor = minute % 5 == 0
                let x = Self.inset + CGFloat(minute) * Self.spacing
                let tickHeight: CGFloat = isMajor ? 14 : 8
                let tick = CGRect(x: x - 0.5, y: size.height - tickHeight, width: 1, height: tickHeight)
                context.fill(
                    Path(roundedRect: tick, cornerRadius: 0.5),
                    with: .color(isMajor ? Theme.textTertiary : Theme.textQuaternary.opacity(0.6))
                )
                if isMajor, minute > 0 {
                    context.draw(
                        Text("\(minute)")
                            .font(Theme.subFont)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textTertiary),
                        at: CGPoint(x: x, y: 12)
                    )
                }
            }
        }
        .frame(
            width: Self.inset * 2 + CGFloat(Self.range.upperBound) * Self.spacing,
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
