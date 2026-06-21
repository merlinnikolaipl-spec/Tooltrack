# CLAUDE KNOWLEDGE BASE — Tooltrack / ToolKeeper iOS App

Purpose: This file preserves all critical knowledge for Claude AI so it can resume work in a new chat session without losing context.
Last Updated: Build #123 SUCCEEDED ✅ — App running on TestFlight. Bug fixes applied (Jun 21, 2026).

## 1. PROJECT OVERVIEW
GitHub Repo: merlinnikolaipl-spec/Tooltrack
App Name (App Store Connect): ToolKeeper
Bundle ID: com.toolkeeper.app
Apple Team ID: VHF76Z663B
Framework: Flutter 3.29.2
macOS Runner: macos-15
Xcode: latest via maxim-lobanov/setup-xcode@v1 (currently Xcode 26.3)
Workflow file: .github/workflows/ios-appstore.yml
Firebase Project ID: tooltrack-ee0aa

## 2. USER GOAL
- Build iOS app and upload to App Store
- Upload to TestFlight FIRST for testing, THEN App Store
- TestFlight upload COMPLETE ✅ (Build #123)
- Current app version: 1.1.0+114

## 3. GITHUB SECRETS (exact names)
| Secret Name | Description |
|---|---|
| BUILD_CERTIFICATE_BASE64 | Base64-encoded .p12 distribution certificate |
| P12_PASSWORD | Password for the .p12 certificate |
| BUILD_PROVISION_PROFILE_BASE64 | Base64-encoded provisioning profile |
| KEYCHAIN_PASSWORD | Any secure password for temp keychain |
| GOOGLE_SERVICE_INFO_PLIST | Full contents of GoogleService-Info.plist |
| ASC_PRIVATE_KEY | Base64-encoded App Store Connect API key (.p8) |
| ASC_KEY_ID | CACM4VT79N |
| ASC_ISSUER_ID | 84281d71-d333-4cf7-8580-3771c0b45e85 |

## 4. APP SIGNING DETAILS
Provisioning Profile Name: ToolKeeper App Store
Provisioning Profile UUID: 7df51f68-589d-481d-aea3-7fc74f529c37
Code Sign Identity: iPhone Distribution
Code Sign Style: Manual

## 5. iOS GOOGLE SIGN-IN SETUP
iOS Client ID: 242560270718-nrq1kk5mg60i7so7li93s7ip8vfa9t6n.apps.googleusercontent.com
REVERSED_CLIENT_ID (URL scheme): com.googleusercontent.apps.242560270718-nrq1kk5mg60i7so7li93s7ip8vfa9t6n
This is configured in ios/Runner/Info.plist under CFBundleURLTypes → CFBundleURLSchemes

CRITICAL: Without the REVERSED_CLIENT_ID URL scheme in Info.plist, Google Sign-In will CRASH on iOS.
The AppDelegate.swift has: GIDSignIn.sharedInstance.handle(url) — this requires the URL scheme to work.

## 6. KNOWN BUGS & FIXES (Jun 21, 2026)

### Bug 1: Google Sign-In crashes on iOS ✅ FIXED
**Root cause:** Missing REVERSED_CLIENT_ID URL scheme in Info.plist + not calling disconnect() before signIn()
**Fix applied:**
- Added CFBundleURLSchemes with com.googleusercontent.apps.242560270718-nrq1kk5mg60i7so7li93s7ip8vfa9t6n to ios/Runner/Info.plist
- Added `try { await googleSignIn.disconnect(); } catch (_) {}` before signOut() in the Google auth flow in main.dart

### Bug 2: GPS tracking not saving data ✅ FIXED
**Root cause:** gps_foreground_service.dart was calling Cloud Functions at WRONG Firebase project URL:
`https://us-central1-tooltrack-f5a6a.cloudfunctions.net/updateGpsLocation`
**Fix applied:** Changed to correct project ID:
`https://us-central1-tooltrack-ee0aa.cloudfunctions.net/updateGpsLocation`

### Bug 3: PDF/Excel reports show hieroglyphs (Cyrillic broken) ✅ PRESENT IN CODE
**Root cause:** iOS doesn't have system fonts with Cyrillic support. The pdf package falls back to a Latin font.
**Fix already in code:** _pdfTheme() function uses rootBundle.load('assets/fonts/Roboto-Regular.ttf')
The Roboto font IS included in assets/fonts/ and declared in pubspec.yaml.
If still showing hieroglyphs - check that excel package uses same font.
Note: excel package was REMOVED (import commented out) due to Border conflict. Excel reports may not work.

## 7. CRITICAL RULES & CONSTRAINTS
DO NOT:
- DO NOT use Bitrise (credits exhausted until July 11, 2026)
- DO NOT use Codemagic (only 7 min left)
- DO NOT use | head -n 2000 pipe on xcodebuild — kills xcodebuild via SIGPIPE
- DO NOT use || true with pipelines when checking PIPESTATUS — resets PIPESTATUS to 0

MUST:
- MUST use CM6 dispatch method to edit files on GitHub web editor
- MUST use cat > ios/Podfile << 'PODEOF' heredoc approach for Podfile
- MUST check BUILD_RESULT=${PIPESTATUS[0]} (with NO || true after pipeline)
- MUST show tail -200 /tmp/xcodebuild.log on build failure

## 8. PUBSPEC OVERRIDES (required in pubspec_overrides.yaml)
```yaml
dependency_overrides:
  win32: 5.5.4
  pdf_widget_wrapper: 1.0.4
  mobile_scanner: 5.2.3
```

## 9. WORKING PODFILE (post_install block)
```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
      config.build_settings['CODE_SIGN_IDENTITY'] = ''
      config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
      config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
      config.build_settings['GCC_TREAT_WARNINGS_AS_ERRORS'] = 'NO'
      config.build_settings['SWIFT_TREAT_WARNINGS_AS_ERRORS'] = 'NO'
      config.build_settings['GCC_WARN_INHIBIT_ALL_WARNINGS'] = 'YES'
      config.build_settings['CLANG_WARN_NON_MODULAR_INCLUDE_IN_FRAMEWORK_MODULE'] = 'NO'
      config.build_settings['CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES'] = 'YES'
      config.build_settings['OTHER_CFLAGS'] = '$(inherited) -Wno-everything'
      config.build_settings['OTHER_CPLUSPLUSFLAGS'] = '$(inherited) -Wno-everything'
      config.build_settings['WARNING_CFLAGS'] = ''
    end
  end
end
```

## 10. WORKING XCODEBUILD COMMAND
```bash
xcodebuild archive \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -archivePath /tmp/Runner.xcarchive \
  -sdk iphoneos \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=VHF76Z663B \
  PROVISIONING_PROFILE="$PP_UUID" \
  PROVISIONING_PROFILE_SPECIFIER="ToolKeeper App Store" \
  CODE_SIGN_IDENTITY="iPhone Distribution" \
  CLANG_WARN_NON_MODULAR_INCLUDE_IN_FRAMEWORK_MODULE=NO \
  CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES=YES \
  GCC_TREAT_WARNINGS_AS_ERRORS=NO \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=NO \
  GCC_WARN_INHIBIT_ALL_WARNINGS=YES \
  COMPILER_INDEX_STORE_ENABLE=NO
```

## 11. WORKING TESTFLIGHT UPLOAD STEP
```bash
mkdir -p ~/.appstoreconnect/private_keys
echo -n "$ASC_PRIVATE_KEY" | base64 --decode > ~/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8
IPA_PATH=$(find /tmp/Runner_export -name "*.ipa" | head -1)
xcrun altool --upload-app \
  --type ios \
  --file "$IPA_PATH" \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID" \
  2>&1 | tee /tmp/upload.log
```
KEY: altool requires the key file to be named AuthKey_KEYID.p8 in ~/.appstoreconnect/private_keys/

## 12. APP ARCHITECTURE
- **Framework:** Flutter 3.29.2
- **State management:** No Riverpod/Bloc. Local StatefulWidget + setState.
- **Main file:** lib/main.dart (~11400 lines) — contains ALL pages, translations (21 languages), Firestore helpers
- **GPS tracking:** lib/gps_foreground_service.dart — uses flutter_background_service + Geolocator, posts to Cloud Functions
- **Admin pages:** lib/admin_employee_pages.dart — IssueTab
- **Billing:** lib/billing/plans.dart — 6 tiers
- **i18n:** Two sources: lib/main.dart (I18n class) + lib/i18n.dart

## 13. FIRESTORE STRUCTURE
```
users/{uid}                    # user profile, companyId, role
companies/{companyId}/
  people/{personId}            # name, status (active/fired)
  tools/{toolId}               # name, inventoryNo, status
  moves/{moveId}               # issuedAt, returnedAt, toolId, personId
  sites/{siteId}               # name, address, latitude, longitude, radius
  timesheets/{sheetId}         # personId, siteId, startTime, endTime, totalHours
  inviteCodes/{code}           # companyId, expiry
```

## 14. BUILD HISTORY SUMMARY
| Platform | Status |
|---|---|
| GitHub Actions | ✅ Working — use .github/workflows/ios-appstore.yml |
| Bitrise | ❌ Credits exhausted until July 11, 2026 |
| Codemagic | ❌ Only 7 min remaining |

Latest successful build: #123 (8m 1s) — Jun 21, 2026

## 15. NEXT STEPS
1. Run new build (#124) to include bug fixes
2. Test on TestFlight: Google Sign-In, GPS tracking, PDF reports
3. Submit to App Store when testing passes
