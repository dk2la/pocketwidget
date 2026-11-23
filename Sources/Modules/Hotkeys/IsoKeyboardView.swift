import SwiftUI

/// Hotkeys as a small keyboard that keeps playing chords: a modifier and
/// a letter go down together, light up, and come back.
struct IsoKeyboardView: View {
    private static let board = IsoBox(x: 0, y: 0, z: 0, w: 160, d: 62, h: 6)
    private static let scene = IsoScene(fitting: [board.lifted(by: 4)])
    private static let columns = 11

    /// Every key, back row first, each row left to right.
    private static let keys: [IsoBox] = {
        var keys: [IsoBox] = []
        for row in 0..<3 {
            for column in 0..<columns {
                keys.append(IsoBox(
                    x: 8 + CGFloat(column) * 13.2, y: 5 + CGFloat(row) * 13, z: 6,
                    w: 11.2, d: 11, h: 4
                ))
            }
        }
        var x: CGFloat = 8
        for width in [18, 18, 62, 18, 18] as [CGFloat] {
            keys.append(IsoBox(x: x, y: 44, z: 6, w: width, d: 11, h: 4))
            x += width + 2.5
        }
        return keys
    }()

    var body: some View {
        let scene = Self.scene
        IsoTicker(every: 0.45) { phase in
            IsoStage(scene: scene) {
                IsoBlocks(scene: scene, blocks: blocks(phase))
            }
        }
    }

    private func blocks(_ phase: Int) -> [(box: IsoBox, tone: IsoTone)] {
        // Down on even steps, up on odd ones; a new chord each time.
        let chord = phase / 2
        let isDown = phase % 2 == 0 && !Theme.reduceMotion
        let letter = (chord * 7) % (Self.columns * 3)
        let modifier = Self.columns * 3 + [0, 1, 3][chord % 3]
        var result: [(box: IsoBox, tone: IsoTone)] = [(Self.board, .body)]
        for (index, key) in Self.keys.enumerated() {
            var box = key
            let pressed = isDown && (index == letter || index == modifier)
            if pressed { box.h = 1.5 }
            result.append((box, pressed ? .lit : .key))
        }
        return result
    }
}
