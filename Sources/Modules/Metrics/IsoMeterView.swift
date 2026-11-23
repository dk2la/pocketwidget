import SwiftUI

/// What a meter's screen shows on one page.
struct MeterPage: Equatable {
    /// Lamp tag under the screen (DAY · WEEK in the original) — short caps.
    var lamp: String
    /// Small line at the top of the screen.
    var caption: String
    /// The big rolling register.
    var value: String
    var unit: String
    var chart: MeterChart = .none
}

/// The little graphic at the right of a meter's screen.
enum MeterChart: Equatable {
    case none
    /// Recent samples, 0...1, oldest first.
    case bars([Double])
    /// One filled band, 0...1 (memory, battery).
    case level(Double)
}

/// A key on the meter's terminal cover.
struct MeterKey {
    var label: String
    var action: () -> Void
}

/// One System parameter as a small isometric device, after the isokit
/// "Smart Meter" on 21st.dev: a wall plate, a body with a glowing screen
/// and a rolling register, page lamps, and rubber keys on the cover.
/// With several pages and no custom keys, a DISPLAY key cycles them.
struct IsoMeterView: View {
    let name: String
    let pages: [MeterPage]
    /// Custom keys replace the DISPLAY key (volume − / +).
    var keys: [MeterKey] = []
    /// Extra lamp shown when there is one page (CHARGING, LIVE).
    var statusLamp: (label: String, on: Bool)?

    @State private var pageIndex = 0

    // Scene geometry, in scene units.
    private static let base = IsoBox(x: 0, y: 0, z: 0, w: 150, d: 112, h: 6)
    private static let body = IsoBox(x: 16, y: 8, z: 6, w: 118, d: 44, h: 84)
    private static let cover = IsoBox(x: 24, y: 52, z: 6, w: 102, d: 20, h: 14)
    private static let scene = IsoScene(fitting: [base, body])

    private static func keyBoxes(count: Int) -> [IsoBox] {
        let y: CGFloat = 55, z = cover.topZ, d: CGFloat = 12, h: CGFloat = 4
        if count <= 1 {
            return [IsoBox(x: 62, y: y, z: z, w: 56, d: d, h: h)]
        }
        let gap: CGFloat = 8, inset: CGFloat = 10
        let w = (cover.w - 2 * inset - gap * CGFloat(count - 1)) / CGFloat(count)
        return (0..<count).map { k in
            IsoBox(x: cover.x + inset + CGFloat(k) * (w + gap), y: y, z: z, w: w, d: d, h: h)
        }
    }

    private var page: MeterPage {
        pages[min(pageIndex, pages.count - 1)]
    }

    private var effectiveKeys: [MeterKey] {
        if !keys.isEmpty { return keys }
        guard pages.count > 1 else { return [] }
        return [MeterKey(label: "DISPLAY") {
            withAnimation(.snappy(duration: 0.35)) {
                pageIndex = (pageIndex + 1) % pages.count
            }
        }]
    }

    var body: some View {
        let scene = Self.scene
        GeometryReader { proxy in
            let scale = proxy.size.width / scene.size.width
            device(scene)
                .frame(width: scene.size.width, height: scene.size.height, alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
        }
        .aspectRatio(scene.size, contentMode: .fit)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name): \(page.value) \(page.unit)")
    }

    // MARK: - Device

    @ViewBuilder
    private func device(_ scene: IsoScene) -> some View {
        let keys = effectiveKeys
        let keyBoxes = keys.isEmpty ? [] : Self.keyBoxes(count: keys.count)
        ZStack(alignment: .topLeading) {
            IsoBlock(scene: scene, box: Self.base, tone: .plate)
            screws.isoFace(.top, of: Self.base, in: scene)
            IsoBlock(scene: scene, box: Self.body)
            vents.isoFace(.top, of: Self.body, in: scene)
            nameplate.isoFace(.side, of: Self.body, in: scene)
            front.isoFace(.front, of: Self.body, in: scene)
            IsoBlock(scene: scene, box: Self.cover)
            coverFront.isoFace(.front, of: Self.cover, in: scene)
            ForEach(Array(zip(keys.indices, keyBoxes)), id: \.0) { index, box in
                Button(action: keys[index].action) {
                    EmptyView()
                }
                .buttonStyle(IsoKeyStyle(scene: scene, box: box, label: keys[index].label))
            }
        }
    }

    /// Four screw heads in the plate's corners.
    private var screws: some View {
        let b = Self.base
        return ZStack(alignment: .topLeading) {
            ForEach(Array([(7.0, 7.0), (b.w - 7, 7.0), (7.0, b.d - 7), (b.w - 7, b.d - 7)].enumerated()), id: \.0) { _, p in
                Circle().fill(Color.white.opacity(0.18))
                    .frame(width: 3.2, height: 3.2)
                    .offset(x: p.0 - 1.6, y: p.1 - 1.6)
            }
        }
    }

    private var vents: some View {
        HStack(spacing: 7) {
            ForEach(0..<6, id: \.self) { _ in
                Capsule().fill(Color.black.opacity(0.55)).frame(width: 2, height: 9)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 9)
    }

    /// Barcode label on the right face.
    private var nameplate: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 1.2) {
                ForEach(0..<14, id: \.self) { k in
                    Rectangle().fill(Color.white.opacity(0.35))
                        .frame(width: k % 3 == 0 ? 1.6 : 0.8, height: 9)
                }
            }
            Rectangle().fill(Color.white.opacity(0.25)).frame(width: 18, height: 0.8)
        }
        .padding(4)
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.white.opacity(0.22), lineWidth: 0.6))
        .padding(.leading, 10)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Front panel

    private var front: some View {
        VStack(alignment: .leading, spacing: 0) {
            screen
                .frame(height: 44)
            lamps
                .padding(.top, 6)
            Text(name.uppercased())
                .font(Theme.mono(4.6, .medium))
                .kerning(0.6)
                .foregroundStyle(Color.white.opacity(0.45))
                .lineLimit(1)
                .padding(.top, 5)
        }
        .padding(8)
    }

    private var screen: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        return ZStack(alignment: .topLeading) {
            shape.fill(Color(white: 0.03))
            HStack(alignment: .bottom, spacing: 4) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(page.caption)
                        .font(Theme.mono(6))
                        .foregroundStyle(Theme.accent.opacity(0.55))
                        .lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(page.value)
                            .font(Theme.mono(16, .semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(Theme.accent)
                            .shadow(color: Theme.accent.opacity(0.7), radius: 2.5)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(page.unit)
                            .font(Theme.mono(5.6))
                            .foregroundStyle(Theme.accent.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                chart
                    .frame(width: 30, height: 18)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .animation(.snappy(duration: 0.35), value: page.value)
        }
        .clipShape(shape)
        .overlay(shape.stroke(Color.white.opacity(0.10), lineWidth: 0.6))
    }

    @ViewBuilder
    private var chart: some View {
        switch page.chart {
        case .none:
            EmptyView()
        case let .bars(values):
            HStack(alignment: .bottom, spacing: 0.9) {
                ForEach(Array(values.suffix(12).enumerated()), id: \.0) { _, v in
                    RoundedRectangle(cornerRadius: 0.4)
                        .fill(Theme.accent.opacity(0.85))
                        .frame(height: max(1, CGFloat(min(1, v)) * 18))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .shadow(color: Theme.accent.opacity(0.5), radius: 1.5)
        case let .level(fraction):
            VStack {
                Spacer(minLength: 0)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1).fill(Theme.accent.opacity(0.18))
                        RoundedRectangle(cornerRadius: 1).fill(Theme.accent)
                            .frame(width: proxy.size.width * CGFloat(max(0, min(1, fraction))))
                            .shadow(color: Theme.accent.opacity(0.6), radius: 1.5)
                    }
                }
                .frame(height: 5)
            }
        }
    }

    private var lamps: some View {
        HStack(spacing: 9) {
            if pages.count > 1 {
                ForEach(Array(pages.enumerated()), id: \.0) { index, p in
                    lamp(p.lamp, on: index == pageIndex)
                }
            } else if let statusLamp {
                lamp(statusLamp.label, on: statusLamp.on)
            }
        }
        .frame(height: 6)
    }

    private func lamp(_ label: String, on: Bool) -> some View {
        HStack(spacing: 2.5) {
            Circle()
                .fill(on ? Theme.accent : Color.white.opacity(0.15))
                .frame(width: 4.2, height: 4.2)
                .shadow(color: on ? Theme.accent.opacity(0.8) : .clear, radius: 2)
            Text(label)
                .font(Theme.mono(4.4, .medium))
                .foregroundStyle(Color.white.opacity(on ? 0.7 : 0.4))
                .lineLimit(1)
        }
    }

    /// Two screw slots on the terminal cover.
    private var coverFront: some View {
        HStack {
            screwSlot
            Spacer()
            screwSlot
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var screwSlot: some View {
        Circle().fill(Color.black.opacity(0.5))
            .frame(width: 5, height: 5)
            .overlay(Rectangle().fill(Color.white.opacity(0.25)).frame(width: 3, height: 0.6))
    }
}

/// A rubber key on the cover: sinks while held.
private struct IsoKeyStyle: ButtonStyle {
    let scene: IsoScene
    let box: IsoBox
    let label: String

    func makeBody(configuration: Configuration) -> some View {
        let shown = configuration.isPressed ? box.lifted(by: -2.5) : box
        ZStack(alignment: .topLeading) {
            IsoBlock(scene: scene, box: shown, tone: .key)
            Text(label)
                .font(Theme.mono(label.count > 2 ? 4.6 : 7, .semibold))
                .kerning(label.count > 2 ? 0.5 : 0)
                .foregroundStyle(Color.white.opacity(0.75))
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .isoFace(.top, of: shown, in: scene)
        }
        .animation(.easeOut(duration: configuration.isPressed ? 0.05 : 0.14), value: configuration.isPressed)
    }
}
