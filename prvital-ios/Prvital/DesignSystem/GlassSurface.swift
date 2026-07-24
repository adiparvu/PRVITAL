import SwiftUI

/// A rounded "liquid glass" card surface using the native SwiftUI Liquid Glass
/// API where available (iOS/watchOS 26+), with a material fallback so the same
/// modifier compiles on every supported OS.
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 22
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .modifier(GlassBackground(cornerRadius: cornerRadius))
    }
}

private struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        // Clip the whole card (content + surface) to the rounded shape so nothing
        // — e.g. a chart's area fill that reaches the padded content's edge — pokes
        // past the rounded corners, since the corner radius can exceed the padding.
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if os(iOS) || os(watchOS)
        if #available(iOS 26, watchOS 26, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                .overlay { edge }
                .clipShape(shape)
        } else {
            content.background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
                .overlay { edge }
                .clipShape(shape)
        }
        #else
        content.background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
            .overlay { edge }
            .clipShape(shape)
        #endif
    }

    /// A hairline edge that gives every card a defined border in light mode and
    /// on the material fallback, where the surface can otherwise blend into the
    /// background.
    private var edge: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: 1)
    }
}

extension View {
    /// Wraps a view in a padded glass card.
    func glassCard(cornerRadius: CGFloat = 22, padding: CGFloat = 16) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, padding: padding))
    }

    /// A translucent "liquid glass" background for Form/List rows, so settings
    /// surfaces read as frosted glass over the app background instead of solid
    /// panels. Use in place of `.listRowBackground(Theme.surface)`.
    func glassListRow() -> some View {
        listRowBackground(GlassListRowBackground())
    }
}

/// The frosted-glass fill behind a settings list row.
///
/// Matches the cards (`glassCard`): the native Liquid Glass effect on iOS/watchOS
/// 26, with an `.ultraThinMaterial` fallback — the more translucent material the
/// companion card uses, so menus read as the same frosted glass that lets the app
/// background show through, rather than a more opaque panel. A hairline keeps each
/// row defined where the glass blends into the backdrop.
struct GlassListRowBackground: View {
    var body: some View {
        glass
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.hairline.opacity(0.5)).frame(height: 0.5)
            }
    }

    @ViewBuilder private var glass: some View {
        #if os(iOS) || os(watchOS)
        if #available(iOS 26, watchOS 26, *) {
            Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 0))
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
        #else
        Rectangle().fill(.ultraThinMaterial)
        #endif
    }
}

/// A titled section container used throughout the app.
struct SectionCard<Content: View>: View {
    let title: LocalizedStringKey
    var systemImage: String?
    var accessory: AnyView?
    @ViewBuilder var content: () -> Content

    init(_ title: LocalizedStringKey, systemImage: String? = nil, accessory: AnyView? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label {
                    Text(title).font(.headline)
                } icon: {
                    if let systemImage { Image(systemName: systemImage).foregroundStyle(Theme.accent) }
                }
                .labelStyle(.titleAndIcon)
                Spacer()
                accessory
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
