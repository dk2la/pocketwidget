import SwiftUI

/// "System" module: one large card on top with the chart of the selected
/// metric (current / average / peak over the last two minutes), and below
/// it, under a "Metrics" heading, a card with a small chart for each metric.
/// Clicking a card selects it; the choice is remembered.
struct MetricsModuleView: View {
    var stats: SystemStatsService
    var power: PowerSourceMonitor
    var audio: AudioSystemMonitor
    var settings: AppSettings

    /// Whether this view instance currently holds a stats observer. SwiftUI
    /// can fire appear/disappear repeatedly during transitions; the flag
    /// keeps the contribution to the service's count at exactly zero or one.
    @State private var isObservingStats = false
    /// Starts empty on every open: nothing is sampled in the background.
    @State private var history: [MetricSample] = []

    /// Sampling step and window of the charts.
    static let step: Double = 2
    static let window = 60

    private var focus: Gauge { settings.systemMetric }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        MetricPanel(
                            gauge: focus,
                            history: history,
                            now: currentSample,
                            audio: audio,
                            chartHeight: MetricGrid.chartHeight(available: proxy.size.height)
                        )
                        // A fresh panel per gauge: the charts cross-fade
                        // instead of morphing one series into another.
                        .id(focus)
                        .transition(.opacity)
                        cards(width: proxy.size.width)
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
        .task {
            // One clock for every series, so the charts line up.
            while !Task.isCancelled {
                record()
                try? await Task.sleep(for: .seconds(Self.step))
            }
        }
    }

    // MARK: - Cards

    /// Every metric as a card with a small chart, in rows that share the
    /// width evenly.
    private func cards(width: CGFloat) -> some View {
        let all = Gauge.allCases
        let rows = MetricGrid.rows(width: width, count: all.count)
        let starts = rows.indices.map { rows[..<$0].reduce(0, +) }
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: L10n.t(.sysMetricsSection))
            VStack(spacing: MetricGrid.spacing) {
                ForEach(rows.indices, id: \.self) { row in
                    HStack(spacing: MetricGrid.spacing) {
                        ForEach(all[starts[row]..<starts[row] + rows[row]]) { gauge in
                            MetricStatCard(
                                gauge: gauge,
                                history: history,
                                now: currentSample,
                                isSelected: gauge == focus
                            ) {
                                withAnimation(.snappy) { settings.systemMetric = gauge }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sampling

    private var currentSample: MetricSample {
        MetricSample(
            cpu: stats.cpuUsage,
            memoryUsed: Double(min(stats.memoryUsed, stats.memoryTotal)) / 1_073_741_824,
            memoryTotal: Double(stats.memoryTotal) / 1_073_741_824,
            download: stats.downloadRate,
            upload: stats.uploadRate,
            battery: Double(power.percent),
            volume: audio.volume
        )
    }

    private func record() {
        history.append(currentSample)
        if history.count > Self.window {
            history.removeFirst(history.count - Self.window)
        }
    }
}

// MARK: - Model

extension Gauge {
    @MainActor var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: L10n.t(.sysMemory)
        case .network: L10n.t(.sysNetwork)
        case .battery: L10n.t(.sysBattery)
        case .volume: L10n.t(.sysVolume)
        }
    }

    /// Series color.
    var color: Color {
        switch self {
        case .cpu: Theme.accent
        case .memory: Color(red: 0.34, green: 0.58, blue: 0.95) // #5794F2
        case .network: Theme.accent
        case .battery: Color(red: 0.98, green: 0.87, blue: 0.16) // #FADE2A
        case .volume: Color(red: 0.72, green: 0.47, blue: 0.85) // #B877D9
        }
    }
}

/// One tick of every series.
struct MetricSample {
    var cpu: Double
    var memoryUsed: Double
    var memoryTotal: Double
    var download: Double
    var upload: Double
    var battery: Double
    var volume: Double
}

enum Format {
    static func gigabytes(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    static func rateParts(_ rate: Double) -> (value: String, unit: String) {
        switch rate {
        case ..<1_000: ("0", "KB/s")
        case ..<1_000_000: (String(format: "%.0f", rate / 1_000), "KB/s")
        case ..<1_000_000_000: (String(format: "%.1f", rate / 1_000_000), "MB/s")
        default: (String(format: "%.1f", rate / 1_000_000_000), "GB/s")
        }
    }

    static func rate(_ rate: Double) -> String {
        let parts = rateParts(rate)
        return "\(parts.value) \(parts.unit)"
    }
}
