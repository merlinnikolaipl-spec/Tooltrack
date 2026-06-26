# CLAUDE KNOWLEDGE BASE — Tooltrack / ToolKeeper iOS App

Purpose: This file preserves all critical knowledge for Claude AI so it can resume work in a new chat session without losing context.
Last Updated: Build #151 — GPS Firestore timestampValue fix (Jun 26, 2026).

## 1. PROJECT OVERVIEW
GitHub Repo: merlinnikolaipl-spec/Tooltrack
App Name (App Store Connect): ToolKeeper: Учёт инструментов
Bundle ID: com.toolkeeper.app
Apple Team ID: VHF76Z663B
Framework: Flutter 3.29.2
macOS Runner: macos-15
Xcode: latest via maxim-lobanov/setup-xcode@v1 (currently Xcode 26.3)
Workflow file: .github/workflows/ios-appstore.yml
Firebase Project ID: tooltrack-ee0aa

## 2. USER GOAL
- Build iOS app and upload to App Store
- App Store status: Waiting for Review (submitted Jun 2026)
- TestFlight: COMPLETE (Build #123 and later)
- Current app version: 1.1.0+114

## 3. GITHUB SECRETS (exact names)
SECRET NAME / DESCRIPTION
BUILD_CERTIFICATE_BASE64 / Base64-encoded .p12 distribution certificate
P12_PASSWORD / Password for the .p12 certificate
BUILD_PROVISION_PROFILE_BASE64 / Base64-encoded provisioning profile
KEYCHAIN_PASSWORD / Any secure password for temp keychain
GOOGLE_SERVICE_INFO_PLIST / Full contents of GoogleService-Info.plist
ASC_PRIVATE_KEY / Base64-encoded App Store Connect API key (.p8)
ASC_KEY_ID / CACM4VT79N
ASC_ISSUER_ID / 84281d71-d333-4cf7-8580-3771c0b45e85

## 4. APP SIGNING DETAILS
Provisioning Profile Name: ToolKeeper App Store
Provisioning Profile UUID: 7df51f68-589d-481d-aea3-7fc74f529c37
Code Sign Identity: iPhone Distribution
Code Sign Style: Manual

## 5. iOS GOOGLE SIGN-IN SETUP
iOS Client ID: 242560270718-nrq1kk5mg60i7so7li93s7ip8vfa9t6n.apps.googleusercontent.com
REVERSED_CLIENT_ID: com.googleusercontent.apps.242560270718-nrq1kk5mg60i7so7li93s7ip8vfa9t6n
Configured in ios/Runner/Info.plist under CFBundleURLTypes - CFBundleURLSchemes
CRITICAL: Without REVERSED_CLIENT_ID URL scheme in Info.plist, Google Sign-In will CRASH on iOS.

## 6. CRITICAL RULES AND CONSTRAINTS

DO NOT:
- DO NOT use Bitrise (credits exhausted until July 11, 2026)
- DO NOT use Codemagic (only 7 min left)
- DO NOT use pipe head -n 2000 on xcodebuild - kills xcodebuild via SIGPIPE
- DO NOT use || true with pipelines when checking PIPESTATUS - resets PIPESTATUS to 0

MUST:
- MUST use GitHub Actions workflow .github/workflows/ios-appstore.yml
- MUST use CM6 dispatch method to edit files on GitHub web editor
- MUST check BUILD_RESULT equal PIPESTATUS[0] (with NO || true after pipeline)
- MUST show tail -200 /tmp/xcodebuild.log on build failure

## 7. WORKFLOW CRITICAL SHA NOTE
The workflow has step "Restore original main.dart from git history":
  git checkout 2c64927700b7c2c7ed5fb1d017b16c1eb4a867b3 -- lib/main.dart pubspec.yaml

This means the workflow always restores main.dart from SHA 2c64927 before building.
Any changes to main.dart via web editor commits are OVERWRITTEN by the workflow.

THEREFORE: Changes to main.dart must be applied as inline patch steps in the workflow yaml itself (sed/awk),
OR the workflow SHA must be updated to point to the new main.dart commit.

Current workflow restore SHA: 2c64927700b7c2c7ed5fb1d017b16c1eb4a867b3
Latest main.dart web editor commit: d203192 (GPS dialog String timestamp parsing - Build #150)
Latest gps_foreground_service.dart commit: ea27cbd (timestampValue fix - Build #151)

NOTE: gps_foreground_service.dart is NOT restored by the workflow - changes there take effect directly.

## 8. GPS ARCHITECTURE

### GPS Service (lib/gps_foreground_service.dart):
- Uses flutter_background_service + Geolocator
- Writes location data via HTTP REST API v3 directly to Firestore (NOT SDK, NOT Cloud Functions)
- Firestore path: companies/{companyId}/timesheets/{sheetId}/locations/{locId}

### Location document fields:
- lat (number) - NOT latitude
- lng (number) - NOT longitude
- accuracy (number)
- timestamp (timestampValue) - GPS fix time from pos.timestamp
- createdAt (timestampValue) - current write time
- source: "gps_service"

### CRITICAL - createdAt must be timestampValue not stringValue:
Firestore .orderBy() with mixed field types returns ONLY docs matching first doc type.
Old Android SDK records had Timestamp type; GPS service was writing String type.
Result: iOS location docs were completely excluded from query results.
Fix: use timestampValue where value = DateTime.now().toUtc().toIso8601String() (UTC with Z suffix)

### iOS GPS stop: invoke('stopTracking') - NOT invoke('stopService')
### Android GPS stop: invoke('stopService')

### SharedPreferences keys:
- shift_companyId - current shift company ID
- shift_shiftId - current shift timesheet document ID
- shift_gpsInterval - GPS throttle interval in MINUTES (int), default 60

### GPS throttle: reads shift_gpsInterval on service start, writes 1 location per interval

## 9. GPS DIALOG UI (main.dart _showGpsTrack)
- Loads: .collection('locations').orderBy('createdAt').get()
- Parses createdAt - handles BOTH Timestamp and String types (added Build #150):
  if (ts is Timestamp) { dt = ts.toDate(); }
  else if (ts is String) { dt = DateTime.tryParse(ts); }
- Displays: "26.06 16:54 ±16м" format

## 10. FIRESTORE STRUCTURE
companies/{companyId}/
  people/{personId}       - name, status (active/fired)
  tools/{toolId}          - name, inventoryNo, status
  moves/{moveId}          - issuedAt, returnedAt, toolId, personId
  sites/{siteId}          - name, address, latitude, longitude, radius
  timesheets/{sheetId}    - personId, siteId, startTime, endTime, totalHours
    locations/{locId}     - lat, lng, accuracy, timestamp, createdAt, source
ios_debug_logs/{docId}    - platform, tag, ts, message (for iOS GPS debugging)

Composite index required: timesheets - personId ASC + endTime ASC (created Jun 2026)

## 11. BUILD HISTORY
Build 123: First TestFlight upload - DONE
Build 126: Google Sign-In + GPS URL fix + compile errors - DONE
Build 146: GPS field names lat/lng fix - DONE
Build 147: Issue/return spinner fix - DONE
Build 148: iOS GPS throttle + zone exit count fix - DONE
Build 149: iOS shift close stopTracking + prefs cleanup - DONE
Build 150: null-safe pos.timestamp + UI String timestamp parsing - DONE
Build 151: Write createdAt+timestamp as Firestore timestampValue - DONE

## 12. APP ARCHITECTURE
Framework: Flutter 3.29.2
State: No Riverpod/Bloc. Local StatefulWidget + setState.
lib/main.dart: ~11400 lines - ALL pages, 21 languages, Firestore helpers
lib/gps_foreground_service.dart: flutter_background_service + Geolocator + HTTP REST
lib/admin_employee_pages.dart: IssueTab
lib/billing/plans.dart: 6 tiers (Free/Basic/Pro/Business/Enterprise/Enterprise+)
i18n: Two sources: lib/main.dart (I18n class) + lib/i18n.dart

## 13. PUBSPEC OVERRIDES (required in pubspec_overrides.yaml)
dependency_overrides:
  win32: 5.5.4
  pdf_widget_wrapper: 1.0.4
  mobile_scanner: 5.2.3

## 14. KNOWN BUGS AND FIXES

Bug 1: Google Sign-In crash on iOS - FIXED Build 126
  Added REVERSED_CLIENT_ID to CFBundleURLSchemes in Info.plist
  Added googleSignIn.disconnect() before signIn()

Bug 2: GPS not saving data - FIXED Build 126
  Wrong Cloud Functions URL: tooltrack-f5a6a corrected to tooltrack-ee0aa

Bug 3: GPS field names wrong - FIXED Build 146
  Was latitude/longitude, corrected to lat/lng

Bug 4: iOS GPS showing 0.00000 coordinates - FIXED Build 150
  pos.timestamp was null on iOS causing crash
  Fix: (pos.timestamp ?? DateTime.now()).toIso8601String()

Bug 5: iOS GPS no date/time in dialog - FIXED Build 150+151
  GPS service wrote createdAt as stringValue; UI only checked Timestamp type
  Build 150: added String parsing branch in UI
  Build 151: changed to write as timestampValue so orderBy works correctly

Bug 6: iOS shift not stopping properly - FIXED Build 149
  Must use invoke('stopTracking') on iOS (not 'stopService')
  Must clear SharedPrefs after stopping shift

Bug 7: Mikalai Shklioda showing 2203 zone exits
  Old data in Firestore from before GPS fixes - expected, new shifts will be correct

## 15. NEXT STEPS (as of Build 151)
1. User tests Build 151 on iOS TestFlight
2. Verify: new iOS shifts show date/time in GPS dialog (26.06 16:54 format)
3. Only NEW records after installing Build 151 will have correct Timestamp type
4. Wait for App Store review result
