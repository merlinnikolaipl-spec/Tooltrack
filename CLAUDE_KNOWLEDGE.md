# CLAUDE KNOWLEDGE BASE — Tooltrack / ToolKeeper iOS App

> **Purpose:** This file preserves all critical knowledge for Claude AI so it can resume work in a new chat session without losing context.  
> **Last Updated:** Build #59 SUCCEEDED ✅ — App uploaded to TestFlight

---

## 1. PROJECT OVERVIEW

- **GitHub Repo:** `merlinnikolaipl-spec/Tooltrack`
- **App Name (App Store Connect):** ToolKeeper
- **Bundle ID:** `com.toolkeeper.app`
- **Apple Team ID:** `VHF76Z663B`
- **Framework:** Flutter 3.29.2
- **macOS Runner:** `macos-15`
- **Xcode:** `latest` via `maxim-lobanov/setup-xcode@v1` (currently Xcode 26.3)
- **Workflow file:** `.github/workflows/ios-appstore.yml`

---

## 2. USER GOAL (ORIGINAL INSTRUCTIONS)

1. **"собираем приложение на iOS и загружаем в абстор"** — Build iOS app and upload to App Store
2. **"давай мне нужно его загрузить в абстор сначала протестить и потом в абстор"** — Upload to **TestFlight FIRST** for testing, THEN App Store
3. **"делай пока не будет готово"** — Keep going until it's completely done. Do not stop.

**Current Status:** TestFlight upload COMPLETE ✅ (Build #59)  
**Next Step:** Test app via TestFlight → Submit to App Store

---

## 3. GITHUB SECRETS (exact names)

| Secret Name | Value / Description |
|-------------|---------------------|
| `BUILD_CERTIFICATE_BASE64` | Base64-encoded .p12 distribution certificate |
| `P12_PASSWORD` | Password for the .p12 certificate |
| `BUILD_PROVISION_PROFILE_BASE64` | Base64-encoded provisioning profile |
| `KEYCHAIN_PASSWORD` | Any secure password for temp keychain |
| `GOOGLE_SERVICE_INFO_PLIST` | Full contents of GoogleService-Info.plist |
| `ASC_PRIVATE_KEY` | Base64-encoded App Store Connect API key (.p8) |
| `ASC_KEY_ID` | `CACM4VT79N` |
| `ASC_ISSUER_ID` | `84281d71-d333-4cf7-8580-3771c0b45e85` |

---

## 4. APP SIGNING DETAILS

- **Provisioning Profile Name:** `ToolKeeper App Store`
- **Provisioning Profile UUID:** `7df51f68-589d-481d-aea3-7fc74f529c37`
- **Code Sign Identity:** `iPhone Distribution`
- **Code Sign Style:** `Manual`

---

## 5. CRITICAL RULES & CONSTRAINTS

### DO NOT:
- DO NOT use Bitrise (credits exhausted until July 11, 2026)
- DO NOT use Codemagic (only 7 min left)
- DO NOT use `document.execCommand('selectAll')` or ClipboardEvent paste — UNRELIABLE
- DO NOT use `| head -n 2000` pipe on xcodebuild — kills xcodebuild via SIGPIPE
- DO NOT use `|| true` with pipelines when checking PIPESTATUS — resets PIPESTATUS to 0

### MUST:
- MUST use **CM6 dispatch method** to edit files:
  ```js
  document.querySelector('.cm-content').cmTile.view.dispatch({changes: {from:0, to:state.doc.length, insert:yaml}})
  ```
- MUST use `cat > ios/Podfile << 'PODEOF'` heredoc approach for Podfile
- MUST set `CODE_SIGN_IDENTITY = ''`, `CODE_SIGNING_REQUIRED = 'NO'`, `CODE_SIGNING_ALLOWED = 'NO'` for ALL Pods targets
- MUST set `CODE_SIGN_STYLE=Manual` and `DEVELOPMENT_TEAM=VHF76Z663B` in pbxproj for Runner
- MUST pass `PROVISIONING_PROFILE="$PP_UUID"` in xcodebuild command
- MUST use tee approach: `2>&1 | tee /tmp/xcodebuild.log | grep -E "..."`
- MUST check `BUILD_RESULT=${PIPESTATUS[0]}` (with NO `|| true` after pipeline)
- MUST show `tail -200 /tmp/xcodebuild.log` on build failure

---

## 6. PUBSPEC OVERRIDES (required in pubspec_overrides.yaml)

```yaml
dependency_overrides:
  win32: 5.5.4
  pdf_widget_wrapper: 1.0.4
  mobile_scanner: 5.2.3
```

---

## 7. WORKING PODFILE (post_install block)

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

---

## 8. WORKING XCODEBUILD COMMAND

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

---

## 9. WORKING TESTFLIGHT UPLOAD STEP

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

**KEY:** altool requires the key file to be named `AuthKey_KEYID.p8` in `~/.appstoreconnect/private_keys/` — NOT an arbitrary path!

---

## 10. ERRORS & FIXES HISTORY

| Build | Error | Root Cause | Fix |
|-------|-------|------------|-----|
| #50–56 | `firebase_auth` PrecompileModule: non-modular header | `CLANG_WARN_NON_MODULAR_INCLUDE_IN_FRAMEWORK_MODULE = YES_ERROR` in pbxproj; Xcode 26 Explicit Modules pass `-Werror=non-modular` to clang | Patch BOTH `Pods.xcodeproj/project.pbxproj` AND `Runner.xcodeproj/project.pbxproj` with sed regex `YES[A-Z_]*`; Podfile OTHER_CFLAGS -Wno-everything |
| #57 | No profile matching 'ToolKeeper Distribution' | Runner.xcodeproj has wrong `PROVISIONING_PROFILE_SPECIFIER = "ToolKeeper Distribution"` | sed to change "Distribution" → "App Store" in pbxproj; add PROVISIONING_PROFILE_SPECIFIER to xcodebuild |
| #58 | `Failed to load AuthKey file. (-43)` | altool requires `AuthKey_KEYID.p8` in `~/.appstoreconnect/private_keys/` not arbitrary path | Save key to `~/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8` |
| **#59** | **NONE — FULL SUCCESS ✅** | — | — |

### Critical Technical Discoveries:
1. Xcode 26 (macos-15) uses **Explicit Module Builds** — passes `-Werror=non-modular-include-in-framework-module` directly to clang
2. Flag comes from BOTH `Pods.xcodeproj/project.pbxproj` AND `Runner.xcodeproj/project.pbxproj`
3. `CLANG_WARN_NON_MODULAR_INCLUDE_IN_FRAMEWORK_MODULE` stored as `YES_ERROR` — sed regex `YES[A-Z_]*` needed
4. altool has strict file naming: `AuthKey_KEYID.p8` in `~/.appstoreconnect/private_keys/`
5. `firebase_storage` fixed by xcconfig patches; `firebase_auth` required pbxproj fix

---

## 11. WORKFLOW ITERATION METHOD (for Claude)

1. Navigate to: `https://github.com/merlinnikolaipl-spec/Tooltrack/edit/main/.github/workflows/ios-appstore.yml`
2. Wait for `.cm-content` element to load
3. Use CM6 dispatch to replace content:
   ```js
   const el = document.querySelector('.cm-content');
   const view = el.cmTile.view;
   const state = view.state;
   view.dispatch({changes: {from: 0, to: state.doc.length, insert: YAML_CONTENT}});
   ```
4. Verify with: `view.state.doc.toString().substring(0, 100)`
5. Click "Commit changes..." → update message → "Commit changes" (green button)
6. Navigate to Actions → Run workflow → Run workflow
7. Monitor `build_ios` job
8. On failure: get logs via JS `document.body.innerText`, analyze, fix, repeat

---

## 12. BUILD HISTORY SUMMARY

| Platform | Builds | Result |
|----------|--------|--------|
| Bitrise | 53 builds | ❌ Credits exhausted (until July 11, 2026) |
| Codemagic | Multiple | ❌ Only 7 min left |
| **GitHub Actions** | **#1–59** | **✅ Build #59 SUCCEEDED** |

**Build #59 timing:**
- Build and archive: 11m 44s ✅
- Export IPA: 24s ✅ (ToolKeeper.ipa, 53MB / 55,725,455 bytes)
- Upload to TestFlight: 1m 55s ✅
- **Total: 19m 18s** ✅

**Working commit:** `e9ea20d` — "Build #59: Fix altool AuthKey path"  
**Actions URL:** `https://github.com/merlinnikolaipl-spec/Tooltrack/actions/runs/27632190785/job/81709866658`

---

## 13. NEXT STEPS

1. **Check App Store Connect → TestFlight** for new ToolKeeper build (10-30 min for Apple processing)
2. **Test app** on physical iOS device via TestFlight
3. **Submit to App Store** when testing is complete

For App Store submission, the workflow already uses `method: app-store-connect` in ExportOptions.plist — just need to update version/build number for each new submission.

---

## 14. PLATFORMS STATUS

- **GitHub Actions:** ✅ Working — use `.github/workflows/ios-appstore.yml`
- **Bitrise:** ❌ Credits exhausted — DO NOT USE until July 11, 2026
- **Codemagic:** ❌ Only 7 min remaining — DO NOT USE
