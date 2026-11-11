import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Firebase options for this app.
///
/// Android and iOS values are configured for project `my-company-driver-prod`.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Firebase web options are not configured for this project.');
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError('Firebase options are not configured for this platform.');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBSTFrFcmwVqxl4FYQjdf3s-QKoJ6Ye6Ug',
    appId: '1:702181048114:android:8a40929b6dbe08dd62612b',
    messagingSenderId: '702181048114',
    projectId: 'my-company-driver-prod',
    storageBucket: 'my-company-driver-prod.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBAFAKh3Yg-ueVaFpH3DI2Suif-1Nze5a4',
    appId: '1:702181048114:ios:cbf6066e6b75984962612b',
    messagingSenderId: '702181048114',
    projectId: 'my-company-driver-prod',
    storageBucket: 'my-company-driver-prod.firebasestorage.app',
    iosBundleId: 'com.ilabinformationtechnology.driver',
  );

}