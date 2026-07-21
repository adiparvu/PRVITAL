import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The person's avatar, rendered from whatever they've set — a photo, their
/// initials, or a fallback symbol — inside a circle with an optional coloured
/// ring. A dumb renderer that takes primitives (not a `UserProfile`), so it's
/// reused unchanged in the profile header, the settings row and the editor.
struct AvatarView: View {
    /// A profile photo; when present it wins over initials and symbol.
    var imageData: Data?
    /// Uppercased initials, shown when there's a name but no photo.
    var initials: String?
    /// The fallback SF Symbol, shown when there's neither photo nor initials.
    var symbol: String = "person.crop.circle.fill"
    /// The tint for the initials/symbol and their soft circle fill.
    var tint: Color
    /// An optional ring drawn around the avatar (nil = no ring).
    var ring: Color?
    var diameter: CGFloat = 56

    private var ringWidth: CGFloat { max(2, diameter * 0.045) }

    var body: some View {
        content
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            .overlay {
                if let ring {
                    Circle().strokeBorder(ring, lineWidth: ringWidth)
                }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        #if canImport(UIKit)
        if let imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            placeholder
        }
        #else
        placeholder
        #endif
    }

    @ViewBuilder
    private var placeholder: some View {
        ZStack {
            Circle().fill(tint.opacity(0.16))
            if let initials, !initials.isEmpty {
                Text(initials)
                    .font(.system(size: diameter * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: diameter * 0.45))
                    .foregroundStyle(tint)
            }
        }
    }
}

#if canImport(UIKit)
/// Shared image helper: downscale a picked photo to a square-ish avatar and
/// re-encode as JPEG so the profile stays small (CloudKit- and widget-friendly).
enum AvatarImage {
    static func downscaledJPEG(from data: Data, maxDimension: CGFloat = 512, quality: CGFloat = 0.8) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
#endif
