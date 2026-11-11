import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'log_redactor.dart';

class DriverLogService {
  DriverLogService._();

  static final DriverLogService instance = DriverLogService._();

  static const String _queueKey = 'driver_app_log_queue_v1';
  static const String _installAtKey = 'driver_app_install_at_iso';
  static const String _deviceIdKey = 'driver_app_install_device_id';
  static const int _maxQueueSize = 80;

  bool _initialized = false;
  bool _flushing = false;
  PackageInfo? _cachedPackageInfo;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    await _ensureInstallMetadata();
    _initialized = true;
    unawaited(flushPending());
  }

  Future<void> recordError(
    Object error,
    StackTrace stack, {
    String reason = 'Unhandled error',
    bool fatal = false,
    Map<String, dynamic>? context,
  }) async {
    final payload = await _buildPayload(
      level: fatal ? 'fatal' : 'error',
      event: reason,
      message: LogRedactor.sanitizeText(error),
      stackTrace: LogRedactor.sanitizeText(stack.toString(), maxChars: 4000),
      context: context,
    );

    await _enqueue(payload);
    unawaited(flushPending());
  }

  Future<void> flushPending() async {
    if (_flushing) {
      return;
    }

    _flushing = true;
    try {
      if (!_initialized) {
        await initialize();
      }

      final queue = await _readQueue();
      if (queue.isEmpty) {
        return;
      }

      final success = await ApiService().sendDriverAppLogs(queue);
      if (success) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_queueKey);
      }
    } catch (e, stack) {
      debugPrint('DriverLogService flush failed: ${LogRedactor.sanitizeText(e)}');
      debugPrint(LogRedactor.sanitizeText(stack.toString(), maxChars: 1200));
    } finally {
      _flushing = false;
    }
  }

  Future<void> clearQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_queueKey);
  }

  Future<Map<String, dynamic>> _buildPayload({
    required String level,
    required String event,
    required String message,
    String? stackTrace,
    Map<String, dynamic>? context,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final installAt = prefs.getString(_installAtKey);
    final deviceId = prefs.getString(_deviceIdKey);
    final packageInfo = await _getPackageInfo();

    return {
      'level': level,
      'event': event,
      'message': LogRedactor.sanitizeText(message),
      'stack_trace': stackTrace == null ? null : LogRedactor.sanitizeText(stackTrace, maxChars: 4000),
      'context': _normalizeContext(context),
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
      'app_install_at': installAt,
      'app_version': packageInfo?.version,
      'build_number': packageInfo?.buildNumber,
      'device_id': deviceId,
      'device_brand': Platform.operatingSystem,
      'device_model': Platform.localHostname,
      'device_name': Platform.localHostname,
      'platform': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
    };
  }

  dynamic _normalizeContext(Map<String, dynamic>? context) {
    if (context == null || context.isEmpty) {
      return null;
    }

    try {
      final sanitized = LogRedactor.sanitizeContext(context);
      return jsonDecode(jsonEncode(sanitized));
    } catch (_) {
      return {'raw': LogRedactor.sanitizeText(context)};
    }
  }

  Future<void> _enqueue(Map<String, dynamic> payload) async {
    final queue = await _readQueue();
    queue.add(payload);

    if (queue.length > _maxQueueSize) {
      queue.removeRange(0, queue.length - _maxQueueSize);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_queueKey, jsonEncode(queue));
  }

  Future<List<Map<String, dynamic>>> _readQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_queueKey);
    if (raw == null || raw.isEmpty) {
      return <Map<String, dynamic>>[];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <Map<String, dynamic>>[];
      }

      return decoded
          .whereType<Map>()
          .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _ensureInstallMetadata() async {
    final prefs = await SharedPreferences.getInstance();

    if (!prefs.containsKey(_installAtKey)) {
      await prefs.setString(_installAtKey, DateTime.now().toUtc().toIso8601String());
    }

    if (!prefs.containsKey(_deviceIdKey)) {
      final generated = '${Platform.operatingSystem}-${DateTime.now().microsecondsSinceEpoch}';
      await prefs.setString(_deviceIdKey, generated);
    }
  }

  Future<PackageInfo?> _getPackageInfo() async {
    if (_cachedPackageInfo != null) {
      return _cachedPackageInfo;
    }

    try {
      _cachedPackageInfo = await PackageInfo.fromPlatform();
      return _cachedPackageInfo;
    } catch (_) {
      return null;
    }
  }
}
