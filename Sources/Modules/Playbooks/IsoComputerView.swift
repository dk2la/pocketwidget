import SwiftUI

/// The Playbooks device: a desktop computer whose screen fills with
/// windows, one per tick, the way a playbook opens apps; a few keys flash
/// on the keyboard as each one appears. Shown while there is no playbook
/// yet.
struct IsoComputerView: View {
    private static let plate = IsoBox(x: 0, y: 10, z: 0, w: 140, d: 62, h: 4)
    private static let stand = IsoBox(x: 52, y: 18, z: 4, w: 36, d: 20, h: 2)
    private static let neck = IsoBox(x: 66, y: 22, z: 6, w: 8, d: 5, h: 14)
    private static let monitor = IsoBox(x: 18, y: 28, z: 14, w: 104, d: 5, h: 66)
    private static let keyboard = IsoBox(x: 22, y: 46, z: 4, w: 84, d: 18, h: 3)
    private static let mouse = IsoBox(x: 114, y: 50, z: 4, w: 9, d: 13, h: 3)
    private static let scene = IsoScene(fitting: [plate, monitor, keyboard, mouse])

    /// Windows on screen at each tick: a pause with all three, a blank
    /// screen, then one more per tick. Tick 0 is the full screen, which is
    /// what Reduce Motion shows.
    private static let sequence = [3, 3, 3, 3, 0, 1, 2, 3]
    /// The first tick on which a window appears.
    private static let firstOpening = 5
    /// Keys "typed" as each window opens.
    private static let typed: [[Int]] = [[5, 18, 30], [9, 22, 37], [2, 27, 44]]
    private static let keyColumns = 12
    private static let keyRows = 4

    var body: some View {
        let scene = Self.scene
        IsoTicker(every: 0.45) { phase in
            let step = phase % Self.sequence.count
            let shown = Self.sequence[step]
            // The window that appeared on this tick, if any.
            let fresh: Int? = step >= Self.firstOpening ? shown - 1 : nil
            IsoStage(scene: scene) {
                IsoBlocks(scene: scene, blocks: [
                    (Self.plate, .plate), (Self.stand, .body), (Self.neck, .body), (Self.monitor, .body),
                ])
                screen(shown: shown, fresh: fresh)
                    .isoFace(.front, of: Self.monitor, in: scene)
                IsoBlocks(scene: scene, blocks: [(Self.keyboard, .body)])
                keys(lit: fresh.map { Self.typed[$0] } ?? [])
                    .isoFace(.top, of: Self.keyboard, in: scene)
                IsoBlocks(scene: scene, blocks: [(Self.mouse, .key)])
            }
            // Windows pop in from tick to tick, unanimated on purpose:
            // every animated frame redraws the whole panel.
        }
    }

    // MARK: - Screen

    /// Menu bar, the open windows side by side, the dock along the bottom.
    private func screen(shown: Int, fresh: Int?) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color(white: 0.055))
            Rectangle().fill(Color.white.opacity(0.07)).frame(height: 4)
            ForEach(0..<shown, id: \.self) { k in
                window(focused: k == fresh)
                    .frame(width: 28, height: 37)
                    .offset(x: 3 + CGFloat(k) * 31, y: 7)
            }
            dock.offset(x: 30, y: 47)
        }
        .frame(width: 96, height: 54, alignment: .topLeading)
        .clipped()
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// A window with a file in it; the one that just opened has a lit
    /// title bar.
    private func window(focused: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(focused ? Theme.accent : Color.white.opacity(0.14))
                .frame(height: 4)
            file
                .frame(maxWidth: .infinity)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 1.8) {
                ForEach([0.8, 0.6, 0.7] as [CGFloat], id: \.self) { share in
                    Capsule().fill(Color.white.opacity(0.12)).frame(width: 22 * share, height: 1.1)
                }
            }
            .padding(.leading, 3)
            .padding(.top, 5)
            Spacer(minLength: 0)
        }
        .background(Color(white: 0.16))
        .clipShape(RoundedRectangle(cornerRadius: 1.6, style: .continuous))
    }

    private var file: some View {
        VStack(alignment: .leading, spacing: 1.2) {
            ForEach([1, 0.8, 0.55] as [CGFloat], id: \.self) { share in
                Rectangle().fill(Color.black.opacity(0.22)).frame(width: 5.4 * share, height: 0.7)
            }
        }
        .padding(.top, 3.5)
        .frame(width: 8, height: 10, alignment: .top)
        .background(Theme.lightFill, in: RoundedRectangle(cornerRadius: 0.8, style: .continuous))
    }

    private var dock: some View {
        HStack(spacing: 3.6) {
            ForEach([0.91, 0.6, 0.36] as [Double], id: \.self) { white in
                RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                    .fill(Color(white: white))
                    .frame(width: 5, height: 5)
            }
        }
        .frame(width: 36, height: 7)
        .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 2, style: .continuous))
    }

    // MARK: - Keyboard

    private func keys(lit: [Int]) -> some View {
        VStack(spacing: 0.8) {
            ForEach(0..<Self.keyRows, id: \.self) { row in
                HStack(spacing: 0.8) {
                    ForEach(0..<Self.keyColumns, id: \.self) { column in
                        RoundedRectangle(cornerRadius: 0.5)
                            .fill(lit.contains(row * Self.keyColumns + column) ? Theme.accent : Color.white.opacity(0.13))
                    }
                }
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
    }
}
