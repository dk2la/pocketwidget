import SwiftUI

/// The shelf as a small empty bookcase, drawn with the same kit as the
/// System meters. It stands on the module's empty screen only: once files
/// are parked they are a list, not books. Display only.
struct IsoShelfView: View {
    /// Files are being dragged over the module.
    var isTargeted = false

    // Case geometry, in scene units.
    private static let width: CGFloat = 170
    private static let depth: CGFloat = 46
    private static let wall: CGFloat = 96
    private static let board: CGFloat = 5

    private static let bottom = IsoBox(x: 0, y: 0, z: 0, w: width, d: depth, h: board)
    private static let back = IsoBox(x: 0, y: 0, z: board, w: width, d: 3, h: wall)
    private static let left = IsoBox(x: 0, y: 3, z: board, w: 4, d: depth - 3, h: wall)
    private static let right = IsoBox(x: width - 4, y: 3, z: board, w: 4, d: depth - 3, h: wall)
    private static let top = IsoBox(x: 0, y: 0, z: board + wall, w: width, d: depth, h: 4)
    private static let scene = IsoScene(fitting: [bottom, back, left, right, top])

    var body: some View {
        let scene = Self.scene
        GeometryReader { proxy in
            let scale = proxy.size.width / scene.size.width
            bookcase(scene)
                .frame(width: scene.size.width, height: scene.size.height, alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
        }
        .aspectRatio(scene.size, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func bookcase(_ scene: IsoScene) -> some View {
        var wood = IsoTone.plate
        if isTargeted { wood.edge = Theme.accent.opacity(0.7) }
        // Painted back to front.
        return ZStack(alignment: .topLeading) {
            IsoBlock(scene: scene, box: Self.bottom, tone: wood)
            IsoBlock(scene: scene, box: Self.back, tone: wood)
            IsoBlock(scene: scene, box: Self.left, tone: wood)
            IsoBlock(scene: scene, box: Self.right, tone: wood)
            IsoBlock(scene: scene, box: Self.top, tone: wood)
        }
    }
}
