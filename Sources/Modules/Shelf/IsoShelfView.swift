import SwiftUI

/// How one parked file looks as a book: cloth color and height from its
/// name, thickness from its size — stable between launches.
struct ShelfBook {
    let red: Double, green: Double, blue: Double
    let height: CGFloat
    let thickness: CGFloat

    /// Index into the cloth palette.
    let cloth: Int

    /// `avoiding` is the cloth of the book to the left: neighbours never
    /// share a color.
    init(url: URL, avoiding neighbour: Int? = nil) {
        var index = Self.stableHash(url.lastPathComponent) / 7 % Self.cloths.count
        if index == neighbour { index = (index + 3) % Self.cloths.count }
        cloth = index
        (red, green, blue) = Self.cloths[index]
        height = 60 + CGFloat(Self.stableHash(url.lastPathComponent) % 6) * 4.5
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        // 11 units for a note, 18 for anything past ~10 MB.
        thickness = 11 + CGFloat(min(7, max(0, log10(Double(max(bytes, 1))) - 3) * 1.75))
    }

    var color: Color { shade(1) }

    func shade(_ k: Double) -> Color {
        Color(red: min(1, red * k), green: min(1, green * k), blue: min(1, blue * k))
    }

    /// Cloth on the spine and the cover, paper on top.
    var tone: IsoTone {
        IsoTone(
            top: Color(red: 0.86, green: 0.83, blue: 0.76),
            front: shade(1),
            side: shade(0.62),
            edge: Color.black.opacity(0.35)
        )
    }

    private static let cloths: [(Double, Double, Double)] = [
        (0.80, 0.31, 0.28), // red
        (0.90, 0.62, 0.22), // amber
        (0.33, 0.62, 0.42), // green
        (0.30, 0.50, 0.85), // blue
        (0.56, 0.42, 0.80), // violet
        (0.25, 0.62, 0.66), // teal
        (0.84, 0.79, 0.67), // cream
    ]

    /// The books of a shelf in order, keyed by item.
    static func row(for items: [ShelfStore.Item]) -> [UUID: ShelfBook] {
        var books: [UUID: ShelfBook] = [:]
        var previous: Int?
        for item in items {
            let book = ShelfBook(url: item.url, avoiding: previous)
            books[item.id] = book
            previous = book.cloth
        }
        return books
    }

    /// `hashValue` is seeded per launch; books must keep their look.
    private static func stableHash(_ text: String) -> Int {
        text.unicodeScalars.reduce(5381) { ($0 &* 33 &+ Int($1.value)) & 0xFFFFFF }
    }
}

/// The shelf as a small bookcase, drawn with the same kit as the System
/// meters: every parked file is a book. Clicking a book slides it out
/// toward the viewer; the module shows that file underneath. A long row of
/// books makes the case wider and it scrolls sideways.
struct IsoShelfView: View {
    let items: [ShelfStore.Item]
    /// From `ShelfBook.row(for:)`.
    let books: [UUID: ShelfBook]
    let selectedID: UUID?
    /// Files are being dragged over the module.
    var isTargeted = false
    let onSelect: (ShelfStore.Item) -> Void

    /// Points per scene unit.
    private static let scale: CGFloat = 1.0
    // Case geometry, in scene units.
    private static let depth: CGFloat = 46
    private static let wall: CGFloat = 96
    private static let board: CGFloat = 5
    private static let bookDepth: CGFloat = 34
    private static let pull: CGFloat = 16

    private struct Placed: Identifiable {
        let item: ShelfStore.Item
        let book: ShelfBook
        let box: IsoBox
        var id: UUID { item.id }
    }

    var body: some View {
        let placed = place()
        let width = max(170, (placed.last.map { $0.box.x + $0.box.w } ?? 0) + 10)
        let parts = caseBoxes(width: width)
        let reach = IsoBox(x: 8, y: 6 + Self.pull, z: Self.board, w: width - 16, d: Self.bookDepth, h: 10)
        let scene = IsoScene(fitting: parts.all + [reach])
        let size = CGSize(width: scene.size.width * Self.scale, height: scene.size.height * Self.scale)
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                bookcase(scene, parts: parts, placed: placed)
                    .frame(width: scene.size.width, height: scene.size.height, alignment: .topLeading)
                    .scaleEffect(Self.scale, anchor: .topLeading)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .frame(minWidth: proxy.size.width)
            }
        }
        .frame(height: size.height)
    }

    // MARK: - Scene

    private struct CaseBoxes {
        let bottom: IsoBox, back: IsoBox, left: IsoBox, right: IsoBox, top: IsoBox
        var all: [IsoBox] { [bottom, back, left, right, top] }
    }

    private func caseBoxes(width: CGFloat) -> CaseBoxes {
        let d = Self.depth, h = Self.wall, b = Self.board
        return CaseBoxes(
            bottom: IsoBox(x: 0, y: 0, z: 0, w: width, d: d, h: b),
            back: IsoBox(x: 0, y: 0, z: b, w: width, d: 3, h: h),
            left: IsoBox(x: 0, y: 3, z: b, w: 4, d: d - 3, h: h),
            right: IsoBox(x: width - 4, y: 3, z: b, w: 4, d: d - 3, h: h),
            top: IsoBox(x: 0, y: 0, z: b + h, w: width, d: d, h: 4)
        )
    }

    /// Books stand left to right, spines flush with each other.
    private func place() -> [Placed] {
        var x: CGFloat = 7
        return items.map { item in
            let book = books[item.id] ?? ShelfBook(url: item.url)
            let box = IsoBox(x: x, y: 6, z: Self.board, w: book.thickness, d: Self.bookDepth, h: book.height)
            x += book.thickness + 0.6
            return Placed(item: item, book: book, box: box)
        }
    }

    private func bookcase(_ scene: IsoScene, parts: CaseBoxes, placed: [Placed]) -> some View {
        var wood = IsoTone.plate
        if isTargeted { wood.edge = Theme.accent.opacity(0.7) }
        // Screen offset of a book slid out toward the viewer.
        let out = Iso.project(0, Self.pull, 0)
        // Painted back to front; the books run left to right so each one
        // covers the cover of its left neighbour.
        return ZStack(alignment: .topLeading) {
            IsoBlock(scene: scene, box: parts.bottom, tone: wood)
            IsoBlock(scene: scene, box: parts.back, tone: wood)
            IsoBlock(scene: scene, box: parts.left, tone: wood)
            ForEach(placed) { p in
                let isOut = p.item.id == selectedID
                ZStack(alignment: .topLeading) {
                    IsoBlock(scene: scene, box: p.box, tone: p.book.tone)
                    spine(p.book)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(p.item) }
                        .isoFace(.front, of: p.box, in: scene)
                }
                .offset(x: isOut ? out.x : 0, y: isOut ? out.y : 0)
                .zIndex(isOut ? 1 : 0)
                .animation(Theme.reduceMotion ? nil : .snappy(duration: 0.3), value: isOut)
            }
            IsoBlock(scene: scene, box: parts.right, tone: wood)
            IsoBlock(scene: scene, box: parts.top, tone: wood)
        }
    }

    /// Two bands and a title label, like a cloth binding.
    private func spine(_ book: ShelfBook) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.white.opacity(0.35)).frame(height: 1.2)
                .padding(.top, 6)
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.white.opacity(0.75))
                .frame(height: 13)
                .padding(.horizontal, 2.4)
                .padding(.top, 6)
            Spacer(minLength: 0)
            Rectangle().fill(Color.white.opacity(0.35)).frame(height: 1.2)
                .padding(.bottom, 6)
        }
    }
}
