import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:driver_app/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/business.dart';
import 'models/driver_profile.dart';
import 'screens/payroll/payroll_list_screen.dart';
import 'screens/chat/chat_list_screen.dart';
import 'screens/requests/requests_hub_screen.dart';
import 'services/chat_service.dart';
import 'services/call_service.dart';
import 'services/callkit_service.dart';
import 'models/driver_stats.dart';
import 'models/order.dart';
import 'models/vehicle.dart';
import 'services/api_service.dart';
import 'services/api_constants.dart';
import 'services/call_state.dart';
import 'locale.dart';
import 'services/background_worker.dart';
import 'services/driver_session_state_service.dart';
import 'services/log_redactor.dart';
import 'services/notification_service.dart';
import 'services/location_service.dart';
import 'services/security_service.dart';
import 'services/refresh_coalescer.dart';

enum _ProfileImageSource { camera, file }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  final ApiService _apiService = ApiService();
  DriverProfile? _profile;
  DriverStats? _stats;
  List<Business> _businesses = [];
  List<Vehicle> _vehicles = [];
  List<Order> _ordersActive = [];
  List<Order> _ordersCompleted = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _actionLoading = false;
  bool _loggingOut = false;
  bool _locating = false;
  bool _isCheckedIn = false;
  Timer? _locationTimer;
  Timer? _orderMonitorTimer;
  Timer? _autoRefreshTimer;
  Timer? _autoRefreshKickoffTimer;
  Timer? _orderOutboxTimer;
  final Map<int, DateTime> _lastPickupReminder = {};
  final Map<int, DateTime> _lastDeliveryReminder = {};

  DateTime? _lastHeavyRefreshAt;
  DateTime? _lastProfileFetchAt;
  DateTime? _lastBusinessesFetchAt;
  late final RefreshCoalescer _refreshCoalescer;
  static const Duration _defaultAutoRefreshInterval = Duration(minutes: 3);
  static const Duration _defaultOrderReminderCooldown = Duration(minutes: 10);
  Duration _autoRefreshInterval = _defaultAutoRefreshInterval;
  Duration _orderReminderCooldown = _defaultOrderReminderCooldown;
  static const Duration _heavyRefreshInterval = Duration(minutes: 5);
  // Static data (profile, businesses) fetched at most once per these TTLs
  static const Duration _profileTtl = Duration(minutes: 30);
  static const Duration _businessesTtl = Duration(minutes: 60);
  static const int _autoRefreshJitterMaxSeconds = 20;

  static const _cachedDriverNameKey = 'driver_name_cached';
  static const _cachedDriverMobileKey = 'driver_mobile_cached';
  static const _cachedCheckinStatusKey = 'driver_checkin_status_cached';
  static const _lastRemoteDiagnosticTokenKey = 'driver_last_remote_diag_token';
  static const _orderRemindersEnabledKey = 'driver_order_reminders_enabled';
  static const _coexistenceModeKey = 'driver_coexistence_mode_enabled';
  static const _orderLifecycleOutboxKey = 'driver_order_lifecycle_outbox_v1';
  static const _orderLocalRefMapKey = 'driver_order_local_ref_map_v1';
  static const _orderLifecycleDeadLetterKey =
      'driver_order_lifecycle_dead_letter_v1';

  int _chatUnreadCount = 0;
  int _lastChatUnreadCount = -1; // -1 = first fetch, don't notify yet
  int? _lastPolledIncomingCallId; // guards the CallKit fallback from re-ringing
  String _appVersion = '';
  Timer? _callPollTimer;
  static const Duration _orderOutboxFlushInterval = Duration(minutes: 1);
  static const Duration _orderOutboxMaxDelay = Duration(minutes: 5);
  static const int _orderOutboxUrgentThreshold = 6;
  static const int _orderOutboxBaseRetrySeconds = 15;
  static const int _orderOutboxMaxRetrySeconds = 300;
  static const int _orderOutboxMaxAttempts = 12;

  bool get _hasActiveOrders => _ordersActive.any((o) => !o.isDelivered);
  String? get _profileImageUrl {
    final raw = _profile?.image?.trim();
    if (raw == null || raw.isEmpty) return null;
    final version = (_profile?.updatedAt ?? '').trim();

    String withVersion(String url) {
      if (version.isEmpty) return url;
      final separator = url.contains('?') ? '&' : '?';
      return '$url${separator}v=${Uri.encodeQueryComponent(version)}';
    }

    // Handle protocol-relative and bare host values
    var normalized = raw.replaceAll(
      '\\',
      '/',
    ); // Normalize any escaped/backslash separators
    if (normalized.startsWith('//')) normalized = 'https:$normalized';
    if (!normalized.startsWith('http') &&
        normalized.contains(ApiConstants.publicHost)) {
      normalized = 'https://$normalized';
    }

    if (normalized.startsWith('http')) {
      // If backend returns a hosted drivers path, force the canonical public storage base.
      final uri = Uri.tryParse(normalized);
      if (uri == null) return normalized; // Fallback to the original string

      final hostIsDms = uri.host.contains(ApiConstants.publicHost);
      final pathHasDrivers = uri.path.contains('/drivers/');
      final needsRewrite = hostIsDms && pathHasDrivers;
      if (needsRewrite) {
        // Strip leading segments then rebuild on the canonical public path
        var path = uri.path;
        if (path.startsWith('/')) path = path.substring(1);
        if (path.startsWith('storage/'))
          path = path.substring('storage/'.length);
        if (path.startsWith('app/public/'))
          path = path.substring('app/public/'.length);
        if (path.startsWith('public/')) path = path.substring('public/'.length);
        path = path.replaceAll(RegExp(r'/+'), '/');
        return withVersion('${ApiConstants.publicStorageBaseUrl}/$path');
      }

      return withVersion(uri.toString());
    }

    // Normalize known storage prefixes for relative paths
    var cleaned = normalized;
    if (cleaned.startsWith('/')) cleaned = cleaned.substring(1);
    if (cleaned.startsWith('storage/'))
      cleaned = cleaned.substring('storage/'.length);
    if (cleaned.startsWith('app/public/'))
      cleaned = cleaned.substring('app/public/'.length);
    if (cleaned.startsWith('public/'))
      cleaned = cleaned.substring('public/'.length);

    // Collapse any duplicated slashes inside the path (e.g., drivers//image.jpg)
    cleaned = cleaned.replaceAll(RegExp(r'/+'), '/');

    // Final absolute URL to public storage
    return withVersion('${ApiConstants.publicStorageBaseUrl}/$cleaned');
  }

  void _refreshAllDataInBackground({bool includeHeavy = true}) {
    _refreshCoalescer.schedule(includeHeavy: includeHeavy);
  }

  final TextEditingController _checkinMeterCtrl = TextEditingController();
  final TextEditingController _checkoutMeterCtrl = TextEditingController();
  final TextEditingController _orderNumberCtrl = TextEditingController();
  final TextEditingController _amountReceivedCtrl = TextEditingController();
  final TextEditingController _amountPaidCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _mobileCtrl = TextEditingController();
  final TextEditingController _nationalityCtrl = TextEditingController();
  final TextEditingController _languageCtrl = TextEditingController();
  final TextEditingController _currentPwdCtrl = TextEditingController();
  final TextEditingController _newPwdCtrl = TextEditingController();
  final TextEditingController _confirmPwdCtrl = TextEditingController();
  bool _obscureCurrentPwd = true;
  bool _obscureNewPwd = true;
  bool _obscureConfirmPwd = true;
  Uint8List? _checkinImageBytes;
  String? _checkinImageName;
  Uint8List? _checkoutImageBytes;
  String? _checkoutImageName;
  Uint8List? _profileImageBytes;
  String? _profileImageName;
  Future<bool>? _cameraPermissionRequest;
  Future<bool>? _mediaPermissionRequest;
  Future<void> _permissionRequestTail = Future<void>.value();

  Business? _selectedBusiness;
  BusinessIdItem? _selectedBusinessId;
  bool _orderSubmitting = false;
  final Map<int, bool> _orderActionBusy = {};
  int _selectedPaymentType = 1; // 1 cash, 2 online

  double? _lat;
  double? _lng;
  String? _locationAddress;
  String? _mapboxToken;
  String? _mapboxStyle;
  double? _mapboxCenterLat;
  double? _mapboxCenterLng;
  double? _mapboxZoom;
  DateTime? _lastLocationSyncErrorAt;
  static const Duration _locationSyncErrorCooldown = Duration(minutes: 1);
  bool _liveTrackingEnabled = true;
  bool _orderRemindersEnabled = true;
  bool _coexistenceMode = false;
  bool _orderOutboxFlushInProgress = false;
  DateTime? _orderOutboxLastFlushAt;
  DateTime? _orderOutboxLastSuccessAt;
  Future<void> _outboxOperationTail = Future<void>.value();
  int _pendingTrackingQueueCount = 0;

  AppLocalizations get l10n => AppLocalizations.of(context)!;
  String get _currentLang => localeNotifier.value.languageCode;

  // Orders filtering/pagination
  String _ordersFilter = 'all';
  int _ordersPage = 0;
  static const int _ordersPageSize = 10;
  static const int _historyOrdersPageSize = 25;
  bool _completedHistoryLoading = false;
  bool _completedHistoryLoadedOnce = false;
  bool _completedHistoryHasMore = false;
  int _completedHistoryPage = 0;
  int _completedHistoryTotal = 0;

  Future<void> _onChangeLanguage(String? value) async {
    if (value == null || value == _currentLang) return;
    await saveLocale(value);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadTrackingSettings() async {
    try {
      final live = await isLiveTrackingEnabled();
      final policy = await getTrackingPolicy();
      final pending = await pendingLocationQueueCount();
      final prefs = await SharedPreferences.getInstance();
      final remindersEnabled = prefs.getBool(_orderRemindersEnabledKey) ?? true;
      final coexistenceMode = prefs.getBool(_coexistenceModeKey) ?? false;

      final autoRefreshSeconds = policy != null
          ? int.tryParse(policy['auto_refresh_seconds']?.toString() ?? '')
          : null;
      final reminderCooldownSeconds = policy != null
          ? int.tryParse(
              policy['order_reminder_cooldown_seconds']?.toString() ?? '',
            )
          : null;

      if (!mounted) return;
      setState(() {
        _liveTrackingEnabled = live;
        _orderRemindersEnabled = remindersEnabled;
        _coexistenceMode = coexistenceMode;
        if (autoRefreshSeconds != null && autoRefreshSeconds >= 30) {
          _autoRefreshInterval = Duration(seconds: autoRefreshSeconds);
        }
        if (reminderCooldownSeconds != null && reminderCooldownSeconds >= 60) {
          _orderReminderCooldown = Duration(seconds: reminderCooldownSeconds);
        }
        _pendingTrackingQueueCount = pending;
      });
    } catch (_) {
      return;
    }
  }

  Future<void> _applyTrackingPolicyFromProfile(
    Map<String, dynamic> payload,
  ) async {
    final rawPolicy = payload['tracking_policy'];
    if (rawPolicy is! Map) return;

    final policy = rawPolicy.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    await applyTrackingPolicy(policy);

    final coexistenceMode = _parseBool(policy['coexistence_mode']) ?? false;
    final liveTrackingEnabled = _parseBool(policy['live_tracking_enabled']);
    final remindersEnabled =
        _parseBool(policy['order_reminders_enabled']) ?? !coexistenceMode;
    final autoRefreshSeconds = int.tryParse(
      policy['auto_refresh_seconds']?.toString() ?? '',
    );
    final reminderCooldownSeconds = int.tryParse(
      policy['order_reminder_cooldown_seconds']?.toString() ?? '',
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_orderRemindersEnabledKey, remindersEnabled);
    await prefs.setBool(_coexistenceModeKey, coexistenceMode);
    if (liveTrackingEnabled != null) {
      await setLiveTrackingEnabled(liveTrackingEnabled);
    }

    if (!mounted) return;
    setState(() {
      _coexistenceMode = coexistenceMode;
      _orderRemindersEnabled = remindersEnabled;
      if (autoRefreshSeconds != null && autoRefreshSeconds >= 30) {
        _autoRefreshInterval = Duration(seconds: autoRefreshSeconds);
      }
      if (reminderCooldownSeconds != null && reminderCooldownSeconds >= 60) {
        _orderReminderCooldown = Duration(seconds: reminderCooldownSeconds);
      }
      if (liveTrackingEnabled != null) {
        _liveTrackingEnabled = liveTrackingEnabled;
      } else if (_coexistenceMode) {
        _liveTrackingEnabled = false;
      }
    });

    _startAutoRefresh();
    _startChatAndCallPolling();
  }

  void _startChatAndCallPolling() {
    _callPollTimer?.cancel();
    unawaited(_pollChatAndCalls());
    _callPollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _pollChatAndCalls();
    });
  }

  Future<void> _pollChatAndCalls() async {
    if (!mounted) return;
    // Refresh chat unread count and notify on new messages
    if (_profile?.chatEnabled == true) {
      final count = await ChatService().fetchUnreadCount();
      if (mounted) {
        if (_lastChatUnreadCount >= 0 && count > _lastChatUnreadCount) {
          unawaited(
            NotificationService.instance.showSimple(
              id: 9001,
              title: 'New Message',
              body: 'You have a new message from admin',
            ),
          );
        }
        _lastChatUnreadCount = count;
        setState(() => _chatUnreadCount = count);
      }
    }
    // Poll for a pending incoming call (FCM fallback, in case the push was
    // dropped). Ring it through the same native CallKit UI as the push path so
    // the experience is identical; the deterministic UUID means calling this
    // for a call already shown by FCM just updates it rather than duplicating.
    if (_profile?.callsEnabled == true && !CallState.callScreenActive) {
      final call = await CallService().checkPendingCall();
      if (call != null && call.callLogId != _lastPolledIncomingCallId) {
        _lastPolledIncomingCallId = call.callLogId;
        unawaited(
          CallkitService.instance.showIncoming(
            callLogId: call.callLogId,
            callerName: call.callerName,
            callType: call.callType,
          ),
        );
      }
    }
  }

  bool _shouldRunHeavyRefresh() {
    final now = DateTime.now();
    if (_lastHeavyRefreshAt == null ||
        now.difference(_lastHeavyRefreshAt!) >= _heavyRefreshInterval) {
      _lastHeavyRefreshAt = now;
      return true;
    }
    return false;
  }

  bool _isProfileStale() {
    if (_lastProfileFetchAt == null) return true;
    return DateTime.now().difference(_lastProfileFetchAt!) >= _profileTtl;
  }

  bool _isBusinessesStale() {
    if (_lastBusinessesFetchAt == null) return true;
    return DateTime.now().difference(_lastBusinessesFetchAt!) >= _businessesTtl;
  }

  // Adaptive polling rate: fastest when checked in with active orders, slowest when idle
  Duration _computeAutoRefreshInterval() {
    if (!_isCheckedIn) return const Duration(minutes: 10);
    if (_ordersActive.isEmpty) return const Duration(minutes: 5);
    return _autoRefreshInterval; // 3 min default (or server override)
  }

  Future<void> _refreshAllData({bool includeHeavy = true}) async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final tasks = <Future<void>>[_fetchStats(), _fetchOrders(liveOnly: true)];

      if (includeHeavy) {
        // Only re-fetch profile and businesses when their TTL has expired
        if (_isProfileStale()) tasks.add(_fetchProfile());
        if (_isBusinessesStale()) tasks.add(_fetchBusinesses());
      }

      await Future.wait(tasks);

      if (includeHeavy) {
        _lastHeavyRefreshAt = DateTime.now();
      }
    } finally {
      _refreshing = false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshCoalescer = RefreshCoalescer(
      runRefresh: (includeHeavy) => _refreshAllData(includeHeavy: includeHeavy),
    );
    _loadTrackingSettings();
    _loadData();
    _startOrderOutboxSync();
    _resumeForegroundLoops();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _appVersion = 'v${info.version}');
    });
    unawaited(() async {
      await _restoreCachedCheckinStatus();
      if (!mounted) return;
      _resumeForegroundLoops();
      await _syncCheckedInRuntime();
    }());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _checkinMeterCtrl.dispose();
    _checkoutMeterCtrl.dispose();
    _orderNumberCtrl.dispose();
    _amountReceivedCtrl.dispose();
    _amountPaidCtrl.dispose();
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    _nationalityCtrl.dispose();
    _languageCtrl.dispose();
    _currentPwdCtrl.dispose();
    _newPwdCtrl.dispose();
    _confirmPwdCtrl.dispose();
    _locationTimer?.cancel();
    _orderMonitorTimer?.cancel();
    _autoRefreshTimer?.cancel();
    _autoRefreshKickoffTimer?.cancel();
    _orderOutboxTimer?.cancel();
    _callPollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumeForegroundLoops();
      unawaited(_flushOrderLifecycleOutbox(force: false));
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _pauseForegroundLoops();
    }
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }
    try {
      await _ensureNotificationPermission();
      await _fetchProfile();
      await Future.wait([
        _fetchStats(),
        _fetchBusinesses(),
        _fetchOrders(liveOnly: true),
      ]);
      _lastHeavyRefreshAt = DateTime.now();
    } catch (e) {
      debugPrint('Load data failed: ${LogRedactor.sanitizeText(e)}');
      if (!mounted) return;
      _setMessage(l10n.failedToLoadData, isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<bool> _handleUnauthorizedIfNeeded() async {
    if (_apiService.isUnauthorized) {
      await _logout();
      return true;
    }
    return false;
  }

  Future<bool> _logoutIfUnauthorizedAfterAction() async {
    if (!_apiService.isUnauthorized) {
      return false;
    }

    await _logout();
    return true;
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  String _lastSyncLabel() {
    final last = _orderOutboxLastSuccessAt ?? _orderOutboxLastFlushAt;
    if (last == null) return 'Last sync: Never';

    final age = DateTime.now().difference(last);
    if (age.inMinutes < 1) return 'Last sync: just now';
    if (age.inMinutes < 60) return 'Last sync: ${age.inMinutes} min ago';
    if (age.inHours < 24) return 'Last sync: ${age.inHours}h ago';
    return 'Last sync: ${_formatDateTime(last)}';
  }

  Future<void> _syncNowFromHome() async {
    if (_orderOutboxFlushInProgress) return;
    await _flushOrderLifecycleOutbox(force: true);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _fetchProfile() async {
    final prevCheckedIn = _isCheckedIn;
    final data = await _apiService.getProfile();
    if (data == null) {
      if (_apiService.isUnauthorized) {
        await _logout();
        return;
      }
      if (!mounted) return;
      _setMessage(l10n.unableLoadProfile, isError: true);
      return;
    }
    final payload = data['driver'] is Map<String, dynamic>
        ? data['driver'] as Map<String, dynamic>
        : data;
    final profile = DriverProfile.fromJson(payload);
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _lat = profile.lat;
      _lng = profile.lng;
      _locationAddress = profile.locationAddress;
      _mapboxToken = profile.mapboxToken;
      _mapboxStyle = profile.mapboxStyle;
      _mapboxCenterLat = profile.mapboxCenterLat;
      _mapboxCenterLng = profile.mapboxCenterLng;
      _mapboxZoom = profile.mapboxZoom;
      final profileCheckedIn = _parseBool(
        payload['is_checked_in'] ??
            payload['checked_in'] ??
            payload['checkedIn'] ??
            payload['check_in'] ??
            payload['checkin_status'],
      );
      if (profileCheckedIn != null) {
        _isCheckedIn = profileCheckedIn; // trust backend flag explicitly
      } else {
        // Fallback: infer explicit checkout if status string contains "out"
        final statusLower = profile.status.toLowerCase();
        if (statusLower.contains('out')) {
          _isCheckedIn = false;
        }
      }
      _nameCtrl.text = profile.name;
      _mobileCtrl.text = profile.mobile ?? '';
      _nationalityCtrl.text = profile.nationality ?? '';
      _languageCtrl.text = profile.language ?? '';
    });
    if (kDebugMode) {
      debugPrint(
        'Profile status=${profile.status}, location=<redacted>, isCheckedIn=$_isCheckedIn',
      );
    }
    _lastProfileFetchAt = DateTime.now();
    await _persistCheckinStatus(_isCheckedIn);
    await _applyTrackingPolicyFromProfile(payload);
    await _cacheProfileBasics(profile);
    await _runRemoteDiagnosticIfRequested(payload);
    if (prevCheckedIn && !_isCheckedIn && mounted) {
      _showToast(
        'You have been checked out automatically.',
        isError: false,
        isSuccess: false,
      );
    }
    _resumeForegroundLoops();
  }

  Future<void> _runRemoteDiagnosticIfRequested(
    Map<String, dynamic> payload,
  ) async {
    final remote = payload['remote_diagnostic'];
    if (remote is! Map) return;

    final token = remote['token']?.toString().trim() ?? '';
    if (token.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final lastToken = prefs.getString(_lastRemoteDiagnosticTokenKey) ?? '';
    if (lastToken == token) return;

    String? appVersion;
    String? buildNumber;
    try {
      final package = await PackageInfo.fromPlatform();
      appVersion = package.version;
      buildNumber = package.buildNumber;
    } catch (_) {}

    final context = <String, dynamic>{
      'token': token,
      'requested_at': remote['requested_at']?.toString(),
      'requested_by': remote['requested_by']?.toString(),
      'api': _apiService.getPerformanceSnapshot(),
      'location': locationPerformanceSnapshot(),
      'runtime': {
        'checked_in': _isCheckedIn,
        'live_tracking_enabled': _liveTrackingEnabled,
        'pending_tracking_queue_count': _pendingTrackingQueueCount,
        'loading': _loading,
        'refreshing': _refreshing,
      },
    };

    final log = <String, dynamic>{
      'level': 'info',
      'event': ApiConstants.remoteDiagnosticEvent,
      'message': 'Remote diagnostic snapshot from driver app',
      'context': context,
      'occurred_at': DateTime.now().toUtc().toIso8601String(),
      'app_version': appVersion,
      'build_number': buildNumber,
    };

    final sent = await _apiService.sendDriverAppLogs([log]);
    if (sent) {
      await prefs.setString(_lastRemoteDiagnosticTokenKey, token);
    }
  }

  Future<void> _cacheProfileBasics(DriverProfile profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cachedDriverNameKey, profile.name);
      if (profile.mobile != null && profile.mobile!.isNotEmpty) {
        await prefs.setString(_cachedDriverMobileKey, profile.mobile!);
      }
      await _syncCheckedInRuntime();
    } catch (e) {
      debugPrint('Cache profile basics failed: ${LogRedactor.sanitizeText(e)}');
    }
  }

  Future<void> _persistCheckinStatus(bool isCheckedIn) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_cachedCheckinStatusKey, isCheckedIn);
    } catch (e) {
      debugPrint(
        'Persist check-in status failed: ${LogRedactor.sanitizeText(e)}',
      );
    }
  }

  Future<void> _restoreCachedCheckinStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getBool(_cachedCheckinStatusKey);
      if (cached != null && mounted) {
        setState(() {
          _isCheckedIn = cached;
        });
      }
    } catch (e) {
      debugPrint(
        'Restore check-in status failed: ${LogRedactor.sanitizeText(e)}',
      );
    }
  }

  Future<void> _fetchStats() async {
    final data = await _apiService.getStats();
    if (data == null) {
      final handled = await _handleUnauthorizedIfNeeded();
      if (handled) return;
      return;
    }
    final stats = DriverStats.fromJson(data);
    if (mounted) {
      setState(() {
        _stats = stats;
      });
    }
  }

  Future<void> _fetchBusinesses() async {
    final data = await _apiService.getBusinesses();
    if (data == null) {
      final handled = await _handleUnauthorizedIfNeeded();
      if (handled) return;
      return;
    }
    // Support multiple response shapes: {response: [...]}, {businesses: [...]}, raw list
    List businessesList = [];
    final driverMapRaw = data['driver'];
    final driverMap = driverMapRaw is Map<String, dynamic>
        ? driverMapRaw
        : null;
    final candidates = [
      data['businesses'],
      data['data'],
      data['response'],
      data,
      if (driverMap != null) driverMap['businesses'],
      if (driverMap != null) driverMap['driver_businesses'],
      if (driverMap != null) driverMap['business'],
    ];
    for (final candidate in candidates) {
      if (candidate is List) {
        businessesList = candidate;
        break;
      }
      if (candidate is Map && candidate['businesses'] is List) {
        businessesList = candidate['businesses'] as List;
        break;
      }
    }

    if (businessesList.isEmpty) {
      // Fallback: find any list-valued entry that looks like businesses
      for (final entry in data.values) {
        if (entry is List && entry.isNotEmpty && entry.first is Map) {
          final first = entry.first as Map;
          if (first.containsKey('name') ||
              first.containsKey('business_name') ||
              first.containsKey('platform_id')) {
            businessesList = entry;
            break;
          }
        }
      }
    }

    final assignedMapRaw = data['assigned_ids_by_business'];
    final idsByBusiness = <int, List<BusinessIdItem>>{};
    if (assignedMapRaw is Map) {
      assignedMapRaw.forEach((key, value) {
        final businessId = int.tryParse(key.toString());
        if (businessId == null || value is! List) return;
        final idValues = value
            .whereType<Map<String, dynamic>>()
            .map(BusinessIdItem.fromJson)
            .where((e) => e.value.isNotEmpty)
            .toList();
        if (idValues.isNotEmpty) {
          idsByBusiness[businessId] = idValues;
        }
      });
    }

    final parsedBusinesses = businessesList
        .whereType<Map<String, dynamic>>()
        .map((e) {
          final base = Business.fromJson(e);
          final mergedIds = <String>{...base.ids};
          final mergedBusinessIds = <BusinessIdItem>[...base.businessIds];
          if (base.id != null && idsByBusiness.containsKey(base.id)) {
            final extras = idsByBusiness[base.id!]!;
            mergedIds.addAll(extras.map((e) => e.value));
            mergedBusinessIds.addAll(extras);
          }
          return Business(
            id: base.id,
            name: base.name,
            image: base.image,
            ids: mergedIds.toList(),
            businessIds: mergedBusinessIds,
            platformId: base.platformId,
          );
        })
        .where(
          (b) =>
              b.ids.isNotEmpty ||
              (b.platformId != null && b.platformId!.isNotEmpty),
        )
        .toList();

    final vehiclesRaw =
        data['vehicles'] ??
        data['vehicle'] ??
        data['assigned_vehicle'] ??
        data['assigned_vehicles'];
    List vehiclesList;
    if (vehiclesRaw is List) {
      vehiclesList = vehiclesRaw;
    } else if (vehiclesRaw is Map<String, dynamic>) {
      vehiclesList = [vehiclesRaw];
    } else {
      vehiclesList = [];
    }

    final parsedVehicles = vehiclesList
        .whereType<Map<String, dynamic>>()
        .map(Vehicle.fromJson)
        .toList();
    final backendCheckedIn = _parseBool(
      data['is_checked_in'] ??
          data['checked_in'] ??
          data['checkedIn'] ??
          (data['driver'] is Map<String, dynamic>
              ? (data['driver'] as Map<String, dynamic>)['is_checked_in']
              : null) ??
          (data['driver'] is Map<String, dynamic>
              ? (data['driver'] as Map<String, dynamic>)['checked_in']
              : null),
    );

    if (mounted) {
      setState(() {
        _businesses = parsedBusinesses;
        _vehicles = parsedVehicles;
        if (backendCheckedIn != null) {
          _isCheckedIn = backendCheckedIn;
        }
      });
    }
    _lastBusinessesFetchAt = DateTime.now();
    await _persistCheckinStatus(_isCheckedIn);
    _restartLocationPolling();
    debugPrint(
      'Businesses parsed=${parsedBusinesses.length}, vehicles=${parsedVehicles.length}, backend_checked_in=$backendCheckedIn, isCheckedIn=$_isCheckedIn',
    );
  }

  List<Order> _parseOrders(dynamic raw) {
    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map((e) => Order.fromJson(e))
          .toList();
    }
    if (raw is Map && raw['orders'] is List) {
      return raw['orders']
          .whereType<Map<String, dynamic>>()
          .map((e) => Order.fromJson(e))
          .toList();
    }
    return [];
  }

  Business? _findBusinessById(int? businessId) {
    if (businessId == null || businessId <= 0) {
      return null;
    }

    for (final business in _businesses) {
      if (business.id == businessId) {
        return business;
      }
    }

    return null;
  }

  bool _sameOrderIdentity(Order left, Order right) {
    final leftNumber = left.orderNumber.trim();
    final rightNumber = right.orderNumber.trim();
    if (leftNumber.isEmpty ||
        rightNumber.isEmpty ||
        leftNumber != rightNumber) {
      return false;
    }

    final sameBusiness =
        left.businessId == null ||
        right.businessId == null ||
        left.businessId == right.businessId;
    final sameBusinessId =
        left.businessIdId == null ||
        right.businessIdId == null ||
        left.businessIdId == right.businessIdId;
    final closeInTime = left.createdAt == null || right.createdAt == null
        ? true
        : left.createdAt!.difference(right.createdAt!).inMinutes.abs() <= 120;

    return sameBusiness && sameBusinessId && closeInTime;
  }

  Order? _pendingCreateOrderFromQueueItem(
    Map<String, dynamic> item,
    Map<String, int> localRefMap,
  ) {
    if ((item['action']?.toString() ?? '') != 'create') {
      return null;
    }

    final payloadRaw = item['payload'];
    if (payloadRaw is! Map) {
      return null;
    }

    final payload = payloadRaw.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final localOrderId = _asInt(payload['local_order_id']);
    if (localOrderId >= 0 || localRefMap.containsKey(localOrderId.toString())) {
      return null;
    }

    final businessId = _asInt(payload['business_id']);
    final businessIdId = _asInt(payload['business_id_id']);
    final business = _findBusinessById(businessId > 0 ? businessId : null);
    String? businessIdValue;

    if (business != null && businessIdId > 0) {
      for (final item in business.businessIds) {
        if (item.id == businessIdId) {
          businessIdValue = item.value;
          break;
        }
      }
    }

    return Order(
      id: localOrderId,
      orderNumber: payload['order_number']?.toString() ?? '',
      businessName: business?.name ?? 'Order',
      businessIdValue: businessIdValue,
      businessId: businessId > 0 ? businessId : null,
      businessIdId: businessIdId > 0 ? businessIdId : null,
      status: 'pending_sync',
      createdAt: DateTime.tryParse(
        item['enqueued_at']?.toString() ?? '',
      )?.toLocal(),
    );
  }

  Future<List<Order>> _loadPendingCreateOrders() async {
    final queue = await _loadOrderLifecycleOutbox();
    if (queue.isEmpty) {
      return const <Order>[];
    }

    final localRefMap = await _loadOrderLocalRefMap();
    final pendingOrders = queue
        .map((item) => _pendingCreateOrderFromQueueItem(item, localRefMap))
        .whereType<Order>()
        .toList();

    pendingOrders.sort((left, right) {
      final leftTime = left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final rightTime =
          right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return rightTime.compareTo(leftTime);
    });

    return pendingOrders;
  }

  List<Order> _mergePendingCreateOrders(
    List<Order> serverOrders,
    List<Order> pendingOrders,
  ) {
    final unresolvedPending = pendingOrders.where((pending) {
      return !serverOrders.any((server) => _sameOrderIdentity(server, pending));
    }).toList();

    return [...unresolvedPending, ...serverOrders];
  }

  int _parsePositiveInt(dynamic value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  List<Order> _mergeOrdersById(List<Order> existing, List<Order> incoming) {
    final merged = <int, Order>{};
    for (final order in existing) {
      merged[order.id] = order;
    }
    for (final order in incoming) {
      merged[order.id] = order;
    }

    final values = merged.values.toList()
      ..sort((left, right) => right.id.compareTo(left.id));
    return values;
  }

  Future<void> _fetchOrders({
    bool liveOnly = false,
    bool includeHistory = false,
    int historyPage = 1,
    bool appendHistory = false,
  }) async {
    if (includeHistory && mounted) {
      setState(() {
        _completedHistoryLoading = true;
      });
    }

    try {
      final data = await _apiService.getOrders(
        liveOnly: liveOnly,
        includeHistory: includeHistory,
        historyPage: historyPage,
        historyPerPage: _historyOrdersPageSize,
      );
      if (data == null) {
        final handled = await _handleUnauthorizedIfNeeded();
        if (handled) return;
        return;
      }

      final rawHistory = data['history'];
      final history = rawHistory is Map
          ? rawHistory.map((key, value) => MapEntry(key.toString(), value))
          : const <String, dynamic>{};

      final all = _parseOrders(
        data['allOrders'] ??
            data['orders'] ??
            data['data'] ??
            data['response'] ??
            data,
      );
      final active = _parseOrders(data['activeOrders']);
      final completed = _parseOrders(data['completedOrders']);
      final pendingCreates = await _loadPendingCreateOrders();

      if (mounted) {
        setState(() {
          final allActive = active.isNotEmpty
              ? active
              : all.where((o) => !o.isDelivered && !o.isCancelled).toList();
          _ordersActive = _mergePendingCreateOrders(
            allActive.where((o) => !o.isCancelled).toList(),
            pendingCreates,
          );

          if (includeHistory) {
            final historyOrders = completed.isNotEmpty
                ? completed
                : all.where((o) => o.isDelivered || o.isCancelled).toList();
            _ordersCompleted = appendHistory
                ? _mergeOrdersById(_ordersCompleted, historyOrders)
                : historyOrders;
            _completedHistoryLoadedOnce = true;
            _completedHistoryPage = _parsePositiveInt(
              history['current_page'],
              fallback: historyPage,
            );
            _completedHistoryHasMore =
                _parseBool(history['has_more_pages']) ?? false;
            _completedHistoryTotal = _parsePositiveInt(
              history['total'],
              fallback: _ordersCompleted.length,
            );
            _completedHistoryLoading = false;
          } else if (!liveOnly) {
            final allCompleted = completed.isNotEmpty
                ? completed
                : all.where((o) => o.isDelivered || o.isCancelled).toList();
            _ordersCompleted = allCompleted;
            _completedHistoryLoadedOnce = true;
            _completedHistoryPage = 1;
            _completedHistoryHasMore = false;
            _completedHistoryTotal = _ordersCompleted.length;
          }
        });
      }
      _pruneReminderCaches();
      // Restart order monitor if orders arrived while timer was stopped
      if (_ordersActive.isNotEmpty && _orderMonitorTimer == null) {
        _startOrderMonitor();
      }
      _evaluateOrderNotifications();
    } finally {
      if (includeHistory && mounted && _completedHistoryLoading) {
        setState(() {
          _completedHistoryLoading = false;
        });
      }
    }
  }

  Future<void> _ensureCompletedHistoryLoaded({
    bool forceRefresh = false,
  }) async {
    if (_completedHistoryLoading) return;
    if (!forceRefresh && _completedHistoryLoadedOnce) return;
    await _fetchOrders(includeHistory: true, historyPage: 1);
  }

  Future<void> _loadMoreCompletedHistory() async {
    if (_completedHistoryLoading || !_completedHistoryHasMore) return;
    await _fetchOrders(
      includeHistory: true,
      historyPage: _completedHistoryPage + 1,
      appendHistory: true,
    );
  }

  void _onOrdersFilterChanged(String value) {
    if (_ordersFilter == value) return;

    setState(() {
      _ordersFilter = value;
      _ordersPage = 0;
    });

    if (value != 'active') {
      unawaited(_ensureCompletedHistoryLoaded());
    }
  }

  void _handleTabTap(int index) {
    if (_currentIndex != index) {
      setState(() {
        _currentIndex = index;
      });
    }

    if (index == 1) {
      unawaited(_ensureCompletedHistoryLoaded(forceRefresh: true));
    }
  }

  void _startOrderMonitor() {
    _orderMonitorTimer?.cancel();
    if (!_isCheckedIn || _ordersActive.isEmpty) {
      _orderMonitorTimer = null;
      return;
    }

    _orderMonitorTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_ordersActive.isEmpty) {
        _orderMonitorTimer?.cancel();
        _orderMonitorTimer = null;
        return;
      }
      _evaluateOrderNotifications();
    });
  }

  void _pauseForegroundLoops() {
    _stopLocationPolling();

    _orderMonitorTimer?.cancel();
    _orderMonitorTimer = null;

    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;

    _autoRefreshKickoffTimer?.cancel();
    _autoRefreshKickoffTimer = null;
  }

  void _resumeForegroundLoops() {
    _startAutoRefresh();
    _startOrderMonitor();
    _restartLocationPolling();
  }

  void _startOrderOutboxSync() {
    _orderOutboxTimer?.cancel();
    unawaited(_flushOrderLifecycleOutbox(force: false));
    _orderOutboxTimer = Timer.periodic(_orderOutboxFlushInterval, (_) {
      unawaited(_flushOrderLifecycleOutbox(force: false));
    });
  }

  bool _canUseResourcesForOutboxFlush() {
    return !_loading &&
        !_refreshing &&
        !_actionLoading &&
        !_orderSubmitting &&
        !_locating;
  }

  String _newOutboxId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(999999)}';

  DateTime _nextRetryTimeForAttempt(int attempts) {
    final power = attempts <= 1 ? 1 : (1 << (attempts - 1));
    final seconds = (_orderOutboxBaseRetrySeconds * power).clamp(
      _orderOutboxBaseRetrySeconds,
      _orderOutboxMaxRetrySeconds,
    );
    return DateTime.now().toUtc().add(Duration(seconds: seconds));
  }

  Future<T> _runOutboxLocked<T>(Future<T> Function() operation) {
    final previous = _outboxOperationTail;
    final gate = Completer<void>();
    _outboxOperationTail = gate.future;

    return previous.catchError((_) {}).then((_) => operation()).whenComplete(
      () {
        if (!gate.isCompleted) {
          gate.complete();
        }
      },
    );
  }

  bool _isOutboxItemReady(
    Map<String, dynamic> item, {
    required bool allowOverride,
  }) {
    if (allowOverride) return true;
    final retryAt = DateTime.tryParse(item['next_retry_at']?.toString() ?? '');
    if (retryAt == null) return true;
    return !DateTime.now().toUtc().isBefore(retryAt);
  }

  Future<List<Map<String, dynamic>>> _loadOrderLifecycleOutbox() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_orderLifecycleOutboxKey);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _saveOrderLifecycleOutbox(
    List<Map<String, dynamic>> queue,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_orderLifecycleOutboxKey, jsonEncode(queue));
  }

  Future<void> _appendOutboxDeadLetter(
    Map<String, dynamic> item,
    String reason,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_orderLifecycleDeadLetterKey);
    final list = <Map<String, dynamic>>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          list.addAll(
            decoded.whereType<Map>().map(
              (e) => e.map((k, v) => MapEntry(k.toString(), v)),
            ),
          );
        }
      } catch (_) {}
    }

    list.add({
      ...item,
      'dead_letter_reason': reason,
      'dead_letter_at': DateTime.now().toUtc().toIso8601String(),
    });

    if (list.length > 100) {
      list.removeRange(0, list.length - 100);
    }

    await prefs.setString(_orderLifecycleDeadLetterKey, jsonEncode(list));
  }

  Future<Map<String, int>> _loadOrderLocalRefMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_orderLocalRefMapKey);
    if (raw == null || raw.isEmpty) return <String, int>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, int>{};
      final map = <String, int>{};
      decoded.forEach((key, value) {
        final parsed = int.tryParse(value?.toString() ?? '');
        if (parsed != null && parsed > 0) {
          map[key.toString()] = parsed;
        }
      });
      return map;
    } catch (_) {
      return <String, int>{};
    }
  }

  Future<void> _saveOrderLocalRefMap(Map<String, int> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_orderLocalRefMapKey, jsonEncode(map));
  }

  Future<void> _enqueueOrderLifecycleAction(
    String action,
    Map<String, dynamic> payload,
  ) async {
    final queueId = _newOutboxId();
    final enrichedPayload = {...payload, 'client_request_id': queueId};

    await _runOutboxLocked(() async {
      final queue = await _loadOrderLifecycleOutbox();
      queue.add({
        'id': queueId,
        'action': action,
        'payload': enrichedPayload,
        'enqueued_at': DateTime.now().toUtc().toIso8601String(),
        'next_retry_at': null,
        'attempts': 0,
      });
      await _saveOrderLifecycleOutbox(queue);
      final urgent = queue.length >= _orderOutboxUrgentThreshold;
      unawaited(_flushOrderLifecycleOutbox(force: urgent));
    });
  }

  int _nextLocalOrderRef() {
    final existingMin = _ordersActive.isEmpty
        ? -1
        : _ordersActive.map((o) => o.id).reduce((a, b) => a < b ? a : b);
    return existingMin <= -1 ? existingMin - 1 : -1;
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  Future<int?> _resolveServerOrderIdByPayload(
    Map<String, dynamic> payload,
  ) async {
    final orderNumber = payload['order_number']?.toString().trim() ?? '';
    if (orderNumber.isEmpty) return null;

    final businessId = _asInt(payload['business_id']);
    final businessIdId = _asInt(payload['business_id_id']);
    final createdAt = DateTime.tryParse(
      payload['enqueued_at']?.toString() ?? '',
    )?.toLocal();

    final ordersData = await _apiService.getOrders();
    if (ordersData == null) return null;
    final all = _parseOrders(
      ordersData['allOrders'] ??
          ordersData['orders'] ??
          ordersData['data'] ??
          ordersData['response'] ??
          ordersData,
    );
    final match = all.where((o) {
      final sameNumber = o.orderNumber.trim() == orderNumber;
      final sameBusiness = businessId <= 0 || o.businessId == businessId;
      final sameBusinessId =
          businessIdId <= 0 || o.businessIdId == businessIdId;
      final nearTime = createdAt == null || o.createdAt == null
          ? true
          : o.createdAt!.difference(createdAt).inMinutes.abs() <= 120;
      return sameNumber && sameBusiness && sameBusinessId && nearTime;
    }).toList();
    if (match.isEmpty) return null;
    match.sort((a, b) {
      final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    return match.first.id > 0 ? match.first.id : null;
  }

  Future<void> _flushOrderLifecycleOutbox({required bool force}) async {
    await _runOutboxLocked(() async {
      if (_orderOutboxFlushInProgress) return;
      _orderOutboxFlushInProgress = true;
      try {
        var queue = await _loadOrderLifecycleOutbox();
        if (queue.isEmpty) return;

        DateTime? oldest;
        for (final item in queue) {
          final parsed = DateTime.tryParse(
            item['enqueued_at']?.toString() ?? '',
          )?.toLocal();
          if (parsed == null) continue;
          oldest = oldest == null || parsed.isBefore(oldest) ? parsed : oldest;
        }

        final mustFlushNow =
            oldest != null &&
            DateTime.now().difference(oldest) >= _orderOutboxMaxDelay;
        final shouldFlush =
            force || mustFlushNow || _canUseResourcesForOutboxFlush();
        if (!shouldFlush) return;

        final localRefMap = await _loadOrderLocalRefMap();
        final remaining = <Map<String, dynamic>>[];

        for (final item in queue) {
          if (!_isOutboxItemReady(item, allowOverride: mustFlushNow || force)) {
            remaining.add(item);
            continue;
          }

          final action = item['action']?.toString() ?? '';
          final payloadRaw = item['payload'];
          final payload = payloadRaw is Map
              ? payloadRaw.map((k, v) => MapEntry(k.toString(), v))
              : <String, dynamic>{};
          var ok = false;

          if (action == 'create') {
            final result = await _apiService.createOrder(
              businessId: _asInt(payload['business_id']),
              businessIdId: _asInt(payload['business_id_id']),
              orderNumber: payload['order_number']?.toString() ?? '',
              latitude: double.tryParse(payload['latitude']?.toString() ?? ''),
              longitude: double.tryParse(
                payload['longitude']?.toString() ?? '',
              ),
              clientRequestId: payload['client_request_id']?.toString(),
            );
            ok = result.success;
            if (ok) {
              final localOrderId = _asInt(payload['local_order_id']);
              final remoteId =
                  result.orderId ??
                  await _resolveServerOrderIdByPayload({
                    ...payload,
                    'enqueued_at': item['enqueued_at'],
                  });
              if (localOrderId < 0 && remoteId != null) {
                localRefMap[localOrderId.toString()] = remoteId;
              } else if (localOrderId < 0 && remoteId == null) {
                // Do not mark create as synced until server order ID is resolvable.
                ok = false;
              }
            }
          } else {
            var orderId = _asInt(payload['order_id']);
            if (orderId <= 0) {
              orderId = localRefMap[payload['order_id']?.toString() ?? ''] ?? 0;
            }

            if (orderId <= 0) {
              final attempts = _asInt(item['attempts']) + 1;
              if (attempts >= _orderOutboxMaxAttempts) {
                await _appendOutboxDeadLetter(item, 'unresolved_order_id');
                continue;
              }
              final retryAt = _nextRetryTimeForAttempt(attempts);
              remaining.add({
                ...item,
                'attempts': attempts,
                'next_retry_at': retryAt.toIso8601String(),
              });
              continue;
            }

            if (action == 'pickup') {
              final result = await _apiService.pickupOrder(
                orderId,
                latitude: double.tryParse(
                  payload['latitude']?.toString() ?? '',
                ),
                longitude: double.tryParse(
                  payload['longitude']?.toString() ?? '',
                ),
              );
              ok = result.success;
            } else if (action == 'deliver') {
              final result = await _apiService.updateOrder(
                orderId: orderId,
                type: _asInt(payload['payment_type'], fallback: 1),
                amountReceived: payload['amount_received']?.toString(),
                amountPaid: null,
                latitude: double.tryParse(
                  payload['latitude']?.toString() ?? '',
                ),
                longitude: double.tryParse(
                  payload['longitude']?.toString() ?? '',
                ),
              );
              ok = result.success;
            } else if (action == 'cancel') {
              final result = await _apiService.cancelOrder(
                orderId: orderId,
                reasonType: payload['reason_type']?.toString() ?? 'other',
                reason: payload['reason']?.toString(),
              );
              ok = result.success;
            }
          }

          if (await _logoutIfUnauthorizedAfterAction()) {
            return;
          }

          if (!ok) {
            final attempts = _asInt(item['attempts']) + 1;
            if (attempts >= _orderOutboxMaxAttempts) {
              await _appendOutboxDeadLetter(item, 'max_attempts_reached');
              continue;
            }
            final retryAt = _nextRetryTimeForAttempt(attempts);
            final retryItem = <String, dynamic>{
              ...item,
              'attempts': attempts,
              'next_retry_at': retryAt.toIso8601String(),
            };
            remaining.add(retryItem);
          }
        }

        await _saveOrderLocalRefMap(localRefMap);
        await _saveOrderLifecycleOutbox(remaining);

        final now = DateTime.now();
        if (mounted) {
          setState(() {
            _orderOutboxLastFlushAt = now;
            if (remaining.length < queue.length) {
              _orderOutboxLastSuccessAt = now;
            }
          });
        } else {
          _orderOutboxLastFlushAt = now;
          if (remaining.length < queue.length) {
            _orderOutboxLastSuccessAt = now;
          }
        }

        if (remaining.length != queue.length) {
          _refreshAllDataInBackground(includeHeavy: false);
        }
      } finally {
        _orderOutboxFlushInProgress = false;
      }
    });
  }

  void _startAutoRefresh() {
    _autoRefreshKickoffTimer?.cancel();
    _autoRefreshTimer?.cancel();

    final interval = _computeAutoRefreshInterval();
    final jitter = Random().nextInt(_autoRefreshJitterMaxSeconds + 1);
    _autoRefreshKickoffTimer = Timer(Duration(seconds: jitter), () {
      if (!mounted) return;

      _refreshAllDataInBackground(includeHeavy: _shouldRunHeavyRefresh());

      _autoRefreshTimer = Timer.periodic(interval, (_) {
        // Recalculate interval on each tick — state may have changed
        final currentInterval = _computeAutoRefreshInterval();
        if (currentInterval != interval) {
          // Restart with correct interval
          _startAutoRefresh();
          return;
        }
        _refreshAllDataInBackground(includeHeavy: _shouldRunHeavyRefresh());
      });
    });
  }

  void _pruneReminderCaches() {
    final activeIds = _ordersActive.map((o) => o.id).toSet();
    _lastPickupReminder.removeWhere((key, _) => !activeIds.contains(key));
    _lastDeliveryReminder.removeWhere((key, _) => !activeIds.contains(key));
  }

  Future<void> _evaluateOrderNotifications() async {
    if (!_isCheckedIn || !_orderRemindersEnabled) return;
    final now = DateTime.now();

    for (final order in _ordersActive) {
      if (order.isCancelled) {
        _lastPickupReminder.remove(order.id);
        _lastDeliveryReminder.remove(order.id);
        continue;
      }
      if (order.isDelivered) {
        _lastPickupReminder.remove(order.id);
        _lastDeliveryReminder.remove(order.id);
        continue;
      }

      final created = order.createdAt;
      final pickupTime = order.pickupTime;
      final isPicked = order.isPickedUp || pickupTime != null;

      if (!isPicked && created != null) {
        final elapsed = now.difference(created);
        if (elapsed >= const Duration(minutes: 15)) {
          final last = _lastPickupReminder[order.id];
          if (last == null || now.difference(last) >= _orderReminderCooldown) {
            await NotificationService.instance.showSimple(
              id: order.id + 1000,
              title: l10n.notificationPickupPendingTitle,
              body: l10n.notificationPickupPendingBody(order.orderNumber),
            );
            _lastPickupReminder[order.id] = now;
          }
        }
      }

      final deliveryBase = pickupTime ?? created;
      if (isPicked && !order.isDelivered && deliveryBase != null) {
        final elapsed = now.difference(deliveryBase);
        if (elapsed >= const Duration(minutes: 15)) {
          final last = _lastDeliveryReminder[order.id];
          if (last == null || now.difference(last) >= _orderReminderCooldown) {
            await NotificationService.instance.showSimple(
              id: order.id + 2000,
              title: l10n.notificationDeliveryPendingTitle,
              body: l10n.notificationDeliveryPendingBody(order.orderNumber),
            );
            _lastDeliveryReminder[order.id] = now;
          }
        }
      }
    }
  }

  void _showToast(
    String message, {
    bool isError = false,
    bool isSuccess = false,
    Color? background,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!mounted) return;
    final bg =
        background ??
        (isError
            ? Colors.red.shade600
            : isSuccess
            ? Colors.green.shade600
            : Colors.blue.shade700);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(color: Colors.white)),
          backgroundColor: bg,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          duration: duration,
        ),
      );
  }

  void _showTimeoutMessage({
    required String actionEn,
    required String actionAr,
  }) {
    final isArabic = _currentLang == 'ar';
    final message = isArabic
        ? 'انتهت مهلة الشبكة اثناء $actionAr. تحقق من الانترنت ثم حاول مرة اخرى.'
        : 'Network timeout while $actionEn. Check your internet and try again.';

    _showToast(
      message,
      isError: true,
      background: Colors.deepOrange.shade700,
      duration: const Duration(seconds: 6),
    );
  }

  void _setMessage(
    String? msg, {
    bool isError = false,
    bool isSuccess = false,
  }) {
    if (!mounted || msg == null) return;
    _showToast(msg, isError: isError, isSuccess: isSuccess);
  }

  bool? _parseBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final str = value?.toString().toLowerCase();
    if (str == null) return null;
    if (str == 'true' ||
        str == 'yes' ||
        str == 'checked_in' ||
        str == 'checkedin' ||
        str == '1' ||
        str == 'on')
      return true;
    if (str == 'false' ||
        str == 'no' ||
        str == '0' ||
        str == 'off' ||
        str == 'out' ||
        str == 'checkout')
      return false;
    return null;
  }

  Future<T> _runPermissionRequestSerial<T>(
    Future<T> Function() requestCall,
  ) async {
    final previousTail = _permissionRequestTail;
    final gate = Completer<void>();
    _permissionRequestTail = gate.future;

    try {
      await previousTail.catchError((_) {});
      return await requestCall();
    } finally {
      if (!gate.isCompleted) {
        gate.complete();
      }
    }
  }

  Future<bool> _ensureCameraPermission() async {
    final inFlight = _cameraPermissionRequest;
    if (inFlight != null) return inFlight;

    final requestFuture = _ensureCameraPermissionInternal();
    _cameraPermissionRequest = requestFuture;

    try {
      return await requestFuture;
    } finally {
      if (identical(_cameraPermissionRequest, requestFuture)) {
        _cameraPermissionRequest = null;
      }
    }
  }

  Future<bool> _ensureCameraPermissionInternal() async {
    if (kIsWeb) return true; // Permissions not needed on web
    final status = await Permission.camera.status;
    if (status.isGranted) return true;
    final result = await _runPermissionRequestSerial(
      () => Permission.camera.request(),
    );
    if (result.isGranted) return true;
    if (result.isPermanentlyDenied) {
      if (!mounted) return false;
      _setMessage(l10n.cameraPermissionDenied, isError: true);
      await openAppSettings();
    } else {
      if (!mounted) return false;
      _setMessage(l10n.cameraPermissionRequired, isError: true);
    }
    return false;
  }

  Future<bool> _ensureMediaPermission() async {
    final inFlight = _mediaPermissionRequest;
    if (inFlight != null) return inFlight;

    final requestFuture = _requestMediaPermissionInternal();
    _mediaPermissionRequest = requestFuture;

    try {
      return await requestFuture;
    } finally {
      if (identical(_mediaPermissionRequest, requestFuture)) {
        _mediaPermissionRequest = null;
      }
    }
  }

  Future<bool> _requestMediaPermissionInternal() async {
    if (kIsWeb) return true; // Web does not expose platform media permissions

    if (Platform.isAndroid) {
      final photosStatus = await Permission.photos.status;
      final storageStatus = await Permission.storage.status;
      if (photosStatus.isGranted ||
          photosStatus.isLimited ||
          storageStatus.isGranted)
        return true;

      final results = await _runPermissionRequestSerial(
        () => [Permission.photos, Permission.storage].request(),
      );
      final photosResult = results[Permission.photos] ?? photosStatus;
      final storageResult = results[Permission.storage] ?? storageStatus;
      if (photosResult.isGranted ||
          photosResult.isLimited ||
          storageResult.isGranted)
        return true;

      if (photosResult.isPermanentlyDenied ||
          storageResult.isPermanentlyDenied) {
        if (!mounted) return false;
        _setMessage(l10n.mediaPermissionDenied, isError: true);
        await openAppSettings();
      } else {
        if (!mounted) return false;
        _setMessage(l10n.mediaPermissionRequired, isError: true);
      }
      return false;
    }

    final photosStatus = await Permission.photos.status;
    if (photosStatus.isGranted || photosStatus.isLimited) return true;

    final photosResult = await _runPermissionRequestSerial(
      () => Permission.photos.request(),
    );
    if (photosResult.isGranted || photosResult.isLimited) return true;

    if (photosResult.isPermanentlyDenied) {
      if (!mounted) return false;
      _setMessage(l10n.mediaPermissionDenied, isError: true);
      await openAppSettings();
    } else {
      if (!mounted) return false;
      _setMessage(l10n.mediaPermissionRequired, isError: true);
    }
    return false;
  }

  Future<bool> _ensureForegroundLocationPermission() async {
    if (kIsWeb) return true;

    final whenInUse = await Permission.locationWhenInUse.status;
    if (!whenInUse.isGranted) {
      final requested = await _runPermissionRequestSerial(
        () => Permission.locationWhenInUse.request(),
      );
      if (!requested.isGranted) {
        if (requested.isPermanentlyDenied) {
          if (!mounted) return false;
          _setMessage(l10n.locationPermissionDenied, isError: true);
          await openAppSettings();
        } else {
          if (!mounted) return false;
          _setMessage(l10n.mapsPermission, isError: true);
        }
        return false;
      }
    }

    return true;
  }

  Future<bool> _maybeRequestBackgroundLocationPermission() async {
    if (kIsWeb || !Platform.isAndroid) return true;

    final hasForegroundPermission = await _ensureForegroundLocationPermission();
    if (!hasForegroundPermission) {
      return false;
    }

    final alwaysStatus = await Permission.locationAlways.status;
    if (alwaysStatus.isGranted) return true;

    final acceptedDisclosure = await _showBackgroundLocationDisclosure();
    if (!acceptedDisclosure) {
      _setMessage(
        'Background location was skipped. Tracking works while the app is open.',
      );
      return true;
    }

    final bgResult = await _runPermissionRequestSerial(
      () => Permission.locationAlways.request(),
    );
    if (bgResult.isGranted) return true;
    if (bgResult.isPermanentlyDenied) {
      if (!mounted) return false;
      _setMessage(l10n.locationPermissionDenied, isError: true);
      await openAppSettings();
      return false;
    }

    _setMessage(
      'Background location was skipped. Tracking works while the app is open.',
    );
    return true;
  }

  Future<bool> _ensureLocationPermission() async {
    if (kIsWeb) return true;

    final hasForegroundPermission = await _ensureForegroundLocationPermission();
    if (!hasForegroundPermission) {
      return false;
    }

    if (Platform.isAndroid) {
      final alwaysStatus = await Permission.locationAlways.status;
      if (!alwaysStatus.isGranted) {
        return true;
      }

      return true;
    }

    return true;
  }

  Future<bool> _showBackgroundLocationDisclosure() async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Allow all-time location access'),
          content: const Text(
            'Speed Driver needs background location so dispatch and trip tracking keep working when the app is minimized or the screen is off. '
            'This is used only during working/checked-in periods.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  Future<bool> _ensureLocationServiceEnabled() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (serviceEnabled) return true;
    if (!mounted) return false;
    _setMessage(l10n.mapsPermission, isError: true);
    await Geolocator.openLocationSettings();
    return false;
  }

  Future<void> _ensureNotificationPermission() async {
    if (kIsWeb) return;
    final status = await Permission.notification.status;
    if (status.isGranted) return;
    await _runPermissionRequestSerial(() => Permission.notification.request());
  }

  static const int _maxMeterImageBytes = 5 * 1024 * 1024;
  static const int _maxProfileImageBytes = 2 * 1024 * 1024;

  ({Uint8List bytes, String fileName})? _normalizeUploadImage({
    required Uint8List sourceBytes,
    required String baseName,
    required int maxBytes,
    int maxDimension = 1600,
  }) {
    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) {
      if (sourceBytes.lengthInBytes > maxBytes) return null;
      final fallback =
          '${baseName}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      return (bytes: sourceBytes, fileName: fallback);
    }

    var current = decoded;
    if (current.width > maxDimension || current.height > maxDimension) {
      current = img.copyResize(
        current,
        width: current.width >= current.height ? maxDimension : null,
        height: current.height > current.width ? maxDimension : null,
        interpolation: img.Interpolation.average,
      );
    }

    var quality = 88;
    var encoded = Uint8List.fromList(img.encodeJpg(current, quality: quality));
    while (encoded.lengthInBytes > maxBytes &&
        (quality > 45 || current.width > 720 || current.height > 720)) {
      if (current.width > 720 || current.height > 720) {
        final scaledWidth = max(1, (current.width * 0.85).round());
        final scaledHeight = max(1, (current.height * 0.85).round());
        current = img.copyResize(
          current,
          width: scaledWidth,
          height: scaledHeight,
          interpolation: img.Interpolation.average,
        );
      }
      quality = max(45, quality - 8);
      encoded = Uint8List.fromList(img.encodeJpg(current, quality: quality));
    }

    if (encoded.lengthInBytes > maxBytes) return null;
    final fileName = '${baseName}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    return (bytes: encoded, fileName: fileName);
  }

  Future<void> _captureMeterImage({required bool isCheckout}) async {
    final cameraOk = await _ensureCameraPermission();
    if (!cameraOk) return;

    final imagePicker = ImagePicker();
    try {
      final captured = await imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 85,
      );
      if (captured == null) return;

      final capturedBytes = await captured.readAsBytes();
      final normalized = _normalizeUploadImage(
        sourceBytes: capturedBytes,
        baseName: isCheckout ? 'meter_checkout' : 'meter_checkin',
        maxBytes: _maxMeterImageBytes,
      );
      if (normalized == null) {
        _setMessage(
          'Meter image is too large. Please retake a clearer image.',
          isError: true,
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        if (isCheckout) {
          _checkoutImageBytes = normalized.bytes;
          _checkoutImageName = normalized.fileName;
        } else {
          _checkinImageBytes = normalized.bytes;
          _checkinImageName = normalized.fileName;
        }
      });
    } catch (e) {
      debugPrint('Meter image capture failed: ${LogRedactor.sanitizeText(e)}');
      _setMessage('Failed to open camera. Please try again.', isError: true);
    }
  }

  Future<void> _pickProfileImage() async {
    if (!mounted) return;
    final selectedSource = await showModalBottomSheet<_ProfileImageSource>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: Text(l10n.profileTakePhoto),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_ProfileImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.upload_file),
                title: Text(l10n.profileChooseFile),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_ProfileImageSource.file),
              ),
            ],
          ),
        );
      },
    );

    if (selectedSource == null) return;
    if (selectedSource == _ProfileImageSource.camera) {
      await _captureProfileImage();
      return;
    }

    await _pickProfileImageFromFile();
  }

  Future<void> _captureProfileImage() async {
    final cameraOk = await _ensureCameraPermission();
    if (!cameraOk) return;

    final imagePicker = ImagePicker();
    try {
      final captured = await imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        imageQuality: 85,
      );
      if (captured == null) return;

      final capturedBytes = await captured.readAsBytes();
      final normalized = _normalizeUploadImage(
        sourceBytes: capturedBytes,
        baseName: 'profile',
        maxBytes: _maxProfileImageBytes,
        maxDimension: 1400,
      );
      if (normalized == null) {
        _setMessage(
          'Profile image is too large. Please choose a smaller image.',
          isError: true,
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        _profileImageBytes = normalized.bytes;
        _profileImageName = normalized.fileName;
      });
    } catch (e) {
      debugPrint(
        'Profile image capture failed: ${LogRedactor.sanitizeText(e)}',
      );
      _setMessage('Failed to open camera. Please try again.', isError: true);
    }
  }

  Future<void> _pickProfileImageFromFile() async {
    final mediaOk = await _ensureMediaPermission();
    if (!mediaOk) return;

    final result = await FilePicker.pickFiles(
      withData: true,
      type: FileType.image,
    );
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      if (file.bytes == null) {
        _setMessage(
          'Unable to read selected image. Please try another file.',
          isError: true,
        );
        return;
      }
      final normalized = _normalizeUploadImage(
        sourceBytes: file.bytes!,
        baseName: 'profile',
        maxBytes: _maxProfileImageBytes,
        maxDimension: 1400,
      );
      if (normalized == null) {
        _setMessage(
          'Profile image is too large. Please choose a smaller image.',
          isError: true,
        );
        return;
      }
      if (mounted) {
        setState(() {
          _profileImageBytes = normalized.bytes;
          _profileImageName = normalized.fileName;
        });
      }
    }
  }

  Future<void> _submitCheckIn() async {
    if (_isCheckedIn) {
      _setMessage(l10n.alreadyCheckedIn, isError: true);
      return;
    }
    final reading = _checkinMeterCtrl.text.trim();
    if (reading.isEmpty) {
      _setMessage(l10n.meterReadingRequired, isError: true);
      return;
    }
    if (_checkinImageBytes == null) {
      _setMessage(l10n.meterImageRequired, isError: true);
      return;
    }
    setState(() {
      _actionLoading = true;
    });

    String? appVersion;
    String? buildNumber;
    try {
      final package = await PackageInfo.fromPlatform();
      appVersion = package.version;
      buildNumber = package.buildNumber;
    } catch (_) {}

    // Capture GPS position + run security checks before check-in
    Position? checkinPosition;
    SecurityCheckResult? security;
    try {
      checkinPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      security = await SecurityService.instance.runChecks(
        position: checkinPosition,
      );
    } catch (_) {}

    if (!mounted) return;

    // VPN and mock GPS are sent as flags to the server — the server decides
    // whether to block based on per-driver allow_vpn / allow_fake_location settings.

    // HARD BLOCK: Rooted device
    if (security?.rootDetected == true) {
      setState(() => _actionLoading = false);
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Security Violation'),
          content: const Text(
            'This device appears to be rooted.\n\nRooted devices cannot be used for check-in due to security policy.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    // Soft warning (logged on server): emulator or suspicious environment
    // Does not block — but violations are sent to server for anomaly logging

    final result = await _apiService.checkIn(
      meterReading: reading,
      meterImageBytes: _checkinImageBytes,
      meterImageName: _checkinImageName,
      appVersion: appVersion,
      buildNumber: buildNumber,
      latitude: checkinPosition?.latitude,
      longitude: checkinPosition?.longitude,
      gpsAccuracyM: checkinPosition?.accuracy,
      mockLocation: security?.mockLocationDetected ?? false,
      vpnDetected: security?.vpnDetected ?? false,
      rootDetected: security?.rootDetected ?? false,
      emulatorDetected: security?.emulatorDetected ?? false,
    );
    if (!mounted) return;

    if (await _logoutIfUnauthorizedAfterAction()) {
      return;
    }

    // Handle security hard-blocks returned by server (403)
    if (!result.success && result.statusCode == 403) {
      final rawMsg = result.message ?? '';
      final lowerMsg = rawMsg.toLowerCase();
      String dialogTitle = 'Check-in Blocked';
      String dialogBody = rawMsg.isNotEmpty
          ? rawMsg
          : 'Check-in was blocked by the server.';
      if (lowerMsg.contains('geofence') ||
          lowerMsg.contains('too far') ||
          lowerMsg.contains('branch')) {
        dialogTitle = 'Outside Branch Zone';
        dialogBody = '$rawMsg\n\nMove closer to your branch and try again.';
      } else if (lowerMsg.contains('mock') || lowerMsg.contains('fake gps')) {
        dialogTitle = 'Fake GPS Detected';
      } else if (lowerMsg.contains('vpn')) {
        dialogTitle = 'VPN Detected';
      }
      if (mounted) {
        setState(() => _actionLoading = false);
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: Text(dialogTitle),
            content: Text(dialogBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }

    final msg = result.message?.toLowerCase() ?? '';
    final alreadyCheckedIn =
        result.statusCode == 400 ||
            result.statusCode == 409 ||
            result.statusCode == 422
        ? (msg.contains('already check') ||
              msg.contains('already checked') ||
              msg.contains('already'))
        : false;

    var confirmedCheckedIn = false;
    if (result.success) {
      await _fetchProfile();
      confirmedCheckedIn = _isCheckedIn;
    }
    if (!result.success && alreadyCheckedIn) {
      await _fetchProfile();
      confirmedCheckedIn = _isCheckedIn;
    }

    if (confirmedCheckedIn) {
      _setMessage(
        result.success
            ? l10n.checkinSuccess
            : (result.message ?? l10n.alreadyCheckedIn),
        isSuccess: true,
      );
      await NotificationService.instance.showSimple(
        id: 5001,
        title: l10n.notificationCheckinCompleteTitle,
        body: l10n.notificationCheckinCompleteBody,
      );
      _checkinImageBytes = null;
      _checkinImageName = null;
      _checkinMeterCtrl.clear();
      await _refreshAllData();
      if (mounted) {
        setState(() {
          _isCheckedIn = true;
        });
        await _persistCheckinStatus(true);
        await _maybeRequestBackgroundLocationPermission();
        _resumeForegroundLoops();
        await _syncCheckedInRuntime();
      }
    } else {
      if (result.success) {
        _setMessage(
          'Check-in acknowledged, but backend did not keep active attendance. Please try again.',
          isError: true,
        );
      } else if (alreadyCheckedIn) {
        _setMessage(
          'Driver status mismatch. Please try check-in again or contact admin.',
          isError: true,
        );
      } else {
        _setMessage(result.message ?? l10n.checkinFailed, isError: true);
      }
    }
    if (mounted) {
      setState(() {
        _actionLoading = false;
      });
    }
  }

  Future<void> _submitCheckOut() async {
    if (_hasActiveOrders) {
      _setMessage('Finish active orders before checkout', isError: true);
      return;
    }
    final reading = _checkoutMeterCtrl.text.trim();
    if (reading.isEmpty) {
      _setMessage(l10n.meterReadingRequired, isError: true);
      return;
    }
    if (_checkoutImageBytes == null) {
      _setMessage(l10n.outMeterImageRequired, isError: true);
      return;
    }
    setState(() {
      _actionLoading = true;
    });
    // Capture GPS at checkout (non-blocking — don't fail if GPS unavailable)
    Position? checkoutPos;
    bool checkoutMock = false;
    try {
      checkoutPos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
      checkoutMock = checkoutPos.isMocked;
    } catch (_) {}

    final result = await _apiService.checkOut(
      meterReading: reading,
      meterImageBytes: _checkoutImageBytes,
      meterImageName: _checkoutImageName,
      latitude: checkoutPos?.latitude,
      longitude: checkoutPos?.longitude,
      mockLocation: checkoutMock,
    );
    if (!mounted) return;

    if (await _logoutIfUnauthorizedAfterAction()) {
      return;
    }

    final alreadyCheckedOut =
        result.statusCode == 400 &&
        ((result.message?.toLowerCase().contains('already checked out') ??
                false) ||
            (result.message?.toLowerCase().contains('no check-in') ?? false));

    var confirmedCheckedOut = false;
    if (result.success || alreadyCheckedOut) {
      await _fetchProfile();
      confirmedCheckedOut = !_isCheckedIn;
    }

    if (confirmedCheckedOut) {
      _setMessage(
        result.success
            ? l10n.checkoutSuccess
            : (result.message ?? l10n.alreadyCheckedOut),
        isSuccess: true,
      );
      await NotificationService.instance.showSimple(
        id: 5002,
        title: l10n.notificationCheckoutCompleteTitle,
        body: l10n.notificationCheckoutCompleteBody,
      );
      _checkoutImageBytes = null;
      _checkoutImageName = null;
      _checkoutMeterCtrl.clear();
      await _refreshAllData();
      if (mounted) {
        setState(() {
          _isCheckedIn = false;
        });
        await _persistCheckinStatus(false);
        _resumeForegroundLoops();
      }
      await clearBackgroundWorkerState();
      await clearLocationSessionState();
      await stopLocationService();
    } else {
      if (result.success || alreadyCheckedOut) {
        _setMessage(
          'Checkout acknowledged, but backend still reports active attendance. Please retry.',
          isError: true,
        );
      } else {
        _setMessage(result.message ?? l10n.checkoutFailed, isError: true);
      }
    }
    if (mounted) {
      setState(() {
        _actionLoading = false;
      });
    }
  }

  Future<void> _submitProfile() async {
    if (_nameCtrl.text.trim().isEmpty || _mobileCtrl.text.trim().isEmpty) {
      _setMessage(l10n.profileRequired);
      return;
    }
    setState(() {
      _actionLoading = true;
    });
    final ok = await _apiService.updateProfile(
      name: _nameCtrl.text.trim(),
      mobile: _mobileCtrl.text.trim(),
      nationality: _nationalityCtrl.text.trim().isEmpty
          ? null
          : _nationalityCtrl.text.trim(),
      language: _languageCtrl.text.trim().isEmpty
          ? null
          : _languageCtrl.text.trim(),
      currentPassword: _currentPwdCtrl.text.trim().isEmpty
          ? null
          : _currentPwdCtrl.text.trim(),
      newPassword: _newPwdCtrl.text.trim().isEmpty
          ? null
          : _newPwdCtrl.text.trim(),
      confirmPassword: _confirmPwdCtrl.text.trim().isEmpty
          ? null
          : _confirmPwdCtrl.text.trim(),
      imageBytes: _profileImageBytes,
      imageName: _profileImageName,
    );
    if (!mounted) return;

    if (await _logoutIfUnauthorizedAfterAction()) {
      return;
    }

    if (ok) {
      _setMessage(l10n.profileUpdateSuccess, isSuccess: true);
      _currentPwdCtrl.clear();
      _newPwdCtrl.clear();
      _confirmPwdCtrl.clear();
      _profileImageBytes = null;
      _profileImageName = null;
      await _refreshAllData();
    } else {
      if (_apiService.lastRequestTimedOut) {
        _showTimeoutMessage(
          actionEn: 'updating profile',
          actionAr: 'تحديث الملف الشخصي',
        );
      } else {
        _setMessage(
          _apiService.lastRequestError ?? l10n.profileUpdateFailed,
          isError: true,
        );
      }
    }
    if (mounted) {
      setState(() {
        _actionLoading = false;
      });
    }
  }

  Future<bool> _launchIfCan(
    Uri uri, {
    LaunchMode mode = LaunchMode.externalApplication,
  }) async {
    try {
      if (!await canLaunchUrl(uri)) return false;
      return await launchUrl(uri, mode: mode);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _launchExternal(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  Future<void> _openMaps() async {
    final hasMapbox = _mapboxToken != null && _mapboxToken!.isNotEmpty;
    final lat = _lat ?? _mapboxCenterLat;
    final lng = _lng ?? _mapboxCenterLng;
    final address = _locationAddress;

    if (hasMapbox && lat != null && lng != null) {
      var stylePath = _mapboxStyle ?? 'mapbox://styles/mapbox/streets-v12';
      stylePath = stylePath.replaceFirst('mapbox://styles/', '');
      final zoom = _mapboxZoom ?? 14;
      final url =
          'https://api.mapbox.com/styles/v1/$stylePath.html?title=copy&access_token=${Uri.encodeComponent(_mapboxToken!)}#$zoom/$lat/$lng';
      final uri = Uri.parse(url);
      if (await _launchIfCan(uri, mode: LaunchMode.externalApplication)) return;
    }

    if (lat != null && lng != null) {
      final googleApp = Uri.parse('comgooglemaps://?q=$lat,$lng');
      if (await _launchIfCan(googleApp)) return;

      final googleNav = Uri.parse('google.navigation:q=$lat,$lng');
      if (await _launchIfCan(googleNav)) return;

      final geo = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
      if (await _launchIfCan(geo)) return;

      final fallback = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
      );
      if (await _launchExternal(fallback)) return;
    }

    if (address != null && address.isNotEmpty) {
      final fallbackAddress = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}',
      );
      if (await _launchExternal(fallbackAddress)) return;
    }

    if (!mounted) return;
    _setMessage(l10n.mapsError, isError: true);
  }

  void _restartLocationPolling() {
    _locationTimer?.cancel();
    if (!_isCheckedIn) return;

    // On Android we rely on the foreground background-service uploader to avoid
    // duplicate uploads from both UI and service timers.
    if (!kIsWeb && Platform.isAndroid) return;

    _locationTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _refreshCurrentLocation();
    });
  }

  void _stopLocationPolling() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  Future<void> _refreshCurrentLocation() async {
    if (_locating) return; // prevent overlapping requests
    final hasPermission = await _ensureLocationPermission();
    if (!hasPermission) return;

    // Ensure GPS/high-accuracy provider is enabled before reading
    final serviceOn = await _ensureLocationServiceEnabled();
    if (!serviceOn) return;

    if (mounted) {
      setState(() {
        _locating = true;
      });
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 20),
        ),
      );

      if (!mounted) return;

      setState(() {
        _lat = position.latitude;
        _lng = position.longitude;
      });

      final name = _nameCtrl.text.trim().isNotEmpty
          ? _nameCtrl.text.trim()
          : (_profile?.name ?? '');
      final mobile = _mobileCtrl.text.trim().isNotEmpty
          ? _mobileCtrl.text.trim()
          : (_profile?.mobile ?? '');

      if (name.isEmpty || mobile.isEmpty) {
        _setMessage(l10n.unableLoadProfile, isError: true);
        return;
      }

      final ok = await _apiService.updateProfile(
        name: name,
        mobile: mobile,
        nationality: _nationalityCtrl.text.trim().isEmpty
            ? null
            : _nationalityCtrl.text.trim(),
        language: _languageCtrl.text.trim().isEmpty
            ? null
            : _languageCtrl.text.trim(),
        latitude: _lat,
        longitude: _lng,
        locationAddress: _locationAddress,
      );

      if (!mounted) return;
      if (await _logoutIfUnauthorizedAfterAction()) {
        return;
      }

      if (!ok) {
        final now = DateTime.now();
        final shouldShowError =
            _lastLocationSyncErrorAt == null ||
            now.difference(_lastLocationSyncErrorAt!) >=
                _locationSyncErrorCooldown;
        if (shouldShowError) {
          _lastLocationSyncErrorAt = now;
          _setMessage(l10n.profileUpdateFailed, isError: true);
        }
      }
    } catch (e) {
      if (!mounted) return;
      final now = DateTime.now();
      final shouldShowError =
          _lastLocationSyncErrorAt == null ||
          now.difference(_lastLocationSyncErrorAt!) >=
              _locationSyncErrorCooldown;
      if (shouldShowError) {
        _lastLocationSyncErrorAt = now;
        _setMessage(l10n.mapsError, isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _locating = false;
        });
      }
    }
  }

  Future<void> _syncCheckedInRuntime() async {
    await BackgroundWorker.syncForCheckinState(isCheckedIn: _isCheckedIn);

    if (_isCheckedIn) {
      await startLocationService();
    } else {
      await stopLocationService();
    }
  }

  Future<void> _clearDriverScopedState() async {
    _lastPickupReminder.clear();
    _lastDeliveryReminder.clear();
    _stopLocationPolling();
    await DriverSessionStateService.clearPersistedState();
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    _loggingOut = true;

    if (mounted) {
      setState(() => _actionLoading = true);
    }

    try {
      await _apiService.logout();
      await _clearDriverScopedState();
    } catch (e) {
      debugPrint(
        'Failed clearing cached driver data: ${LogRedactor.sanitizeText(e)}',
      );
    } finally {
      if (mounted) {
        setState(() => _actionLoading = false);
      }
    }

    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  void _openOrderCreateSheet(Business business, BusinessIdItem businessId) {
    _selectedBusiness = business;
    _selectedBusinessId = businessId;
    _orderNumberCtrl.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        final safeBottom = MediaQuery.of(ctx).viewPadding.bottom;
        final bottomPadding = bottomInset + safeBottom + 24;
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: bottomPadding,
              left: 16,
              right: 16,
              top: 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.add_shopping_cart,
                      color: Colors.deepPurple,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.newOrderFor(business.name),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.businessIdValue(businessId.value),
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _orderNumberCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.orderNumberInputLabel,
                    hintText: l10n.orderNumberHint,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    prefixIcon: const Icon(Icons.confirmation_number_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: _orderSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check),
                    label: Text(
                      _orderSubmitting ? l10n.creating : l10n.createOrder,
                    ),
                    onPressed: _orderSubmitting ? null : _submitCreateOrder,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _submitCreateOrder() async {
    final business = _selectedBusiness;
    final businessId = _selectedBusinessId;
    final orderNo = _orderNumberCtrl.text.trim();
    if (business == null || businessId == null) {
      _showToast(l10n.selectBusinessIdFirst, isError: true);
      return;
    }
    if (orderNo.isEmpty) {
      _showToast(l10n.orderNumberRequired, isError: true);
      return;
    }
    if (_orderSubmitting) return;
    setState(() => _orderSubmitting = true);
    final localOrderId = _nextLocalOrderRef();
    final optimisticOrder = Order(
      id: localOrderId,
      orderNumber: orderNo,
      businessName: business.name,
      businessId: business.id,
      businessIdId: businessId.id,
      businessIdValue: businessId.value,
      status: 'pending_sync',
      createdAt: DateTime.now(),
    );
    setState(() {
      _ordersActive = [
        optimisticOrder,
        ..._ordersActive.where((o) => o.id != localOrderId),
      ];
    });
    await _enqueueOrderLifecycleAction('create', {
      'local_order_id': localOrderId,
      'business_id': business.id ?? 0,
      'business_id_id': businessId.id ?? 0,
      'order_number': orderNo,
      'latitude': _lat,
      'longitude': _lng,
    });
    await _flushOrderLifecycleOutbox(force: true);
    if (!mounted) return;
    setState(() => _orderSubmitting = false);
    _showToast(l10n.toastOrderQueuedLocalSync, isSuccess: true);
    await NotificationService.instance.showSimple(
      id: 6000 + (business.id ?? 0) + (businessId.id ?? 0),
      title: l10n.notificationOrderQueuedTitle,
      body: l10n.notificationOrderQueuedBody(orderNo),
    );
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
    _refreshAllDataInBackground(includeHeavy: false);
    if (!mounted) return;
    setState(() => _currentIndex = 1);
  }

  Future<void> _pickupOrder(Order order) async {
    if (_orderActionBusy[order.id] == true) return;
    setState(() => _orderActionBusy[order.id] = true);
    await _enqueueOrderLifecycleAction('pickup', {
      'order_id': order.id,
      'latitude': _lat,
      'longitude': _lng,
    });
    if (!mounted) return;
    setState(() => _orderActionBusy[order.id] = false);
    setState(() {
      _ordersActive = _ordersActive
          .map(
            (o) => o.id == order.id
                ? Order(
                    id: o.id,
                    orderNumber: o.orderNumber,
                    businessName: o.businessName,
                    businessIdValue: o.businessIdValue,
                    businessId: o.businessId,
                    businessIdId: o.businessIdId,
                    status: 'pickup',
                    pickupTime: DateTime.now(),
                    deliveredTime: o.deliveredTime,
                    cancelledTime: o.cancelledTime,
                    dropTime: o.dropTime,
                    createdAt: o.createdAt,
                    type: o.type,
                    amountReceived: o.amountReceived,
                    amountPaid: o.amountPaid,
                  )
                : o,
          )
          .toList();
    });
    _showToast(l10n.toastPickupQueued, isSuccess: true);
    await NotificationService.instance.showSimple(
      id: 7000 + order.id,
      title: l10n.notificationOrderPickupQueuedTitle,
      body: l10n.notificationOrderSavedForSyncBody(order.orderNumber),
    );
    _refreshAllDataInBackground(includeHeavy: false);
  }

  Future<void> _openCancelSheet(Order order) async {
    final reasonCtrl = TextEditingController();
    String? errorText;
    String? typeError;
    String? selectedType; // customer | business | other
    bool submitting = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        final safeBottom = MediaQuery.of(ctx).viewPadding.bottom;
        final bottomPadding = bottomInset + safeBottom + 24;

        return SafeArea(
          top: false,
          child: StatefulBuilder(
            builder: (context, setModalState) {
              Future<void> handleSubmit() async {
                if (selectedType == null) {
                  setModalState(
                    () => typeError = l10n.cancelReasonTypeRequired,
                  );
                  return;
                }
                final reason = reasonCtrl.text.trim();
                if (selectedType == 'other' && reason.isEmpty) {
                  setModalState(() => errorText = l10n.cancelReasonRequired);
                  return;
                }
                setModalState(() {
                  submitting = true;
                  errorText = null;
                  typeError = null;
                });
                final reasonType = selectedType!;
                final resolvedReason = reasonType == 'other'
                    ? reason
                    : reasonType == 'customer'
                    ? l10n.cancelByCustomer
                    : l10n.cancelByBusiness(
                        order.businessName.isNotEmpty
                            ? order.businessName
                            : l10n.businessesAndIds,
                      );

                final success = await _cancelOrder(
                  order,
                  reasonType,
                  resolvedReason,
                  suppressToast: true,
                );
                if (!mounted || !ctx.mounted) return;
                if (success) {
                  Navigator.pop(ctx);
                  _showToast(l10n.orderCancelled, isSuccess: true);
                } else {
                  setModalState(() => submitting = false);
                }
              }

              return Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 20,
                  bottom: bottomPadding,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.cancel, color: Colors.red.shade600),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.cancelOrderAction,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          [
                            ('customer', l10n.cancelByCustomer),
                            (
                              'business',
                              l10n.cancelByBusiness(
                                order.businessName.isNotEmpty
                                    ? order.businessName
                                    : l10n.businessesAndIds,
                              ),
                            ),
                            ('other', l10n.cancelByOther),
                          ].map((entry) {
                            final type = entry.$1;
                            final label = entry.$2;
                            final selected = selectedType == type;
                            return ChoiceChip(
                              label: Text(
                                label,
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                              ),
                              selected: selected,
                              selectedColor: Colors.red.shade600,
                              backgroundColor: Colors.grey.shade100,
                              onSelected: submitting
                                  ? null
                                  : (v) {
                                      setModalState(() {
                                        selectedType = v ? type : null;
                                        typeError = null;
                                        errorText = null;
                                        if (selectedType != 'other') {
                                          reasonCtrl.clear();
                                        }
                                      });
                                    },
                            );
                          }).toList(),
                    ),
                    if (typeError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            typeError!,
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    if (selectedType == 'other') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: reasonCtrl,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: l10n.cancelReasonLabel,
                          hintText: l10n.cancelReasonHint,
                          prefixIcon: const Icon(Icons.notes),
                          errorText: errorText,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: submitting
                                ? null
                                : () => Navigator.pop(ctx),
                            child: Text(
                              MaterialLocalizations.of(
                                context,
                              ).cancelButtonLabel,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: submitting ? null : handleSubmit,
                            icon: submitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check_circle_outline),
                            label: Text(
                              submitting
                                  ? l10n.submitting
                                  : l10n.cancelOrderAction,
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade600,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<bool> _cancelOrder(
    Order order,
    String reasonType,
    String reason, {
    bool suppressToast = false,
  }) async {
    if (_orderActionBusy[order.id] == true) return false;
    setState(() => _orderActionBusy[order.id] = true);
    await _enqueueOrderLifecycleAction('cancel', {
      'order_id': order.id,
      'reason_type': reasonType,
      'reason': reason,
    });
    if (!mounted) return true;
    setState(() => _orderActionBusy[order.id] = false);
    setState(() {
      final cancelled = _ordersActive.where((o) => o.id == order.id).toList();
      _ordersActive = _ordersActive.where((o) => o.id != order.id).toList();
      _ordersCompleted = [
        ...cancelled.map(
          (o) => Order(
            id: o.id,
            orderNumber: o.orderNumber,
            businessName: o.businessName,
            businessIdValue: o.businessIdValue,
            businessId: o.businessId,
            businessIdId: o.businessIdId,
            status: 'cancelled',
            pickupTime: o.pickupTime,
            deliveredTime: o.deliveredTime,
            cancelledTime: DateTime.now(),
            dropTime: o.dropTime,
            createdAt: o.createdAt,
            type: o.type,
            amountReceived: o.amountReceived,
            amountPaid: o.amountPaid,
          ),
        ),
        ..._ordersCompleted,
      ];
    });
    if (!suppressToast) {
      _showToast(l10n.toastCancellationQueued, isSuccess: true);
    }
    _refreshAllDataInBackground(includeHeavy: false);
    return true;
  }

  void _openDeliverSheet(Order order) {
    final initialType = order.type;
    // Map legacy/default values to two-option set: cash(1) or online(2)
    _selectedPaymentType = initialType == 2 ? 2 : 1;
    int localPaymentType = _selectedPaymentType;
    _amountReceivedCtrl.text = order.amountReceived?.toString() ?? '';
    _amountPaidCtrl.text = order.amountPaid?.toString() ?? '';
    if (_selectedPaymentType == 2) {
      _amountReceivedCtrl.clear();
      _amountPaidCtrl.clear();
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        final safeBottom = MediaQuery.of(ctx).viewPadding.bottom;
        final bottomPadding = bottomInset + safeBottom + 24;

        void updatePayment(
          int val,
          void Function(void Function()) setModalState,
        ) {
          setModalState(() {
            localPaymentType = val;
          });
          setState(() => _selectedPaymentType = val);
        }

        return SafeArea(
          top: false,
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: bottomPadding,
                  left: 16,
                  right: 16,
                  top: 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.delivery_dining, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.deliverOrderTitle(order.orderNumber),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.paymentType,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        _paymentChip(
                          label: l10n.cash,
                          value: 1,
                          selectedValue: localPaymentType,
                          onSelected: (v) => updatePayment(v, setModalState),
                        ),
                        _paymentChip(
                          label: l10n.online,
                          value: 2,
                          selectedValue: localPaymentType,
                          onSelected: (v) => updatePayment(v, setModalState),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (localPaymentType == 1) ...[
                      TextField(
                        controller: _amountReceivedCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: l10n.amountReceivedRequiredCash,
                          prefixIcon: const Icon(Icons.payments),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: (_orderActionBusy[order.id] == true)
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_circle),
                        label: Text(
                          (_orderActionBusy[order.id] == true)
                              ? l10n.submitting
                              : l10n.markDelivered,
                        ),
                        onPressed: (_orderActionBusy[order.id] == true)
                            ? null
                            : () => _deliverOrder(order),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _paymentChip({
    required String label,
    required int value,
    required int selectedValue,
    required void Function(int) onSelected,
  }) {
    final selected = selectedValue == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(value),
      selectedColor: Colors.green.shade100,
    );
  }

  Future<void> _deliverOrder(Order order) async {
    if (_orderActionBusy[order.id] == true) return;
    final amountReceivedText = _amountReceivedCtrl.text.trim();
    if (_selectedPaymentType == 1 && amountReceivedText.isEmpty) {
      _showToast(l10n.cashAmountRequired, isError: true);
      return;
    }
    if (_selectedPaymentType == 1) {
      final parsed = double.tryParse(amountReceivedText.replaceAll(',', ''));
      if (parsed == null || parsed <= 0) {
        _showToast(l10n.cashAmountRequired, isError: true);
        return;
      }
    }
    setState(() => _orderActionBusy[order.id] = true);
    await _enqueueOrderLifecycleAction('deliver', {
      'order_id': order.id,
      'payment_type': _selectedPaymentType,
      'amount_received':
          _selectedPaymentType == 1 && amountReceivedText.isNotEmpty
          ? amountReceivedText
          : null,
      'latitude': _lat,
      'longitude': _lng,
    });
    if (!mounted) return;
    setState(() => _orderActionBusy[order.id] = false);
    setState(() {
      final delivered = _ordersActive.where((o) => o.id == order.id).toList();
      _ordersActive = _ordersActive.where((o) => o.id != order.id).toList();
      _ordersCompleted = [
        ...delivered.map(
          (o) => Order(
            id: o.id,
            orderNumber: o.orderNumber,
            businessName: o.businessName,
            businessIdValue: o.businessIdValue,
            businessId: o.businessId,
            businessIdId: o.businessIdId,
            status: 'drop',
            pickupTime: o.pickupTime,
            deliveredTime: DateTime.now(),
            cancelledTime: o.cancelledTime,
            dropTime: DateTime.now(),
            createdAt: o.createdAt,
            type: _selectedPaymentType,
            amountReceived:
                _selectedPaymentType == 1 && amountReceivedText.isNotEmpty
                ? double.tryParse(amountReceivedText)
                : null,
            amountPaid: null,
          ),
        ),
        ..._ordersCompleted,
      ];
    });
    _showToast(l10n.toastDeliveryQueued, isSuccess: true);
    await NotificationService.instance.showSimple(
      id: 8000 + order.id,
      title: l10n.notificationOrderDeliveryQueuedTitle,
      body: l10n.notificationOrderSavedForSyncBody(order.orderNumber),
    );
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
    _refreshAllDataInBackground(includeHeavy: false);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      _buildHomeTab(),
      _buildOrdersTab(),
      _buildCheckInOutTab(),
      if (_profile?.payrollEnabled == true) const PayrollListScreen(),
      if (_profile?.chatEnabled == true) const ChatListScreen(),
      _buildProfileTab(),
    ];

    final items = <BottomNavigationBarItem>[
      BottomNavigationBarItem(
        icon: const Icon(Icons.dashboard),
        label: l10n.home,
      ),
      BottomNavigationBarItem(
        icon: const Icon(Icons.local_shipping),
        label: l10n.orders,
      ),
      BottomNavigationBarItem(
        icon: const Icon(Icons.login),
        label: l10n.checkInOut,
      ),
      if (_profile?.payrollEnabled == true)
        const BottomNavigationBarItem(
          icon: Icon(Icons.receipt_long),
          label: 'Payroll',
        ),
      if (_profile?.chatEnabled == true)
        BottomNavigationBarItem(
          label: 'Messages',
          icon: _chatUnreadCount > 0
              ? Badge(
                  label: Text('$_chatUnreadCount'),
                  child: const Icon(Icons.chat_bubble_outline),
                )
              : const Icon(Icons.chat_bubble_outline),
        ),
      BottomNavigationBarItem(
        icon: const Icon(Icons.person),
        label: l10n.profile,
      ),
    ];

    if (_loading) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF62109F), Color(0xFF9C6BB8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
      );
    }

    final clampedIndex = _currentIndex.clamp(0, tabs.length - 1);

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: clampedIndex, children: tabs),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: BottomNavigationBar(
          currentIndex: clampedIndex,
          onTap: _handleTabTap,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFF62109F),
          unselectedItemColor: Colors.grey,
          selectedFontSize: 12,
          unselectedFontSize: 11,
          items: items,
        ),
      ),
    );
  }

  Widget _buildHomeTab() {
    final assignedBusinesses = _businesses;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Profile Header Card
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [Color(0xFF62109F), Color(0xFF9C6BB8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.white,
                  child: _profileImageUrl != null
                      ? ClipOval(
                          child: Image.network(
                            _profileImageUrl!,
                            fit: BoxFit.cover,
                            width: 80,
                            height: 80,
                            cacheWidth: 160,
                            cacheHeight: 160,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  Icons.person,
                                  size: 40,
                                  color: Colors.deepPurple,
                                ),
                          ),
                        )
                      : const Icon(
                          Icons.person,
                          size: 40,
                          color: Colors.deepPurple,
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _profile?.name ?? l10n.driverNameFallback,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Builder(
                                      builder: (context) {
                                        final hasActiveOrders = _ordersActive
                                            .any(
                                              (o) =>
                                                  !o.isDelivered &&
                                                  !o.isCancelled,
                                            );
                                        final isCheckedIn = _isCheckedIn;
                                        final badgeLabel =
                                            hasActiveOrders && isCheckedIn
                                            ? 'Busy'
                                            : isCheckedIn
                                            ? 'Active'
                                            : 'Inactive';
                                        final badgeColor =
                                            hasActiveOrders && isCheckedIn
                                            ? Colors
                                                  .green // Busy -> green
                                            : isCheckedIn
                                            ? Colors
                                                  .amber // Active -> yellow/amber
                                            : Colors
                                                  .red; // Inactive/offline -> red
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: badgeColor,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Text(
                                            badgeLabel,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(
                                      Icons.verified,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ],
                                ),
                                if (_profile?.mobile != null)
                                  const SizedBox(height: 4),
                                if (_profile?.mobile != null)
                                  Text(
                                    _profile!.mobile!,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                  ),
                                if (_appVersion.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    _appVersion,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.logout, color: Colors.white),
                            tooltip: l10n.logout,
                            onPressed: _actionLoading ? null : _logout,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [Colors.green.shade400, Colors.green.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.query_stats,
                        color: Colors.white,
                        size: 32,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_stats?.totalOrders ?? _stats?.todayOrdersCount ?? 0}',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.ordersSelected,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade400, Colors.blue.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.local_shipping,
                        color: Colors.white,
                        size: 32,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(_stats?.deliveredPercentage ?? 0).toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.deliveredPercent,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _statChip(
                l10n.delivered,
                '${_stats?.deliveredOrders ?? 0}',
                Colors.green.shade50,
                Colors.green.shade800,
              ),
              const SizedBox(width: 8),
              _statChip(
                l10n.pickup,
                '${_stats?.pickupOrders ?? 0}',
                Colors.blue.shade50,
                Colors.blue.shade800,
              ),
              const SizedBox(width: 8),
              _statChip(
                l10n.cancelled,
                '${_stats?.cancelledOrders ?? 0}',
                Colors.red.shade50,
                Colors.red.shade800,
              ),
              const SizedBox(width: 8),
              _statChip(
                l10n.thisMonth,
                '${_stats?.monthlyOrders ?? 0}',
                Colors.indigo.shade50,
                Colors.indigo.shade800,
              ),
              if (_stats?.filterLabel != null) ...[
                const SizedBox(width: 8),
                _statChip(
                  _stats!.filterLabel!,
                  '',
                  Colors.grey.shade100,
                  Colors.grey.shade700,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _orderOutboxFlushInProgress
                        ? 'Sync in progress...'
                        : _lastSyncLabel(),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(
                  height: 32,
                  child: OutlinedButton(
                    onPressed: _orderOutboxFlushInProgress
                        ? null
                        : _syncNowFromHome,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: Text(
                      _orderOutboxFlushInProgress ? 'Syncing' : 'Sync now',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RequestsHubScreen(driverMobile: _profile?.mobile),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.local_gas_station,
                      color: Colors.deepPurple.shade700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.requestsTitle,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.requestsSubtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_vehicles.isNotEmpty)
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.directions_car,
                          color: Colors.indigo.shade700,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        l10n.assignedVehicle,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  for (final v in _vehicles)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.car_rental,
                                color: Colors.indigo.shade700,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  v.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (v.plateNumber != null) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  Icons.confirmation_number,
                                  size: 16,
                                  color: Colors.grey.shade700,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  l10n.plate,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    v.plateNumber!,
                                    style: TextStyle(
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (v.model != null ||
                              v.type != null ||
                              v.color != null) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                if (v.model != null)
                                  Chip(
                                    label: Text(
                                      v.model!,
                                      style: TextStyle(
                                        color: Colors.blueGrey.shade800,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    backgroundColor: Colors.blueGrey.shade50,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                if (v.type != null)
                                  Chip(
                                    label: Text(
                                      v.type!,
                                      style: TextStyle(
                                        color: Colors.blueGrey.shade800,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    backgroundColor: Colors.blueGrey.shade50,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                if (v.color != null)
                                  Chip(
                                    label: Text(
                                      v.color!,
                                      style: TextStyle(
                                        color: Colors.blueGrey.shade800,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    backgroundColor: Colors.blueGrey.shade50,
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),
                          ],
                          if (v.note != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              v.note!,
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (_vehicles.isNotEmpty) const SizedBox(height: 16),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.store, color: Colors.orange.shade700),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      l10n.businessesAndIds,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (!_isCheckedIn) ...[
                  Text(
                    l10n.checkinRequiredAccess,
                    style: TextStyle(
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.checkinPrompt,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() => _currentIndex = 2);
                      },
                      icon: const Icon(Icons.login),
                      label: Text(l10n.goToCheckin),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ] else if (assignedBusinesses.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Icon(
                            Icons.store_outlined,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.noIdsAssigned,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  for (final b in assignedBusinesses)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (b.platformId != null &&
                              b.platformId!.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(
                                  l10n.platformId,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  b.platformId!,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children:
                                (b.businessIds.isNotEmpty
                                        ? b.businessIds
                                        : b.ids
                                              .map(
                                                (id) =>
                                                    BusinessIdItem(value: id),
                                              )
                                              .toList())
                                    .map(
                                      (item) => InkWell(
                                        onTap: () =>
                                            _openOrderCreateSheet(b, item),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.deepPurple.shade50,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: Colors.deepPurple.shade200,
                                            ),
                                          ),
                                          child: Text(
                                            item.value,
                                            style: TextStyle(
                                              color: Colors.deepPurple.shade700,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.location_on,
                        color: Colors.blue.shade700,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l10n.currentLocation,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _locationAddress ?? l10n.noAddress,
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                ),
                if (_lat != null && _lng != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.coordinates('$_lat', '$_lng'),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _locating ? null : _refreshCurrentLocation,
                        icon: _locating
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.my_location),
                        label: Text(
                          _locating ? 'Updating...' : 'Refresh location',
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _locating ? null : _openMaps,
                        icon: const Icon(Icons.map),
                        label: Text(l10n.openInMaps),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrdersTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.local_shipping,
                        color: Colors.blue.shade700,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      l10n.ordersHeading,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    DropdownButton<String>(
                      value: _ordersFilter,
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('All orders'),
                        ),
                        DropdownMenuItem(
                          value: 'active',
                          child: Text('Active'),
                        ),
                        DropdownMenuItem(
                          value: 'completed',
                          child: Text('Completed'),
                        ),
                        DropdownMenuItem(
                          value: 'cancelled',
                          child: Text('Cancelled'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          _onOrdersFilterChanged(value);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_ordersFilter != 'active' && _completedHistoryLoading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (_ordersActive.isEmpty && _ordersCompleted.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child:
                          _ordersFilter != 'active' && _completedHistoryLoading
                          ? const SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            )
                          : Column(
                              children: [
                                Icon(
                                  Icons.local_shipping_outlined,
                                  size: 48,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  l10n.noOrders,
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                    ),
                  )
                else ...[
                  Builder(
                    builder: (context) {
                      final filteredOrders = _filteredOrders();
                      final totalPages = filteredOrders.isEmpty
                          ? 1
                          : (filteredOrders.length / _ordersPageSize).ceil();
                      final currentPage = filteredOrders.isEmpty
                          ? 0
                          : min(_ordersPage, totalPages - 1);
                      final startIndex = filteredOrders.isEmpty
                          ? 0
                          : currentPage * _ordersPageSize;
                      final endIndex = filteredOrders.isEmpty
                          ? 0
                          : min(
                              startIndex + _ordersPageSize,
                              filteredOrders.length,
                            );
                      final visibleOrders = filteredOrders.isEmpty
                          ? <Order>[]
                          : filteredOrders.sublist(startIndex, endIndex);

                      if (filteredOrders.isEmpty) {
                        if (_ordersFilter != 'active' &&
                            _completedHistoryLoading) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                ),
                              ),
                            ),
                          );
                        }

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Column(
                            children: [
                              Icon(
                                Icons.local_shipping_outlined,
                                size: 48,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                l10n.noOrders,
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            alignment: WrapAlignment.spaceBetween,
                            children: [
                              Text(
                                'Showing ${startIndex + 1}-$endIndex of ${filteredOrders.length}',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.chevron_left),
                                    onPressed: currentPage > 0
                                        ? () => setState(
                                            () => _ordersPage = currentPage - 1,
                                          )
                                        : null,
                                  ),
                                  Text(
                                    'Page ${currentPage + 1} / $totalPages',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.chevron_right),
                                    onPressed: currentPage < totalPages - 1
                                        ? () => setState(
                                            () => _ordersPage = currentPage + 1,
                                          )
                                        : null,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ListView.separated(
                            key: const ValueKey('orders-paged'),
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: visibleOrders.length,
                            separatorBuilder: (context, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (_, index) {
                              final order = visibleOrders[index];
                              final isCompleted =
                                  order.isDelivered || order.isCancelled;
                              return _orderTile(
                                order,
                                isCompleted: isCompleted,
                              );
                            },
                          ),
                          if (_ordersFilter != 'active')
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Column(
                                children: [
                                  if (_completedHistoryHasMore &&
                                      !_completedHistoryLoading)
                                    OutlinedButton.icon(
                                      onPressed: _loadMoreCompletedHistory,
                                      icon: const Icon(Icons.expand_more),
                                      label: const Text('Load more history'),
                                    ),
                                  if (_completedHistoryLoading)
                                    const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                      ),
                                    ),
                                  if (_completedHistoryLoadedOnce &&
                                      _completedHistoryTotal > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        'Loaded ${_ordersCompleted.length} of $_completedHistoryTotal completed/cancelled orders',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Order> _filteredOrders() {
    final combined = _mergeOrdersById(_ordersActive, _ordersCompleted);
    Iterable<Order> base;
    switch (_ordersFilter) {
      case 'active':
        base = _ordersActive;
        break;
      case 'completed':
        base = _ordersCompleted;
        break;
      case 'cancelled':
        base = combined.where((o) => o.isCancelled);
        break;
      default:
        base = combined;
    }
    return base.toList();
  }

  Widget _orderTile(Order o, {bool isCompleted = false}) {
    final isBusy = _orderActionBusy[o.id] == true;
    final statusLabel = o.isCancelled
        ? l10n.statusCancelled
        : o.isDelivered
        ? l10n.statusDelivered
        : o.isPickedUp
        ? 'Pickup'
        : 'Busy';
    final statusColor = o.isCancelled
        ? Colors.red.shade700
        : o.isDelivered
        ? Colors.green.shade700
        : o.isPickedUp
        ? Colors.blue.shade700
        : Colors.green.shade700;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.receipt_long, color: Colors.blue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.businessName.isNotEmpty
                          ? o.businessName
                          : l10n.orderFallback('${o.id}'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.orderNumberValue(o.orderNumber),
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    if (o.createdAt != null)
                      Text(
                        'Accepted: ${_formatDateTime(o.createdAt)}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              if (o.pickupTime != null)
                Text(
                  l10n.pickupTime(_formatDateTime(o.pickupTime)),
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              if (o.deliveredTime != null)
                Text(
                  l10n.deliveredTime(_formatDateTime(o.deliveredTime)),
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
            ],
          ),
          if (!isCompleted) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (!o.isPickedUp && !o.isDelivered && !o.isCancelled)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isBusy ? null : () => _pickupOrder(o),
                      icon: isBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.local_shipping),
                      label: Text(isBusy ? l10n.working : l10n.markPickup),
                    ),
                  ),
                if (o.isPickedUp && !o.isDelivered && !o.isCancelled) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isBusy ? null : () => _openDeliverSheet(o),
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(l10n.deliverAction),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
                if (!o.isDelivered && !o.isCancelled) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isBusy ? null : () => _openCancelSheet(o),
                      icon: const Icon(Icons.cancel, color: Colors.red),
                      label: Text(
                        l10n.cancelOrderAction,
                        style: const TextStyle(color: Colors.red),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.red.shade400),
                        foregroundColor: Colors.red,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCheckInOutTab() {
    final isCheckedIn = _isCheckedIn;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!isCheckedIn) ...[
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.login, color: Colors.green.shade700),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        l10n.checkinTitle,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _checkinMeterCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.meterReading,
                      prefixIcon: const Icon(Icons.speed),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      hintText: l10n.meterReadingHintCurrent,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () => _captureMeterImage(isCheckout: false),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.grey.shade300,
                          width: 2,
                          style: BorderStyle.solid,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        color: _checkinImageName != null
                            ? Colors.green.shade50
                            : Colors.grey.shade50,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _checkinImageName != null
                                ? Icons.check_circle
                                : Icons.photo_camera,
                            color: _checkinImageName != null
                                ? Colors.green.shade700
                                : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _checkinImageName ?? l10n.uploadMeterImage,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _checkinImageName != null
                                        ? Colors.green.shade700
                                        : Colors.grey.shade700,
                                  ),
                                ),
                                if (_checkinImageName == null)
                                  Text(
                                    'Tap to open camera',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _actionLoading ? null : _submitCheckIn,
                      icon: _actionLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.login),
                      label: Text(
                        _actionLoading ? l10n.checkingIn : l10n.checkinTitle,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.logout,
                          color: Colors.orange.shade700,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        l10n.checkoutTitle,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _checkoutMeterCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.meterReading,
                      prefixIcon: const Icon(Icons.speed),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      hintText: l10n.meterReadingHintFinal,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () => _captureMeterImage(isCheckout: true),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.grey.shade300,
                          width: 2,
                          style: BorderStyle.solid,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        color: _checkoutImageName != null
                            ? Colors.orange.shade50
                            : Colors.grey.shade50,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _checkoutImageName != null
                                ? Icons.check_circle
                                : Icons.photo_camera,
                            color: _checkoutImageName != null
                                ? Colors.orange.shade700
                                : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _checkoutImageName ?? l10n.uploadMeterImage,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _checkoutImageName != null
                                        ? Colors.orange.shade700
                                        : Colors.grey.shade700,
                                  ),
                                ),
                                if (_checkoutImageName == null)
                                  Text(
                                    'Tap to open camera',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: (_actionLoading || _hasActiveOrders)
                          ? null
                          : _submitCheckOut,
                      icon: _actionLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.logout),
                      label: Text(
                        _actionLoading
                            ? l10n.checkingOut
                            : _hasActiveOrders
                            ? 'Complete active orders to checkout'
                            : l10n.checkoutTitle,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildProfileTab() {
    final isRtl = _currentLang == 'ar';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Logo and Profile Picture Section with Language Switcher
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [Color(0xFF62109F), Color(0xFF9C6BB8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.all(20),
            child: Stack(
              children: [
                Column(
                  children: [
                    // Profile Picture with Camera Icon Overlapping
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        CircleAvatar(
                          radius: 60,
                          backgroundColor: Colors.white,
                          child: _profileImageBytes != null
                              ? ClipOval(
                                  child: Image.memory(
                                    _profileImageBytes!,
                                    width: 116,
                                    height: 116,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : _profileImageUrl != null
                              ? ClipOval(
                                  child: Image.network(
                                    _profileImageUrl!,
                                    width: 116,
                                    height: 116,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Icon(
                                              Icons.person,
                                              size: 60,
                                              color: Color(0xFF62109F),
                                            ),
                                  ),
                                )
                              : const Icon(
                                  Icons.person,
                                  size: 60,
                                  color: Color(0xFF62109F),
                                ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Color(0xFF9C6BB8),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 8,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: IconButton(
                              icon: const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 20,
                              ),
                              onPressed: _pickProfileImage,
                              padding: const EdgeInsets.all(8),
                              constraints: const BoxConstraints(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _profile?.name ?? l10n.driverNameFallback,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (_profileImageName != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _profileImageName!,
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
                Positioned(
                  top: 0,
                  right: isRtl ? null : 0,
                  left: isRtl ? 0 : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: DropdownButton<String>(
                      value: _currentLang,
                      underline: const SizedBox.shrink(),
                      icon: const Icon(
                        Icons.language,
                        color: Colors.white,
                        size: 20,
                      ),
                      dropdownColor: Color(0xFF62109F),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      items: [
                        DropdownMenuItem(
                          value: 'en',
                          child: Text(
                            l10n.english,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'ar',
                          child: Text(
                            l10n.arabic,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                      onChanged: _onChangeLanguage,
                    ),
                  ),
                ),
                // Camera icon now overlaps profile picture, so this is removed.
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Personal Information
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Color(0xFF62109F).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.person_outline,
                        color: Color(0xFF62109F),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      l10n.personalInformation,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.fullName,
                    prefixIcon: const Icon(Icons.person),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _mobileCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.mobileNumber,
                    prefixIcon: const Icon(Icons.phone),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _nationalityCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.nationality,
                    prefixIcon: const Icon(Icons.flag),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _languageCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.language,
                    prefixIcon: const Icon(Icons.language),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Security Section
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Color(0xFF9C6BB8).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.lock_outline, color: Color(0xFF9C6BB8)),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      l10n.changePassword,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.leaveBlankPassword,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _currentPwdCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.currentPassword,
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureCurrentPwd
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () => setState(
                        () => _obscureCurrentPwd = !_obscureCurrentPwd,
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  obscureText: _obscureCurrentPwd,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _newPwdCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.newPassword,
                    prefixIcon: const Icon(Icons.lock_open),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureNewPwd
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () =>
                          setState(() => _obscureNewPwd = !_obscureNewPwd),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  obscureText: _obscureNewPwd,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _confirmPwdCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.confirmNewPassword,
                    prefixIcon: const Icon(Icons.lock_reset),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPwd
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () => setState(
                        () => _obscureConfirmPwd = !_obscureConfirmPwd,
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  obscureText: _obscureConfirmPwd,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _actionLoading ? null : _submitProfile,
            icon: _actionLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save),
            label: Text(_actionLoading ? l10n.saving : l10n.saveChanges),
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _statChip(String label, String value, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: fg, fontWeight: FontWeight.w600),
          ),
          if (value.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(value, style: TextStyle(color: fg)),
          ],
        ],
      ),
    );
  }
}
