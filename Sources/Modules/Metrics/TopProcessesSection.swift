import AppKit
import SwiftUI

/// "Top processes" under the metric cards: the five heaviest processes by
/// what the large chart shows (CPU or memory; CPU for the other metrics).
/// Read-only — rows do nothing on click.
struct TopProcessesSection: View {
    let loads: [ProcessLoad]
    let gauge: Gauge
    var isDemo = false

    static let count = 5

    private var key: ProcessSortKey { ProcessSortKey(gauge: gauge) }

    private var rows: [ProcessLoad] {
        ProcessLoad.top(isDemo ? Self.demoLoads : loads, by: key, count: Self.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                title: L10n.t(.sysProcessesSection),
                trailing: key == .cpu ? Gauge.cpu.title : Gauge.memory.title
            )
            GroupedCard {
                if rows.isEmpty {
                    Text(L10n.t(.sysProcessesLoading))
                        .font(Theme.subFont)
                        .foregroundStyle(Theme.textTertiary)
                        .groupedRow(isLast: true)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, load in
                        row(load)
                            .groupedRow(isLast: index == rows.count - 1)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("system.processes")
    }

    private func row(_ load: ProcessLoad) -> some View {
        let app = isDemo ? nil : NSRunningApplication(processIdentifier: load.pid)
        let icon = isDemo ? Self.demoIcon(load.pid) : app?.icon
        let primary = key == .cpu ? ProcessLoad.formatCPU(load.cpu) : ProcessLoad.formatMemory(load.resident)
        let secondary = key == .cpu ? ProcessLoad.formatMemory(load.resident) : ProcessLoad.formatCPU(load.cpu)
        return HStack(spacing: 10) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 24, height: 24)
            } else {
                IconTile(systemName: "gearshape", size: 24)
            }
            Text(app?.localizedName ?? load.name)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(secondary)
                .font(Theme.captionFont)
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
            Text(primary)
                .font(Theme.smallValueFont)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .frame(minWidth: 52, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Demo

    /// Fixed list for promo recordings, so the user's real processes never
    /// end up on video.
    private static let demoLoads: [ProcessLoad] = [
        ProcessLoad(pid: 1, name: "Safari", cpu: 0.184, resident: 1_310_720_000),
        ProcessLoad(pid: 2, name: "Xcode", cpu: 0.126, resident: 2_254_438_400),
        ProcessLoad(pid: 3, name: "WindowServer", cpu: 0.093, resident: 524_288_000),
        ProcessLoad(pid: 4, name: "Music", cpu: 0.041, resident: 318_767_104),
        ProcessLoad(pid: 5, name: "Finder", cpu: 0.012, resident: 167_772_160)
    ]

    private static let demoBundles: [Int32: String] = [
        1: "com.apple.Safari", 2: "com.apple.dt.Xcode", 4: "com.apple.Music", 5: "com.apple.finder"
    ]

    private static func demoIcon(_ pid: Int32) -> NSImage? {
        guard let bundle = demoBundles[pid],
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
