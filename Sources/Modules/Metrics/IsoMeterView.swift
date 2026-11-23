import SwiftUI

/// What a meter's screen shows.
struct MeterPage: Equatable {
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

/// One System parameter as a small device, after the isokit "Smart Meter"
/// on 21st.dev: a wall plate, a body with a glowing screen and a rolling
/// register, status lamps, and a terminal cover. Display only — choosing
/// and reading happens in the module around it.
struct IsoMeterView: View {
    let name: String
    let page: MeterPage
    /// Status lamps under the screen (LIVE, AC).
    var lamps: [(label: String, on: Bool)] = []
    /// Dimmed when it is not the meter in focus.
    var isLit = true

    // Scene geometry, in scene units.
    private static let base = IsoBox(x: 0, y: 0, z: 0, w: 150, d: 66, h: 6)
    private static let body = IsoBox(x: 14, y: 8, z: 6, w: 122, d: 38, h: 88)
    private static let cover = IsoBox(x: 22, y: 46, z: 6, w: 106, d: 14, h: 12)
    private static let scene = IsoScene(fitting: [base, body, cover])

    var body: some View {
        let scene = Self.scene
        GeometryReader { proxy in
            let scale = proxy.size.width / scene.size.width
            device(scene)
                .frame(width: scene.size.width, height: scene.size.height, alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
        }
        .aspectRatio(scene.size, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(page.value) \(page.unit)")
    }

    // MARK: - Device

    private func device(_ scene: IsoScene) -> some View {
        ZStack(alignment: .topLeading) {
            IsoBlock(scene: scene, box: Self.base, tone: .plate)
            screws.isoFace(.top, of: Self.base, in: scene)
            IsoBlock(scene: scene, box: Self.body)
            vents.isoFace(.top, of: Self.body, in: scene)
            nameplate.isoFace(.side, of: Self.body, in: scene)
            front.isoFace(.front, of: Self.body, in: scene)
            IsoBlock(scene: scene, box: Self.cover)
            coverFront.isoFace(.front, of: Self.cover, in: scene)
        }
    }

    /// Four screw heads in the plate's corners.
    private var screws: some View {
        let b = Self.base
        let points: [CGPoint] = [
            CGPoint(x: 7, y: 7), CGPoint(x: b.w - 7, y: 7),
            CGPoint(x: 7, y: b.d - 7), CGPoint(x: b.w - 7, y: b.d - 7),
        ]
        return ZStack(alignment: .topLeading) {
            ForEach(points.indices, id: \.self) { k in
                Circle().fill(Color.white.opacity(0.18))
                    .frame(width: 3.2, height: 3.2)
                    .offset(x: points[k].x - 1.6, y: points[k].y - 1.6)
            }
        }
    }

    private var vents: some View {
        HStack(spacing: 7) {
            ForEach(0..<8, id: \.self) { _ in
                Capsule().fill(Color.black.opacity(0.55)).frame(width: 2, height: 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Barcode label on the right face.
    private var nameplate: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 1.2) {
                ForEach(0..<10, id: \.self) { k in
                    Rectangle().fill(Color.white.opacity(0.35))
                        .frame(width: k % 3 == 0 ? 1.6 : 0.8, height: 9)
                }
            }
            Rectangle().fill(Color.white.opacity(0.25)).frame(width: 14, height: 0.8)
        }
        .padding(3)
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.white.opacity(0.22), lineWidth: 0.6))
        .padding(.leading, 6)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Front panel

    private var front: some View {
        VStack(alignment: .leading, spacing: 0) {
            screen
                .frame(height: 50)
            HStack(spacing: 9) {
                ForEach(lamps.indices, id: \.self) { k in
                    lamp(lamps[k].label, on: lamps[k].on)
                }
                Spacer(minLength: 0)
                Text(name.uppercased())
                    .font(Theme.mono(5, .medium))
                    .kerning(0.6)
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(1)
            }
            .frame(height: 7)
            .padding(.top, 7)
        }
        .padding(8)
    }

    private var screen: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        let glow = isLit ? Theme.accent : Theme.accent.opacity(0.45)
        return ZStack(alignment: .topLeading) {
            shape.fill(Color(white: 0.03))
            HStack(alignment: .bottom, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(page.caption)
                        .font(Theme.mono(6.4))
                        .foregroundStyle(glow.opacity(0.6))
                        .lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(page.value)
                            .font(Theme.mono(20, .semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(glow)
                            .shadow(color: glow.opacity(isLit ? 0.7 : 0), radius: 2.5)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(page.unit)
                            .font(Theme.mono(6.6))
                            .foregroundStyle(glow.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                chart(glow)
                    .frame(width: 34, height: 22)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 7)
        }
        .clipShape(shape)
        .overlay(shape.stroke(Color.white.opacity(0.10), lineWidth: 0.6))
    }

    @ViewBuilder
    private func chart(_ glow: Color) -> some View {
        switch page.chart {
        case .none:
            EmptyView()
        case let .bars(values):
            HStack(alignment: .bottom, spacing: 0.9) {
                ForEach(Array(values.suffix(12).enumerated()), id: \.0) { _, v in
                    RoundedRectangle(cornerRadius: 0.4)
                        .fill(glow.opacity(0.85))
                        .frame(height: max(1, CGFloat(min(1, v)) * 22))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .shadow(color: glow.opacity(isLit ? 0.5 : 0), radius: 1.5)
        case let .level(fraction):
            VStack {
                Spacer(minLength: 0)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1).fill(glow.opacity(0.18))
                        RoundedRectangle(cornerRadius: 1).fill(glow)
                            .frame(width: proxy.size.width * CGFloat(max(0, min(1, fraction))))
                            .shadow(color: glow.opacity(isLit ? 0.6 : 0), radius: 1.5)
                    }
                }
                .frame(height: 6)
            }
        }
    }

    private func lamp(_ label: String, on: Bool) -> some View {
        HStack(spacing: 2.5) {
            Circle()
                .fill(on ? Theme.accent : Color.white.opacity(0.15))
                .frame(width: 4.4, height: 4.4)
                .shadow(color: on ? Theme.accent.opacity(0.8) : .clear, radius: 2)
            Text(label)
                .font(Theme.mono(4.8, .medium))
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
        .frame(maxHeight: .infinity)
    }

    private var screwSlot: some View {
        Circle().fill(Color.black.opacity(0.5))
            .frame(width: 5, height: 5)
            .overlay(Rectangle().fill(Color.white.opacity(0.25)).frame(width: 3, height: 0.6))
    }
}
