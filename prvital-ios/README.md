# Prvital — iOS

A premium, privacy-first diabetes-monitoring app for iPhone, built natively with
**SwiftUI**, **SwiftData**, **HealthKit**, **WidgetKit**, **WatchConnectivity**,
**Swift Charts** and **CloudKit**. It follows Apple's design philosophy — calm,
fast, Health-app-inspired — and is architected so new medical data sources (CGM
sensors and beyond) can be added without touching the UI or the medical logic.

> **Status / honesty note:** this code is authored to open and build in **Xcode
> 26 on macOS** (Swift 6, iOS/watchOS 26 SDK). It has **not** been compiled in
> the Linux environment where it was written; the `Prvital (Apple)`
> GitHub Actions workflow builds it on a macOS runner so Swift compilation is
> validated in CI. Generate the project and build it in Xcode before relying on it.

## Getting started

```bash
cd prvital-ios
brew install xcodegen
xcodegen generate
open Prvital.xcodeproj
```

Select the **Prvital** scheme and run on an iPhone simulator. There is
**no configuration and no backend** — on first launch the app seeds a realistic,
deterministic demo dataset so every screen is immediately explorable, and all
data lives on-device (optionally synced through your private CloudKit database).

Requirements: macOS with **Xcode 26** (iOS 26 SDK). The app targets iOS 26 and
watchOS 26 and builds with Swift 6. HealthKit, CloudKit and App Groups require an
Apple Developer account for a signed device build; the simulator runs unsigned.

## What it does (MVP)

- **Dashboard** — current glucose gauge tinted by zone (green / yellow / orange /
  red), trend, provenance (which source), a 3-hour chart, and the last insulin,
  meal and activity. Pull to refresh syncs external sources.
- **Journal & quick entry** — one-tap insulin (`+1…+10 U`) and carbs
  (`20…100 g`), plus full editors for glucose, insulin, carbs, activity and
  contextual observations (illness, stress, sleep…). A day-grouped timeline.
- **Calendar** — a month grid coloured by each day's glucose control, tap for the
  day's detail.
- **History** — every record with Today / Yesterday / Week / Month / Custom
  filters, sorting, and edit / delete.
- **Insights** — glucose / insulin / carb / activity charts over Day / Week /
  Month / Year, and statistics: average, min, max, **Time in Range**, time above
  / below, estimated A1c (GMI), variability (CV), hypo / hyper events, insulin and
  carb totals.
- **Export** — locally-generated **PDF** and **CSV** reports for your care team,
  each carrying a data-sensitivity notice and shared only through the system sheet.
- **Widgets** — Home Screen (small / medium / large) and Lock Screen
  (circular / rectangular / inline) glucose widgets.
- **Apple Watch** — current glucose and trend on the wrist, with quick insulin /
  carb logging that flows back to the phone.
- **Privacy** — first-run consent onboarding, a per-scope privacy dashboard, a
  full audit trail, and complete data control (view, export, delete, revoke).

## Architecture

The app is modular with clear boundaries so any new medical data source lands
through the same pipeline without UI or domain changes:

```
External sources (Dexcom / FreeStyle Libre / HealthKit / Apple Watch / Manual)
        │  Integration layer      Data/Integration/*  (GlucoseSource protocol)
        ▼
   Normalization                  Data/Integration/GlucoseNormalizer
        ▼
   Medical domain                 Domain/*  (unified model, thresholds, statistics)
        ▼
Conflict resolution + Audit       Domain/Conflicts + Data/Audit
        ▼
     Storage                      Data/Persistence  (SwiftData, encrypted at rest, CloudKit-ready)
        ▼
   Presentation                   Prvital/Features/*  (SwiftUI)
```

```
Prvital/           (app target)
  App/            Entry point, root tabs, composition root (AppEnvironment), Preferences
  Domain/         Unified data model (SwiftData @Model), enums, thresholds, units,
                  statistics engine, deterministic conflict resolver, analytics
  Data/           Persistence, CGM source abstraction + sync, HealthKit, audit,
                  consent, export (PDF/CSV), notifications, snapshot publisher
  DesignSystem/   Theme tokens, glass surfaces, components, glucose visuals, haptics
  Features/       Dashboard, Journal, QuickEntry, Calendar, History, Insights,
                  Settings, Onboarding (SwiftUI screens)
  DemoData/       Deterministic seed data used on first launch
  Resources/      Assets, generated Info.plist / entitlements (via XcodeGen)
PrvitalWidgets/    (WidgetKit extension) — reads the App Group snapshot
PrvitalWatch/      (watchOS app) — snapshot over WatchConnectivity
Shared/                    GlucoseSnapshot + SharedStore (App Group bridge)
Connectivity/              WatchSessionManager (WatchConnectivity, app + watch)
```

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the data model, the conflict-resolution
strategy, and the privacy/security design in detail.

### Adding a new CGM source

Conform a class to `GlucoseSource` (`source`, `isAvailable`, `connectionState`,
`requestAccess()`, `fetchLatest()`, `fetchSamples(since:)`), register it in
`AppEnvironment` — done. Normalization, storage, conflict resolution, audit,
provenance display and the dashboard all work unchanged.

## Privacy & security

Privacy is part of the architecture, not a feature bolted on:

- **On-device by default.** Records are stored with SwiftData under Apple's
  **Data Protection** (`NSFileProtectionComplete`); tokens/keys belong in the
  Keychain / Secure Enclave. Cloud sync is **opt-in** through the user's private
  CloudKit database (Apple cannot read the contents).
- **Granular consent.** HealthKit, Apple Watch, external CGM, cloud sync, export
  and future intelligent features are each consented to — and revocable —
  independently, with a plain-language rationale shown before any system prompt.
- **Audit trail.** Every sensitive operation (source access, sync, export, manual
  edit, permission change, conflict resolution, deletion) is recorded — **without**
  copying medical values into the log — and is browsable in-app.
- **Full data control.** View what's stored, export it, delete it, disable sync,
  and revoke source access at any time.
- **Not for sale.** Medical data is never used for advertising, commercial
  profiling, sale to third parties, or model training.

The design targets GDPR, Apple's App Store / HealthKit review guidelines, and
HIPAA principles where applicable. Any future AI feature is gated on explicit
consent, only ever offers suggestions (never automatic changes to medical data),
and keeps the user in control.

## Continuous integration

`.github/workflows/prvital-ios.yml` builds the app + widgets and the watch app
on a macOS runner (XcodeGen + `xcodebuild`, no signing) whenever
`prvital-ios/**` changes.

## TestFlight

The same workflow has a **manual** `testflight` job that archives the app (with
its widget and watch targets) and uploads the build to **TestFlight** via the
App Store Connect API. It runs only when you trigger it by hand — never on push.

### One-time setup

1. **Apple Developer Program** membership, and in App Store Connect create the
   app record for bundle id `com.prvital.app`.
2. **Register the App IDs** and enable their capabilities (so automatic signing
   can provision them):
   - `com.prvital.app` — HealthKit, App Groups (`group.com.prvital`),
     iCloud → CloudKit (`iCloud.com.prvital`), Data Protection.
   - `com.prvital.app.widgets` — App Groups.
   - `com.prvital.app.watchkitapp` — App Groups.
3. **Set your team id** in [`project.yml`](project.yml) → `settings.base.DEVELOPMENT_TEAM`
   (10-character Apple Team ID). Commit that change.
4. **Create an App Store Connect API key** (App Store Connect → Users and Access →
   Integrations → App Store Connect API → *App Manager* role) and note the
   **Key ID** and **Issuer ID**; download the `.p8` once.
5. **Add repository secrets** (Settings → Secrets and variables → Actions):

   | Secret | Value |
   | --- | --- |
   | `ASC_KEY_ID` | the API **Key ID** |
   | `ASC_ISSUER_ID` | the API **Issuer ID** |
   | `ASC_API_KEY_P8` | the **full contents** of the downloaded `AuthKey_*.p8` |

### Run it

GitHub → **Actions** → **Prvital (Apple)** → **Run workflow** → set
**testflight** to `true` → **Run**. The job:

1. generates the Xcode project with XcodeGen,
2. writes the API key to `~/private_keys/AuthKey_<KEY_ID>.p8`,
3. `xcodebuild archive` with `-allowProvisioningUpdates` (automatic signing),
4. `xcodebuild -exportArchive` with `method: app-store-connect`,
   `destination: upload` — pushing the build straight to TestFlight.

Bump the build number for each upload via `CURRENT_PROJECT_VERSION` (and
`MARKETING_VERSION` for a new version) in `project.yml`. After processing
finishes in App Store Connect, add it to a TestFlight group to invite testers.

### Doing it from Xcode instead

On a Mac you can skip CI: set your team, `xcodegen generate`, open the project,
select **Any iOS Device**, **Product → Archive**, then **Distribute App →
TestFlight & App Store** in the Organizer.

> Because the app uses **HealthKit**, App Review requires a filled-in
> **health-data usage** section and a privacy policy URL before external testing
> is approved; internal testing works as soon as the build finishes processing.
