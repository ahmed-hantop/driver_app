# iOS Release Steps

The Flutter iOS project is prepared in `ios/`, but the final `.ipa` must be built on macOS with Xcode.

## 1. Prepare the Mac

Install:

- Xcode from the Mac App Store
- Flutter stable
- CocoaPods

Then, from this folder:

```sh
flutter pub get
cd ios
pod install
cd ..
```

Open the workspace, not the project:

```sh
open ios/Runner.xcworkspace
```

## 2. Set Apple Signing

In Xcode:

- Select `Runner`
- Open `Signing & Capabilities`
- Select your Apple Developer Team
- Confirm the bundle identifier is `com.ilabinformationtechnology.driver`

## 3. Regenerate Firebase iOS Config

The current Firebase iOS config still points to `com.example.driverApp`.

Before release:

- Create an iOS app in Firebase using bundle id `com.ilabinformationtechnology.driver`
- Replace `ios/Runner/GoogleService-Info.plist`
- Regenerate `lib/firebase_options.dart` with FlutterFire if Crashlytics should work on iOS

## 4. Build for TestFlight/App Store

From the Mac:

```sh
flutter build ipa --release --build-name=1.0.5 --build-number=6
```

Upload the archive with Xcode Organizer or Transporter.

## Note on Background Location

The current iOS path uses foreground location polling. Full background location on iOS needs Apple-reviewed background location capability, `Always` location permission flow, and a clear App Review explanation.
