import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_constants.dart';
import 'log_redactor.dart';
import 'network_client.dart';
import '../l10n/app_localization_helper.dart';

class AppUpdateDecision {
  const AppUpdateDecision({
    required this.mustUpdate,
    required this.message,
    required this.updateUrl,
    required this.latestVersion,
    required this.currentVersion,
  });

  final bool mustUpdate;
  final String message;
  final String updateUrl;
  final String latestVersion;
  final String currentVersion;
}

class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  static const Duration _timeout = Duration(seconds: 12);
  static const String _cachedPolicyKey = 'driver_app_version_policy_v1';
  static const Set<String> _allowedStoreHosts = {
    'play.google.com',
    'market.android.com',
    'apps.apple.com',
    'itunes.apple.com',
  };

  Future<AppUpdateDecision> checkForRequiredUpdate() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version.trim();

    try {
      final uri = Uri.parse(ApiConstants.baseUrl + ApiConstants.appVersionPolicy);
      final response = await DriverAppHttpClient.client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final policy = _extractPolicy(response.body);
        await _cachePolicy(policy);
        return _decisionFromPolicy(currentVersion, policy);
      }

      if (kDebugMode) {
        debugPrint('Forced update policy request failed with status ${response.statusCode}. Falling back to cache.');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Forced update check failed: ${LogRedactor.sanitizeText(e)}');
      }
    }

    final cachedPolicy = await _loadCachedPolicy();
    if (cachedPolicy != null) {
      return _decisionFromPolicy(currentVersion, cachedPolicy);
    }

    return AppUpdateDecision(
      mustUpdate: false,
      message: '',
      updateUrl: '',
      latestVersion: '',
      currentVersion: currentVersion,
    );
  }

  Uri? allowedUpdateUri(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;

    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'market' || scheme == 'itms-apps') {
      return uri;
    }

    if (scheme != 'https') {
      return null;
    }

    final host = uri.host.toLowerCase();
    if (_allowedStoreHosts.contains(host) || _isApprovedCompanyHost(host)) {
      return uri;
    }

    return null;
  }

  bool _isApprovedCompanyHost(String host) {
    return host == ApiConstants.publicHost || host == 'speedlogi.sa' || host.endsWith('.speedlogi.sa');
  }

  Map<String, dynamic> _extractPolicy(String responseBody) {
    final decoded = json.decode(responseBody);
    if (decoded is Map<String, dynamic>) {
      final response = decoded['response'];
      if (response is Map<String, dynamic>) {
        return response;
      }
      return decoded;
    }
    return <String, dynamic>{};
  }

  Future<void> _cachePolicy(Map<String, dynamic> policy) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cachedPolicyKey,
      jsonEncode({
        'latest_version': (policy['latest_version'] ?? '').toString().trim(),
        'minimum_version': (policy['minimum_version'] ?? '').toString().trim(),
        'force_update': policy['force_update'],
        'android_url': (policy['android_url'] ?? '').toString().trim(),
        'ios_url': (policy['ios_url'] ?? '').toString().trim(),
        'message': (policy['message'] ?? '').toString(),
      }),
    );
  }

  Future<Map<String, dynamic>?> _loadCachedPolicy() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cachedPolicyKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) {
        return null;
      }
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    } catch (_) {
      return null;
    }
  }

  AppUpdateDecision _decisionFromPolicy(String currentVersion, Map<String, dynamic> policy) {
    final latestVersion = (policy['latest_version'] ?? '').toString().trim();
    final minimumVersion = (policy['minimum_version'] ?? '').toString().trim();
    final forceUpdate = (policy['force_update'] == true) ||
        (policy['force_update']?.toString().toLowerCase() == 'true') ||
        (policy['force_update']?.toString() == '1');
    final androidUrl = (policy['android_url'] ?? '').toString().trim();
    final iosUrl = (policy['ios_url'] ?? '').toString().trim();
    final message = (policy['message'] ??
          currentAppLocalizations().forceUpdateDefaultMessage)
        .toString();
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final updateUrl = isIOS ? iosUrl : androidUrl;
    final allowedUri = allowedUpdateUri(updateUrl);
    final belowMinimum = _isVersionLower(currentVersion, minimumVersion);
    final belowLatest = _isVersionLower(currentVersion, latestVersion);
    final mustUpdate = belowMinimum || (forceUpdate && belowLatest);

    return AppUpdateDecision(
      mustUpdate: mustUpdate,
      message: message,
      updateUrl: allowedUri?.toString() ?? '',
      latestVersion: latestVersion,
      currentVersion: currentVersion,
    );
  }

  bool _isVersionLower(String current, String target) {
    if (target.isEmpty || current.isEmpty) return false;

    final currentParts = _toParts(current);
    final targetParts = _toParts(target);
    final maxLength = currentParts.length > targetParts.length
        ? currentParts.length
        : targetParts.length;

    for (var i = 0; i < maxLength; i++) {
      final a = i < currentParts.length ? currentParts[i] : 0;
      final b = i < targetParts.length ? targetParts[i] : 0;
      if (a < b) return true;
      if (a > b) return false;
    }

    return false;
  }

  List<int> _toParts(String version) {
    final normalized = version.split('+').first.trim();
    return normalized
        .split('.')
        .map((part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
  }

  @visibleForTesting
  AppUpdateDecision decisionFromPolicyForTest(String currentVersion, Map<String, dynamic> policy) {
    return _decisionFromPolicy(currentVersion, policy);
  }

  @visibleForTesting
  bool isVersionLowerForTest(String current, String target) {
    return _isVersionLower(current, target);
  }
}
