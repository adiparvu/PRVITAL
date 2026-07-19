import AppIntents
import Foundation
import SwiftData

// Siri / Shortcuts / Spotlight entry points. Intents run outside the app's
// normal lifecycle, so writes open their own container on the shared App Group
// store (the app observes the same store via @Query) and reads use the
// pre-computed `GlucoseSnapshot`. Every write also records an audit row.

/// "What's my glucose?" — reads the shared snapshot, no data store needed.
struct CurrentGlucoseIntent: AppIntent {
    static let title: LocalizedStringResource = "Current glucose"
    static let description = IntentDescription("Check your latest glucose reading.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let snapshot = SharedStore.load()
        let value = "\(snapshot.valueText) \(snapshot.unitText)"
        let phrase: String
        if snapshot.updatedAt == .distantPast {
            phrase = "There's no glucose reading yet."
        } else if snapshot.isStale {
            phrase = "Your last glucose was \(value), \(snapshot.zoneLabel)."
        } else {
            phrase = "Your glucose is \(value), \(snapshot.trendLabel), \(snapshot.zoneLabel)."
        }
        return .result(value: value, dialog: IntentDialog(stringLiteral: phrase))
    }
}

/// "Log 4 units of insulin".
struct LogInsulinIntent: AppIntent {
    static let title: LocalizedStringResource = "Log insulin"
    static let description = IntentDescription("Record a rapid-acting insulin dose.")

    @Parameter(title: "Units")
    var units: Double

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = PersistenceController.makeContainer().mainContext
        context.insert(InsulinDose(units: units))
        IntentAudit.record(.manualEdit, in: context, detail: "Insulin \(units) U via Siri")
        try? context.save()
        return .result(dialog: IntentDialog(stringLiteral: "Logged \(units.formatted()) units of insulin."))
    }
}

/// "Log 30 grams of carbs".
struct LogCarbsIntent: AppIntent {
    static let title: LocalizedStringResource = "Log carbs"
    static let description = IntentDescription("Record a carbohydrate amount.")

    @Parameter(title: "Grams")
    var grams: Double

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = PersistenceController.makeContainer().mainContext
        context.insert(CarbEntry(grams: grams))
        IntentAudit.record(.manualEdit, in: context, detail: "Carbs \(grams) g via Siri")
        try? context.save()
        return .result(dialog: IntentDialog(stringLiteral: "Logged \(grams.formatted()) grams of carbs."))
    }
}

/// "Log glucose 120" — value is entered in the user's display unit.
struct LogGlucoseIntent: AppIntent {
    static let title: LocalizedStringResource = "Log glucose"
    static let description = IntentDescription("Record a glucose reading in your preferred unit.")

    @Parameter(title: "Value")
    var value: Double

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let unit = Preferences().glucoseUnit
        let mgdL = unit.toMgdL(value)
        let context = PersistenceController.makeContainer().mainContext
        context.insert(GlucoseReading(valueMgdL: mgdL, source: .manual, measurementType: .manual))
        IntentAudit.record(.manualEdit, in: context, detail: "Glucose via Siri")
        try? context.save()
        return .result(dialog: IntentDialog(stringLiteral: "Logged glucose \(value.formatted()) \(unit.rawValue)."))
    }
}

/// Small helper so intents keep the audit trail consistent with in-app edits.
private enum IntentAudit {
    @MainActor
    static func record(_ action: AuditActionType, in context: ModelContext, detail: String) {
        context.insert(PrivacyAuditRecord(
            actionType: action,
            userConfirmation: true,
            deviceIdentifier: DeviceIdentity.current,
            detail: detail
        ))
    }
}

/// Exposes the intents to Siri / Spotlight with spoken phrases.
struct PrvitalShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CurrentGlucoseIntent(),
            phrases: [
                "What's my glucose in \(.applicationName)",
                "Check my glucose in \(.applicationName)"
            ],
            shortTitle: "Current glucose",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: LogInsulinIntent(),
            phrases: ["Log insulin in \(.applicationName)"],
            shortTitle: "Log insulin",
            systemImageName: "syringe"
        )
        AppShortcut(
            intent: LogCarbsIntent(),
            phrases: ["Log carbs in \(.applicationName)"],
            shortTitle: "Log carbs",
            systemImageName: "fork.knife"
        )
        AppShortcut(
            intent: LogGlucoseIntent(),
            phrases: ["Log glucose in \(.applicationName)"],
            shortTitle: "Log glucose",
            systemImageName: "cross.vial"
        )
    }
}
