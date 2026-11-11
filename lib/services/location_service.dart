import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_constants.dart';
import 'auth_storage.dart';
import 'network_client.dart';

const _locationChannelId = 'driver_location_channel';
const _locationNotificationId = 9001;

const _cachedCheckinStatusKey = 'driver_checkin_status_cached';
const _liveTrackingEnabledKey = 'driver_live_tracking_enabled';
const _trackingPolicyKey = 'driver_tracking_policy_v1';
const _lastLatKey = 'driver_last_lat';
const _lastLngKey = 'driver_last_lng';
const _lastRecordedAtKey = 'driver_last_recorded_at';
const _lastUploadedAtKey = 'driver_last_uploaded_at';
const _pendingLocationQueueKey = 'driver_pending_location_queue';

// Service wakeup interval stays short; upload cadence is governed by mode.
const _serviceTickInterval = Duration(seconds: 30);
const _liveMinUpdateInterval = Duration(seconds: 60);
const _liveMaxUpdateInterval = Duration(seconds: 180);
const _liveMinDistanceMeters = 35.0;
const _batteryMinUpdateInterval = Duration(minutes: 3);
const _batteryMaxUpdateInterval = Duration(minutes: 5);
const _batteryMinDistanceMeters = 120.0;
const _recentFixAge = Duration(seconds: 45);
const _highSpeedMps = 4.5; // ~16 km/h; above this, request higher accuracy
const _lowPowerDistanceFilter = 100;
const _activeDistanceFilter = 30;
const _maxAcceptableAccuracyMeters = 75.0;
const _forceHighAccuracyMeters = 200.0;
const _maxLastKnownAge = Duration(minutes: 5);
const _retryDelay = Duration(seconds: 4);
const _uploadTimeout = Duration(seconds: 8);
const _maxQueuedLocationPoints = 60;
const _batchUploadPointLimit = 12;
const _batchUploadPointThreshold = 4;
bool _locationUpdateInProgress = false;
DateTime? _networkBackoffUntil;
DateTime? _lastHeartbeatSentAt;
const _heartbeatInterval = Duration(minutes: 15);
int _consecutiveNetworkFailures = 0;
int _locationSendAttempts = 0;
int _locationSendSuccesses = 0;
int _locationSendFailures = 0;
int _locationQueueEnqueues = 0;

enum _LocationBatchStatus { success, checkedOut, retryableFailure }

class _LocationBatchResult {
  const _LocationBatchResult({required this.status, this.sentCount = 0});

  final _LocationBatchStatus status;
  final int sentCount;
}

Map<String, int> locationPerformanceSnapshot() {
  return {
    'attempts': _locationSendAttempts,
    'successes': _locationSendSuccesses,
    'failures': _locationSendFailures,
    'queued_points': _locationQueueEnqueues,
    'consecutive_network_failures': _consecutiveNetworkFailures,
  };
}

void _recordSendSuccess() {
  _locationSendSuccesses += 1;
  _consecutiveNetworkFailures = 0;
  _networkBackoffUntil = null;
}

void _recordSendFailure() {
  _locationSendFailures += 1;
  _consecutiveNetworkFailures += 1;
  final stepSeconds = 10 * _consecutiveNetworkFailures;
  final backoffSeconds = stepSeconds > 120 ? 120 : stepSeconds;
  _networkBackoffUntil = DateTime.now().add(Duration(seconds: backoffSeconds));
}

int _toInt(dynamic value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

double _toDouble(dynamic value, double fallback) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

double? _toNullableDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

bool _toBool(dynamic value, bool fallback) {
  if (value is bool) return value;
  final str = value?.toString().toLowerCase().trim();
  if (str == null || str.isEmpty) return fallback;
  if (str == '1' || str == 'true' || str == 'yes' || str == 'on') return true;
  if (str == '0' || str == 'false' || str == 'no' || str == 'off') return false;
  return fallback;
}

Map<String, dynamic> _sanitizeTrackingPolicy(Map<String, dynamic> policy) {
  final sanitized = <String, dynamic>{
    'live_min_seconds': _toInt(
      policy['live_min_seconds'],
      _liveMinUpdateInterval.inSeconds,
    ),
    'live_max_seconds': _toInt(
      policy['live_max_seconds'],
      _liveMaxUpdateInterval.inSeconds,
    ),
    'battery_min_seconds': _toInt(
      policy['battery_min_seconds'],
      _batteryMinUpdateInterval.inSeconds,
    ),
    'battery_max_seconds': _toInt(
      policy['battery_max_seconds'],
      _batteryMaxUpdateInterval.inSeconds,
    ),
    'live_min_distance_m': _toDouble(
      policy['live_min_distance_m'],
      _liveMinDistanceMeters,
    ),
    'battery_min_distance_m': _toDouble(
      policy['battery_min_distance_m'],
      _batteryMinDistanceMeters,
    ),
    'coexistence_mode': _toBool(policy['coexistence_mode'], false),
  };

  final liveMin = (sanitized['live_min_seconds'] as int).clamp(5, 120);
  final liveMax = (sanitized['live_max_seconds'] as int).clamp(liveMin, 300);
  final batteryMin = (sanitized['battery_min_seconds'] as int).clamp(10, 300);
  final batteryMax = (sanitized['battery_max_seconds'] as int).clamp(
    batteryMin,
    600,
  );

  sanitized['live_min_seconds'] = liveMin;
  sanitized['live_max_seconds'] = liveMax;
  sanitized['battery_min_seconds'] = batteryMin;
  sanitized['battery_max_seconds'] = batteryMax;
  sanitized['live_min_distance_m'] =
      (sanitized['live_min_distance_m'] as double).clamp(3.0, 200.0);
  sanitized['battery_min_distance_m'] =
      (sanitized['battery_min_distance_m'] as double).clamp(5.0, 500.0);

  return sanitized;
}

Future<Map<String, dynamic>?> getTrackingPolicy() async {
  if (kIsWeb || !Platform.isAndroid) return null;
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_trackingPolicyKey);
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  } catch (_) {
    return null;
  }
}

Future<void> applyTrackingPolicy(Map<String, dynamic> policy) async {
  if (kIsWeb || !Platform.isAndroid) return;
  final prefs = await SharedPreferences.getInstance();
  final normalized = _sanitizeTrackingPolicy(policy);
  await prefs.setString(_trackingPolicyKey, jsonEncode(normalized));

  final forceBatterySaver =
      _toBool(policy['force_battery_saver'], false) ||
      _toBool(normalized['coexistence_mode'], false);
  if (forceBatterySaver) {
    await prefs.setBool(_liveTrackingEnabledKey, false);
  }
}

Future<bool> isLiveTrackingEnabled() async {
  if (kIsWeb || !Platform.isAndroid) return true;
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_liveTrackingEnabledKey) ?? true;
}

Future<void> setLiveTrackingEnabled(bool enabled) async {
  if (kIsWeb || !Platform.isAndroid) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_liveTrackingEnabledKey, enabled);
}

Future<int> pendingLocationQueueCount() async {
  if (kIsWeb || !Platform.isAndroid) return 0;
  final prefs = await SharedPreferences.getInstance();
  final queue = _readPendingQueue(prefs);
  return queue.length;
}

Future<void> clearLocationSessionState({
  bool clearTrackingPreferences = false,
}) async {
  if (kIsWeb || !Platform.isAndroid) return;

  final prefs = await SharedPreferences.getInstance();
  final removals = <Future<bool>>[
    prefs.remove(_pendingLocationQueueKey),
    prefs.remove(_lastLatKey),
    prefs.remove(_lastLngKey),
    prefs.remove(_lastRecordedAtKey),
    prefs.remove(_lastUploadedAtKey),
  ];

  if (clearTrackingPreferences) {
    removals.addAll([
      prefs.remove(_trackingPolicyKey),
      prefs.remove(_liveTrackingEnabledKey),
    ]);
  }

  await Future.wait(removals);
  _networkBackoffUntil = null;
  _consecutiveNetworkFailures = 0;
}

Future<bool> _canStartLocationService({
  bool requireBackgroundPermission = false,
}) async {
  if (kIsWeb || !Platform.isAndroid) return false;

  final prefs = await SharedPreferences.getInstance();
  final isCheckedIn = prefs.getBool(_cachedCheckinStatusKey) ?? false;
  if (!isCheckedIn) {
    return false;
  }

  final permission = await Geolocator.checkPermission();
  if (requireBackgroundPermission) {
    return permission == LocationPermission.always;
  }

  return permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse;
}

Future<void> initializeLocationService() async {
  if (kIsWeb || !Platform.isAndroid) return;
  await _ensureLocationChannel();
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: _locationChannelId,
      initialNotificationTitle: 'Location active',
      initialNotificationContent: 'Sharing location in background',
      foregroundServiceNotificationId: _locationNotificationId,
      foregroundServiceTypes: [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(),
  );
}

Future<void> _ensureLocationChannel() async {
  final plugin = FlutterLocalNotificationsPlugin();
  const channel = AndroidNotificationChannel(
    _locationChannelId,
    'Driver Location',
    description: 'Foreground service for continuous driver location updates',
    importance: Importance.high,
  );
  await plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);
}

Future<void> startLocationService({
  bool requireBackgroundPermission = false,
}) async {
  if (kIsWeb || !Platform.isAndroid) return;
  if (!await _canStartLocationService(
    requireBackgroundPermission: requireBackgroundPermission,
  )) {
    await stopLocationService();
    return;
  }

  final service = FlutterBackgroundService();
  final isRunning = await service.isRunning();
  if (!isRunning) {
    await service.startService();
  } else {
    service.invoke('ping');
  }
}

Future<void> stopLocationService() async {
  if (kIsWeb || !Platform.isAndroid) return;
  final service = FlutterBackgroundService();
  service.invoke('stopService');
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title: 'Location active',
      content: 'Sharing location in background',
    );
  }

  service.on('stopService').listen((_) {
    service.stopSelf();
  });

  unawaited(sendLocationUpdate());

  Timer.periodic(_serviceTickInterval, (timer) async {
    try {
      await sendLocationUpdate();
    } catch (_) {
      // Intentionally swallow errors to keep service alive
    }
  });
}

Future<Position?> _getAdaptivePosition(SharedPreferences prefs) async {
  final permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    return null;
  }
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) return null;

  final lastLat = prefs.getDouble(_lastLatKey);
  final lastLng = prefs.getDouble(_lastLngKey);
  final lastRecordedAtMillis = prefs.getInt(_lastRecordedAtKey);
  final lastRecordedAt = lastRecordedAtMillis != null
      ? DateTime.fromMillisecondsSinceEpoch(lastRecordedAtMillis)
      : null;
  final now = DateTime.now();
  final recentlySent =
      lastRecordedAt != null && now.difference(lastRecordedAt) <= _recentFixAge;
  final hasRecentFix = recentlySent && lastLat != null && lastLng != null;

  // Cheap path: if we have a recent fix and last known location is close, reuse it.
  if (hasRecentFix) {
    final cached = await Geolocator.getLastKnownPosition();
    if (cached != null) {
      final dist = Geolocator.distanceBetween(
        lastLat,
        lastLng,
        cached.latitude,
        cached.longitude,
      );
      if (dist <= _liveMinDistanceMeters) {
        return cached;
      }
    }
  }

  final lowPowerSettings = LocationSettings(
    accuracy: hasRecentFix ? LocationAccuracy.low : LocationAccuracy.medium,
    distanceFilter: hasRecentFix
        ? _lowPowerDistanceFilter
        : _activeDistanceFilter,
    timeLimit: const Duration(seconds: 8),
  );
  var position = await _tryGetPosition(lowPowerSettings);

  // If moving fast or accuracy is coarse, briefly switch to high accuracy.
  final needsHighAccuracy =
      position == null ||
      position.speed >= _highSpeedMps ||
      position.accuracy > _forceHighAccuracyMeters;
  if (needsHighAccuracy) {
    final highSettings = const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: _activeDistanceFilter,
      timeLimit: Duration(seconds: 8),
    );
    position = await _tryGetPosition(highSettings);

    // Retry once more after a short delay if still null.
    if (position == null) {
      await Future.delayed(_retryDelay);
      position = await _tryGetPosition(highSettings);
    }
  }

  // Fallback to a recent last known fix if live attempts failed.
  if (position == null) {
    final cached = await Geolocator.getLastKnownPosition();
    if (cached != null) {
      final ageOk = now.difference(cached.timestamp) <= _maxLastKnownAge;
      if (ageOk) {
        position = cached;
      }
    }
  }

  return position;
}

List<Map<String, dynamic>> _readPendingQueue(SharedPreferences prefs) {
  final raw = prefs.getString(_pendingLocationQueueKey);
  if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <Map<String, dynamic>>[];
    return decoded
        .whereType<Map>()
        .map((entry) {
          final latitude = _toNullableDouble(entry['lat'] ?? entry['latitude']);
          final longitude = _toNullableDouble(
            entry['lng'] ?? entry['longitude'],
          );
          final accuracy = _toNullableDouble(entry['accuracy']);
          final speed = _toNullableDouble(entry['speed']);
          final recordedAtRaw = entry['recorded_at'] ?? entry['timestamp'];
          final recordedAt = recordedAtRaw is String
              ? recordedAtRaw
              : DateTime.fromMillisecondsSinceEpoch(
                  recordedAtRaw is num
                      ? recordedAtRaw.toInt()
                      : DateTime.now().millisecondsSinceEpoch,
                ).toUtc().toIso8601String();

          return {
            'lat': latitude,
            'lng': longitude,
            'accuracy': accuracy,
            'speed': speed,
            'recorded_at': recordedAt,
          };
        })
        .where((entry) => entry['lat'] != null && entry['lng'] != null)
        .toList();
  } catch (_) {
    return <Map<String, dynamic>>[];
  }
}

Future<void> _writePendingQueue(
  SharedPreferences prefs,
  List<Map<String, dynamic>> queue,
) async {
  await prefs.setString(_pendingLocationQueueKey, jsonEncode(queue));
}

Future<void> _enqueuePendingLocation(
  SharedPreferences prefs, {
  required Map<String, dynamic> point,
}) async {
  final queue = _readPendingQueue(prefs);
  _locationQueueEnqueues += 1;
  queue.add(point);
  if (queue.length > _maxQueuedLocationPoints) {
    queue.removeRange(0, queue.length - _maxQueuedLocationPoints);
  }
  await _writePendingQueue(prefs, queue);
}

Map<String, dynamic>? _decodeJsonObject(String rawBody) {
  if (rawBody.isEmpty) return null;

  try {
    final decoded = jsonDecode(rawBody);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
  } catch (_) {}

  return null;
}

bool _isCheckedOutResponse(http.Response response) {
  if (response.statusCode != 403 && response.statusCode != 409) {
    return false;
  }

  final decoded = _decodeJsonObject(response.body);
  final responsePayload = decoded?['response'];
  final reason = responsePayload is Map
      ? (responsePayload['reason'] ?? responsePayload['code'])
            ?.toString()
            .toLowerCase()
      : null;
  final message = (decoded?['message'] ?? '').toString().toLowerCase();

  return reason == 'checked_out' ||
      message.contains('checked out') ||
      message.contains('checkout') ||
      message.contains('checkin first');
}

Map<String, dynamic> _buildQueuedPoint(Position position, DateTime recordedAt) {
  return {
    'lat': position.latitude,
    'lng': position.longitude,
    'accuracy': position.accuracy,
    'speed': position.speed,
    'recorded_at': recordedAt.toUtc().toIso8601String(),
  };
}

Future<_LocationBatchResult> _sendLocationBatch(
  String token,
  List<Map<String, dynamic>> points,
) async {
  if (points.isEmpty) {
    return const _LocationBatchResult(status: _LocationBatchStatus.success);
  }

  _locationSendAttempts += 1;

  final uri = Uri.parse(ApiConstants.baseUrl + ApiConstants.location);
  final response = await DriverAppHttpClient.client
      .post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'Accept-Encoding': 'gzip',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'points': points}),
      )
      .timeout(_uploadTimeout);

  if (response.statusCode >= 200 && response.statusCode < 300) {
    return _LocationBatchResult(
      status: _LocationBatchStatus.success,
      sentCount: points.length,
    );
  }

  if (_isCheckedOutResponse(response)) {
    return const _LocationBatchResult(status: _LocationBatchStatus.checkedOut);
  }

  return const _LocationBatchResult(
    status: _LocationBatchStatus.retryableFailure,
  );
}

Future<_LocationBatchResult> _flushPendingQueue(
  SharedPreferences prefs,
  String token,
) async {
  final queue = _readPendingQueue(prefs);
  if (queue.isEmpty) {
    return const _LocationBatchResult(status: _LocationBatchStatus.success);
  }

  final batch = queue.take(_batchUploadPointLimit).toList();
  final result = await _sendLocationBatch(token, batch);
  if (result.status == _LocationBatchStatus.success && result.sentCount > 0) {
    final remaining = queue.skip(result.sentCount).toList();
    await _writePendingQueue(prefs, remaining);
    await prefs.setInt(
      _lastUploadedAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  return result;
}

Future<void> markDriverCheckedOutLocally([
  SharedPreferences? existingPrefs,
]) async {
  if (kIsWeb || !Platform.isAndroid) return;
  final prefs = existingPrefs ?? await SharedPreferences.getInstance();
  await prefs.setBool(_cachedCheckinStatusKey, false);
  await clearLocationSessionState();
  await stopLocationService();
}

Future<Position?> _tryGetPosition(LocationSettings settings) async {
  try {
    return await Geolocator.getCurrentPosition(locationSettings: settings);
  } catch (_) {
    return null;
  }
}

Future<void> sendLocationUpdate() async {
  if (kIsWeb || !Platform.isAndroid) return;
  if (_locationUpdateInProgress) return;

  _locationUpdateInProgress = true;
  double? currentLatitude;
  double? currentLongitude;
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = await AuthStorage.instance.readToken();
    final isCheckedIn = prefs.getBool(_cachedCheckinStatusKey) ?? false;
    final policyRaw = prefs.getString(_trackingPolicyKey);
    final policy = () {
      if (policyRaw == null || policyRaw.isEmpty) return <String, dynamic>{};
      try {
        final decoded = jsonDecode(policyRaw);
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {}
      return <String, dynamic>{};
    }();
    final liveTrackingEnabled = prefs.getBool(_liveTrackingEnabledKey) ?? true;
    final liveMinSec = _toInt(
      policy['live_min_seconds'],
      _liveMinUpdateInterval.inSeconds,
    );
    final liveMaxSec = _toInt(
      policy['live_max_seconds'],
      _liveMaxUpdateInterval.inSeconds,
    );
    final batteryMinSec = _toInt(
      policy['battery_min_seconds'],
      _batteryMinUpdateInterval.inSeconds,
    );
    final batteryMaxSec = _toInt(
      policy['battery_max_seconds'],
      _batteryMaxUpdateInterval.inSeconds,
    );
    final minUpdateInterval = Duration(
      seconds: liveTrackingEnabled ? liveMinSec : batteryMinSec,
    );
    final maxUpdateInterval = Duration(
      seconds: liveTrackingEnabled ? liveMaxSec : batteryMaxSec,
    );
    final minDistanceMeters = liveTrackingEnabled
        ? _toDouble(policy['live_min_distance_m'], _liveMinDistanceMeters)
        : _toDouble(
            policy['battery_min_distance_m'],
            _batteryMinDistanceMeters,
          );
    final backoffUntil = _networkBackoffUntil;
    if (backoffUntil != null && DateTime.now().isBefore(backoffUntil)) {
      return;
    }

    if (token == null || token.isEmpty || !isCheckedIn) {
      return;
    }

    final lastRecordedAtMillis = prefs.getInt(_lastRecordedAtKey);
    final lastRecordedAt = lastRecordedAtMillis != null
        ? DateTime.fromMillisecondsSinceEpoch(lastRecordedAtMillis)
        : null;
    final sampleElapsed = lastRecordedAt != null
        ? DateTime.now().difference(lastRecordedAt)
        : maxUpdateInterval;
    if (sampleElapsed < minUpdateInterval) {
      return;
    }

    final position = await _getAdaptivePosition(prefs);
    if (position == null) return;
    final latitude = position.latitude;
    final longitude = position.longitude;
    currentLatitude = latitude;
    currentLongitude = longitude;

    // Ignore very coarse fixes unless we are overdue.
    final isOverdue = () {
      final lastRecordedAtMillis = prefs.getInt(_lastRecordedAtKey);
      final lastRecordedAt = lastRecordedAtMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(lastRecordedAtMillis)
          : null;
      if (lastRecordedAt == null) return true;
      return DateTime.now().difference(lastRecordedAt) >= maxUpdateInterval;
    }();
    if (position.accuracy > _maxAcceptableAccuracyMeters && !isOverdue) {
      return;
    }

    final lastLat = prefs.getDouble(_lastLatKey);
    final lastLng = prefs.getDouble(_lastLngKey);

    final movedEnough = () {
      if (lastLat == null || lastLng == null) return true;
      final dist = Geolocator.distanceBetween(
        lastLat,
        lastLng,
        position.latitude,
        position.longitude,
      );
      return dist >= minDistanceMeters;
    }();

    final overMaxInterval = sampleElapsed >= maxUpdateInterval;
    if (!movedEnough && !overMaxInterval) {
      return;
    }

    final recordedAt = position.timestamp.toUtc();
    final point = _buildQueuedPoint(position, recordedAt);
    await _enqueuePendingLocation(prefs, point: point);
    await prefs.setDouble(_lastLatKey, latitude);
    await prefs.setDouble(_lastLngKey, longitude);
    await prefs.setInt(_lastRecordedAtKey, recordedAt.millisecondsSinceEpoch);

    final queue = _readPendingQueue(prefs);
    final lastUploadedAtMillis = prefs.getInt(_lastUploadedAtKey);
    final lastUploadedAt = lastUploadedAtMillis != null
        ? DateTime.fromMillisecondsSinceEpoch(lastUploadedAtMillis)
        : null;
    final uploadElapsed = lastUploadedAt != null
        ? DateTime.now().difference(lastUploadedAt)
        : maxUpdateInterval;
    final shouldFlushNow =
        queue.length >= _batchUploadPointThreshold ||
        uploadElapsed >= maxUpdateInterval ||
        overMaxInterval;
    if (!shouldFlushNow) {
      return;
    }

    final flushResult = await _flushPendingQueue(prefs, token);

    if (flushResult.status == _LocationBatchStatus.success) {
      _recordSendSuccess();
      // Piggyback a heartbeat every 15 min — sends security telemetry to /v1/heartbeat
      final now = DateTime.now();
      final lastBeat = _lastHeartbeatSentAt;
      if (lastBeat == null || now.difference(lastBeat) >= _heartbeatInterval) {
        _lastHeartbeatSentAt = now;
        unawaited(
          _sendHeartbeatPing(
            token: token,
            latitude: position.latitude,
            longitude: position.longitude,
            accuracy: position.accuracy,
            isMocked: position.isMocked ?? false,
          ),
        );
      }
    } else if (flushResult.status == _LocationBatchStatus.checkedOut) {
      await markDriverCheckedOutLocally(prefs);
    } else {
      _recordSendFailure();
    }
  } on TimeoutException {
    _recordSendFailure();
    // Keep service responsive on slow networks; queue latest point for retry.
    try {
      final prefs = await SharedPreferences.getInstance();
      if (currentLatitude != null && currentLongitude != null) {
        await _enqueuePendingLocation(
          prefs,
          point: {
            'lat': currentLatitude,
            'lng': currentLongitude,
            'recorded_at': DateTime.now().toUtc().toIso8601String(),
          },
        );
      }
    } catch (_) {}
    return;
  } on SocketException {
    _recordSendFailure();
    try {
      if (currentLatitude != null && currentLongitude != null) {
        final prefs = await SharedPreferences.getInstance();
        await _enqueuePendingLocation(
          prefs,
          point: {
            'lat': currentLatitude,
            'lng': currentLongitude,
            'recorded_at': DateTime.now().toUtc().toIso8601String(),
          },
        );
      }
    } catch (_) {}
    return;
  } on http.ClientException {
    _recordSendFailure();
    try {
      if (currentLatitude != null && currentLongitude != null) {
        final prefs = await SharedPreferences.getInstance();
        await _enqueuePendingLocation(
          prefs,
          point: {
            'lat': currentLatitude,
            'lng': currentLongitude,
            'recorded_at': DateTime.now().toUtc().toIso8601String(),
          },
        );
      }
    } catch (_) {}
    return;
  } finally {
    _locationUpdateInProgress = false;
  }
}

/// Fire-and-forget heartbeat — sends security telemetry to /v1/heartbeat.
/// Called at most once every [_heartbeatInterval] from within sendLocationUpdate.
Future<void> _sendHeartbeatPing({
  required String token,
  double? latitude,
  double? longitude,
  double? accuracy,
  bool isMocked = false,
}) async {
  try {
    final body = <String, String>{
      'mock_location': isMocked ? '1' : '0',
      'device_timestamp': DateTime.now().toUtc().toIso8601String(),
      'app_state': 'background',
    };
    if (latitude != null) body['latitude'] = latitude.toStringAsFixed(7);
    if (longitude != null) body['longitude'] = longitude.toStringAsFixed(7);
    if (accuracy != null) body['gps_accuracy_m'] = accuracy.toStringAsFixed(2);

    await DriverAppHttpClient.client
        .post(
          Uri.parse(ApiConstants.baseUrl + ApiConstants.heartbeat),
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
            'Accept-Encoding': 'gzip',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 8));
  } catch (_) {
    // Heartbeat is best-effort — never throw or break location service
  }
}
