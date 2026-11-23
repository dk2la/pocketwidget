import SwiftUI

/// The assistant as a small desk robot: eyes that blink while it waits, a
/// wave while it listens, three dots and a flashing antenna while it
/// thinks.
struct IsoAssistantView: View {
    enum Mode {
        case idle, listening, thinking
    }

    let mode: Mode

    private static let base = IsoBox(x: 0, y: 0, z: 0, w: 120, d: 52, h: 5)
    private static let body = IsoBox(x: 16, y: 8, z: 5, w: 88, d: 34, h: 62)
    private static let mast = IsoBox(x: 58, y: 23, z: 67, w: 4, d: 4, h: 12)
    private static let bulb = IsoBox(x: 55, y: 20, z: 79, w: 10, d: 10, h: 7)
    private static let scene = IsoScene(fitting: [base, body, bulb])

    var body: some View {
        let scene = Self.scene
        IsoTicker(every: 0.3) { phase in
            let bulbOn = mode != .idle && phase % 2 == 0
            IsoStage(scene: scene) {
                IsoBlock(scene: scene, box: Self.base, tone: .plate)
                IsoBlock(scene: scene, box: Self.body)
                grille.isoFace(.side, of: Self.body, in: scene)
                front(phase).isoFace(.front, of: Self.body, in: scene)
                IsoBlock(scene: scene, box: Self.mast, tone: .key)
                IsoBlock(scene: scene, box: Self.bulb, tone: bulbOn ? .lit : .key)
            }
            .animation(.easeInOut(duration: 0.2), value: phase)
        }
    }

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

    private func front(_ phase: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            ZStack {
                shape.fill(Color(white: 0.03))
                face(phase)
            }
            .frame(height: 36)
            .clipShape(shape)
            .overlay(shape.stroke(Color.white.opacity(0.10), lineWidth: 0.6))
            HStack(spacing: 7) {
                IsoLamp("MIC", on: mode == .listening)
                IsoLamp("THINK", on: mode == .thinking)
                Spacer(minLength: 0)
                IsoNameTag("AI")
            }
            .frame(height: 7)
            .padding(.top, 5)
        }
        .padding(7)
    }

    @ViewBuilder
    private func face(_ phase: Int) -> some View {
        let glow = Theme.accent
        switch mode {
        case .idle:
            // A blink every few seconds.
            let closed = phase % 11 == 0
            HStack(spacing: 16) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(glow)
                        .frame(width: 8, height: closed ? 1.6 : 12)
                }
            }
            .shadow(color: glow.opacity(0.7), radius: 2.5)
        case .listening:
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<9, id: \.self) { k in
                    Capsule()
                        .fill(glow)
                        .frame(width: 3, height: 4 + CGFloat((phase * 7 + k * 5) % 6) * 3.4)
                }
            }
            .shadow(color: glow.opacity(0.6), radius: 2)
        case .thinking:
            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { k in
                    let up = phase % 3 == k
                    Circle()
                        .fill(glow.opacity(up ? 1 : 0.35))
                        .frame(width: 6, height: 6)
                        .offset(y: up ? -4 : 0)
                }
            }
            .shadow(color: glow.opacity(0.6), radius: 2)
        }
    }
}
