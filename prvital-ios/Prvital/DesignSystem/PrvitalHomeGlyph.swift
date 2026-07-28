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

#if canImport(UIKit)
/// Renders the custom glyphs the tab bar needs as template images.
///
/// A tab item only takes an `Image`, so the shape is rasterised once and cached.
/// `alwaysTemplate` hands the tinting back to the system, which is what keeps it
/// looking like the SF Symbols beside it — including the selected state and the
/// user's accent colour.
@MainActor
enum PrvitalTabGlyph {
    static let home: UIImage = render(PrvitalHomeGlyph())

    /// Matches the optical size SF Symbols draw at in a tab bar.
    private static let side: CGFloat = 26

    private static func render<S: Shape>(_ shape: S) -> UIImage {
        let renderer = ImageRenderer(content:
            shape
                .fill(style: FillStyle(eoFill: true))
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
