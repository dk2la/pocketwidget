import SwiftUI

/// Press feedback: subtle scale + dim, 120ms ease-out.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            // Asymmetric on purpose: the press lands near-instantly ("heard
            // you"), the release settles a touch softer.
            .animation(
                .easeOut(duration: configuration.isPressed ? 0.06 : 0.16),
                value: configuration.isPressed
            )
    }
}

/// Instrument caption: mono uppercase with tracking (CPU · MEM · REC).
struct InstrumentLabel: View {
    let text: String
    var color: Color = Theme.textQuaternary

    init(_ text: String, color: Color = Theme.textQuaternary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.labelFont)
            .kerning(1.2)
            .foregroundStyle(color)
    }
}

/// Blinking indicator dot — the only permitted "animation of data":
/// hardware-style 2s pulse.
struct BlinkingDot: View {
    var color: Color = Theme.accent
    var size: CGFloat = 6
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(dimmed ? 0.2 : 1)
            // Value-scoped, not withAnimation-in-onAppear: re-created view
            // identities would stack forever-animations and double the pulse.
            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: dimmed)
            .onAppear { dimmed = true }
    }
}

/// Discrete segmented meter — reads better peripherally than a smooth bar.
/// Values jump; no animation by design.
struct SegmentBar: View {
    let fraction: Double
    var segments = 10
    var height: CGFloat = 3
    /// nil → severity coloring (white → amber → red).
    var fillColor: Color?

    var body: some View {
        let filled = Int((max(0, min(1, fraction)) * Double(segments)).rounded())
        let color = fillColor ?? Theme.severity(fraction)
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { index in
                Rectangle()
                    .fill(index < filled ? color : Theme.segmentOff)
                    .frame(height: height)
            }
        }
    }
}

/// 1px separator line.
struct Hairline: View {
    var color: Color = Theme.hairlineSoft

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 1)
    }
}

/// Quiet empty state: centered label + optional subline, no chrome. (The
/// shelf's drop tile draws its own dashed border — that one is a real drop
/// target, not an empty state.)
struct EmptyStateZone: View {
    let label: String
    var sublabel: String?

    var body: some View {
        VStack(spacing: 6) {
            // The strings are stored lower case ("no notes"); the label reads
            // as a sentence.
            Text(label.prefix(1).uppercased() + label.dropFirst())
                .font(Theme.headlineFont)
                .foregroundStyle(Theme.textSecondary)
            if let sublabel {
                Text(sublabel)
                    .font(Theme.subFont)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Themed shell for any capsule surface — the three treatments of the capsule.
/// Glass is the V3 dark-glass recipe (system blur + black tint); Glow tints
/// its ring with the artwork's average color.
struct InstrumentShell<S: Shape>: View {
    let shape: S
    let theme: CapsuleTheme
    var accent: Color?

    var body: some View {
        switch theme {
        case .stealth:
            shape.fill(Theme.capsuleFill)
        case .glass:
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(Theme.glassTintDark))
        case .glow:
            let ring = accent ?? Theme.textQuaternary
            shape.fill(Theme.capsuleFill)
                .overlay(shape.stroke(ring.opacity(0.9), lineWidth: 1).blur(radius: 2.5))
                .overlay(shape.stroke(ring.opacity(0.7), lineWidth: 1))
        }
    }
}
