# Crashlytics Setup

This app is now wired to report uncaught errors via Firebase Crashlytics.

Implemented code:
- `lib/services/crash_reporting_service.dart`
- `lib/main.dart`
- `android/settings.gradle.kts`
- `android/app/build.gradle.kts`

## Current Behavior

- App initializes Firebase at startup using `DefaultFirebaseOptions.currentPlatform`.
- `lib/firebase_options.dart` currently contains placeholders so the app remains buildable until `flutterfire configure` is executed.
- If Firebase config is missing, app continues without crashing and logs a message.
- Global uncaught errors are captured from:
  - `FlutterError.onError`
  - `PlatformDispatcher.instance.onError`
  - `runZonedGuarded`

## Configured In This Workspace

- Firebase project: `my-company-driver-prod`
- Android app package: `com.ilabinformationtechnology.driver`
- Firebase Android App ID: `1:702181048114:android:8a40929b6dbe08dd62612b`
- iOS bundle ID: `com.example.driverApp`
- Firebase iOS App ID: `1:702181048114:ios:cbf6066e6b75984962612b`
- Generated files:
  - `lib/firebase_options.dart` (Android + iOS configured)
  - `android/app/google-services.json`
  - `ios/Runner/GoogleService-Info.plist`

## Required Firebase Project Setup

## 1. Install tooling

```bash
dart pub global activate flutterfire_cli
```

Ensure Firebase CLI is installed and logged in:

```bash
npm install -g firebase-tools
firebase login
```

## 2. Configure Firebase for this app

From `driver_app` root:

```bash
flutterfire configure --project <YOUR_FIREBASE_PROJECT_ID> --platforms=android,ios
```

Use Android package name:
- `com.ilabinformationtechnology.driver`

This command generates:
- `lib/firebase_options.dart`
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist` (if iOS selected)

## 3. Fetch packages

```bash
flutter pub get
```

## 4. Build and test crash reporting (release/profile)

Crashlytics collection is enabled for release mode only.

To force a test crash after setup, temporarily add:

```dart
FirebaseCrashlytics.instance.crash();
```

Then run a release/profile build and verify event appears in Firebase Crashlytics dashboard.

## Notes

- Enable Windows Developer Mode for plugin symlink support:
  - Run: `start ms-settings:developers`
- If `android/local.properties` is missing, create it with:
  - `flutter.sdk=C:\\Users\\uaqx1\\Downloads\\Compressed\\flutter_windows_3.41.4-stable\\flutter`
- Android SDK is currently missing on this machine (`flutter doctor` warning). Install Android Studio/SDK and set `flutter config --android-sdk <path>` if needed.
- You should enable symbol/mapping upload in CI for best stack traces in release builds.
