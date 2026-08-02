import SwiftUI

/// The per-dose story behind the summed IOB number: every still-active bolus on
/// its own row — units injected, units left, when it was given, when it ends,
/// and a decay bar — so "1.9 U" reads as "1.5 U of the correction from just now
/// plus 0.4 U tailing off from lunch".
struct ActiveInsulinSheet: View {
    let doses: [InsulinMath.ActiveDose]
    @Environment(\.dismiss) private var dismiss

    private var totalRemaining: Double {
        doses.map(\.remainingUnits).reduce(0, +)
    }

    private var allClearAt: Date? {
        doses.map(\.endsAt).max()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(doses) { dose in
                        doseRow(dose)
                    }
                    if let allClearAt {
                        HStack {
                            Text("Total")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text("\(totalRemaining.formatted(.number.precision(.fractionLength(1)))) U · \(allClearAt.formatted(date: .omitted, time: .shortened))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, 2)
                    }
                    Text("How much of each dose is still working, on the same activity curve the calculator uses. The bar empties as the dose is used up.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Active insulin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func doseRow(_ dose: InsulinMath.ActiveDose) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "syringe.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Theme.accent, in: .rect(cornerRadius: 8))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(dose.units.formatted()) U · \(dose.context.label)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(dose.timestamp.formatted(date: .omitted, time: .shortened)) → \(dose.endsAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(dose.remainingUnits.formatted(.number.precision(.fractionLength(1)))) U")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                        .monospacedDigit()
                    Text("still active")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            ProgressView(value: max(0, min(1, 1 - dose.usedFraction)))
                .tint(Theme.accent)
        }
        .glassCard(cornerRadius: 16, padding: 14)
        .accessibilityElement(children: .combine)
    }
}
