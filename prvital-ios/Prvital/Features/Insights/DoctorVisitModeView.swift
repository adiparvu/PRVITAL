import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Doctor-visit mode: the phone, prepared for a consultation. One tap presents
/// the full AGP report (the clinician's lingua franca) full screen, with the
/// in-app type bumped up so it reads across a desk — and the screen stays
/// awake for the whole conversation instead of dimming mid-sentence.
///
/// Deliberately a *presentation* of the existing report, not a new report:
/// the AGP screen already carries the 90-day percentiles, time-in-range bar,
/// GMI and comparisons, and its PDF export lives right there for handing over.
struct DoctorVisitModeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AGPReportView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            Haptics.play(.light)
                            dismiss()
                        }
                    }
                }
        }
        // Larger-than-usual type: legible for someone reading from the other
        // side of the desk. The user's own Dynamic Type still wins above this.
        .dynamicTypeSize(.xLarge ... .accessibility2)
        .onAppear {
            #if canImport(UIKit)
            UIApplication.shared.isIdleTimerDisabled = true
            #endif
        }
        .onDisappear {
            #if canImport(UIKit)
            UIApplication.shared.isIdleTimerDisabled = false
            #endif
        }
    }
}
