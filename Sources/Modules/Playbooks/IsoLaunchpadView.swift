import SwiftUI

/// Playbooks as a key pad: one armed key per playbook. While a playbook
/// runs the keys fire in sequence; at rest one of them glints now and then.
struct IsoLaunchpadView: View {
    /// How many playbooks there are.
    let count: Int
    let isRunning: Bool

    private static let plate = IsoBox(x: 0, y: 0, z: 0, w: 150, d: 72, h: 5)
    private static let deck = IsoBox(x: 8, y: 6, z: 5, w: 134, d: 60, h: 9)
    private static let scene = IsoScene(fitting: [plate, deck.lifted(by: 6)])
    private static let columns = 4

    var body: some View {
        let scene = Self.scene
        IsoTicker(every: isRunning ? 0.22 : 1.6) { phase in
            IsoStage(scene: scene) {
                IsoBlocks(scene: scene, blocks: blocks(phase))
                HStack(spacing: 9) {
                    IsoLamp("RUN", on: isRunning)
                    Spacer(minLength: 0)
                    IsoNameTag("PLAYBOOKS")
                }
                .padding(.horizontal, 7)
                .frame(maxHeight: .infinity)
                .isoFace(.front, of: Self.deck, in: scene)
            }
        }
    }

    private func blocks(_ phase: Int) -> [(box: IsoBox, tone: IsoTone)] {
        let armed = min(count, Self.columns * 2)
        let hot = armed > 0 ? phase % armed : -1
        var result: [(box: IsoBox, tone: IsoTone)] = [(Self.plate, .plate), (Self.deck, .body)]
        // Back row first, each row left to right.
        for index in 0..<(Self.columns * 2) {
            let row = index / Self.columns, column = index % Self.columns
            let isHot = index == hot
            let pressed = isHot && isRunning
            let tone: IsoTone = if pressed {
                .lit
            } else if index < armed {
                isHot ? Self.glint : .key
            } else {
                .body
            }
            result.append((
                IsoBox(
                    x: 15 + CGFloat(column) * 31, y: 12 + CGFloat(row) * 27, z: 14,
                    w: 26, d: 21, h: pressed ? 2.5 : 6
                ),
                tone
            ))
        }
        return result
    }

    private static let glint = IsoTone(
        top: Color(white: 0.44),
        front: Color(white: 0.24),
        side: Color(white: 0.17),
        edge: Color.white.opacity(0.28)
    )
}
