# iOS Widget Setup Status

This document tracks the remaining setup steps required in the Apple Developer Portal to finish enabling the ShiftWidget home-screen widget. All code, Xcode project wiring, and the GitHub Actions workflow have already been completed and committed to `main`.

## Already done (code side)

- Created `ios/ShiftWidgetExtension/ShiftWidget.swift` (WidgetKit + SwiftUI widget reading shift status from an App Group).
- Created `ios/ShiftWidgetExtension/Info.plist` and `ios/ShiftWidgetExtension/ShiftWidgetExtension.entitlements`.
- Added the App Group entitlement to `ios/Runner/Runner.entitlements`.
- Registered a new `ShiftWidgetExtension` target in `ios/Runner.xcodeproj/project.pbxproj`, linked as a dependency of the `Runner` target and embedded via an "Embed Foundation Extensions" build phase.
- Updated `.github/workflows/ios-appstore.yml` to install a widget-specific provisioning profile and inject it into the export options plist during the Export IPA step.

## Steps you need to complete in the Apple Developer Portal

### 1. Create the App Group

- Go to Certificates, Identifiers & Profiles > Identifiers > App Groups.
- Create a new App Group with identifier `group.com.toolkeeper.app.widget`.

### 2. Register the widget extension App ID

- Create a new App ID with bundle identifier `com.toolkeeper.app.ShiftWidget`.
- Enable the App Groups capability on this App ID and assign it to the group created in step 1.
- Also enable App Groups on the main `com.toolkeeper.app` App ID and assign it to the same group.

### 3. Create the distribution provisioning profile

- Create a new App Store distribution provisioning profile for the `com.toolkeeper.app.ShiftWidget` App ID.
- Name it exactly `ToolKeeper Widget App Store` (this exact name is already referenced in the Xcode project build settings).
- Download the generated `.mobileprovision` file.

### 4. Add the profile as a GitHub secret

- Base64-encode the downloaded `.mobileprovision` file.
- Add it to the repository as a GitHub Actions secret named `WIDGET_BUILD_PROVISION_PROFILE_BASE64` (Settings > Secrets and variables > Actions).

### 5. Verify in Xcode (recommended)

Since the new target was added by direct edits to `project.pbxproj` rather than through Xcode's UI, it is strongly recommended to open the project in Xcode at least once, confirm the `ShiftWidgetExtension` target builds and appears correctly in the target list, and resolve any signing prompts before relying on the CI workflow.

Once steps 1-4 are complete, the `ios-appstore.yml` workflow will automatically sign and embed the widget when building the App Store release.
