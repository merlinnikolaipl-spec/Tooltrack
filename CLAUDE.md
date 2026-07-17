# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
flutter pub get              # Install dependencies
flutter run                  # Run on connected device/emulator
flutter run -d windows       # Run on Windows desktop
flutter build apk            # Build Android APK
flutter build windows        # Build Windows desktop
flutter test                 # Run tests
```

**Windows desktop Google Sign-In** requires OAuth credentials passed at runtime:
```bash
flutter run -d windows \
  --dart-define=GOOGLE_CLIENT_ID=<id> \
  --dart-define=GOOGLE_CLIENT_SECRET=<secret>
```
These constants are consumed in `lib/google_oauth.dart` as `kGoogleDesktopClientId` and `kGoogleDesktopClientSecret`.

## Architecture

ToolTrack/ToolKeeper is a multi-tenant tool inventory management app for construction/field crews. Companies track tools issued to workers, manage shifts with GPS, and operate under subscription tiers.

### State management

No Riverpod/Bloc/Provider. Language selection uses `InheritedNotifier<ValueNotifier<AppLang>>` (`AppState` widget in `main.dart`). All other state is local `StatefulWidget` + `setState`. Firebase calls are made directly inside widgets — there is no service/repository layer.

### `lib/main.dart` — monolithic core

At ~7000 lines, `main.dart` contains the entire application: all pages (LoginPage, SessionChoicePage, ProfileFormPage, JoinCompanyPage, ShiftButton, SitesPage, TimesheetsPage, admin pages, etc.), Firestore query helpers, and the full inline translation table for 21 languages. Changes to page logic, navigation, or translations usually happen here.

Key time-tracking classes (defined in `main.dart`, integrated into `CompanyProfilePage`):
- `ShiftButton` — card shown to all users in the Profile tab to start/end their work shift. Requires at least one `site` document to exist in Firestore.
- `SitesPage` — admin/owner page to manage work sites (objects). Accessible via "Управление объектами" button in Profile tab.
- `TimesheetsPage` — shift history for a company or specific person.

### i18n — two sources

Translations live in **two places**:
- `lib/main.dart` — inline `I18n` class with `_dict` map, used by all main pages. Fallback chain: current lang → Russian → raw key.
- `lib/i18n.dart` — separate dictionary used by newer/split-out pages, with parameterized `tf()` helper

When adding new string keys, add them to **both** files if the feature spans both. `AppLang` enum (21 languages) is the canonical language identifier. All 21 languages must have the key; if omitted, the fallback shows Russian text.

### Firebase / Firestore

**Project:** `tooltrack-ee0aa`. Services: Auth, Firestore, Storage.

Firestore collection layout:
```
users/{uid}                         # user profile, companyId, role
companies/{companyId}/
  people/{personId}                 # name, status (active/fired)
  tools/{toolId}                    # name, inventoryNo, status
  moves/{moveId}                    # issuedAt, returnedAt, toolId, personId
  sites/{siteId}                    # name, address, latitude, longitude, radius
  timesheets/{sheetId}              # personId, personName, siteId, siteName, startTime, endTime, totalHours, workReport
inviteCodes/{code}                  # companyId, expiry
```

### Roles

`owner → admin → foreman → worker` — used in Firestore documents and UI guards. Tool issue/return is restricted to owner/admin/foreman. Site management (`SitesPage`) is restricted to owner/admin. Starting/ending shifts (`ShiftButton`) is available to all roles.

### Billing tiers (`lib/billing/plans.dart`)

Six tiers (Free/Basic/Pro/Business/Enterprise/Enterprise+) with people-count limits (3/10/20/50/100/500) and PLN/month pricing. Plan enforcement is checked against `companies/{companyId}.plan` in Firestore.

### Platforms

Supported: Android, Windows, Web, iOS. Android Firebase config is `android/app/google-services.json`; iOS config is `ios/Runner/GoogleService-Info.plist`. iOS build/release uses GitHub Actions workflow `.github/workflows/ios-appstore.yml` exclusively (Bitrise and Codemagic are no longer used, out of credits). See `README.md` for full iOS build history, critical rules, and current status.
