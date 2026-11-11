# OTA Setup (Shorebird)

This app now includes runtime OTA patch checks via `shorebird_code_push`.

## What Is Implemented

- Startup checks for OTA patch availability.
- If a patch is available, it is downloaded automatically.
- Patch is applied on next app restart.
- Check runs on `SplashScreen` before navigation to login/dashboard.
- Drivers are shown an in-app "Update ready" dialog and the app closes automatically to enforce restart when a patch is pending.
- OTA check includes timeout protection to avoid blocking startup on poor internet.
- API layer includes request timeouts and safe retry for idempotent GET requests.
- Global crash guards are enabled in `main.dart` to capture uncaught async/platform errors.

Code references:
- `lib/services/ota_update_service.dart`
- `lib/screens/splash_screen.dart`
- `lib/services/api_service.dart`
- `lib/main.dart`

## One-Time Setup (Developer Machine)

0. Verify Flutter and project dependencies:

```bash
flutter --version
flutter doctor -v
cd driver_app
flutter pub get
```

1. Install Shorebird CLI (use the official instructions for your OS):

- Docs: `https://docs.shorebird.dev/code-push/initialize/`
- For Windows, follow the Windows install steps from that page.

2. Login:

```bash
shorebird login
```

3. Initialize this app (creates `shorebird.yaml`):

```bash
cd driver_app
shorebird init
```

## First OTA-Capable Build (Release)

Create a release build through Shorebird and distribute it to drivers:

```bash
shorebird release android
```

Important: drivers must install a Shorebird-built release once before they can receive OTA patches.

## Publish OTA Patches After Dart Code Fixes

After changing Dart-only code, publish patch:

```bash
shorebird patch android
```

Drivers receive the patch automatically (download on launch, apply next restart).

## When OTA Will NOT Work

You must ship a new APK/AAB (new release) for:
- Native Android changes (`android/`, Gradle, Manifest, permissions)
- Plugin changes requiring native code updates
- Asset-only changes (images/fonts)
- Flutter engine/version changes

## Recommended Team Flow

1. Backend bug: deploy backend only.
2. Dart/UI bug: `shorebird patch android`.
3. Native or manifest change: `shorebird release android` and share new APK/AAB.
