import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  static const String _generalChannelId = 'driver-general';
  // v2: forces channel recreation so the ringtone sound setting takes effect
  static const String _callsChannelId = 'driver-calls-v2';

  Future<void> init({
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    bool requestPermissions = true,
  }) async {
    if (kIsWeb) {
      _initialized = true; // nothing to do on web
      return;
    }
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    );
    if (requestPermissions) {
      await _requestPermissions();
    }
    await _ensureChannels();
    _initialized = true;
  }

  Future<void> _requestPermissions() async {
    if (kIsWeb) return;
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestFullScreenIntentPermission();
    await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    await _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> _ensureChannels() async {
    if (kIsWeb) return;

    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    await android.createNotificationChannel(const AndroidNotificationChannel(
      _generalChannelId,
      'Driver Alerts',
      description: 'Driver status and message alerts',
      importance: Importance.high,
    ));

    await android.createNotificationChannel(AndroidNotificationChannel(
      _callsChannelId,
      'Driver Calls',
      description: 'Incoming driver calls',
      importance: Importance.max,
      sound: const UriAndroidNotificationSound('content://settings/system/ringtone'),
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 300, 500]),
    ));
  }

  Future<void> showSimple({required int id, required String title, required String body}) async {
    if (!_initialized) {
      await init();
    }
    if (kIsWeb) return; // no-op on web
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _generalChannelId,
        'Driver Alerts',
        channelDescription: 'Driver status and order reminders',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  Future<void> cancel(int id) async {
    if (!_initialized || kIsWeb) return;
    await _plugin.cancel(id: id);
  }

  Future<String?> getLaunchPayload() async {
    if (kIsWeb) return null;
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return details?.notificationResponse?.payload;
  }

  Future<void> showIncomingCall({required int id, required String callerName, required bool isVideo, String? payload}) async {
    if (!_initialized) {
      await init();
    }
    if (kIsWeb) return;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _callsChannelId,
        'Driver Calls',
        channelDescription: 'Incoming driver calls',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.call,
        fullScreenIntent: true,
        ongoing: true,
        autoCancel: false,
        visibility: NotificationVisibility.public,
        playSound: true,
      ),
      iOS: const DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
      macOS: const DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
    );
    await _plugin.show(
      id: id,
      title: callerName,
      body: isVideo ? 'Incoming video call' : 'Incoming voice call',
      notificationDetails: details,
      payload: payload,
    );
  }
}
