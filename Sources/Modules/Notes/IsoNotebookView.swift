import SwiftUI

/// Notes as a notebook with a pencil at work: a written line per note (up
/// to four) and the next one being written. The pencil hurries while a
/// note is being dictated.
struct IsoNotebookView: View {
    let count: Int
    let isRecording: Bool

    private static let cover = IsoBox(x: 0, y: 0, z: 0, w: 104, d: 76, h: 7)
    private static let pages = IsoBox(x: 4, y: 4, z: 7, w: 96, d: 68, h: 3)
    private static let scene = IsoScene(fitting: [cover, pages.lifted(by: 5)])
    private static let steps = 8
    private static let lineGap: CGFloat = 10
    private static let firstLine: CGFloat = 13

    var body: some View {
        let scene = Self.scene
        let written = min(max(count, 0), 4)
        IsoTicker(every: isRecording ? 0.22 : 0.55) { phase in
            let progress = CGFloat(phase % Self.steps) / CGFloat(Self.steps - 1)
            let pencil = IsoBox(
                x: 14, y: 4 + Self.firstLine + CGFloat(written) * Self.lineGap - 1,
                z: 10, w: 26, d: 4, h: 4
            )
            IsoStage(scene: scene) {
                IsoBlock(scene: scene, box: Self.cover)
                IsoBlock(scene: scene, box: Self.pages, tone: .paper)
                page(written: written, progress: progress)
                    .isoFace(.top, of: Self.pages, in: scene)
                IsoBlock(scene: scene, box: pencil, tone: isRecording ? .lit : .pencil)
                    .isoShift(x: progress * 50)
            }
            .animation(.linear(duration: isRecording ? 0.22 : 0.55), value: phase)
        }
    }

    /// Spiral holes down the left edge, finished lines, and the one under
    /// the pencil.
    private func page(written: Int, progress: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 5) {
                ForEach(0..<8, id: \.self) { _ in
                    Circle().fill(Color.black.opacity(0.45)).frame(width: 2.6, height: 2.6)
                }
            }
            .padding(.leading, 3)
            .frame(maxHeight: .infinity)
            ForEach(0...written, id: \.self) { k in
                let share: CGFloat = k < written ? [0.92, 0.70, 0.84, 0.58][k] : progress * 0.66
                Capsule().fill(Color.black.opacity(0.34))
                    .frame(width: max(0, 76 * share), height: 2.2)
                    .offset(x: 12, y: Self.firstLine + CGFloat(k) * Self.lineGap)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
