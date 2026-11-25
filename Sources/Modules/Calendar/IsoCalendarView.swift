import SwiftUI

/// The calendar as a desk tear-off block: the page of `date` with the
/// month, the day and the weekday, a dot per event. The page flips in when
/// the module opens and when the date moves to another day.
struct IsoCalendarView: View {
    let date: Date
    /// Events on that day.
    let events: Int

    @State private var isShown = false

    private static let base = IsoBox(x: 0, y: 0, z: 0, w: 120, d: 50, h: 5)
    private static let block = IsoBox(x: 14, y: 10, z: 5, w: 92, d: 30, h: 70)
    private static let rings = [
        IsoBox(x: 34, y: 8, z: 75, w: 6, d: 34, h: 4),
        IsoBox(x: 80, y: 8, z: 75, w: 6, d: 34, h: 4),
    ]
    private static let scene = IsoScene(fitting: [base, block] + rings)

    var body: some View {
        let scene = Self.scene
        let day = Calendar.current.component(.day, from: date)
        IsoStage(scene: scene) {
            IsoBlock(scene: scene, box: Self.base, tone: .plate)
            IsoBlock(scene: scene, box: Self.block)
            page(day: day)
                .scaleEffect(y: isShown ? 1 : 0.06, anchor: .top)
                .opacity(isShown ? 1 : 0)
                .isoFace(.front, of: Self.block, in: scene)
            ForEach(Self.rings.indices, id: \.self) { k in
                IsoBlock(scene: scene, box: Self.rings[k], tone: .key)
            }
        }
        .onAppear { flip() }
        // The whole date, not the day number: the 28th of another month is
        // another page.
        .onChange(of: Calendar.current.startOfDay(for: date)) { flip() }
    }

    private func flip() {
        guard !Theme.reduceMotion else {
            isShown = true
            return
        }
        isShown = false
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.15)) {
            isShown = true
        }
    }

    private func page(day: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        return VStack(spacing: 0) {
            Text(Self.month.string(from: date).uppercased())
                .font(Theme.mono(6.4, .semibold))
                .kerning(0.8)
                .foregroundStyle(Theme.lightFill)
                .frame(maxWidth: .infinity)
                .frame(height: 13)
                .background(Theme.inkOnAccent)
            Text("\(day)")
                .font(.system(size: 28, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.inkOnAccent)
                .padding(.top, 1)
            Text(Self.weekday.string(from: date).uppercased())
                .font(Theme.mono(5.6, .medium))
                .kerning(0.6)
                .foregroundStyle(Theme.inkOnAccent.opacity(0.6))
            HStack(spacing: 2.5) {
                ForEach(0..<min(events, 6), id: \.self) { _ in
                    Circle().fill(Theme.inkOnAccent.opacity(0.75)).frame(width: 3, height: 3)
                }
            }
            .frame(height: 3)
            .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .background(Theme.lightFill)
        .clipShape(shape)
        .padding(6)
    }

    private static let month = DateFormatter(template: "MMMM")
    private static let weekday = DateFormatter(template: "EEEE")
}
