import SwiftUI

/// "System" module: every parameter is its own little isometric meter
/// (CPU, memory, network, battery, volume) in a two-column grid. Meters
/// with more than one page have a DISPLAY key; the volume meter has − / +.
/// Screen text is hardware-style English, like the labels on a real device;
/// the captions under the meters are localized.
struct MetricsModuleView: View {
    var stats: SystemStatsService
    var power: PowerSourceMonitor
    var audio: AudioSystemMonitor

    /// Whether this view instance currently holds a stats observer. SwiftUI
    /// can fire appear/disappear repeatedly during transitions; the flag
    /// keeps the contribution to the service's count at exactly zero or one.
    @State private var isObservingStats = false
    /// Recent samples for the screens' bar charts, oldest first.
    @State private var cpuHistory: [Double] = []
    @State private var downHistory: [Double] = []
    @State private var upHistory: [Double] = []

    private static let historyLength = 12
    private static let volumeStep = 1.0 / 16

    private let columns = [
        GridItem(.flexible(), spacing: 12, alignment: .top),
        GridItem(.flexible(), spacing: 12, alignment: .top),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    tile(title: "CPU", detail: percentText(stats.cpuUsage)) {
                        IsoMeterView(name: "cpu load", pages: cpuPages)
                    }
                    tile(title: L10n.t(.sysMemory), detail: "\(gigabytes(stats.memoryUsed)) / \(gigabytes(stats.memoryTotal)) GB") {
                        IsoMeterView(name: "memory", pages: memoryPages)
                    }
                    tile(title: L10n.t(.sysNetwork), detail: "↓ \(Self.rateText(stats.downloadRate))") {
                        IsoMeterView(name: "network", pages: networkPages)
                    }
                    tile(title: L10n.t(.sysBattery), detail: batteryDetail) {
                        IsoMeterView(
                            name: "battery",
                            pages: [MeterPage(
                                lamp: "BAT",
                                caption: "charge",
                                value: "\(power.percent)",
                                unit: "%",
                                chart: .level(Double(power.percent) / 100)
                            )],
                            statusLamp: ("AC", power.isPlugged)
                        )
                    }
                    tile(title: L10n.t(.sysVolume), detail: "\(volumePercent)%") {
                        IsoMeterView(
                            name: "output",
                            pages: [MeterPage(
                                lamp: "VOL",
                                caption: audio.currentDeviceName?.lowercased() ?? "output",
                                value: "\(volumePercent)",
                                unit: "%",
                                chart: .level(audio.volume)
                            )],
                            keys: [
                                MeterKey(label: "−") { audio.setVolume(max(0, audio.volume - Self.volumeStep)) },
                                MeterKey(label: "+") { audio.setVolume(min(1, audio.volume + Self.volumeStep)) },
                            ]
                        )
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
        .onChange(of: stats.cpuUsage) { _, value in
            Self.push(value, into: &cpuHistory)
        }
        .onChange(of: stats.downloadRate) { _, value in
            Self.push(value, into: &downHistory)
        }
        .onChange(of: stats.uploadRate) { _, value in
            Self.push(value, into: &upHistory)
        }
    }

    // MARK: - Tiles

    /// A meter with its localized name and a plain readout underneath.
    private func tile<Meter: View>(title: String, detail: String, @ViewBuilder meter: () -> Meter) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            meter()
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.subFont)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(detail)
                    .font(Theme.captionFont)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            .padding(.leading, 4)
        }
    }

    // MARK: - Pages

    private var cpuPages: [MeterPage] {
        let peak = cpuHistory.max() ?? stats.cpuUsage
        return [
            MeterPage(lamp: "NOW", caption: "load now", value: percentNumber(stats.cpuUsage), unit: "%", chart: .bars(cpuHistory)),
            MeterPage(lamp: "PEAK", caption: "peak · last \(Self.historyLength)s", value: percentNumber(peak), unit: "%", chart: .bars(cpuHistory)),
        ]
    }

    private var memoryPages: [MeterPage] {
        let total = stats.memoryTotal
        let used = min(stats.memoryUsed, total)
        let fraction = total > 0 ? Double(used) / Double(total) : 0
        return [
            MeterPage(lamp: "USED", caption: "in use", value: gigabytes(used), unit: "GB", chart: .level(fraction)),
            MeterPage(lamp: "FREE", caption: "available", value: gigabytes(total - used), unit: "GB", chart: .level(1 - fraction)),
        ]
    }

    private var networkPages: [MeterPage] {
        let down = Self.rateParts(stats.downloadRate)
        let up = Self.rateParts(stats.uploadRate)
        return [
            MeterPage(lamp: "DOWN", caption: "download", value: down.value, unit: down.unit, chart: .bars(Self.normalized(downHistory))),
            MeterPage(lamp: "UP", caption: "upload", value: up.value, unit: up.unit, chart: .bars(Self.normalized(upHistory))),
        ]
    }

    private var batteryDetail: String {
        guard power.isPlugged else { return "\(power.percent)%" }
        // Stored lower case ("charging"); reads as a sentence here.
        let charging = L10n.t(.sysCharging)
        return "\(power.percent)% · " + charging.prefix(1).uppercased() + charging.dropFirst()
    }

    private var volumePercent: Int {
        Int((audio.volume * 100).rounded())
    }

    // MARK: - Formatting

    private func percentNumber(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))"
    }

    private func percentText(_ fraction: Double) -> String {
        percentNumber(fraction) + "%"
    }

    private func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f", Double(bytes) / 1_073_741_824)
    }

    private static func rateParts(_ rate: Double) -> (value: String, unit: String) {
        switch rate {
        case ..<1_000: ("0", "KB/s")
        case ..<1_000_000: (String(format: "%.0f", rate / 1_000), "KB/s")
        case ..<1_000_000_000: (String(format: "%.1f", rate / 1_000_000), "MB/s")
        default: (String(format: "%.1f", rate / 1_000_000_000), "GB/s")
        }
    }

    private static func rateText(_ rate: Double) -> String {
        let parts = rateParts(rate)
        return "\(parts.value) \(parts.unit)"
    }

    private static func push(_ value: Double, into history: inout [Double]) {
        history.append(value)
        if history.count > historyLength {
            history.removeFirst(history.count - historyLength)
        }
    }

    /// Scales rates to the busiest recent sample so the bars always read.
    private static func normalized(_ values: [Double]) -> [Double] {
        guard let top = values.max(), top > 0 else { return values.map { _ in 0 } }
        return values.map { $0 / top }
    }
}
