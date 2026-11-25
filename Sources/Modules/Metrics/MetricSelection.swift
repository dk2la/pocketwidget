import Foundation

/// The metrics of the System module, in the order of their cards.
enum Gauge: String, CaseIterable, Identifiable {
    case cpu, memory, network, battery, volume

    var id: String { rawValue }
}

/// Which metric the large chart shows. CPU on first open; afterwards the
/// last one chosen.
enum MetricSelection {
    static let key = "settings.systemMetric"
    static let initial: Gauge = .cpu

    static func load(from defaults: UserDefaults) -> Gauge {
        defaults.string(forKey: key).flatMap(Gauge.init(rawValue:)) ?? initial
    }

    static func save(_ gauge: Gauge, to defaults: UserDefaults) {
        defaults.set(gauge.rawValue, forKey: key)
    }
}

/// Layout of the System module: how the small cards share the width, and
/// how tall the large chart is.
enum MetricGrid {
    /// A card never gets narrower than this; narrower panels use fewer
    /// cards per row.
    static let minCardWidth: CGFloat = 128
    static let spacing: CGFloat = 10

    /// Cards per row, top to bottom. As many rows as the width demands,
    /// with the cards shared evenly between them, so five cards break into
    /// 3 + 2 and never 4 + 1. Every row is stretched to the full width.
    static func rows(width: CGFloat, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let fit = Int(((width + spacing) / (minCardWidth + spacing)).rounded(.down))
        let columns = min(max(fit, 1), count)
        let rowCount = (count + columns - 1) / columns
        let perRow = (count + rowCount - 1) / rowCount
        return (0..<rowCount).map { row in
            min(perRow, count - row * perRow)
        }
    }

    static let chartHeightRange: ClosedRange<CGFloat> = 120...200

    /// Height of the large chart for the height the module has: it grows
    /// with a tall panel and stays readable in a short one.
    static func chartHeight(available: CGFloat) -> CGFloat {
        min(max(available * 0.4, chartHeightRange.lowerBound), chartHeightRange.upperBound)
    }
}
