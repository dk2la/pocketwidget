import SwiftUI

/// The Playbooks device: a key pad with one armed key per playbook. Shown
/// while there is no playbook yet, so every key is blank. While a playbook
/// runs the armed keys fire in sequence.
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
        let firing = armed > 0 ? phase % armed : -1
        var result: [(box: IsoBox, tone: IsoTone)] = [(Self.plate, .plate), (Self.deck, .body)]
        // Back row first, each row left to right.
        for index in 0..<(Self.columns * 2) {
            let pressed = isRunning && index == firing
            let tone: IsoTone = if pressed {
                .lit
            } else if index < armed {
                .key
            } else {
                .body
            }
            result.append((Self.key(index, pressed: pressed), tone))
        }
        return result
    }

    private static func key(_ index: Int, pressed: Bool) -> IsoBox {
        let row = index / columns, column = index % columns
        return IsoBox(
            x: 15 + CGFloat(column) * 31, y: 12 + CGFloat(row) * 27, z: 14,
            w: 26, d: 21, h: pressed ? 2.5 : 6
        )
    }
}
