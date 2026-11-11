import 'dart:ui';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter/widgets.dart';
import 'package:driver_app/l10n/app_localizations.dart';

import 'api_constants.dart';
import 'auth_storage.dart';
import 'log_redactor.dart';
import 'network_client.dart';
import '../l10n/app_localization_helper.dart';
import 'notification_service.dart';
import 'location_service.dart';

const _orderReminderTask = 'order_reminder_task';
const _locationWatchdogTask = 'location_watchdog_task';
const _cachedCheckinStatusKey = 'driver_checkin_status_cached';
const _orderRemindersEnabledKey = 'driver_order_reminders_enabled';
const _orderReminderStateKey = 'driver_order_reminder_state_v1';
const _orderReminderCooldown = Duration(hours: 1);

int _orderId(Map<String, dynamic> order) {
  final raw = order['id'];
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '') ?? 0;
}

Future<void> _showPickupReminder(Map<String, dynamic> order, AppLocalizations l10n) async {
  await NotificationService.instance.showSimple(
    id: 9000 + _orderId(order),
    title: l10n.notificationPickupPendingTitle,
    body: l10n.notificationPickupPendingBody(
      order['order_number'] ?? order['order_id'] ?? order['value'] ?? order['id'],
    ),
  );
}

Future<void> _showDeliveryReminder(Map<String, dynamic> order, AppLocalizations l10n) async {
  await NotificationService.instance.showSimple(
    id: 9500 + _orderId(order),
    title: l10n.notificationDeliveryPendingTitle,
    body: l10n.notificationDeliveryPendingBody(
      order['order_number'] ?? order['order_id'] ?? order['value'] ?? order['id'],
    ),
  );
}

DateTime? _parseDate(dynamic raw) {
  if (raw == null) return null;
  try {
    return DateTime.parse(raw.toString());
  } catch (_) {
    return null;
  }
}

bool _isDelivered(Map<String, dynamic> order) {
  final status = (order['status'] ?? '').toString().toLowerCase();
  final delivered = order['delivered_time'] ?? order['delivered_at'] ?? order['drop_time'];
  return delivered != null || status == 'drop' || status == 'delivered' || status.contains('deliver');
}

bool _isCancelled(Map<String, dynamic> order) {
  final status = (order['status'] ?? '').toString().toLowerCase();
  return status == 'cancel' || status == 'cancelled' || status.contains('cancel');
}

bool _isPicked(Map<String, dynamic> order) {
  final status = (order['status'] ?? '').toString().toLowerCase();
  final pickup = order['pickup_time'];
  return pickup != null || status == 'pickup';
}

List<Map<String, dynamic>> _extractActiveOrders(dynamic payload) {
  if (payload is Map<String, dynamic>) {
    if (payload['activeOrders'] is List) {
      return payload['activeOrders'].whereType<Map<String, dynamic>>().toList();
    }
    if (payload['orders'] is List) {
      return payload['orders'].whereType<Map<String, dynamic>>().toList();
    }
  }
  if (payload is List) {
    return payload.whereType<Map<String, dynamic>>().toList();
  }
  return [];
}

bool _isCheckedOutResponse(http.Response response) {
  if (response.statusCode != 403 && response.statusCode != 409) {
    return false;
  }

  try {
    final decoded = json.decode(response.body);
    if (decoded is Map<String, dynamic>) {
      final responsePayload = decoded['response'];
      final reason = responsePayload is Map
          ? (responsePayload['reason'] ?? responsePayload['code'])?.toString().toLowerCase()
          : null;
      final message = (decoded['message'] ?? '').toString().toLowerCase();
      return reason == 'checked_out' ||
          message.contains('checked out') ||
          message.contains('checkout') ||
          message.contains('checkin first');
    }
  } catch (_) {}

  return false;
}

Map<String, int> _readReminderState(SharedPreferences prefs) {
  final raw = prefs.getString(_orderReminderStateKey);
  return _decodeReminderState(raw);
}

Map<String, int> _decodeReminderState(String? raw) {
  if (raw == null || raw.isEmpty) {
    return <String, int>{};
  }

  try {
    final decoded = json.decode(raw);
    if (decoded is! Map) {
      return <String, int>{};
    }

    return decoded.map(
      (key, value) => MapEntry(
        key.toString(),
        value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0,
      ),
    )..removeWhere((_, value) => value <= 0);
  } catch (_) {
    return <String, int>{};
  }
}

Future<void> _writeReminderState(SharedPreferences prefs, Map<String, int> state) async {
  if (state.isEmpty) {
    await prefs.remove(_orderReminderStateKey);
    return;
  }

  await prefs.setString(_orderReminderStateKey, json.encode(state));
}

String _reminderKey(Map<String, dynamic> order, String type) {
  return '$type:${_orderId(order)}';
}

bool _canSendReminder(Map<String, int> state, String key, DateTime now) {
  final lastSentAtMillis = state[key];
  if (lastSentAtMillis == null || lastSentAtMillis <= 0) {
    return true;
  }

  final lastSentAt = DateTime.fromMillisecondsSinceEpoch(lastSentAtMillis);
  return now.difference(lastSentAt) >= _orderReminderCooldown;
}

@visibleForTesting
Map<String, int> decodeReminderStateForTest(String? raw) {
  return _decodeReminderState(raw);
}

@visibleForTesting
bool canSendReminderForTest(Map<String, int> state, String key, DateTime now) {
  return _canSendReminder(state, key, now);
}

@visibleForTesting
String reminderKeyForTest(Map<String, dynamic> order, String type) {
  return _reminderKey(order, type);
}

Future<void> clearBackgroundWorkerState() async {
  if (kIsWeb || !Platform.isAndroid) return;
  await BackgroundWorker.stop();
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_orderReminderStateKey);
}

Future<void> _processOrders() async {
  final prefs = await SharedPreferences.getInstance();
  final token = await AuthStorage.instance.readToken();
  final isCheckedIn = prefs.getBool(_cachedCheckinStatusKey) ?? false;
  final remindersEnabled = prefs.getBool(_orderRemindersEnabledKey) ?? true;
  if (token == null || token.isEmpty || !isCheckedIn || !remindersEnabled) return;

  try {
    final l10n = await loadStoredAppLocalizations();
    final uri = Uri.parse(ApiConstants.baseUrl + ApiConstants.orderReminders);
    final resp = await DriverAppHttpClient.client.get(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'Accept-Encoding': 'gzip',
      },
    ).timeout(const Duration(seconds: 10));
    if (_isCheckedOutResponse(resp)) {
      await markDriverCheckedOutLocally(prefs);
      await clearBackgroundWorkerState();
      return;
    }
    if (resp.statusCode != 200) return;

    final decoded = json.decode(resp.body);
    final payload = decoded is Map<String, dynamic>
        ? ((decoded['response'] is Map<String, dynamic>)
            ? (decoded['response'] as Map<String, dynamic>)['orders'] ?? decoded['response']
            : decoded['orders'] ?? decoded['response'] ?? decoded)
        : decoded;
    final orders = _extractActiveOrders(payload);
    final reminderState = _readReminderState(prefs);
    final activeReminderKeys = <String>{};
    final now = DateTime.now();

    for (final order in orders) {
      if (_isDelivered(order) || _isCancelled(order)) continue;

      final createdAt = _parseDate(order['created_at']);
      final pickupTime = _parseDate(order['pickup_time']);
      final isPicked = _isPicked(order);

      if (!isPicked && createdAt != null) {
        final elapsed = now.difference(createdAt);
        final reminderKey = _reminderKey(order, 'pickup');
        activeReminderKeys.add(reminderKey);
        if (elapsed >= const Duration(minutes: 15) && _canSendReminder(reminderState, reminderKey, now)) {
          await _showPickupReminder(order, l10n);
          reminderState[reminderKey] = now.millisecondsSinceEpoch;
        }
      }

      final deliveryBase = pickupTime ?? createdAt;
      if (isPicked && !_isDelivered(order) && deliveryBase != null) {
        final elapsed = now.difference(deliveryBase);
        final reminderKey = _reminderKey(order, 'delivery');
        activeReminderKeys.add(reminderKey);
        if (elapsed >= const Duration(minutes: 15) && _canSendReminder(reminderState, reminderKey, now)) {
          await _showDeliveryReminder(order, l10n);
          reminderState[reminderKey] = now.millisecondsSinceEpoch;
        }
      }
    }

    reminderState.removeWhere((key, _) => !activeReminderKeys.contains(key));
    await _writeReminderState(prefs, reminderState);
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Order reminder fetch failed: ${LogRedactor.sanitizeText(e)}');
    }
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (kIsWeb || !Platform.isAndroid) return true;
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    await NotificationService.instance.init();
    switch (task) {
      case _orderReminderTask:
        await _processOrders();
        break;
      case _locationWatchdogTask:
        await startLocationService(requireBackgroundPermission: true);
        break;
      default:
        break;
    }
    return true;
  });
}

class BackgroundWorker {
  static bool _initialized = false;

  static Future<void> init() async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (_initialized) return;
    await Workmanager().initialize(callbackDispatcher);
    _initialized = true;
  }

  static Future<void> stop() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await init();
    await _cancelScheduledTasks();
  }

  static Future<void> syncForCheckinState({required bool isCheckedIn}) async {
    if (kIsWeb || !Platform.isAndroid) return;

    await init();
    await _cancelScheduledTasks();

    if (!isCheckedIn) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final remindersEnabled = prefs.getBool(_orderRemindersEnabledKey) ?? true;

    if (remindersEnabled) {
      await Workmanager().registerPeriodicTask(
        _orderReminderTask,
        _orderReminderTask,
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    }

    await Workmanager().registerPeriodicTask(
      _locationWatchdogTask,
      _locationWatchdogTask,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  static Future<void> _cancelScheduledTasks() async {
    await Workmanager().cancelByUniqueName(_orderReminderTask);
    await Workmanager().cancelByUniqueName(_locationWatchdogTask);
    await Workmanager().cancelByUniqueName('location_update_task');
  }
}
