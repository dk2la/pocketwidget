import SwiftUI

/// The timer as a small desk clock, drawn with the same kit as the System
/// meters: a plate, a body with a glowing screen — the time left and a dial
/// that drains with it — status lamps, a speaker grille on the side and a
/// bar on top that sits pressed while the countdown runs. Display only;
/// the controls live in the module around it. Screen text is
/// hardware-style English, like the labels on a real device.
struct IsoClockView: View {
    let time: String
    /// Share of the countdown still left, 0...1.
    let fraction: Double
    let isRunning: Bool
    /// The countdown ends at a set clock time.
    var isAlarm = false

    // Scene geometry, in scene units.
    private static let base = IsoBox(x: 0, y: 0, z: 0, w: 150, d: 56, h: 5)
    private static let body = IsoBox(x: 12, y: 8, z: 5, w: 126, d: 36, h: 62)
    private static let bar = IsoBox(x: 46, y: 17, z: 67, w: 58, d: 18, h: 5)
    private static let scene = IsoScene(fitting: [base, body, bar])

    var body: some View {
        let scene = Self.scene
        GeometryReader { proxy in
            let scale = proxy.size.width / scene.size.width
            device(scene)
                .frame(width: scene.size.width, height: scene.size.height, alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
        }
        .aspectRatio(scene.size, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("timer: \(time)")
    }

    private func device(_ scene: IsoScene) -> some View {
        // Pressed in while running, like a latched snooze bar.
        var bar = Self.bar
        bar.h = isRunning ? 2 : 5
        return ZStack(alignment: .topLeading) {
            IsoBlock(scene: scene, box: Self.base, tone: .plate)
            IsoBlock(scene: scene, box: Self.body)
            grille.isoFace(.side, of: Self.body, in: scene)
            front.isoFace(.front, of: Self.body, in: scene)
            IsoBlock(scene: scene, box: bar, tone: .key)
        }
    }

    /// Speaker holes on the right face.
    private var grille: some View {
        VStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { _ in
                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { _ in
                        Circle().fill(Color.black.opacity(0.6)).frame(width: 2.2, height: 2.2)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Front panel

    private var front: some View {
        VStack(alignment: .leading, spacing: 0) {
            screen
                .frame(height: 36)
            HStack(spacing: 9) {
                lamp("RUN", on: isRunning)
                lamp("ALARM", on: isAlarm)
                Spacer(minLength: 0)
                Text("TIMER")
                    .font(Theme.mono(5, .medium))
                    .kerning(0.6)
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            .frame(height: 7)
            .padding(.top, 5)
        }
        .padding(7)
    }

    private var screen: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        let glow = Theme.accent
        return ZStack {
            shape.fill(Color(white: 0.03))
            HStack(alignment: .center, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isRunning ? "focus" : "ready")
                        .font(Theme.mono(6.4))
                        .foregroundStyle(glow.opacity(0.6))
                    Text(time)
                        .font(Theme.mono(19, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(glow)
                        .shadow(color: glow.opacity(0.7), radius: 2.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                Spacer(minLength: 0)
                dial(glow)
                    .frame(width: 24, height: 24)
            }
            .padding(.horizontal, 7)
        }
        .clipShape(shape)
        .overlay(shape.stroke(Color.white.opacity(0.10), lineWidth: 0.6))
    }

    /// What is left as an arc from 12 o'clock, with a hand at its end.
    private func dial(_ glow: Color) -> some View {
        let left = max(0, min(1, fraction))
        return ZStack {
            Circle().stroke(glow.opacity(0.18), lineWidth: 2.4)
            Circle()
                .trim(from: 0, to: left)
                .stroke(glow, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: glow.opacity(0.6), radius: 1.5)
            Capsule().fill(glow)
                .frame(width: 1.2, height: 8)
                .offset(y: -4)
                .rotationEffect(.degrees(360 * left))
            Circle().fill(glow).frame(width: 2.6, height: 2.6)
        }
        .padding(1.2)
    }

    private func lamp(_ label: String, on: Bool) -> some View {
        HStack(spacing: 2.5) {
            Circle()
                .fill(on ? Theme.accent : Color.white.opacity(0.15))
                .frame(width: 4.4, height: 4.4)
                .shadow(color: on ? Theme.accent.opacity(0.8) : .clear, radius: 2)
            Text(label)
                .font(Theme.mono(4.8, .medium))
                .foregroundStyle(Color.white.opacity(on ? 0.7 : 0.4))
                .lineLimit(1)
        }
    }
}
