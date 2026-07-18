# Prvital — Architecture

This document describes the layered architecture, the unified data model, the
deterministic conflict-resolution strategy, and the privacy/security design.

## Layered data flow

Every value — whether it comes from a Dexcom sensor, a FreeStyle Libre, Apple
Health, the Apple Watch or manual entry — travels the same path:

| Layer | Responsibility | Code |
| --- | --- | --- |
| **Integration** | Talk to each source; emit a source-agnostic sample | `Data/Integration/GlucoseSource.swift`, `GlucoseSources.swift` |
| **Normalization** | Map a sample onto the unified persisted model | `Data/Integration/GlucoseNormalizer.swift` |
| **Medical domain** | Thresholds, units, statistics, analytics | `Domain/*` |
| **Conflict resolution + Audit** | Pick one active value deterministically; record it | `Domain/Conflicts/ConflictResolver.swift`, `Data/Audit/*` |
| **Storage** | Persist locally (encrypted), optionally sync via CloudKit | `Data/Persistence/PersistenceController.swift` |
| **Presentation** | SwiftUI dashboard, journal, charts, statistics | `Prvital/Features/*` |

The **integration boundary** is a single protocol, `GlucoseSource`. Adding a
sensor is one conformer plus one line in `AppEnvironment` — nothing downstream
changes. `SyncCoordinator` is the one place that runs the whole pipeline
(fetch → normalize → dedup + store → resolve → audit), so a background sync and a
pull-to-refresh are identical and equally auditable.

## Unified data model

All records share standardized identity, provenance and time fields
(`MedicalRecord`): `id`, `source`, `deviceID`, `timestamp`, `createdAt`,
`updatedAt`, and the capture `timeZoneIdentifier` (so the original local time is
recoverable after the device moves). Timestamps are stored as `Date` (UTC) and
exported in **ISO 8601 UTC** (e.g. `2025-01-15T08:30:00Z`).

The five record types (all SwiftData `@Model`, CloudKit-safe: defaults on every
property, no unique constraints):

- **GlucoseReading** — `valueMgdL` (canonical mg/dL), `trend`, `measurementType`,
  `sensorTimestamp`, `confidence`, plus conflict fields (`isActive`,
  `conflictGroupID`, `resolutionReason`) and `externalID` for dedup.
- **InsulinDose** — `units`, `insulinType`, `insulinName`, `deliveryMethod`,
  `doseContext`.
- **CarbEntry** — `grams`, `mealType`, `foodDescription`.
- **ActivityEntry** — `activityType`, `startTimestamp`, `endTimestamp`,
  `durationSeconds`, `intensity`, `caloriesBurned`, `distanceMeters`.
- **ObservationEntry** — `tags` (illness, stress, sleep…), `text`.

Glucose is stored **once** in mg/dL; the display unit (mg/dL or mmol/L) is a pure
presentation concern resolved through `GlucoseUnit`. Zone classification (very
low / low / in range / high / very high → red / orange / green / yellow) comes
from a single user-configurable `GlucoseThresholds` (ADA/ATTD defaults: target
70–180, with 54 and 250 boundaries).

## Deterministic conflict resolution

When two sources report glucose at nearly the same instant, `ConflictResolver`
produces a single, predictable, repeatable decision (`Domain/Conflicts`):

- **No original value is ever deleted.** Losers keep `isActive == false` and the
  shared `conflictGroupID`, so alternatives stay queryable.
- Readings within a small window (default ±150 s) form a cluster; one is marked
  active and given a human-readable `resolutionReason`.
- The comparison is fully ordered, so the result never depends on input order:
  1. the user's **primary source** preference (`SourceRegistry.sourcePriority`),
  2. measurement-type authority (lab > finger-stick > CGM > calibration > manual),
  3. reported **confidence**,
  4. freshest sensor sample, then freshest capture time,
  5. UUID as a stable final tiebreak.
- Each resolution pass writes one audit row summarising the outcome.

The user selects the primary source in **Settings → Sources** and can see the
provenance of every value and the reason the active one was chosen.

## Privacy & security by design

- **Data minimization**: only what the app needs is collected; medical, technical
  and analytics data are kept separate.
- **Encryption at rest**: SwiftData store under `NSFileProtectionComplete`;
  Keychain / Secure Enclave for keys and tokens; nothing medical stored in the
  clear.
- **Encryption in transit / cloud**: sync is opt-in through the user's **private
  CloudKit database** over TLS; Apple cannot read the contents.
- **Granular, revocable consent** per scope (`ConsentScope`): HealthKit, Apple
  Watch, external CGM, cloud sync, export, future intelligent features — each with
  a plain-language rationale shown before the system prompt, requested separately.
- **Audit & traceability** (`PrivacyAuditRecord`): `id`, `timestamp`,
  `action_type`, `data_source`, `user_confirmation`, `device_identifier`,
  `result`, and an optional non-medical `detail`. The log never stores medical
  values, and the device tag is a random per-install token, not a hardware ID.
- **Retention**: audit rows older than the retention window are pruned on launch.
- **User control**: view what's stored, export (PDF/CSV, generated locally with a
  sensitivity notice), delete local data, disable cloud sync, revoke source access.
- **Never** used for advertising, commercial profiling, sale to third parties, or
  model training without explicit consent.

### Future AI features

Any future intelligence (pattern detection, daily summaries, report prep) is
gated on the `aiFeatures` consent scope, explains its purpose, **never**
automatically changes medical data, presents results as suggestions (not medical
decisions), keeps the user in control, and respects Apple's health-data policies.

## Extensibility

- **New sources**: conform to `GlucoseSource`, register in `AppEnvironment`.
- **New record types**: add a `@Model` + enums; the audit/export layers treat
  records uniformly through `MedicalRecord`.
- **New surfaces** (visionOS, new HealthKit/Watch APIs, Apple Intelligence): the
  presentation layer is isolated from domain and integration, so adopting new OS
  capabilities does not require refactoring the medical core.
