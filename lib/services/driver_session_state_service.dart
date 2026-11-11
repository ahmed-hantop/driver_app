import 'package:shared_preferences/shared_preferences.dart';

import 'background_worker.dart';
import 'location_service.dart';

class DriverSessionStateService {
  DriverSessionStateService._();

  static const String _cachedDriverNameKey = 'driver_name_cached';
  static const String _cachedDriverMobileKey = 'driver_mobile_cached';
  static const String _cachedCheckinStatusKey = 'driver_checkin_status_cached';
  static const String _lastRemoteDiagnosticTokenKey = 'driver_last_remote_diag_token';
  static const String _orderRemindersEnabledKey = 'driver_order_reminders_enabled';
  static const String _coexistenceModeKey = 'driver_coexistence_mode_enabled';
  static const String _orderLifecycleOutboxKey = 'driver_order_lifecycle_outbox_v1';
  static const String _orderLocalRefMapKey = 'driver_order_local_ref_map_v1';
  static const String _orderLifecycleDeadLetterKey = 'driver_order_lifecycle_dead_letter_v1';
  static const String _orderReminderStateKey = 'driver_order_reminder_state_v1';
  static const String _trackingPolicyKey = 'driver_tracking_policy_v1';
  static const String _liveTrackingEnabledKey = 'driver_live_tracking_enabled';
  static const String _lastLatKey = 'driver_last_lat';
  static const String _lastLngKey = 'driver_last_lng';
  static const String _lastRecordedAtKey = 'driver_last_recorded_at';
  static const String _lastUploadedAtKey = 'driver_last_uploaded_at';
  static const String _pendingLocationQueueKey = 'driver_pending_location_queue';
  static const String _driverLogQueueKey = 'driver_app_log_queue_v1';

  static Future<void> clearPersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_cachedDriverNameKey),
      prefs.remove(_cachedDriverMobileKey),
      prefs.remove(_cachedCheckinStatusKey),
      prefs.remove(_lastRemoteDiagnosticTokenKey),
      prefs.remove(_orderRemindersEnabledKey),
      prefs.remove(_coexistenceModeKey),
      prefs.remove(_orderLifecycleOutboxKey),
      prefs.remove(_orderLocalRefMapKey),
      prefs.remove(_orderLifecycleDeadLetterKey),
      prefs.remove(_orderReminderStateKey),
      prefs.remove(_trackingPolicyKey),
      prefs.remove(_liveTrackingEnabledKey),
      prefs.remove(_lastLatKey),
      prefs.remove(_lastLngKey),
      prefs.remove(_lastRecordedAtKey),
      prefs.remove(_lastUploadedAtKey),
      prefs.remove(_pendingLocationQueueKey),
      prefs.remove(_driverLogQueueKey),
    ]);

    await BackgroundWorker.stop();
    await stopLocationService();
  }
}