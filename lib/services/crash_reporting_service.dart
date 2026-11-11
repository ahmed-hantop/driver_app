import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import '../firebase_options.dart';
import 'log_redactor.dart';

class CrashReportingService {
  CrashReportingService._();

  static final CrashReportingService instance = CrashReportingService._();

  bool _enabled = false;

  bool _hasPlaceholderOptions(FirebaseOptions options) {
    return options.projectId.startsWith('REPLACE_WITH_');
  }

  bool get isEnabled => _enabled;

  Future<void> initialize() async {
    try {
      final options = DefaultFirebaseOptions.currentPlatform;
      if (_hasPlaceholderOptions(options)) {
        _enabled = false;
        debugPrint('Firebase options placeholder detected. Run `flutterfire configure` to enable Crashlytics.');
        return;
      }

      await Firebase.initializeApp(
        options: options,
      );
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(kReleaseMode);
      _enabled = true;
      debugPrint('Crashlytics initialized (enabled: $kReleaseMode).');
    } catch (e, stack) {
      _enabled = false;
      debugPrint('Crashlytics initialization skipped: ${LogRedactor.sanitizeText(e)}');
      debugPrint(LogRedactor.sanitizeText(stack.toString(), maxChars: 1200));
    }
  }

  Future<void> recordError(
    Object error,
    StackTrace stack, {
    String reason = 'Unhandled error',
    bool fatal = false,
  }) async {
    final sanitizedError = LogRedactor.sanitizeText(error);
    final sanitizedStack = StackTrace.fromString(
      LogRedactor.sanitizeText(stack.toString(), maxChars: 4000),
    );

    if (!_enabled) {
      debugPrint('Crashlytics disabled. Error: $sanitizedError');
      return;
    }

    await FirebaseCrashlytics.instance.recordError(
      sanitizedError,
      sanitizedStack,
      reason: reason,
      fatal: fatal,
    );
  }

  Future<void> recordFlutterError(FlutterErrorDetails details) async {
    final sanitizedException = LogRedactor.sanitizeText(details.exceptionAsString());
    final sanitizedStack = StackTrace.fromString(
      LogRedactor.sanitizeText(
        (details.stack ?? StackTrace.current).toString(),
        maxChars: 4000,
      ),
    );

    if (!_enabled) {
      debugPrint('Crashlytics disabled. Flutter error: $sanitizedException');
      return;
    }

    await FirebaseCrashlytics.instance.recordError(
      sanitizedException,
      sanitizedStack,
      reason: details.library ?? 'FlutterError',
      fatal: true,
    );
  }
}
