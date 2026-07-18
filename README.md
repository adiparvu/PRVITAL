# Diabetes Journal

A premium, privacy-first **diabetes-monitoring app for iPhone**, built natively
with SwiftUI, SwiftData, HealthKit, WidgetKit, WatchConnectivity, Swift Charts
and CloudKit. It follows Apple's design philosophy — calm, fast, Health-app
inspired — and is architected so new medical data sources (CGM sensors and
beyond) can be added without touching the UI or the medical logic.

The app lives in **[`diabetes-journal-ios/`](diabetes-journal-ios/)**.

## Quick start

```bash
cd diabetes-journal-ios
brew install xcodegen
xcodegen generate
open DiabetesJournal.xcodeproj
```

Requires macOS with **Xcode 26** (iOS/watchOS 26 SDK, Swift 6). There is no
backend and no configuration — on first launch the app seeds realistic demo data
so every screen is browsable, and all data stays on-device (with optional private
CloudKit sync).

## What's inside

- **iPhone app** — Dashboard, Journal + quick entry, Calendar, History, Insights
  (charts + statistics), PDF/CSV export, Settings, and a privacy/consent flow.
- **Widgets** — Home Screen (small / medium / large) and Lock Screen glucose widgets.
- **Apple Watch app** — current glucose glance + quick insulin/carb logging.

See **[`diabetes-journal-ios/README.md`](diabetes-journal-ios/README.md)** for the
full guide (build, TestFlight, requirements) and
**[`diabetes-journal-ios/ARCHITECTURE.md`](diabetes-journal-ios/ARCHITECTURE.md)**
for the data model, the deterministic conflict-resolution strategy, and the
privacy/security design.

## Continuous integration

`.github/workflows/diabetes-ios.yml` builds the app + widgets and the watch app
on a macOS runner whenever the sources change, and has a manual TestFlight job.
