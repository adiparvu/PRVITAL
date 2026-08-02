import SwiftUI

/// The eight standard injection zones and when each was last used. No body
/// silhouette pretending to be anatomy — a clear labeled grid, colour-coded by
/// how RESTED each site is, which is the actual question rotation answers:
/// green = rested (4+ days), amber = recent, red = used in the last day.
enum InjectionSite: String, CaseIterable, Identifiable {
    case abdomenLeft, abdomenRight
    case thighLeft, thighRight
    case armLeft, armRight
    case buttockLeft, buttockRight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .abdomenLeft: return String(localized: "Abdomen · left")
        case .abdomenRight: return String(localized: "Abdomen · right")
        case .thighLeft: return String(localized: "Thigh · left")
        case .thighRight: return String(localized: "Thigh · right")
        case .armLeft: return String(localized: "Arm · left")
        case .armRight: return String(localized: "Arm · right")
        case .buttockLeft: return String(localized: "Buttock · left")
        case .buttockRight: return String(localized: "Buttock · right")
        }
    }

    var symbol: String {
        switch self {
        case .abdomenLeft, .abdomenRight: return "figure.stand"
        case .thighLeft, .thighRight: return "figure.walk"
        case .armLeft, .armRight: return "figure.arms.open"
        case .buttockLeft, .buttockRight: return "figure.seated.side"
        }
    }
}

/// Last-used dates per site, in the shared defaults — tiny, device-local.
enum InjectionSiteStore {
    private static let key = "injectionSites.lastUsed"

    static func lastUsed() -> [InjectionSite: Date] {
        let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: Date] ?? [:]
        var out: [InjectionSite: Date] = [:]
        for (name, date) in raw {
            if let site = InjectionSite(rawValue: name) { out[site] = date }
        }
        return out
    }

    static func markUsed(_ site: InjectionSite, at date: Date = Date()) {
        var raw = UserDefaults.standard.dictionary(forKey: key) as? [String: Date] ?? [:]
        raw[site.rawValue] = date
        UserDefaults.standard.set(raw, forKey: key)
    }

    /// The most rested site — the suggestion.
    static func mostRested(now: Date = Date()) -> InjectionSite {
        let used = lastUsed()
        return InjectionSite.allCases.min { lhs, rhs in
            (used[lhs] ?? .distantPast) < (used[rhs] ?? .distantPast)
        } ?? .abdomenLeft
    }
}

/// The rotation grid: tap a zone to mark it used now. The most rested zone
/// wears a "suggested" ring.
struct InjectionSitesView: View {
    @State private var lastUsed = InjectionSiteStore.lastUsed()

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Rotating sites keeps the tissue healthy and the absorption predictable. Tap where you injected — the greenest zone is the most rested.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(InjectionSite.allCases) { site in
                        siteCell(site)
                    }
                }
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle("Injection sites")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func siteCell(_ site: InjectionSite) -> some View {
        let last = lastUsed[site]
        let restedDays = last.map { Date().timeIntervalSince($0) / 86_400 }
        let tint: Color = {
            guard let restedDays else { return Theme.zoneInRange }
            if restedDays >= 4 { return Theme.zoneInRange }
            if restedDays >= 1 { return Theme.zoneWarning }
            return Theme.zoneCritical
        }()
        let suggested = InjectionSiteStore.mostRested() == site

        return Button {
            Haptics.play(.success)
            InjectionSiteStore.markUsed(site)
            lastUsed = InjectionSiteStore.lastUsed()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: site.symbol)
                    .font(.title3)
                    .foregroundStyle(tint)
                Text(site.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(last.map { $0.formatted(.relative(presentation: .named)) }
                     ?? String(localized: "Never used"))
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .padding(10)
            .background(tint.opacity(0.10), in: .rect(cornerRadius: 16))
            .overlay {
                if suggested {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Theme.accent, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(site.label). \(suggested ? String(localized: "Suggested next site.") : "")")
    }
}
