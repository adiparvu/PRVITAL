import SwiftUI

/// The ⓘ sheet for the evolving badges: how they level up, what each tier is
/// worth, and every family's full ladder of thresholds.
struct BadgeInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Badges grow with you: the same badge levels up from Bronze to Diamond as your counts build. Every level earned adds points — your score for the upcoming community leaderboard.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .glassListRow()

                Section {
                    ForEach(BadgeTier.allCases, id: \.rawValue) { tier in
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color(hex: tier.colorHex))
                                .frame(width: 26)
                            Text(tier.displayName)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(tier.points) p")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("Levels")
                }
                .glassListRow()

                ForEach(BadgeCatalog.families) { family in
                    Section {
                        ForEach(Array(family.thresholds.enumerated()), id: \.offset) { index, threshold in
                            let tier = family.tier(atIndex: index)
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color(hex: tier.colorHex))
                                    .frame(width: 22)
                                Text(String(format: family.detailFormat, threshold))
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text(tier.displayName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(hex: tier.colorHex))
                            }
                        }
                    } header: {
                        Label {
                            Text(family.title)
                        } icon: {
                            Image(systemName: family.symbol).foregroundStyle(Theme.accent)
                        }
                    }
                    .glassListRow()
                }
            }
            .scrollContentBackground(.hidden)
            .prvitalTabBackground()
            .navigationTitle("How badges work")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large, .medium])
    }
}

#Preview {
    BadgeInfoView()
}
