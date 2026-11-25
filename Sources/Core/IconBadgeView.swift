import SwiftUI

/// Draws an `IconBadge` inside a strip cell, below the glyph. The cell is
/// small, so both badges hug its bottom edge and the glyph moves up to make
/// room (see `IconBadgeView.glyphLift`).
struct IconBadgeView: View {
    let badge: IconBadge

    /// How far the glyph rises while a badge sits under it.
    static let glyphLift: CGFloat = 5

    var body: some View {
        switch badge {
        case .timer(let remaining):
            Text(TimeFormat.mmss(remaining))
                .font(Theme.mono(8, .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(Capsule().fill(Theme.accentWash))
                .padding(.bottom, 2)
                .accessibilityIdentifier("strip.badge.timer")
                .accessibilityLabel(L10n.t(.modTimer) + " " + TimeFormat.mmss(remaining))
        case .musicPlaying:
            LiveBars()
                .padding(.bottom, 5)
                .accessibilityElement()
                .accessibilityIdentifier("strip.badge.music")
                .accessibilityLabel(L10n.t(.modMusic))
        }
    }
}

/// Three tiny equalizer bars that bob while music plays. Reduce Motion
/// keeps them still at staggered heights.
private struct LiveBars: View {
    private let phases: [Double] = [0, 1.9, 3.7]

    var body: some View {
        if Theme.reduceMotion {
            bars(at: nil)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                bars(at: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func bars(at time: Double?) -> some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(phases.indices, id: \.self) { index in
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: 2, height: height(index: index, time: time))
            }
        }
        .frame(height: 6, alignment: .bottom)
    }

    private func height(index: Int, time: Double?) -> CGFloat {
        guard let time else { return [3.5, 6, 4.5][index] }
        let wave = (sin(time * 7 + phases[index]) + 1) / 2
        return 2 + 4 * wave
    }
}
