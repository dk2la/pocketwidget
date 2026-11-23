import Charts
import SwiftUI

/// "System" module: a row of small devices on top — one per parameter,
/// swipe or click to bring one into focus — and below, a Grafana-style
/// panel for the focused one: current / average / peak and a live chart
/// of the last two minutes. Screen text on the devices is hardware-style
/// English, like the labels on a real device; everything else is localized.
struct MetricsModuleView: View {
    var stats: SystemStatsService
    var power: PowerSourceMonitor
    var audio: AudioSystemMonitor

    /// Whether this view instance currently holds a stats observer. SwiftUI
    /// can fire appear/disappear repeatedly during transitions; the flag
    /// keeps the contribution to the service's count at exactly zero or one.
    @State private var isObservingStats = false
    @State private var selected: Gauge? = .cpu
    @State private var history: [MetricSample] = []

    /// Sampling step and window of the charts.
    static let step: Double = 2
    static let window = 60

    private var focus: Gauge { selected ?? .cpu }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    carousel
                    picker
                    MetricPanel(
                        gauge: focus,
                        history: history,
                        now: currentSample,
                        audio: audio
                    )
                    // A fresh panel per gauge: the charts cross-fade instead
                    // of morphing one series into another.
                    .id(focus)
                    .transition(.opacity)
                    overview
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

    // MARK: - Devices

    private var carousel: some View {
        GeometryReader { proxy in
            let itemWidth = min(proxy.size.width * 0.62, 260)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(Gauge.allCases) { gauge in
                        IsoMeterView(
                            name: gauge.deviceName,
                            page: page(for: gauge),
                            lamps: lamps(for: gauge),
                            isLit: gauge == focus
                        )
                        .frame(width: itemWidth)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.snappy) { selected = gauge }
                        }
                        .scrollTransition(.interactive) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.82)
                                .opacity(phase.isIdentity ? 1 : 0.45)
                        }
                        .id(gauge)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selected, anchor: .center)
            .safeAreaPadding(.horizontal, (proxy.size.width - itemWidth) / 2)
            .overlay(alignment: .leading) { arrow(-1) }
            .overlay(alignment: .trailing) { arrow(1) }
        }
        .frame(height: 170)
    }

    /// Round chevron at the carousel's edge: steps to the neighbour.
    @ViewBuilder
    private func arrow(_ direction: Int) -> some View {
        let all = Gauge.allCases
        let index = all.firstIndex(of: focus) ?? 0
        let target = index + direction
        if all.indices.contains(target) {
            Button {
                withAnimation(.snappy) { selected = all[target] }
            } label: {
                Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                    .font(Theme.iconSmallFont)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Theme.raisedFill))
                    .overlay(Circle().stroke(Theme.hairlineSoft, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
        }
    }

    /// The same choice as plain labelled chips — the obvious way to switch.
    private var picker: some View {
        HStack(spacing: 6) {
            ForEach(Gauge.allCases) { gauge in
                let isOn = gauge == focus
                Button {
                    withAnimation(.snappy) { selected = gauge }
                } label: {
                    Text(gauge.title)
                        .font(Theme.captionFont)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .foregroundStyle(isOn ? Theme.inkOnAccent : Theme.textSecondary)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(Capsule().fill(isOn ? Theme.lightFill : Theme.cardFill))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Every gauge as a small stat panel with a sparkline.
    private var overview: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 120), spacing: 10)],
            spacing: 10
        ) {
            ForEach(Gauge.allCases) { gauge in
                MetricStatCard(
                    gauge: gauge,
                    history: history,
                    now: currentSample,
                    isSelected: gauge == focus
                ) {
                    withAnimation(.snappy) { selected = gauge }
                }
            }
        }
    }

    // MARK: - Screens

    private func page(for gauge: Gauge) -> MeterPage {
        let recent = history.suffix(12)
        switch gauge {
        case .cpu:
            return MeterPage(
                caption: "load", value: Format.percentNumber(stats.cpuUsage), unit: "%",
                chart: .bars(recent.map(\.cpu))
            )
        case .memory:
            let s = currentSample
            return MeterPage(
                caption: "in use", value: Format.gigabytes(s.memoryUsed), unit: "GB",
                chart: .level(s.memoryTotal > 0 ? s.memoryUsed / s.memoryTotal : 0)
            )
        case .network:
            let parts = Format.rateParts(stats.downloadRate)
            let top = recent.map(\.download).max() ?? 0
            return MeterPage(
                caption: "download", value: parts.value, unit: parts.unit,
                chart: .bars(recent.map { top > 0 ? $0.download / top : 0 })
            )
        case .battery:
            return MeterPage(
                caption: "charge", value: "\(power.percent)", unit: "%",
                chart: .level(Double(power.percent) / 100)
            )
        case .volume:
            return MeterPage(
                caption: audio.currentDeviceName?.lowercased() ?? "output",
                value: "\(Int((audio.volume * 100).rounded()))", unit: "%",
                chart: .level(audio.volume)
            )
        }
    }

    private func lamps(for gauge: Gauge) -> [(label: String, on: Bool)] {
        switch gauge {
        case .battery: [("LIVE", true), ("AC", power.isPlugged)]
        case .volume: [("LIVE", true), ("MUTE", audio.volume == 0)]
        default: [("LIVE", true)]
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

/// The parameters, in carousel order.
enum Gauge: String, CaseIterable, Identifiable {
    case cpu, memory, network, battery, volume

    var id: String { rawValue }

    @MainActor var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: L10n.t(.sysMemory)
        case .network: L10n.t(.sysNetwork)
        case .battery: L10n.t(.sysBattery)
        case .volume: L10n.t(.sysVolume)
        }
    }

    /// The tag printed on the device itself.
    var deviceName: String {
        switch self {
        case .cpu: "cpu load"
        case .memory: "memory"
        case .network: "network"
        case .battery: "battery"
        case .volume: "output"
        }
    }

    /// Series color, from the Grafana palette.
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
    static func percentNumber(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))"
    }

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
