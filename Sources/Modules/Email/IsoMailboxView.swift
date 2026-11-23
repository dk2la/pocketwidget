import SwiftUI

/// Mail as a small mailbox: a letter stands in the slot and the flag is up
/// while something is unread; the screen counts it.
struct IsoMailboxView: View {
    let unread: Int

    private static let base = IsoBox(x: 0, y: 0, z: 0, w: 150, d: 56, h: 5)
    private static let body = IsoBox(x: 16, y: 10, z: 5, w: 104, d: 36, h: 52)
    private static let letter = IsoBox(x: 38, y: 26, z: 45, w: 60, d: 3, h: 26)
    private static let mast = IsoBox(x: 128, y: 26, z: 5, w: 3, d: 3, h: 62)
    private static let flag = IsoBox(x: 128, y: 12, z: 54, w: 3, d: 14, h: 11)
    private static let scene = IsoScene(fitting: [base, body, letter.lifted(by: 4), mast])

    var body: some View {
        let scene = Self.scene
        let hasMail = unread > 0
        IsoTicker(every: 1.4) { phase in
            IsoStage(scene: scene) {
                IsoBlock(scene: scene, box: Self.base, tone: .plate)
                // Painted before the body, so the body hides what is inside.
                ZStack(alignment: .topLeading) {
                    IsoBlock(scene: scene, box: Self.letter, tone: .paper)
                    flap.isoFace(.front, of: Self.letter, in: scene)
                }
                .isoShift(z: hasMail ? (phase % 2 == 0 ? 0 : 3) : -18)
                IsoBlock(scene: scene, box: Self.body)
                front.isoFace(.front, of: Self.body, in: scene)
                IsoBlock(scene: scene, box: Self.mast, tone: .key)
                IsoBlock(scene: scene, box: Self.flag, tone: hasMail ? .lit : .key)
                    .isoShift(z: hasMail ? 0 : -40)
            }
            .animation(.snappy(duration: 0.45), value: hasMail)
            // The letter hops, unanimated on purpose: every animated
            // frame redraws the whole panel.
        }
    }

    /// The envelope's flap.
    private var flap: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: proxy.size.width / 2, y: proxy.size.height * 0.42))
                path.addLine(to: CGPoint(x: proxy.size.width, y: 0))
            }
            .stroke(Color.black.opacity(0.35), lineWidth: 0.8)
        }
    }

    private var front: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(unread)")
                    .font(Theme.mono(17, .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Theme.accent)
                    .shadow(color: Theme.accent.opacity(0.7), radius: 2.5)
                Text("new")
                    .font(Theme.mono(6.4))
                    .foregroundStyle(Theme.accent.opacity(0.6))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .frame(height: 26)
            .background(shape.fill(Color(white: 0.03)))
            .overlay(shape.stroke(Color.white.opacity(0.10), lineWidth: 0.6))
            .animation(.snappy(duration: 0.35), value: unread)
            HStack(spacing: 9) {
                IsoLamp("NEW", on: unread > 0)
                Spacer(minLength: 0)
                IsoNameTag("MAIL")
            }
            .frame(height: 7)
            .padding(.top, 5)
        }
        .padding(7)
    }
}
