import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The app's own Home glyph: a house with generously rounded corners and a
/// droplet cut out of its middle — the one custom symbol in the tab bar.
///
/// The droplet is a *hole*, not a drawn-on shape: filled with the even-odd rule
/// it reads clearly at tab-bar size, where a droplet painted in the same colour
/// as the house would simply vanish.
struct PrvitalHomeGlyph: Shape {

    func path(in rect: CGRect) -> Path {
        var path = house(in: rect)
        path.addPath(droplet(in: dropletRect(in: rect)))
        return path
    }

    /// A five-sided house — peaked roof, straight walls, flat floor — with every
    /// corner rounded, the apex most of all.
    private func house(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }

        // Inset so the rounded corners stay inside the frame.
        let apex = point(0.5, 0.03)
        let rightEave = point(0.97, 0.42)
        let bottomRight = point(0.97, 0.97)
        let bottomLeft = point(0.03, 0.97)
        let leftEave = point(0.03, 0.42)

        let corner = w * 0.20
        let apexCorner = w * 0.24
        // Eaves are shallow angles; a smaller radius keeps them from collapsing.
        let eave = w * 0.14

        var path = Path()
        // Start mid-roof, so the first arc has a full edge to lean on.
        path.move(to: CGPoint(x: (apex.x + rightEave.x) / 2,
                              y: (apex.y + rightEave.y) / 2))
        path.addArc(tangent1End: rightEave, tangent2End: bottomRight, radius: eave)
        path.addArc(tangent1End: bottomRight, tangent2End: bottomLeft, radius: corner)
        path.addArc(tangent1End: bottomLeft, tangent2End: leftEave, radius: corner)
        path.addArc(tangent1End: leftEave, tangent2End: apex, radius: eave)
        path.addArc(tangent1End: apex, tangent2End: rightEave, radius: apexCorner)
        path.closeSubpath()
        return path
    }

    /// Sits a touch above the true centre of the walls — the roof pulls the eye
    /// upward, so a dead-centre droplet reads as low.
    private func dropletRect(in rect: CGRect) -> CGRect {
        let width = rect.width * 0.34
        let height = rect.height * 0.40
        return CGRect(x: rect.midX - width / 2,
                      y: rect.minY + rect.height * 0.45,
                      width: width,
                      height: height)
    }

    /// A classic teardrop: pointed at the top, round at the bottom, drawn as two
    /// mirrored curves so it stays perfectly symmetric at any size.
    private func droplet(in rect: CGRect) -> Path {
        let tip = CGPoint(x: rect.midX, y: rect.minY)
        let base = CGPoint(x: rect.midX, y: rect.maxY)
        let shoulder = rect.minY + rect.height * 0.38

        var path = Path()
        path.move(to: tip)
        path.addCurve(to: base,
                      control1: CGPoint(x: rect.maxX, y: shoulder),
                      control2: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addCurve(to: tip,
                      control1: CGPoint(x: rect.minX, y: rect.maxY),
                      control2: CGPoint(x: rect.minX, y: shoulder))
        path.closeSubpath()
        return path
    }
}

/// The Profile glyph: a head over a wide, shallow shoulder dome — the reference
/// silhouette.
///
/// `filled` picks the proportions, not just the paint. A stroked outline needs a
/// generous gap between head and shoulders so the two strokes don't merge; a
/// solid silhouette needs a bigger head, wider shoulders and a much tighter gap,
/// or it reads as a dot floating over a hill. The tab bar uses the solid one
/// (device feedback: "iconițele să fie mai pline, mai groase").
struct PrvitalPersonGlyph: Shape {
    var filled = false

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        func offset(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: center.x + x * side, y: center.y + y * side)
        }

        let headDiameter: CGFloat = filled ? 0.34 : 0.31
        let headCenterY: CGFloat = filled ? -0.27 : -0.285
        let shoulderRadius: CGFloat = filled ? 0.42 : 0.33
        let shoulderCenterY: CGFloat = filled ? 0.39 : 0.40

        var path = Path()
        // Head.
        path.addEllipse(in: CGRect(
            x: offset(-headDiameter / 2, 0).x,
            y: offset(0, headCenterY - headDiameter / 2).y,
            width: side * headDiameter,
            height: side * headDiameter))
        // Shoulders: the top half of a wide circle sitting low, so the shape is
        // broad and shallow and its ends turn down at the sides. Filled, the
        // arc closes on its own chord into a solid dome.
        path.move(to: offset(-shoulderRadius, shoulderCenterY))
        path.addArc(center: offset(0, shoulderCenterY),
                    radius: side * shoulderRadius,
                    startAngle: .degrees(180),
                    endAngle: .degrees(360),
                    clockwise: false)
        if filled { path.closeSubpath() }
        return path
    }
}

#if canImport(UIKit)
/// Renders every tab-bar glyph as a template image in one shared, SOLID weight.
///
/// A tab item only takes an `Image`, so each glyph is rasterised once and
/// cached. Going through images for ALL five — the two custom shapes and the
/// three SF Symbols — is what makes the bar read as one set: the symbols are
/// built with an explicit point size and weight instead of whatever the tab bar
/// would pick, and the custom shapes are drawn to match.
///
/// Every glyph is FILLED (device feedback: "iconițele să fie mai pline, mai
/// groase"). The house always was; the grid, the chart and the person now use
/// their solid forms too, and the one glyph with no solid form — the plus —
/// carries a heavy weight so its bar thickness matches the rest.
///
/// `alwaysTemplate` hands tinting back to the system, so the selected state and
/// the user's accent colour still apply.
@MainActor
enum PrvitalTabGlyph {
    // Every glyph is measured by the pixels it actually inks and scaled to one
    // shared optical size, because neither route produces equal footprints on
    // its own: SF Symbols at the same point size draw different-sized shapes,
    // and the custom paths don't reach the edges of their boxes. Rounded,
    // organic shapes (the house, the person) get a touch more than the boxy
    // symbols — same-height rounded forms read smaller.
    static let home: UIImage = normalized(
        render(PrvitalHomeGlyph().fill(style: FillStyle(eoFill: true))), optical: 21)
    static let journal: UIImage = normalized(symbol("square.grid.2x2.fill"), optical: 19.5)
    static let add: UIImage = normalized(symbol("plus", weight: .heavy), optical: 19)
    static let insights: UIImage = normalized(symbol("chart.bar.fill"), optical: 19.5)
    static let profile: UIImage = normalized(
        render(PrvitalPersonGlyph(filled: true).fill()), optical: 21)

    /// The canvas every glyph is centred in — identical for all five, so the
    /// tab bar lays them out on the same baseline.
    private static let side: CGFloat = 22

    private static func symbol(_ name: String, weight: UIImage.SymbolWeight = .semibold) -> UIImage {
        let configuration = UIImage.SymbolConfiguration(pointSize: side - 1, weight: weight)
        return UIImage(systemName: name, withConfiguration: configuration) ?? UIImage()
    }

    private static func render<V: View>(_ content: V) -> UIImage {
        let renderer = ImageRenderer(content:
            content
                .frame(width: side, height: side)
                .foregroundStyle(.black)
        )
        renderer.scale = 3
        return renderer.uiImage ?? UIImage()
    }

    /// Scales the image so its INKED region's longest side equals `optical`
    /// and centres that region in the shared canvas. This is the equaliser:
    /// per-glyph raster margins stop mattering, only visible shape size counts.
    private static func normalized(_ image: UIImage, optical: CGFloat) -> UIImage {
        guard let ink = inkedBounds(image), ink.width > 0, ink.height > 0 else {
            return image.withRenderingMode(.alwaysTemplate)
        }
        let factor = optical / max(ink.width, ink.height)
        let drawSize = CGSize(width: image.size.width * factor,
                              height: image.size.height * factor)
        let origin = CGPoint(
            x: (side - ink.width * factor) / 2 - ink.minX * factor,
            y: (side - ink.height * factor) / 2 - ink.minY * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let source = image.withRenderingMode(.alwaysOriginal)
        let out = UIGraphicsImageRenderer(size: CGSize(width: side, height: side),
                                          format: format).image { _ in
            source.draw(in: CGRect(origin: origin, size: drawSize))
        }
        return out.withRenderingMode(.alwaysTemplate)
    }

    /// The rectangle of pixels with meaningful alpha, in point coordinates.
    private static func inkedBounds(_ image: UIImage) -> CGRect? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 16 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let scale = max(image.scale, 1)
        return CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                      width: CGFloat(maxX - minX + 1) / scale,
                      height: CGFloat(maxY - minY + 1) / scale)
    }
}
#endif

#Preview {
    VStack(spacing: 30) {
        PrvitalHomeGlyph()
            .fill(style: FillStyle(eoFill: true))
            .foregroundStyle(Theme.accent)
            .frame(width: 120, height: 120)
        PrvitalHomeGlyph()
            .fill(style: FillStyle(eoFill: true))
            .foregroundStyle(Theme.textPrimary)
            .frame(width: 26, height: 26)
    }
    .padding()
}
