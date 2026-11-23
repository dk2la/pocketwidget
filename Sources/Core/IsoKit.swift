import SwiftUI

/// A tiny isometric drawing kit for the System module's devices, after the
/// isokit illustrations on 21st.dev. A scene is drawn in its own units: x
/// runs right-down, y left-down, z up. Boxes are painted back to front by
/// the caller; flat content is pinned onto a box's faces with `isoFace`.
enum Iso {
    static let cos30: CGFloat = 0.8660254
    static let sin30: CGFloat = 0.5

    /// Screen point of a scene point, before the scene's own offset.
    static func project(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGPoint {
        CGPoint(x: (x - y) * cos30, y: (x + y) * sin30 - z)
    }
}

/// One axis-aligned block in scene units.
struct IsoBox: Equatable {
    var x: CGFloat, y: CGFloat, z: CGFloat
    var w: CGFloat, d: CGFloat, h: CGFloat

    func lifted(by dz: CGFloat) -> IsoBox {
        IsoBox(x: x, y: y, z: z + dz, w: w, d: d, h: h)
    }

    var topZ: CGFloat { z + h }
}

/// The scene's frame: everything is drawn relative to `origin`, the screen
/// point of (0, 0, 0), inside a canvas of `size`.
struct IsoScene {
    let size: CGSize
    let origin: CGPoint

    /// Fits a set of boxes snugly.
    init(fitting boxes: [IsoBox]) {
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for b in boxes {
            for (x, y, z) in [
                (b.x, b.y, b.z), (b.x + b.w, b.y, b.z), (b.x, b.y + b.d, b.z), (b.x + b.w, b.y + b.d, b.z),
                (b.x, b.y, b.topZ), (b.x + b.w, b.y, b.topZ), (b.x, b.y + b.d, b.topZ), (b.x + b.w, b.y + b.d, b.topZ),
            ] {
                let p = Iso.project(x, y, z)
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
        }
        size = CGSize(width: maxX - minX, height: maxY - minY)
        origin = CGPoint(x: -minX, y: -minY)
    }

    func point(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGPoint {
        let p = Iso.project(x, y, z)
        return CGPoint(x: p.x + origin.x, y: p.y + origin.y)
    }
}

/// The three visible faces of a box.
enum IsoFace {
    /// Faces the viewer on the left (y = max); local u runs along x.
    case front
    /// Faces the viewer on the right (x = max); local u runs along -y.
    case side
    /// Looks up; local u along x, v along y.
    case top
}

extension IsoScene {
    /// Maps a face's flat local coordinates (u right, v down, origin at the
    /// face's top-left as seen) onto the screen.
    func transform(for face: IsoFace, of b: IsoBox) -> CGAffineTransform {
        switch face {
        case .front:
            let o = point(b.x, b.y + b.d, b.topZ)
            return CGAffineTransform(a: Iso.cos30, b: Iso.sin30, c: 0, d: 1, tx: o.x, ty: o.y)
        case .side:
            let o = point(b.x + b.w, b.y + b.d, b.topZ)
            return CGAffineTransform(a: Iso.cos30, b: -Iso.sin30, c: 0, d: 1, tx: o.x, ty: o.y)
        case .top:
            let o = point(b.x, b.y, b.topZ)
            return CGAffineTransform(a: Iso.cos30, b: Iso.sin30, c: -Iso.cos30, d: Iso.sin30, tx: o.x, ty: o.y)
        }
    }

    /// Flat size of a face in its local coordinates.
    func faceSize(_ face: IsoFace, of b: IsoBox) -> CGSize {
        switch face {
        case .front: CGSize(width: b.w, height: b.h)
        case .side: CGSize(width: b.d, height: b.h)
        case .top: CGSize(width: b.w, height: b.d)
        }
    }

    /// Outline of one face on the screen.
    func path(_ face: IsoFace, of b: IsoBox) -> Path {
        let s = faceSize(face, of: b)
        return Path(CGRect(origin: .zero, size: s)).applying(transform(for: face, of: b))
    }
}

/// Paints a box: three shaded faces and a hairline outline.
struct IsoBlock: View {
    let scene: IsoScene
    let box: IsoBox
    var tone: IsoTone = .body

    var body: some View {
        Canvas { context, _ in
            for (face, fill) in [(IsoFace.top, tone.top), (.front, tone.front), (.side, tone.side)] {
                let p = scene.path(face, of: box)
                context.fill(p, with: .color(fill))
                context.stroke(p, with: .color(tone.edge), lineWidth: 0.6)
            }
        }
        .frame(width: scene.size.width, height: scene.size.height)
        .allowsHitTesting(false)
    }
}

/// Face shading for the dark widget: light from the top-left.
struct IsoTone {
    var top: Color
    var front: Color
    var side: Color
    var edge: Color = Color.white.opacity(0.16)

    static let body = IsoTone(
        top: Color(white: 0.20),
        front: Color(white: 0.14),
        side: Color(white: 0.10)
    )
    static let plate = IsoTone(
        top: Color(white: 0.11),
        front: Color(white: 0.08),
        side: Color(white: 0.06),
        edge: Color.white.opacity(0.10)
    )
    static let key = IsoTone(
        top: Color(white: 0.30),
        front: Color(white: 0.20),
        side: Color(white: 0.15),
        edge: Color.white.opacity(0.22)
    )
}

extension View {
    /// Pins flat content onto a face of a box in the scene. The content is
    /// laid out in the face's own units and sheared into place; hit testing
    /// follows the shear.
    func isoFace(_ face: IsoFace, of box: IsoBox, in scene: IsoScene) -> some View {
        let size = scene.faceSize(face, of: box)
        return frame(width: size.width, height: size.height, alignment: .topLeading)
            .transformEffect(scene.transform(for: face, of: box))
            .frame(width: scene.size.width, height: scene.size.height, alignment: .topLeading)
    }
}
