import Foundation

/// A therapy summary of insulin over a period: the basal/bolus totals, the
/// number of days that had any dose, and the derived average daily dose and
/// basal share.
struct InsulinSummary: Equatable, Sendable {
    let totalUnits: Double
    let basalUnits: Double
    let bolusUnits: Double
    let daysWithDoses: Int

    /// Average total dose per day that had any insulin (the "TDD").
    var averageDailyUnits: Double { daysWithDoses > 0 ? totalUnits / Double(daysWithDoses) : 0 }
    /// Basal share of the total (0…1). Bolus share is `1 - basalFraction`.
    var basalFraction: Double { totalUnits > 0 ? basalUnits / totalUnits : 0 }
    var bolusFraction: Double { totalUnits > 0 ? bolusUnits / totalUnits : 0 }
}

/// Aggregates insulin doses into a basal/bolus balance. Pure and deterministic
/// given a calendar; long-acting insulin is basal, everything else is bolus.
enum InsulinAnalyzer {
    static func summary(_ doses: [InsulinDose], calendar: Calendar = .current) -> InsulinSummary? {
        guard !doses.isEmpty else { return nil }

        var basal = 0.0
        var bolus = 0.0
        var days: Set<Date> = []
        for dose in doses where dose.units > 0 {
            if dose.insulinType.isBasal { basal += dose.units } else { bolus += dose.units }
            days.insert(calendar.startOfDay(for: dose.timestamp))
        }

        let total = basal + bolus
        guard total > 0 else { return nil }
        return InsulinSummary(totalUnits: total, basalUnits: basal, bolusUnits: bolus, daysWithDoses: days.count)
    }
}
