import SwiftUI

// Shared pieces of the small devices the modules show: the stage
// that scales a scene to its width, a one-canvas painter for many boxes,
// a slow clock for idle motion, lamps, and a few extra tones.

/// Lays a scene out in its own units and scales it to the width it gets.
struct IsoStage<Content: View>: View {
    let scene: IsoScene
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / scene.size.width
            ZStack(alignment: .topLeading) {
                content
            }
            .frame(width: scene.size.width, height: scene.size.height, alignment: .topLeading)
            .scaleEffect(scale, anchor: .topLeading)
        }
        .aspectRatio(scene.size, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Paints a list of boxes in one canvas, in the order given (back to
/// front). For devices with many parts — a keyboard, a key pad.
struct IsoBlocks: View {
    let scene: IsoScene
    let blocks: [(box: IsoBox, tone: IsoTone)]

    var body: some View {
        Canvas { context, _ in
            for block in blocks {
                let tone = block.tone
                for (face, fill) in [(IsoFace.top, tone.top), (.front, tone.front), (.side, tone.side)] {
                    let p = scene.path(face, of: block.box)
                    context.fill(p, with: .color(fill))
                    context.stroke(p, with: .color(tone.edge), lineWidth: 0.6)
                }
            }
        }
        .frame(width: scene.size.width, height: scene.size.height)
        .allowsHitTesting(false)
    }
}

/// A slow clock for idle motion: hands the content a step counter that
/// advances every `every` seconds, only while the view is on screen. With
/// Reduce Motion on the device simply stands still.
struct IsoTicker<Content: View>: View {
    let every: Double
    @ViewBuilder let content: (Int) -> Content

    var body: some View {
        if Theme.reduceMotion {
            content(0)
        } else {
            TimelineView(.periodic(from: .now, by: every)) { context in
                content(Int(context.date.timeIntervalSinceReferenceDate / every))
            }
        }
    }
}

/// Status lamp with a tiny hardware label.
struct IsoLamp: View {
    let label: String
    let on: Bool

    init(_ label: String, on: Bool) {
        self.label = label
        self.on = on
    }

    var body: some View {
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
}

/// The name printed on a device's front.
struct IsoNameTag: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Theme.mono(5, .medium))
            .kerning(0.6)
            .foregroundStyle(Color.white.opacity(0.45))
            .lineLimit(1)
    }
}

extension IsoTone {
    static let paper = IsoTone(
        top: Color(red: 0.90, green: 0.88, blue: 0.82),
        front: Color(red: 0.76, green: 0.74, blue: 0.68),
        side: Color(red: 0.60, green: 0.58, blue: 0.53),
        edge: Color.black.opacity(0.30)
    )
    /// A lit part in the app's acid green.
    static let lit = IsoTone(
        top: Theme.accent,
        front: Color(red: 0.18, green: 0.74, blue: 0),
        side: Color(red: 0.13, green: 0.54, blue: 0),
        edge: Color.black.opacity(0.35)
    )
    static let pencil = IsoTone(
        top: Color(red: 0.96, green: 0.72, blue: 0.26),
        front: Color(red: 0.82, green: 0.58, blue: 0.18),
        side: Color(red: 0.62, green: 0.42, blue: 0.12),
        edge: Color.black.opacity(0.35)
    )
}

extension View {
    /// Moves a part by a vector in scene units — the animatable way to
    /// shift something a canvas has already painted.
    func isoShift(x: CGFloat = 0, y: CGFloat = 0, z: CGFloat = 0) -> some View {
        let p = Iso.project(x, y, z)
        return offset(x: p.x, y: p.y)
    }

    /// Where a module's device sits: one slot of the same size in every
    /// module. The device is fitted into it — a tall one by height, a flat
    /// one by width — so they all carry about the same weight. With
    /// `shrinks` the slot gives height back when the panel is too short
    /// for it, and the device scales down instead of pushing its
    /// neighbours out (the empty screen uses this).
    func moduleScene(shrinks: Bool = false) -> some View {
        frame(maxWidth: 200, maxHeight: 104)
            .frame(maxWidth: .infinity)
            .frame(minHeight: shrinks ? 0 : 112, maxHeight: 112)
            .padding(.top, 4)
    }
}
