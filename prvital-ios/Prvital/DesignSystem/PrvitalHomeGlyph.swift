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

/// The Profile glyph: a ring for the head over a wide, shallow shoulder arc,
/// both drawn in one stroke weight with round caps — the reference silhouette.
struct PrvitalPersonGlyph: Shape {

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        func offset(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: center.x + x * side, y: center.y + y * side)
        }

        var path = Path()
        // Head.
        path.addEllipse(in: CGRect(
            x: offset(-0.155, -0.44).x,
            y: offset(0, -0.44).y,
            width: side * 0.31,
            height: side * 0.31))
        // Shoulders: the top half of a wide circle sitting low, so the arc is
        // broad and shallow and its ends turn down at the sides.
        path.addArc(center: offset(0, 0.40),
                    radius: side * 0.33,
                    startAngle: .degrees(180),
                    endAngle: .degrees(360),
                    clockwise: false)
        return path
    }
}

#if canImport(UIKit)
/// Renders every tab-bar glyph as a template image at one shared weight.
///
/// A tab item only takes an `Image`, so each glyph is rasterised once and
/// cached. Going through images for ALL five — the two custom shapes and the
/// three SF Symbols — is what makes the bar read as one set: the symbols are
/// built with an explicit point size and weight instead of whatever the tab bar
/// would pick, and the custom strokes are drawn to match. It also stops the tab
/// bar silently swapping in `.fill` variants, which is why the grid and the
/// chart used to look heavier than everything beside them.
///
/// `alwaysTemplate` hands tinting back to the system, so the selected state and
/// the user's accent colour still apply.
@MainActor
enum PrvitalTabGlyph {
    static let home: UIImage = render(PrvitalHomeGlyph().fill(style: FillStyle(eoFill: true)))
    static let journal: UIImage = symbol("square.grid.2x2")
    static let add: UIImage = symbol("plus")
    static let insights: UIImage = symbol("chart.bar")
    static let profile: UIImage = render(
        PrvitalPersonGlyph().stroke(style: StrokeStyle(
            lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)))

    /// The optical size every glyph is drawn at.
    private static let side: CGFloat = 22
    /// Matched to an SF Symbol of the same point size at `.regular` weight, so
    /// the hand-drawn strokes sit at the same weight as the symbols.
    private static let strokeWidth: CGFloat = 2

    private static func symbol(_ name: String) -> UIImage {
        let configuration = UIImage.SymbolConfiguration(pointSize: side - 1, weight: .regular)
        return UIImage(systemName: name, withConfiguration: configuration)?
            .withRenderingMode(.alwaysTemplate) ?? UIImage()
    }

    private static func render<V: View>(_ content: V) -> UIImage {
        let renderer = ImageRenderer(content:
            content
                .frame(width: side, height: side)
                .foregroundStyle(.black)
        )
        renderer.scale = 3
        guard let image = renderer.uiImage else { return UIImage() }
        return image.withRenderingMode(.alwaysTemplate)
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
