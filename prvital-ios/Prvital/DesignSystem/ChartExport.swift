import SwiftUI

/// A share button for any chart card: renders the given content to a crisp
/// image on tap and hands it to the system share sheet — so one chart can go
/// to the doctor without exporting the whole PDF report.
///
/// The render happens ON TAP, not per body pass: `ImageRenderer` rasterises the
/// whole view, and doing that every render would drag the chart's own
/// scrolling. The image is framed on the app background with a title and a
/// small wordmark, so it stands on its own outside the app.
struct ChartExportButton<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: () -> Content

    @State private var exported: ExportedChartImage?

    var body: some View {
        Button {
            Haptics.play(.light)
            exported = render()
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textTertiary)
                .padding(6)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share this chart as an image")
        .sheet(item: $exported) { item in
            ExportPreviewSheet(item: item)
        }
    }

    @MainActor private func render() -> ExportedChartImage? {
        let framed = VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            content()
            Text(verbatim: "Prvital")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(20)
        .frame(width: 700)
        .background(Theme.background)

        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        guard let image = renderer.uiImage else { return nil }
        return ExportedChartImage(image: image)
    }
}

/// The rendered chart, ready for the share sheet.
struct ExportedChartImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// A quick look at exactly what will be shared, with the share action on top —
/// nothing leaves the device until the user picks a destination here.
private struct ExportPreviewSheet: View {
    let item: ExportedChartImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Image(uiImage: item.image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 12))
                    .padding()
            }
            .background(Theme.background)
            .navigationTitle("Share chart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    ShareLink(
                        item: Image(uiImage: item.image),
                        preview: SharePreview("Glucose chart", image: Image(uiImage: item.image))
                    )
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
