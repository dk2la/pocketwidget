import Charts
import SwiftUI

/// The Grafana-style panel under the devices: the focused parameter's
/// current value, average and peak, and an area chart of the last two
/// minutes with a dashed average line. Volume adds a slider.
struct MetricPanel: View {
    let gauge: Gauge
    let history: [MetricSample]
    let now: MetricSample
    var audio: AudioSystemMonitor

    /// One line on the chart.
    private struct Series: Identifiable {
        let name: String
        let color: Color
        let values: [Double]
        var id: String { name }
    }

    private struct Point: Identifiable {
        let t: Double
        let v: Double
        var id: Double { t }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 14) {
            header
            stats
            chart
                .frame(height: 150)
            if gauge == .volume {
                volumeControl
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardFill, in: shape)
        .overlay(shape.stroke(Theme.hairlineSoft, lineWidth: 1))
    }

    // MARK: - Header and stats

    private var header: some View {
        HStack(spacing: 8) {
            StatusDot(color: gauge.color, size: 7)
            Text(gauge.title)
                .font(Theme.headlineFont)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            Text(L10n.t(.sysLastMinutes))
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var stats: some View {
        let primary = series.first?.values ?? []
        let current = value(of: now)
        let average = primary.isEmpty ? current : primary.reduce(0, +) / Double(primary.count)
        // A falling battery is the worry, so it shows the lowest point.
        let extreme = gauge == .battery ? (primary.min() ?? current) : (primary.max() ?? current)
        return HStack(alignment: .top, spacing: 0) {
            stat(L10n.t(.sysNow), format(current), large: true)
            stat(L10n.t(.sysAverage), format(average))
            stat(L10n.t(gauge == .battery ? .sysLowest : .sysPeak), format(extreme))
        }
    }

    private func stat(_ label: String, _ value: String, large: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
            Text(value)
                .font(large ? Theme.heroFont : Theme.headlineFont)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(large ? gauge.color : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.3), value: value)
    }

    // MARK: - Chart

    private var chart: some View {
        let all = series
        let step = MetricsModuleView.step
        let span = Double(MetricsModuleView.window - 1) * step
        return Chart {
            ForEach(all) { s in
                ForEach(points(s.values)) { p in
                    AreaMark(
                        x: .value("Time", p.t),
                        yStart: .value("Base", 0),
                        yEnd: .value(s.name, p.v),
                        series: .value("Series", s.name)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [s.color.opacity(0.35), s.color.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("Time", p.t),
                        y: .value(s.name, p.v),
                        series: .value("Series", s.name)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(s.color)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            }
            if let first = all.first, !first.values.isEmpty {
                RuleMark(y: .value("Average", first.values.reduce(0, +) / Double(first.values.count)))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: -span...0)
        .chartYScale(domain: 0...yTop)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: [-span, -span / 2, 0]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(Color.white.opacity(0.12))
                AxisValueLabel(anchor: value.index == 2 ? .topTrailing : (value.index == 0 ? .topLeading : .top)) {
                    if let t = value.as(Double.self) {
                        Text(t == 0 ? L10n.t(.sysNow).lowercased() : "−\(Int((-t / 60).rounded()))m")
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(Color.white.opacity(0.12))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(axisLabel(v))
                            .font(Theme.captionFont)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if all.count > 1 { legend(all) }
        }
    }

    private func legend(_ all: [Series]) -> some View {
        HStack(spacing: 10) {
            ForEach(all) { s in
                HStack(spacing: 4) {
                    Capsule().fill(s.color).frame(width: 10, height: 3)
                    Text(s.name)
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.4)))
    }

    private func points(_ values: [Double]) -> [Point] {
        let step = MetricsModuleView.step
        let last = values.count - 1
        return values.enumerated().map { index, v in
            Point(t: Double(index - last) * step, v: v)
        }
    }

    // MARK: - Volume

    private var volumeControl: some View {
        HStack(spacing: 10) {
            Button {
                audio.setVolume(audio.volume > 0 ? 0 : 0.5)
            } label: {
                Image(systemName: audio.volume > 0 ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(Theme.iconSmallFont)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Theme.raisedFill))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            ScrubberBar(fraction: audio.volume, fillColor: gauge.color) { target in
                audio.setVolume(target)
            }
            Text("\(Int((audio.volume * 100).rounded()))%")
                .font(Theme.subFont)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    // MARK: - Per-gauge data

    private var series: [Series] {
        gauge.series(history).map { Series(name: $0.name, color: $0.color, values: $0.values) }
    }

    private func value(of s: MetricSample) -> Double {
        gauge.value(of: s)
    }

    private var yTop: Double {
        gauge.chartTop(history: history, now: now)
    }

    private func format(_ v: Double) -> String {
        gauge.format(v)
    }

    private func axisLabel(_ v: Double) -> String {
        switch gauge {
        case .cpu, .battery, .volume: "\(Int(v))"
        case .memory: "\(Int(v.rounded()))G"
        case .network: Format.rate(v).replacingOccurrences(of: "/s", with: "")
        }
    }
}

// MARK: - Gauge data

extension Gauge {
    /// The chart lines of a gauge, first one primary.
    @MainActor
    func series(_ history: [MetricSample]) -> [(name: String, color: Color, values: [Double])] {
        switch self {
        case .cpu:
            [("CPU", color, history.map { $0.cpu * 100 })]
        case .memory:
            [(L10n.t(.sysMemory), color, history.map(\.memoryUsed))]
        case .network:
            [
                (L10n.t(.sysDownload), color, history.map(\.download)),
                (L10n.t(.sysUpload), Theme.selection, history.map(\.upload)),
            ]
        case .battery:
            [(L10n.t(.sysBattery), color, history.map(\.battery))]
        case .volume:
            [(L10n.t(.sysVolume), color, history.map { $0.volume * 100 })]
        }
    }

    /// The plotted value of a sample (first series).
    func value(of s: MetricSample) -> Double {
        switch self {
        case .cpu: s.cpu * 100
        case .memory: s.memoryUsed
        case .network: s.download
        case .battery: s.battery
        case .volume: s.volume * 100
        }
    }

    func chartTop(history: [MetricSample], now: MetricSample) -> Double {
        switch self {
        case .cpu, .battery, .volume:
            return 100
        case .memory:
            return max(now.memoryTotal, 1)
        case .network:
            let top = history.map { max($0.download, $0.upload) }.max() ?? 0
            return max(top * 1.2, 100_000)
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .cpu, .battery, .volume: "\(Int(v.rounded()))%"
        case .memory: "\(Format.gigabytes(v)) GB"
        case .network: Format.rate(v)
        }
    }
}

/// A small Grafana stat panel: name, current value and a sparkline.
/// Clicking it brings that gauge into focus.
struct MetricStatCard: View {
    let gauge: Gauge
    let history: [MetricSample]
    let now: MetricSample
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        let values = history.map { gauge.value(of: $0) }
        let top = gauge.chartTop(history: history, now: now)
        // Newest sample on the right edge, like the big chart.
        let shift = MetricsModuleView.window - values.count
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    StatusDot(color: gauge.color, size: 5)
                    Text(gauge.title)
                        .font(Theme.captionFont)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Text(gauge.format(gauge.value(of: now)))
                    .font(Theme.headlineFont)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Chart {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, v in
                        AreaMark(x: .value("t", index + shift), yStart: .value("b", 0), yEnd: .value("v", v))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [gauge.color.opacity(0.3), gauge.color.opacity(0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        LineMark(x: .value("t", index + shift), y: .value("v", v))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(gauge.color)
                            .lineStyle(StrokeStyle(lineWidth: 1.2))
                    }
                }
                .chartXScale(domain: 0...max(MetricsModuleView.window - 1, 1))
                .chartYScale(domain: 0...top)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .frame(height: 30)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardFill, in: shape)
            .overlay(shape.stroke(isSelected ? gauge.color.opacity(0.6) : Theme.hairlineSoft, lineWidth: 1))
            .contentShape(shape)
            .animation(.snappy(duration: 0.3), value: gauge.format(gauge.value(of: now)))
        }
        .buttonStyle(PressableStyle())
    }
}
