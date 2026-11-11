import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

import 'log_redactor.dart';

enum OtaCheckResult {
  upToDate,
  restartRequired,
  unavailable,
  failed,
}

class OtaUpdateService {
  OtaUpdateService._();

  static final OtaUpdateService instance = OtaUpdateService._();

  final ShorebirdUpdater _updater = ShorebirdUpdater();
  final ValueNotifier<bool> restartRequired = ValueNotifier<bool>(false);

  bool _checkInProgress = false;
  Future<OtaCheckResult>? _ongoingCheck;

  Future<OtaCheckResult> checkAndDownloadUpdate({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (_ongoingCheck != null) {
      return _ongoingCheck!;
    }

    final run = _runCheck(timeout: timeout);
    _ongoingCheck = run;
    try {
      return await run;
    } finally {
      _ongoingCheck = null;
    }
  }

  Future<OtaCheckResult> _runCheck({
    required Duration timeout,
  }) async {
    if (_checkInProgress) return OtaCheckResult.failed;
    _checkInProgress = true;

    if (!_updater.isAvailable) {
      debugPrint('OTA updater unavailable in this build.');
      restartRequired.value = false;
      _checkInProgress = false;
      return OtaCheckResult.unavailable;
    }

    try {
      final status = await _updater.checkForUpdate().timeout(timeout);

      switch (status) {
        case UpdateStatus.outdated:
          await _updater.update().timeout(timeout);
          restartRequired.value = true;
          debugPrint('OTA patch downloaded. Restart app to apply patch.');
          return OtaCheckResult.restartRequired;
        case UpdateStatus.restartRequired:
          restartRequired.value = true;
          debugPrint('OTA patch already downloaded. Restart required.');
          return OtaCheckResult.restartRequired;
        case UpdateStatus.upToDate:
          restartRequired.value = false;
          debugPrint('OTA check: app is up to date.');
          return OtaCheckResult.upToDate;
        case UpdateStatus.unavailable:
          restartRequired.value = false;
          debugPrint('OTA check unavailable for this build.');
          return OtaCheckResult.unavailable;
      }
    } on TimeoutException {
      restartRequired.value = false;
      debugPrint('OTA update timed out. Continuing app startup.');
      return OtaCheckResult.failed;
    } on UpdateException catch (e) {
      debugPrint('OTA update failed: ${LogRedactor.sanitizeText(e.message)}');
      restartRequired.value = false;
      return OtaCheckResult.failed;
    } catch (e, stack) {
      debugPrint('OTA update check crashed: ${LogRedactor.sanitizeText(e)}');
      debugPrint(LogRedactor.sanitizeText(stack.toString(), maxChars: 1200));
      restartRequired.value = false;
      return OtaCheckResult.failed;
    } finally {
      _checkInProgress = false;
    }
  }
}
