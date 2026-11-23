import SwiftUI

/// "System" module: CPU and memory as two large readouts with severity
/// bars on the hero card; network, battery and volume as one grouped list.
/// Values jump.
struct MetricsModuleView: View {
    var stats: SystemStatsService
    var power: PowerSourceMonitor
    var audio: AudioSystemMonitor

    /// Whether this view instance currently holds a stats observer. SwiftUI
    /// can fire appear/disappear repeatedly during transitions; the flag
    /// keeps the contribution to the service's count at exactly zero or one.
    @State private var isObservingStats = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HeroCard {
                        HStack(alignment: .top, spacing: 20) {
                            gauge(label: "CPU", fraction: stats.cpuUsage)
                            gauge(label: L10n.t(.sysMemory), fraction: memoryFraction)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: L10n.t(.sysNow))
                        GroupedCard {
                            networkRow
                            powerRow
                            volumeRow
                        }
                    }
                }
            }
            ModuleFootnote(systemName: "eye", text: L10n.t(.sysLiveNote))
        }
        .onAppear {
            guard !isObservingStats else { return }
            isObservingStats = true
            stats.beginObserving()
        }
        .onDisappear {
            guard isObservingStats else { return }
            isObservingStats = false
            stats.endObserving()
        }
    }

    private var memoryFraction: Double {
        stats.memoryTotal > 0 ? Double(stats.memoryUsed) / Double(stats.memoryTotal) : 0
    }

    private func percentText(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    // MARK: - Hero

    /// One half of the hero: caption, large percentage, severity bar.
    private func gauge(label: String, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .heroCaption()
            CountdownText(text: percentText(fraction))
            GlassProgressBar(fraction: fraction, fillColor: Theme.severity(fraction))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Rows

    private var networkRow: some View {
        statRow(
            icon: "arrow.up.arrow.down",
            title: L10n.t(.sysNetwork),
            detail: "↑ \(Self.rate(stats.uploadRate))",
            value: "↓ \(Self.rate(stats.downloadRate))",
            isLast: false
        )
    }

    private var powerRow: some View {
        let charging = L10n.t(.sysCharging)
        return statRow(
            icon: power.isPlugged ? "battery.100.bolt" : "battery.75",
            title: L10n.t(.sysBattery),
            // Stored lower case ("charging"); reads as a sentence here.
            detail: power.isPlugged ? charging.prefix(1).uppercased() + charging.dropFirst() : nil,
            value: "\(power.percent)%",
            isLast: false
        )
    }

    private func statRow(icon: String, title: String, detail: String?, value: String, isLast: Bool) -> some View {
        HStack(spacing: 12) {
            IconTile(systemName: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.bodyFont)
                    .lineLimit(1)
                    .foregroundStyle(Theme.textPrimary)
                if let detail {
                    Text(detail)
                        .font(Theme.subFont)
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer(minLength: 8)
            Text(value)
                .font(Theme.bodyFont)
                .fontWeight(.medium)
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(Theme.textPrimary)
        }
        .groupedRow(isLast: isLast)
    }

    private var volumeRow: some View {
        HStack(spacing: 12) {
            IconTile(systemName: "speaker.wave.2")
            Text(L10n.t(.sysVolume))
                .font(Theme.bodyFont)
                .lineLimit(1)
                .foregroundStyle(Theme.textPrimary)
            Slider(
                value: Binding(
                    get: { audio.volume },
                    set: { audio.setVolume($0) }
                ),
                in: 0...1
            )
            .controlSize(.mini)
            .tint(Theme.segmentOn)
            Text("\(Int(audio.volume * 100))")
                .font(Theme.bodyFont)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 28, alignment: .trailing)
        }
        .groupedRow(isLast: true)
    }

    // MARK: - Formatting

    private static func rate(_ rate: Double) -> String {
        switch rate {
        case ..<1_000: "0 KB/s"
        case ..<1_000_000: String(format: "%.0f KB/s", rate / 1_000)
        case ..<1_000_000_000: String(format: "%.1f MB/s", rate / 1_000_000)
        default: String(format: "%.1f GB/s", rate / 1_000_000_000)
        }
    }
}
