
import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:driver_app/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:driver_app/dashboard_screen.dart';
import 'firebase_options.dart';
import 'package:driver_app/screens/permissions_setup_screen.dart';
import 'package:driver_app/screens/login_screen.dart';
import 'package:driver_app/screens/forgot_password_screen.dart';
import 'package:driver_app/screens/splash_screen.dart';
import 'package:driver_app/screens/calls/in_call_screen.dart';
import 'locale.dart';
import 'services/api_service.dart';
import 'services/call_service.dart';
import 'services/call_state.dart';
import 'services/callkit_service.dart';
import 'services/notification_service.dart';
import 'services/background_worker.dart';
import 'services/location_service.dart';
import 'services/crash_reporting_service.dart';
import 'services/driver_log_service.dart';
import 'services/log_redactor.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> _ensureFirebaseInitialized() async {
  if (Firebase.apps.isNotEmpty) return;
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

int _callIdFromData(Map<String, dynamic> data) {
  return int.tryParse(data['call_log_id']?.toString() ?? '') ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
}

// Guards against answering/declining the same call twice across the several
// entry points (live onEvent listener, cold-start activeCalls scan, background
// isolate).
final Set<int> _handledCallActions = <int>{};

// Set when an accept arrives before the navigator is ready (cold start from a
// killed app); routed once the first frame is up.
Map<String, dynamic>? _pendingAcceptedCall;

// FCM background/terminated data messages. Must be a top-level function.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await _ensureFirebaseInitialized();
  DartPluginRegistrant.ensureInitialized();

  final type = message.data['type'];
  final data = Map<String, dynamic>.from(message.data);

  if (type == 'call_invite') {
    // Ring the phone via the native telecom UI — works even when the app is
    // fully killed (the whole point of moving off local notifications).
    await CallkitService.instance.showIncoming(
      callLogId: _callIdFromData(data),
      callerName: data['caller_name']?.toString() ?? 'Admin',
      callType: data['call_type']?.toString() ?? 'voice',
    );
    // Tell DMS that the native telecom UI was actually shown. This gives the
    // caller an honest delivery state even when a terminated app cannot wake.
    try {
      await CallService().markRinging(_callIdFromData(data));
    } catch (_) {}
  } else if (type == 'call_cancel') {
    // Admin cancelled / call was answered elsewhere — dismiss the ringing UI.
    await CallkitService.instance.endCall(_callIdFromData(data));
  }
}

// CallKit events fired while the app is KILLED run in a dedicated background
// isolate. Accept re-launches the app (handled by the live onEvent listener);
// decline does not, so we settle it with the backend here. Must be top-level.
@pragma('vm:entry-point')
Future<void> _callkitBackgroundHandler(CallEvent event) async {
  if (event case CallEventActionCallDecline(:final callKitParams)) {
    final id = CallkitService.callLogIdFromExtra(callKitParams.extra);
    if (id != null) {
      try {
        await CallService().rejectCall(id);
      } catch (_) {}
    }
  }
  // Timeout => missed: recorded by the backend's scheduled missed-call sweep.
}

void _handleLocalNotificationResponse(NotificationResponse response) {
  // Chat notifications only — incoming-call UI is owned by CallKit now.
}

void _routeFcmMessage(RemoteMessage message) {
  final type = message.data['type'];
  final data = Map<String, dynamic>.from(message.data);

  if (type == 'call_invite') {
    final callLogId = _callIdFromData(data);
    unawaited(CallkitService.instance.showIncoming(
      callLogId: callLogId,
      callerName: data['caller_name']?.toString() ?? 'Admin',
      callType: data['call_type']?.toString() ?? 'voice',
    ));
    unawaited(CallService().markRinging(callLogId).catchError((_) {}));
  } else if (type == 'call_cancel') {
    unawaited(CallkitService.instance.endCall(_callIdFromData(data)));
  } else if (type == 'chat_message') {
    final title = message.notification?.title ?? message.data['title'] ?? 'New message';
    final body = message.notification?.body ?? message.data['body'] ?? 'You have a new chat message';
    unawaited(NotificationService.instance.showSimple(
      id: int.tryParse(message.data['conversation_id'] ?? '0') ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
    ));
    // Notify any open chat screen to reload — the screen polls every 5 s on its
    // own, but this fires an immediate refresh via the global key's context.
    chatRefreshNotifier.value++;
  }
}

// Subscribe to CallKit events while the app process is ALIVE.
void _listenForCallkitEvents() {
  FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
    switch (event) {
      case CallEventActionCallAccept(:final callKitParams):
        _onCallAccepted(callKitParams);
        break;
      case CallEventActionCallDecline(:final callKitParams):
        final id = CallkitService.callLogIdFromExtra(callKitParams.extra);
        if (id != null) unawaited(_settleDeclined(id));
        break;
      default:
        break;
    }
  });
}

void _onCallAccepted(CallKitParams params) {
  final callLogId = CallkitService.callLogIdFromExtra(params.extra);
  if (callLogId == null) return;
  if (_handledCallActions.contains(callLogId)) return;
  _handledCallActions.add(callLogId);

  final data = <String, dynamic>{
    'call_log_id': callLogId,
    'caller_name': CallkitService.callerNameFromExtra(params.extra),
    'call_type': CallkitService.callTypeFromExtra(params.extra),
  };

  if (navigatorKey.currentState == null) {
    // Cold start: nav not ready yet — flush after the first frame.
    _pendingAcceptedCall = data;
    return;
  }
  _navigateToAnsweredCall(data);
}

void _navigateToAnsweredCall(Map<String, dynamic> data) {
  final nav = navigatorKey.currentState;
  if (nav == null) return;
  final callLogId = (data['call_log_id'] as num).toInt();
  CallState.callScreenActive = true;
  nav
      .push(MaterialPageRoute(
        builder: (_) => InCallScreen.answering(
          answerCallLogId: callLogId,
          callerName: data['caller_name']?.toString() ?? 'Admin',
          callType: data['call_type']?.toString() ?? 'voice',
        ),
      ))
      .then((_) {
    CallState.callScreenActive = false;
    _handledCallActions.remove(callLogId);
  });
}

Future<void> _settleDeclined(int callLogId) async {
  try {
    await CallService().rejectCall(callLogId);
  } catch (_) {}
  await CallkitService.instance.endCall(callLogId);
}

// On cold start the app may have been launched by accepting a call from a
// killed state; the accept event can land before the listener is attached, so
// scan the active CallKit calls for one already accepted.
Future<void> _routeColdStartAcceptedCall() async {
  try {
    final calls = await CallkitService.instance.activeCalls();
    for (final c in calls) {
      if (c.isAccepted) {
        _onCallAccepted(c);
        return;
      }
    }
  } catch (_) {}
}

// Lightweight notifier so ChatScreen / ChatListScreen can react to FCM pushes.
final ValueNotifier<int> chatRefreshNotifier = ValueNotifier(0);

String _generateInstallId() {
  final rand = Random.secure();
  final b = List<int>.generate(16, (_) => rand.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // variant
  String h(int n) => n.toRadixString(16).padLeft(2, '0');
  return '${b.sublist(0, 4).map(h).join()}-'
      '${b.sublist(4, 6).map(h).join()}-'
      '${b.sublist(6, 8).map(h).join()}-'
      '${b.sublist(8, 10).map(h).join()}-'
      '${b.sublist(10, 16).map(h).join()}';
}

Future<void> _bootstrapApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _ensureFirebaseInitialized();

  // Register before optional startup work. An Android data-only call invite can
  // arrive while the foreground app is still booting.
  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

  // Write a stable install UUID once on first launch — used for new-device detection
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getString('driver_app_install_device_id') == null) {
    await prefs.setString('driver_app_install_device_id', _generateInstallId());
  }

  await CrashReportingService.instance.initialize();
  await DriverLogService.instance.initialize();
  await loadSavedLocale();
  await NotificationService.instance.init(onDidReceiveNotificationResponse: _handleLocalNotificationResponse);
  await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
  await BackgroundWorker.init();
  await initializeLocationService();

  // CallKit wiring is fully isolated so that a plugin / native / AOT-callback
  // failure can never take down app launch — calling just degrades, the app
  // still opens. onBackgroundMessage is async (it resolves a callback handle),
  // so its failure is caught via the returned Future, not the sync try/catch.
  void logCallkitInitError(Object e, StackTrace s) => unawaited(
        CrashReportingService.instance
            .recordError(e, s, reason: 'CallKit init', fatal: false),
      );
  try {
    // CallKit: Decline/Timeout fired while the app is killed (background isolate).
    unawaited(
      FlutterCallkitIncoming.onBackgroundMessage(_callkitBackgroundHandler)
          .catchError(logCallkitInitError),
    );
    // CallKit: Accept/Decline fired while the app is alive.
    _listenForCallkitEvents();
    // Runtime permissions CallKit needs (best-effort).
    unawaited(CallkitService.instance.requestPermissions());
  } catch (e, s) {
    logCallkitInitError(e, s);
  }

  // FCM: foreground — fires when a message arrives while the app is open.
  FirebaseMessaging.onMessage.listen(_routeFcmMessage);

  // FCM: background tap — user taps a system-tray notification while app is running in background.
  FirebaseMessaging.onMessageOpenedApp.listen(_routeFcmMessage);

  // FCM: token refresh — keep server in sync when Firebase rotates the push token.
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString('driver_app_install_device_id');
    final api = ApiService();
    await api.loadToken();
    await api.updateFcmToken(newToken, deviceId: deviceId);
  });

  // FCM: terminated tap — app was launched by tapping a (chat) notification.
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();

  runApp(const DriverApp());

  // Delay until the navigator is ready after runApp.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_pendingAcceptedCall != null) {
      // App was launched by accepting a call from a killed state.
      final pending = _pendingAcceptedCall!;
      _pendingAcceptedCall = null;
      _navigateToAnsweredCall(pending);
    } else {
      // Fallback: the accept event may have landed before our listener; scan
      // the OS for an already-accepted call.
      unawaited(_routeColdStartAcceptedCall());
    }
    if (initialMessage != null) {
      _routeFcmMessage(initialMessage);
    }
  });
}

Future<void> main() async {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    unawaited(CrashReportingService.instance.recordFlutterError(details));
    unawaited(
      DriverLogService.instance.recordError(
        details.exception,
        details.stack ?? StackTrace.current,
        reason: 'FlutterError.onError',
        fatal: true,
        context: {
          if (details.library != null) 'library': details.library,
          if (details.context != null) 'context': details.context.toString(),
        },
      ),
    );
    Zone.current.handleUncaughtError(details.exception, details.stack ?? StackTrace.current);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(
      CrashReportingService.instance.recordError(
        error,
        stack,
        reason: 'PlatformDispatcher.onError',
        fatal: true,
      ),
    );
    unawaited(
      DriverLogService.instance.recordError(
        error,
        stack,
        reason: 'PlatformDispatcher.onError',
        fatal: true,
      ),
    );
    if (kDebugMode) {
      debugPrint('Uncaught platform error: ${LogRedactor.sanitizeText(error)}');
      debugPrint(LogRedactor.sanitizeText(stack.toString(), maxChars: 1200));
    }
    return true;
  };

  await runZonedGuarded(
    _bootstrapApp,
    (error, stack) {
      unawaited(
        CrashReportingService.instance.recordError(
          error,
          stack,
          reason: 'runZonedGuarded',
          fatal: true,
        ),
      );
      unawaited(
        DriverLogService.instance.recordError(
          error,
          stack,
          reason: 'runZonedGuarded',
          fatal: true,
        ),
      );
      if (kDebugMode) {
        debugPrint('Uncaught zone error: ${LogRedactor.sanitizeText(error)}');
        debugPrint(LogRedactor.sanitizeText(stack.toString(), maxChars: 1200));
      }
    },
  );
}

class DriverApp extends StatelessWidget {
  const DriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: localeNotifier,
      builder: (context, locale, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
            useMaterial3: true,
          ),
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          routes: {
            '/login': (context) => const LoginScreen(),
            '/forgot-password': (context) => const ForgotPasswordScreen(),
            '/dashboard': (context) => const PermissionsSetupScreen(child: DashboardScreen()),
          },
          home: const SplashScreen(),
        );
      },
    );
  }
}
