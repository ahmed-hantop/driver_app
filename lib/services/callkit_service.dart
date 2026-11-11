import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

/// Wraps `flutter_callkit_incoming` so the rest of the app can show a native,
/// telecom-integrated incoming-call UI that rings even when the app process is
/// fully killed (Android ConnectionService / iOS CallKit) — the WhatsApp-style
/// experience — instead of a plain full-screen-intent local notification.
///
/// CallKit identifies every call by a UUID, but the backend keys calls by an
/// integer `call_log_id`. We map deterministically between the two so the same
/// call can be shown from an FCM push and later dismissed by a "call_cancel"
/// push (both sides derive the identical UUID from the call_log_id, no lookup
/// table needed).
class CallkitService {
  CallkitService._();
  static final CallkitService instance = CallkitService._();

  // The server keeps a small buffer beyond this value before recording a
  // missed call, so an accepting driver can never race a server timeout.
  static const int ringTimeoutSeconds = 60;

  /// Deterministic RFC-4122-shaped UUID from an integer call id.
  /// Format: 00000000-0000-4000-8000-XXXXXXXXXXXX (12 hex of the id, zero-padded).
  /// iOS CallKit rejects malformed UUIDs, so the shape must stay valid.
  static String uuidForCallId(int callLogId) {
    final hex = callLogId.toRadixString(16).padLeft(12, '0');
    final tail = hex.length > 12 ? hex.substring(hex.length - 12) : hex;
    return '00000000-0000-4000-8000-$tail';
  }

  /// Pull our integer call id back out of a CallKit params' extra map.
  static int? callLogIdFromExtra(Map<String, dynamic>? extra) {
    if (extra == null) return null;
    final raw = extra['call_log_id'];
    if (raw == null) return null;
    return int.tryParse(raw.toString());
  }

  static String callerNameFromExtra(Map<String, dynamic>? extra) =>
      extra?['caller_name']?.toString() ?? 'Admin';

  static String callTypeFromExtra(Map<String, dynamic>? extra) =>
      extra?['call_type']?.toString() ?? 'voice';

  CallKitParams _buildParams({
    required int callLogId,
    required String callerName,
    required String callType,
    Map<String, dynamic> extra = const {},
  }) {
    final isVideo = callType == 'video';
    return CallKitParams(
      id: uuidForCallId(callLogId),
      nameCaller: callerName,
      appName: 'Speed Driver',
      handle: 'Speed Logistics',
      type: isVideo ? 1 : 0,
      // Auto-times-out the native ring after N seconds (missed call).
      duration: ringTimeoutSeconds * 1000,
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: 'Missed call',
      ),
      extra: <String, dynamic>{
        'call_log_id': callLogId.toString(),
        'caller_name': callerName,
        'call_type': callType,
        ...extra,
      },
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#1A237E',
        actionColor: '#4CAF50',
        textColor: '#ffffff',
        incomingCallNotificationChannelName: 'Incoming Calls',
        missedCallNotificationChannelName: 'Missed Calls',
        isShowCallID: false,
        isShowFullLockedScreen: true,
        isImportant: true,
        textAccept: 'Answer',
        textDecline: 'Decline',
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );
  }

  /// Show the native incoming-call UI. Safe to call from the FCM background
  /// isolate (this is the canonical use case for the plugin).
  Future<void> showIncoming({
    required int callLogId,
    required String callerName,
    required String callType,
    Map<String, dynamic> extra = const {},
  }) async {
    try {
      final params = _buildParams(
        callLogId: callLogId,
        callerName: callerName,
        callType: callType,
        extra: extra,
      );
      await FlutterCallkitIncoming.showCallkitIncoming(params);
    } catch (e) {
      if (kDebugMode) debugPrint('CallkitService.showIncoming error: $e');
    }
  }

  /// Mark the call as connected in the OS (starts the CallKit call timer on iOS,
  /// promotes the Android notification to an ongoing call).
  Future<void> setConnected(int callLogId) async {
    try {
      await FlutterCallkitIncoming.setCallConnected(uuidForCallId(callLogId));
    } catch (e) {
      if (kDebugMode) debugPrint('CallkitService.setConnected error: $e');
    }
  }

  /// Dismiss a specific call's native UI (declined, ended, or cancelled by admin).
  Future<void> endCall(int callLogId) async {
    try {
      await FlutterCallkitIncoming.endCall(uuidForCallId(callLogId));
    } catch (e) {
      if (kDebugMode) debugPrint('CallkitService.endCall error: $e');
    }
  }

  Future<void> endAll() async {
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (e) {
      if (kDebugMode) debugPrint('CallkitService.endAll error: $e');
    }
  }

  /// Currently active/showing calls (used on cold start to detect an
  /// already-accepted call the app was launched for).
  Future<List<CallKitParams>> activeCalls() async {
    try {
      return await FlutterCallkitIncoming.activeCalls();
    } catch (e) {
      if (kDebugMode) debugPrint('CallkitService.activeCalls error: $e');
      return const [];
    }
  }

  /// Ask for the runtime permissions CallKit needs (Android 13 notifications,
  /// Android 14 full-screen-intent). No-op where already granted.
  Future<void> requestPermissions() async {
    try {
      await FlutterCallkitIncoming.requestNotificationPermission({
        'title': 'Notifications',
        'rationaleMessagePermission':
            'Notification permission is required to show incoming calls.',
        'postNotificationMessageRequired':
            'Enable notifications in Settings to receive incoming calls.',
      });
      final canFullScreen =
          await FlutterCallkitIncoming.canUseFullScreenIntent();
      if (!canFullScreen) {
        await FlutterCallkitIncoming.requestFullIntentPermission();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('CallkitService.requestPermissions error: $e');
    }
  }

  /// iOS VoIP push token (wired for later — needs an Apple VoIP push cert +
  /// APNs VoIP channel on the backend before it does anything on iOS).
  Future<String?> getIosVoipToken() async {
    try {
      final token = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
      return (token == null || token.isEmpty) ? null : token;
    } catch (_) {
      return null;
    }
  }
}
