import SwiftUI

/// The cloth color of one parked file, from its name — stable between
/// launches. It marks the file's row in the list.
struct ShelfBook {
    let red: Double, green: Double, blue: Double

    /// Index into the cloth palette.
    let cloth: Int

    /// `avoiding` is the cloth of the row above: neighbours never share a
    /// color.
    init(url: URL, avoiding neighbour: Int? = nil) {
        var index = Self.stableHash(url.lastPathComponent) / 7 % Self.cloths.count
        if index == neighbour { index = (index + 3) % Self.cloths.count }
        cloth = index
        (red, green, blue) = Self.cloths[index]
    }

    var color: Color { Color(red: red, green: green, blue: blue) }

    private static let cloths: [(Double, Double, Double)] = [
        (0.80, 0.31, 0.28), // red
        (0.90, 0.62, 0.22), // amber
        (0.33, 0.62, 0.42), // green
        (0.30, 0.50, 0.85), // blue
        (0.56, 0.42, 0.80), // violet
        (0.25, 0.62, 0.66), // teal
        (0.84, 0.79, 0.67), // cream
    ]

    /// The colors of a shelf in order, keyed by item.
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

    /// `hashValue` is seeded per launch; rows must keep their color.
    private static func stableHash(_ text: String) -> Int {
        text.unicodeScalars.reduce(5381) { ($0 &* 33 &+ Int($1.value)) & 0xFFFFFF }
    }
}
