# driver_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Performance Notes

- The app defaults to battery-saver tracking mode on Android to reduce CPU/GPS/network load.
- Live tracking can still be enabled from the profile tab when needed.
- Background location uploads now apply adaptive backoff during network failures.

## Smaller Android Builds

Use one of these release options to reduce download/install size:

1. Preferred for Play Store:

```bash
flutter build appbundle --release
```

2. For direct APK distribution (per-ABI split APKs):

```bash
flutter build apk --release --split-per-abi
```

Pass runtime API targets with `--dart-define` when you need non-production environments:

```bash
flutter run --dart-define=API_BASE_URL=https://example.com/api/v1 --dart-define=PUBLIC_BASE_URL=https://example.com --dart-define=PUBLIC_HOST=example.com
```

Configure release signing from a path outside the repo before building releases:

```bash
$env:DRIVER_APP_KEY_PROPERTIES="C:\secure\driver_app\key.properties"
flutter build appbundle --release
```

The external `key.properties` file should point `storeFile` at an absolute keystore path outside the repository.

Release binaries should be published through CI artifacts, GitHub Releases, or the Play Console instead of being committed under `releases/`.

The Android project is configured with:
- R8 minification (`isMinifyEnabled=true`)
- Resource shrinking (`isShrinkResources=true`)
- ABI splits (no universal APK)

## Dependency Upgrade Status

Validated on Flutter 3.41.9 and Dart 3.11.5.

The app is currently on the newest resolvable package set for this toolchain.

- `package_info_plus` remains on `9.0.1` because `10.x` requires `win32 ^6`, while the current stable `file_picker 11.x` line still depends on `win32 ^5`.
- `matcher` and `test_api` are managed transitively by `flutter_test` and should not be pinned directly in `pubspec.yaml`.
- Updating the stable SDK from Flutter `3.41.4` to `3.41.9` did not unlock any newer resolvable package versions for this app.
- The remaining outdated packages shown by `flutter pub outdated` are transitive and cannot be moved further without upstream package releases or a newer Flutter SDK test stack.
