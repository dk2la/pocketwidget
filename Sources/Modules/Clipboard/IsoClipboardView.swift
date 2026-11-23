import SwiftUI

/// The clipboard as, well, a clipboard: a sheet per copied thing (up to
/// four), under a metal clip. A new copy drops onto the stack.
struct IsoClipboardView: View {
    let count: Int
    /// Identity of the newest entry — a change drops a fresh sheet.
    let latestID: UUID?

    private static let board = IsoBox(x: 0, y: 0, z: 0, w: 112, d: 84, h: 4)
    private static let maxSheets = 4
    private static let scene = IsoScene(fitting: [
        board, IsoBox(x: 36, y: 3, z: 4, w: 40, d: 14, h: CGFloat(maxSheets) * 2 + 6),
    ])

    private static func sheet(_ index: Int) -> IsoBox {
        IsoBox(x: 9, y: 14, z: 4 + CGFloat(index) * 2, w: 94, d: 62, h: 2)
    }

    var body: some View {
        let scene = Self.scene
        let sheets = min(max(count, 0), Self.maxSheets)
        let clip = IsoBox(x: 36, y: 3, z: 4 + CGFloat(sheets) * 2, w: 40, d: 14, h: 6)
        IsoStage(scene: scene) {
            IsoBlock(scene: scene, box: Self.board)
            ForEach(0..<max(sheets - 1, 0), id: \.self) { index in
                IsoBlock(scene: scene, box: Self.sheet(index), tone: .paper)
            }
            if sheets > 0 {
                let top = Self.sheet(sheets - 1)
                ZStack(alignment: .topLeading) {
                    IsoBlock(scene: scene, box: top, tone: .paper)
                    lines.isoFace(.top, of: top, in: scene)
                }
                .id(latestID)
                .transition(.asymmetric(
                    insertion: .offset(y: -26).combined(with: .opacity),
                    removal: .opacity
                ))
            }
            IsoBlock(scene: scene, box: clip, tone: .key)
        }
        .animation(Theme.reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.7), value: latestID)
    }

    /// A few lines of writing on the top sheet.
    private var lines: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach([0.82, 0.64, 0.74, 0.40], id: \.self) { share in
                GeometryReader { proxy in
                    Capsule().fill(Color.black.opacity(0.32))
                        .frame(width: proxy.size.width * share)
                }
                .frame(height: 2.4)
            }
        }
        .padding(.horizontal, 9)
        .padding(.top, 20)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
