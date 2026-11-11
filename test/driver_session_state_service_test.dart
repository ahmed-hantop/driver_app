import 'package:driver_app/services/driver_session_state_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clearPersistedState removes cached driver session artifacts', () async {
    SharedPreferences.setMockInitialValues(const {
      'driver_name_cached': 'Jane Driver',
      'driver_mobile_cached': '0555000111',
      'driver_checkin_status_cached': true,
      'driver_last_remote_diag_token': 'diag-token',
      'driver_order_reminders_enabled': true,
      'driver_coexistence_mode_enabled': true,
      'driver_order_lifecycle_outbox_v1': '[1,2,3]',
      'driver_order_local_ref_map_v1': '{"1":"abc"}',
      'driver_order_lifecycle_dead_letter_v1': '[4]',
      'driver_order_reminder_state_v1': '{"pickup:1":123}',
      'driver_tracking_policy_v1': 'always',
      'driver_live_tracking_enabled': true,
      'driver_last_lat': 26.42,
      'driver_last_lng': 50.08,
      'driver_last_recorded_at': 123,
      'driver_last_uploaded_at': 456,
      'driver_pending_location_queue': '[{"lat":1}]',
      'driver_app_log_queue_v1': '[{"message":"oops"}]',
      'unrelated_pref': 'keep-me',
    });

    await DriverSessionStateService.clearPersistedState();

    final prefs = await SharedPreferences.getInstance();

    expect(prefs.getString('driver_name_cached'), isNull);
    expect(prefs.getString('driver_mobile_cached'), isNull);
    expect(prefs.getBool('driver_checkin_status_cached'), isNull);
    expect(prefs.getString('driver_last_remote_diag_token'), isNull);
    expect(prefs.getBool('driver_order_reminders_enabled'), isNull);
    expect(prefs.getBool('driver_coexistence_mode_enabled'), isNull);
    expect(prefs.getString('driver_order_lifecycle_outbox_v1'), isNull);
    expect(prefs.getString('driver_order_local_ref_map_v1'), isNull);
    expect(prefs.getString('driver_order_lifecycle_dead_letter_v1'), isNull);
    expect(prefs.getString('driver_order_reminder_state_v1'), isNull);
    expect(prefs.getString('driver_tracking_policy_v1'), isNull);
    expect(prefs.getBool('driver_live_tracking_enabled'), isNull);
    expect(prefs.getDouble('driver_last_lat'), isNull);
    expect(prefs.getDouble('driver_last_lng'), isNull);
    expect(prefs.getInt('driver_last_recorded_at'), isNull);
    expect(prefs.getInt('driver_last_uploaded_at'), isNull);
    expect(prefs.getString('driver_pending_location_queue'), isNull);
    expect(prefs.getString('driver_app_log_queue_v1'), isNull);
    expect(prefs.getString('unrelated_pref'), 'keep-me');
  });
}