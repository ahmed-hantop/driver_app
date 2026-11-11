import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'api_constants.dart';
import 'auth_storage.dart';
import 'driver_session_state_service.dart';
import 'log_redactor.dart';
import 'network_client.dart';

class _CachedGetEntry {
  _CachedGetEntry({
    required this.response,
    required this.cachedAt,
    required this.ttl,
  });

  final http.Response response;
  final DateTime cachedAt;
  final Duration ttl;

  bool get isFresh => DateTime.now().difference(cachedAt) <= ttl;
}

class ApiService {
  static const Duration _requestTimeout = Duration(seconds: 20);
  static const Duration _multipartRequestTimeout = Duration(seconds: 45);
  static const Duration _retryDelay = Duration(milliseconds: 700);
  static const Duration _getCacheTtl = Duration(seconds: 15);
  static const Duration _statsCacheTtl = Duration(seconds: 20);
  static const Duration _ordersCacheTtl = Duration(seconds: 5);
  static const Duration _businessesCacheTtl = Duration(seconds: 60);

  String? _token;
  bool _unauthorized = false;
  bool _lastRequestTimedOut = false;
  String? _lastRequestError;
  final Map<String, _CachedGetEntry> _getCache = {};
  final Map<String, Future<http.Response>> _inFlightGetRequests = {};
  int _cacheHitCount = 0;
  int _dedupJoinCount = 0;
  int _networkRequestCount = 0;

  bool get isUnauthorized => _unauthorized;
  bool get hasToken => _token != null && _token!.isNotEmpty;
  bool get lastRequestTimedOut => _lastRequestTimedOut;
  String? get lastRequestError => _lastRequestError;

  Map<String, int> getPerformanceSnapshot() {
    return {
      'cache_hits': _cacheHitCount,
      'dedup_joins': _dedupJoinCount,
      'network_calls': _networkRequestCount,
      'cache_entries': _getCache.length,
      'inflight_gets': _inFlightGetRequests.length,
    };
  }

  void _resetRequestStatus() {
    _lastRequestTimedOut = false;
    _lastRequestError = null;
  }

  void _setRequestException(Object error) {
    _lastRequestTimedOut = error is TimeoutException;
    _lastRequestError = null;
  }

  static const int _maxDebugPayloadChars = 220;
  static final RegExp _jsonSensitiveFieldPattern = RegExp(
    r'("?(?:token|password|authorization|access_token|refresh_token|secret|lat|lng|long|latitude|longitude|created_latitude|created_longitude|pickup_latitude|pickup_longitude|delivered_latitude|delivered_longitude|location_address)"?\s*:\s*")([^"]*)(")',
    caseSensitive: false,
  );
  static final RegExp _querySensitiveFieldPattern = RegExp(
    r'\b(token|password|authorization|access_token|refresh_token|secret|lat|lng|long|latitude|longitude|created_latitude|created_longitude|pickup_latitude|pickup_longitude|delivered_latitude|delivered_longitude|location_address)=([^&,\s]+)',
    caseSensitive: false,
  );

  bool _isSensitiveField(String key) {
    final normalized = key.toLowerCase();
    return normalized.contains('token') ||
        normalized.contains('password') ||
        normalized.contains('secret') ||
        normalized.contains('authorization') ||
        normalized == 'lat' ||
        normalized == 'lng' ||
        normalized == 'long' ||
        normalized.contains('latitude') ||
        normalized.contains('longitude') ||
        normalized.contains('location');
  }

  Map<String, String> _sanitizeDebugMap(Map<String, String> values) {
    return values.map(
      (key, value) => MapEntry(key, _isSensitiveField(key) ? '<redacted>' : value),
    );
  }

  String _summarizeDebugText(String raw) {
    if (raw.isEmpty) return '';

    var sanitized = raw.replaceAllMapped(
      _jsonSensitiveFieldPattern,
      (match) => '${match.group(1)}<redacted>${match.group(3)}',
    );
    sanitized = sanitized.replaceAllMapped(
      _querySensitiveFieldPattern,
      (match) => '${match.group(1)}=<redacted>',
    );

    if (sanitized.length <= _maxDebugPayloadChars) {
      return sanitized;
    }

    return '${sanitized.substring(0, _maxDebugPayloadChars)}...';
  }

  void _debugLog(String message) {
    if (!kDebugMode) return;
    debugPrint(LogRedactor.sanitizeText(message));
  }

  void _debugRequest(String label, {Map<String, String>? body}) {
    if (!kDebugMode) return;
    if (body == null || body.isEmpty) {
      debugPrint(label);
      return;
    }

    debugPrint('$label body=${_summarizeDebugText(jsonEncode(_sanitizeDebugMap(body)))}');
  }

  void _debugResponse(String label, http.Response response) {
    if (!kDebugMode) return;
    final summary = _summarizeDebugText(response.body);
    if (summary.isEmpty) {
      debugPrint('$label status=${response.statusCode}');
      return;
    }

    debugPrint('$label status=${response.statusCode} body=$summary');
  }

  void _debugException(String label, Object error, [StackTrace? stack]) {
    if (!kDebugMode) return;
    debugPrint('$label: ${LogRedactor.sanitizeText(error)}');
    if (stack != null) {
      debugPrint(LogRedactor.sanitizeText(stack.toString(), maxChars: 1200));
    }
  }

  http.Response _cloneResponse(http.Response response) {
    return http.Response.bytes(
      response.bodyBytes,
      response.statusCode,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
      request: response.request,
    );
  }

  String _buildGetCacheKey(Uri uri, Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return uri.toString();
    final sorted = headers.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final joined = sorted.map((e) => '${e.key}:${e.value}').join('|');
    return '${uri.toString()}::$joined';
  }

  void _invalidateGetCaches() {
    _getCache.clear();
    _inFlightGetRequests.clear();
  }

  Map<String, String> get _authHeaders => {
        if (_token != null) 'Authorization': 'Bearer $_token',
        'Accept': 'application/json',
        'Accept-Encoding': 'gzip',
      };

  bool _isRetryableNetworkError(Object error) {
    return error is SocketException || error is TimeoutException || error is http.ClientException;
  }

  Future<http.Response> _performRequest({
    required Future<http.Response> Function() call,
    required String label,
    bool retryOnNetworkFailure = false,
  }) async {
    final maxAttempts = retryOnNetworkFailure ? 2 : 1;
    Object? lastError;
    StackTrace? lastStack;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await call();
      } catch (e, stack) {
        lastError = e;
        lastStack = stack;
        final canRetry = retryOnNetworkFailure && attempt < maxAttempts && _isRetryableNetworkError(e);
        if (canRetry) {
          _debugLog('$label failed on attempt $attempt. Retrying... ($e)');
          await Future<void>.delayed(_retryDelay);
          continue;
        }
        rethrow;
      }
    }

    if (lastError != null && lastStack != null) {
      Error.throwWithStackTrace(lastError, lastStack);
    }
    throw StateError('Request failed without error: $label');
  }

  Future<http.Response> _get(
    Uri uri, {
    Map<String, String>? headers,
    bool retryOnNetworkFailure = true,
    bool useCache = false,
    Duration? cacheTtl,
  }) {
    final cacheKey = _buildGetCacheKey(uri, headers);

    if (useCache) {
      final cached = _getCache[cacheKey];
      if (cached != null && cached.isFresh) {
        _cacheHitCount += 1;
        return Future.value(_cloneResponse(cached.response));
      }
      if (cached != null && !cached.isFresh) {
        _getCache.remove(cacheKey);
      }
    }

    final inFlight = _inFlightGetRequests[cacheKey];
    if (inFlight != null) {
      _dedupJoinCount += 1;
      return inFlight.then(_cloneResponse);
    }

    _networkRequestCount += 1;

    final future = _performRequest(
      call: () => DriverAppHttpClient.client.get(uri, headers: headers).timeout(_requestTimeout),
      label: 'GET $uri',
      retryOnNetworkFailure: retryOnNetworkFailure,
    );
    _inFlightGetRequests[cacheKey] = future;

    return future.then((response) {
      if (useCache && response.statusCode == 200) {
        _getCache[cacheKey] = _CachedGetEntry(
          response: _cloneResponse(response),
          cachedAt: DateTime.now(),
          ttl: cacheTtl ?? _getCacheTtl,
        );
      }
      return _cloneResponse(response);
    }).whenComplete(() {
      _inFlightGetRequests.remove(cacheKey);
    });
  }

  Future<http.Response> _post(
    Uri uri, {
    Map<String, String>? headers,
    Map<String, String>? body,
    bool retryOnNetworkFailure = false,
  }) {
    return _performRequest(
      call: () => DriverAppHttpClient.client.post(uri, headers: headers, body: body).timeout(_requestTimeout),
      label: 'POST $uri',
      retryOnNetworkFailure: retryOnNetworkFailure,
    );
  }

  Future<http.Response> _patch(
    Uri uri, {
    Map<String, String>? headers,
    Map<String, String>? body,
  }) {
    return _performRequest(
      call: () => DriverAppHttpClient.client.patch(uri, headers: headers, body: body).timeout(_requestTimeout),
      label: 'PATCH $uri',
    );
  }

  Future<http.Response> _postJson(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    bool retryOnNetworkFailure = false,
  }) {
    final requestHeaders = <String, String>{
      ...?headers,
      'Content-Type': 'application/json',
    };

    return _performRequest(
      call: () => DriverAppHttpClient.client
          .post(uri, headers: requestHeaders, body: jsonEncode(body ?? {}))
          .timeout(_requestTimeout),
      label: 'POST $uri',
      retryOnNetworkFailure: retryOnNetworkFailure,
    );
  }

  Future<http.Response> _put(
    Uri uri, {
    Map<String, String>? headers,
    Map<String, String>? body,
    bool retryOnNetworkFailure = false,
  }) {
    return _performRequest(
      call: () => DriverAppHttpClient.client.put(uri, headers: headers, body: body).timeout(_requestTimeout),
      label: 'PUT $uri',
      retryOnNetworkFailure: retryOnNetworkFailure,
    );
  }

  Future<http.StreamedResponse> _sendMultipart(http.MultipartRequest request) {
    return DriverAppHttpClient.client.send(request).timeout(_multipartRequestTimeout);
  }

  Future<void> loadToken() async {
    if (_token != null && _token!.isNotEmpty) return;
    _token = await AuthStorage.instance.readToken();
    _unauthorized = false;
  }

  Future<void> _clearAuth() async {
    _token = null;
    _invalidateGetCaches();
    await AuthStorage.instance.clearToken();
    await DriverSessionStateService.clearPersistedState();
    _unauthorized = true;
  }

  Future<bool> hasValidStoredSession() async {
    _token = await AuthStorage.instance.readToken();
    if (_token == null || _token!.isEmpty) {
      await DriverSessionStateService.clearPersistedState();
      _unauthorized = false;
      return false;
    }

    final stillValid = await _isSessionStillValid();
    if (!stillValid) {
      await _clearAuth();
      return false;
    }

    _unauthorized = false;
    return true;
  }

  Future<bool> _isSessionStillValid() async {
    if (_token == null || _token!.isEmpty) return false;

    try {
      final response = await _get(
        Uri.parse(ApiConstants.baseUrl + ApiConstants.profile),
        headers: _authHeaders,
      );
      return response.statusCode != 401;
    } catch (e) {
      // Keep the local session on transient network failures.
      _debugLog('Session validation skipped due to network error: $e');
      return true;
    }
  }

  Future<void> _handleUnauthorized({bool verifyWithProfile = true}) async {
    if (!verifyWithProfile) {
      await _clearAuth();
      return;
    }

    final stillValid = await _isSessionStillValid();
    if (!stillValid) {
      await _clearAuth();
      return;
    }

    _unauthorized = false;
  }

  Future<bool> login(
    String iqamaNumber,
    String password, {
    String? deviceId,
    String? deviceModel,
    String? osVersion,
    String? fcmToken,
  }) async {
    try {
      _debugLog('Attempting login');
      final body = <String, String>{
        'iqaama_number': iqamaNumber,
        'password': password,
      };
      if (deviceId    != null && deviceId.isNotEmpty)    body['device_id']    = deviceId;
      if (deviceModel != null && deviceModel.isNotEmpty) body['device_model'] = deviceModel;
      if (osVersion   != null && osVersion.isNotEmpty)   body['os_version']   = osVersion;
      if (fcmToken    != null && fcmToken.isNotEmpty)    body['fcm_token']    = fcmToken;
      body['supports_full_screen_calls'] = '1';

      final response = await _post(
        Uri.parse(ApiConstants.baseUrl + ApiConstants.login),
        body: body,
      );

      _debugLog('Login response status: ${response.statusCode}');
      _debugResponse('Login response', response);

      if (response.statusCode != 200) {
        _debugResponse('Login failed', response);
        return false;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final payload = (data['response'] ?? data) as Map<String, dynamic>;
      final token = payload['token'] as String?;

      if (token == null || token.isEmpty) {
        _debugResponse('Login failed: token missing', response);
        return false;
      }

      _token = token;
      await AuthStorage.instance.writeToken(_token!);
      _unauthorized = false;
      _debugLog('Login successful, token saved.');
      return true;
    } catch (e, stack) {
      _debugException('Login exception', e, stack);
      return false;
    }
  }

  Future<void> updateFcmToken(String fcmToken, {String? deviceId}) async {
    try {
      final headers = Map<String, String>.from(_authHeaders);
      if (deviceId != null && deviceId.isNotEmpty) {
        headers['X-Device-Id'] = deviceId;
      }
      await _patch(
        Uri.parse(ApiConstants.baseUrl + ApiConstants.updateFcmToken),
        body: {
          'fcm_token': fcmToken,
          'supports_full_screen_calls': '1',
        },
        headers: headers,
      );
    } catch (_) {}
  }

  String? _parseMessage(http.Response response) {
    return ApiService.parseUserVisibleMessage(response);
  }

  static String? parseUserVisibleMessage(http.Response response) {
    try {
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message']?.toString().trim();
        final validationMessage = _extractValidationMessage(decoded);

        final hasGenericValidationMessage = message != null &&
            message.isNotEmpty &&
            (message.toLowerCase() == 'validation error' ||
                message.toLowerCase() == 'validation errors');

        if (hasGenericValidationMessage && validationMessage != null) {
          return validationMessage;
        }

        if (message != null && message.isNotEmpty) {
          return message;
        }

        final responseMessage = decoded['response']?.toString().trim();
        if (responseMessage != null && responseMessage.isNotEmpty) {
          return responseMessage;
        }

        if (validationMessage != null) {
          return validationMessage;
        }
      }
    } catch (_) {}
    return null;
  }

  static String? _extractValidationMessage(Map<String, dynamic> body) {
    final candidates = <dynamic>[
      body['errors'],
      body['response'],
      body['data'],
      body['error'],
    ];

    for (final candidate in candidates) {
      final message = _firstNestedMessage(candidate);
      if (message != null && message.isNotEmpty) {
        return message;
      }
    }

    return null;
  }

  static String? _firstNestedMessage(dynamic value) {
    if (value == null) return null;

    if (value is String) {
      final text = value.trim();
      return text.isEmpty ? null : text;
    }

    if (value is List) {
      for (final item in value) {
        final message = _firstNestedMessage(item);
        if (message != null && message.isNotEmpty) {
          return message;
        }
      }
      return null;
    }

    if (value is Map) {
      for (final entry in value.entries) {
        final message = _firstNestedMessage(entry.value);
        if (message != null && message.isNotEmpty) {
          return message;
        }
      }
      return null;
    }

    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  String? _coordValue(double? value) {
    if (value == null) return null;
    return value.toString();
  }

  Future<({bool success, String? message})> requestPasswordReset({
    required String emailOrIqama,
  }) async {
    try {
      final response = await _post(
        Uri.parse(ApiConstants.baseUrl + ApiConstants.forgotPassword),
        headers: _authHeaders,
        body: {'email_or_iqama': emailOrIqama},
      );

      if (response.statusCode == 200) {
        return (success: true, message: _parseMessage(response));
      }

      final message = _parseMessage(response);
      _debugResponse('Forgot password failed', response);
      return (success: false, message: message);
    } catch (e, stack) {
      _debugException('Forgot password exception', e, stack);
      return (success: false, message: null);
    }
  }

  Future<({bool success, String? message})> verifyResetOtp({
    required String emailOrIqama,
    required String otp,
  }) async {
    try {
      final response = await _post(
        Uri.parse(ApiConstants.baseUrl + ApiConstants.verifyResetToken),
        headers: _authHeaders,
        body: {
          'email_or_iqama': emailOrIqama,
          'otp': otp,
        },
      );

      if (response.statusCode == 200) {
        return (success: true, message: _parseMessage(response));
      }

      final message = _parseMessage(response);
      _debugResponse('Verify reset OTP failed', response);
      return (success: false, message: message);
    } catch (e, stack) {
      _debugException('Verify reset OTP exception', e, stack);
      return (success: false, message: null);
    }
  }

  Future<({bool success, String? message})> confirmResetPassword({
    required String emailOrIqama,
    required String otp,
    required String password,
    required String passwordConfirmation,
  }) async {
    try {
      final response = await _post(
        Uri.parse(ApiConstants.baseUrl + ApiConstants.resetPassword),
        headers: _authHeaders,
        body: {
          'email_or_iqama': emailOrIqama,
          'otp': otp,
          'password': password,
          'password_confirmation': passwordConfirmation,
        },
      );

      if (response.statusCode == 200) {
        return (success: true, message: _parseMessage(response));
      }

      final message = _parseMessage(response);
      _debugResponse('Reset password failed', response);
      return (success: false, message: message);
    } catch (e, stack) {
      _debugException('Reset password exception', e, stack);
      return (success: false, message: null);
    }
  }

  Future<({bool success, String? message})> resendResetOtp({
    required String emailOrIqama,
  }) async {
    try {
      final response = await _post(
        Uri.parse(ApiConstants.baseUrl + ApiConstants.resendResetLink),
        headers: _authHeaders,
        body: {'email_or_iqama': emailOrIqama},
      );

      if (response.statusCode == 200) {
        return (success: true, message: _parseMessage(response));
      }

      final message = _parseMessage(response);
      _debugResponse('Resend reset OTP failed', response);
      return (success: false, message: message);
    } catch (e, stack) {
      _debugException('Resend reset OTP exception', e, stack);
      return (success: false, message: null);
    }
  }

  Future<Map<String, dynamic>?> getProfile() async {
    await loadToken();
    try {
      final response = await _get(
        Uri.parse(ApiConstants.baseUrl + ApiConstants.profile),
        headers: _authHeaders,
      );

      if (response.statusCode == 401) {
        await _handleUnauthorized(verifyWithProfile: false);
        return null;
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final payload = (data['response'] ?? data) as Map<String, dynamic>;
        return payload;
      }

      _debugResponse('Profile failed', response);
      return null;
    } catch (e, stack) {
      _debugException('Profile exception', e, stack);
      return null;
    }
  }

  Future<Map<String, dynamic>?> getBusinesses() async {
    await loadToken();
    final uri = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.businesses}?only_driver_businesses=true');
    try {
      final response = await _get(
        uri,
        headers: _authHeaders,
        useCache: true,
        cacheTtl: _businessesCacheTtl,
      );

      if (response.statusCode == 401) {
        await _handleUnauthorized();
        return null;
      }

      if (response.statusCode != 200) {
        _debugResponse('Businesses failed', response);
        return null;
      }

      final decoded = json.decode(response.body);
      if (decoded is List) {
        return {'businesses': decoded};
      }
      if (decoded is Map<String, dynamic>) {
        // If response is a list, wrap it under businesses
        if (decoded['response'] is List) {
          return {
            'businesses': decoded['response'],
            'is_checked_in': decoded['is_checked_in'] ?? decoded['checked_in'],
          };
        }
        final payload = decoded['response'];
        if (payload is Map<String, dynamic>) return payload;
        return decoded;
      }

      _debugLog('Businesses unexpected shape: ${_summarizeDebugText(response.body)}');
      return null;
    } catch (e, stack) {
      _debugException('Businesses exception', e, stack);
      return null;
    }
  }

  Future<Map<String, dynamic>?> getStats({
    String? day,
    String? month,
    String? year,
    String? startDate,
    String? endDate,
  }) async {
    await loadToken();
    try {
      final queryParameters = <String, String>{};
      if (day != null) queryParameters['day'] = day;
      if (month != null) queryParameters['month'] = month;
      if (year != null) queryParameters['year'] = year;
      if (startDate != null) queryParameters['start'] = startDate;
      if (endDate != null) queryParameters['end'] = endDate;
      final uri = Uri.parse(ApiConstants.baseUrl + ApiConstants.stats)
          .replace(queryParameters: queryParameters.isEmpty ? null : queryParameters);
      final response = await _get(
        uri,
        headers: _authHeaders,
        useCache: true,
        cacheTtl: _statsCacheTtl,
      );

      if (response.statusCode == 401) {
        await _handleUnauthorized();
        return null;
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final payload = (data['response'] ?? data) as Map<String, dynamic>;
        return payload;
      }

      _debugResponse('Stats failed', response);
      return null;
    } catch (e, stack) {
      _debugException('Stats exception', e, stack);
      return null;
    }
  }

  Future<Map<String, dynamic>?> getUniqueOrderBusiness() async {
    await loadToken();
    try {
      final response = await _get(
        Uri.parse(ApiConstants.baseUrl + ApiConstants.uniqueOrderBusiness),
        headers: _authHeaders,
      );

      if (response.statusCode == 401) {
        await _handleUnauthorized();
        return null;
      }

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is Map<String, dynamic>) {
          final payload = decoded['response'] ?? decoded;
          return payload is Map<String, dynamic> ? payload : {'response': payload};
        }
        return {'response': decoded};
      }

      _debugResponse('UniqueOrderBusiness failed', response);
      return null;
    } catch (e, stack) {
      _debugException('UniqueOrderBusiness exception', e, stack);
      return null;
    }
  }

  Future<Map<String, dynamic>?> getOrders({
    bool liveOnly = false,
    bool includeHistory = false,
    int historyPage = 1,
    int historyPerPage = 25,
  }) async {
    await loadToken();
    try {
      final baseUri = Uri.parse(ApiConstants.baseUrl + ApiConstants.orders);
      final queryParameters = <String, String>{};
      if (includeHistory) {
        queryParameters['mode'] = 'history';
        queryParameters['include_history'] = 'true';
        queryParameters['history_page'] = historyPage.toString();
        queryParameters['history_per_page'] = historyPerPage.toString();
      } else if (liveOnly) {
        queryParameters['mode'] = 'live';
      }

      final uri = queryParameters.isEmpty
          ? baseUri
          : baseUri.replace(queryParameters: queryParameters);

      final response = await _get(
        uri,
        headers: _authHeaders,
        useCache: true,
        cacheTtl: _ordersCacheTtl,
      );

      if (response.statusCode == 401) {
        await _handleUnauthorized();
        return null;
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final payload = (data['orders'] ?? data['response'] ?? data);
        return payload is Map<String, dynamic> ? payload : {'orders': payload};
      }

      _debugResponse('Orders failed', response);
      return null;
    } catch (e, stack) {
      _debugException('Orders exception', e, stack);
      return null;
    }
  }

  Future<({bool success, String? message, int? orderId})> createOrder({
    required int businessId,
    required int businessIdId,
    required String orderNumber,
    double? latitude,
    double? longitude,
    String? clientRequestId,
  }) async {
    await loadToken();
    try {
      final lat = _coordValue(latitude);
      final lng = _coordValue(longitude);
      final body = <String, String>{
        'business_id': businessId.toString(),
        'business_id_id': businessIdId.toString(),
        'order_id': orderNumber,
      };
      if (clientRequestId != null && clientRequestId.isNotEmpty) {
        body['client_request_id'] = clientRequestId;
      }
      if (lat != null) {
        body['created_latitude'] = lat;
        body['lat'] = lat;
      }
      if (lng != null) {
        body['created_longitude'] = lng;
        body['long'] = lng;
      }

      final response = await _post(
        Uri.parse(ApiConstants.baseUrl + ApiConstants.orders),
        headers: _authHeaders,
        body: body,
      );

      if (response.statusCode == 401) {
        await _handleUnauthorized();
        return (success: false, message: 'Unauthorized', orderId: null);
      }

      if (response.statusCode == 200) {
        _invalidateGetCaches();
        int? orderId;
        try {
          final decoded = json.decode(response.body);
          if (decoded is Map) {
            final responseObj = decoded['response'];
            final candidates = [
              decoded['order_id'],
              decoded['id'],
              responseObj is Map ? responseObj['order_id'] : null,
              responseObj is Map ? responseObj['id'] : null,
            ];
            for (final candidate in candidates) {
              final parsed = candidate is num ? candidate.toInt() : int.tryParse(candidate?.toString() ?? '');
              if (parsed != null && parsed > 0) {
                orderId = parsed;
                break;
              }
            }
          }
        } catch (_) {}
        return (success: true, message: null, orderId: orderId);
      }

      final msg = _parseMessage(response);
      _debugResponse('Create order failed', response);
      return (success: false, message: msg, orderId: null);
    } catch (e, stack) {
      _debugException('Create order exception', e, stack);
      return (success: false, message: null, orderId: null);
    }
  }

  Future<({bool success, String? message})> pickupOrder(
    int orderId, {
    double? latitude,
    double? longitude,
  }) async {
    await loadToken();
    try {
      final lat = _coordValue(latitude);
      final lng = _coordValue(longitude);
      final body = <String, String>{};
      if (lat != null) {
        body['pickup_latitude'] = lat;
        body['lat'] = lat;
      }
      if (lng != null) {
        body['pickup_longitude'] = lng;
        body['long'] = lng;
      }

      final response = await _put(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.orderPickup}/$orderId'),
        headers: _authHeaders,
        body: body,
      );
      if (response.statusCode == 401) {
        await _handleUnauthorized();
        return (success: false, message: 'Unauthorized');
      }
      if (response.statusCode == 200) {
        _invalidateGetCaches();
        return (success: true, message: null);
      }
      final msg = _parseMessage(response);
      _debugResponse('Pickup order failed', response);
      return (success: false, message: msg);
    } catch (e, stack) {
      _debugException('Pickup order exception', e, stack);
      return (success: false, message: null);
    }
  }

  Future<({bool success, String? message})> cancelOrder({
    required int orderId,
    required String reasonType,
    String? reason,
  }) async {
    await loadToken();
    try {
      final body = {
        'cancel_reason_type': reasonType,
        if (reason != null && reason.isNotEmpty) 'cancel_reason': reason,
      };
      final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.orderCancel}/$orderId');
      _debugRequest('cancelOrder POST $url', body: body);
      final response = await _post(url, headers: _authHeaders, body: body);
      _debugResponse('cancelOrder response', response);
      if (response.statusCode == 401) {
        await _handleUnauthorized();
        return (success: false, message: 'Unauthorized');
      }
      if (response.statusCode == 200) {
        _invalidateGetCaches();
        return (success: true, message: null);
      }

      final msg = _parseMessage(response);

      _debugResponse('Cancel order failed', response);
      return (success: false, message: msg);
    } catch (e, stack) {
      _debugException('Cancel order exception', e, stack);
      return (success: false, message: null);
    }
  }

  Future<({bool success, String? message})> updateOrder({
    required int orderId,
    required int type,
    String? amountReceived,
    String? amountPaid,
    double? latitude,
    double? longitude,
  }) async {
    await loadToken();
    try {
      final lat = _coordValue(latitude);
      final lng = _coordValue(longitude);

      final body = <String, String>{
        'type': type.toString(),
        'status': 'drop',
      };
      if (amountReceived != null && amountReceived.isNotEmpty) {
        body['amount_received'] = amountReceived;
      }
      if (amountPaid != null && amountPaid.isNotEmpty) {
        body['amount_paid'] = amountPaid;
      }
      if (lat != null) {
        body['delivered_latitude'] = lat;
        body['lat'] = lat;
      }
      if (lng != null) {
        body['delivered_longitude'] = lng;
        body['long'] = lng;
      }
      final url = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.orders}/$orderId');
      _debugRequest('updateOrder POST $url', body: body);
      final response = await _post(url, headers: _authHeaders, body: body);
      _debugResponse('updateOrder response', response);
      if (response.statusCode == 401) {
        await _handleUnauthorized();
        return (success: false, message: 'Unauthorized');
      }
      if (response.statusCode == 200 || response.statusCode == 201) {
        try {
          final decoded = json.decode(response.body);
          if (decoded is Map) {
            final codeVal = decoded['code'];
            final statusVal = decoded['status']?.toString().toLowerCase();
            if (decoded.containsKey('success')) {
              final successFlag = decoded['success'] == true || decoded['success'] == 'true';
              if (!successFlag) {
                final msg = decoded['message']?.toString();
                return (success: false, message: msg);
              }
            }
            if (codeVal is num && codeVal != 200) {
              final msg = decoded['message']?.toString();
              return (success: false, message: msg);
            }
            if (statusVal == 'error') {
              final msg = decoded['message']?.toString();
              return (success: false, message: msg);
            }
          }
        } catch (_) {
          // ignore parse errors; treat as success if status code is OK
        }
        _invalidateGetCaches();
        return (success: true, message: null);
      }
      final msg = _parseMessage(response);
      _debugResponse('Update order failed', response);
      return (success: false, message: msg);
    } catch (e, stack) {
      _debugException('Update order exception', e, stack);
      return (success: false, message: null);
    }
  }

  Future<({bool success, String? message, int statusCode})> checkIn({
    required String meterReading,
    File? meterImage,
    Uint8List? meterImageBytes,
    String? meterImageName,
    String? appVersion,
    String? buildNumber,
    double? latitude,
    double? longitude,
    double? gpsAccuracyM,
    bool mockLocation = false,
    bool vpnDetected = false,
    bool rootDetected = false,
    bool emulatorDetected = false,
    int? batteryLevel,
    String? networkType,
  }) async {
    await loadToken();
    final uri = Uri.parse(ApiConstants.baseUrl + ApiConstants.checkin);
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_authHeaders)
      ..fields['meter_reading'] = meterReading;

    if (appVersion != null && appVersion.trim().isNotEmpty) {
      request.fields['app_version'] = appVersion.trim();
    }
    if (buildNumber != null && buildNumber.trim().isNotEmpty) {
      request.fields['build_number'] = buildNumber.trim();
    }
    if (latitude != null)     request.fields['latitude']       = latitude.toStringAsFixed(7);
    if (longitude != null)    request.fields['longitude']      = longitude.toStringAsFixed(7);
    if (gpsAccuracyM != null) request.fields['gps_accuracy_m'] = gpsAccuracyM.toStringAsFixed(2);
    request.fields['mock_location']     = mockLocation     ? '1' : '0';
    request.fields['vpn_detected']      = vpnDetected      ? '1' : '0';
    request.fields['root_detected']     = rootDetected     ? '1' : '0';
    request.fields['emulator_detected'] = emulatorDetected ? '1' : '0';
    if (batteryLevel != null) request.fields['battery_level']  = batteryLevel.toString();
    if (networkType  != null && networkType.isNotEmpty) request.fields['network_type'] = networkType;

    if (meterImage != null) {
      request.files.add(await http.MultipartFile.fromPath(
        'meter_image',
        meterImage.path,
        contentType: _inferImageContentType(meterImage.path),
      ));
    } else if (meterImageBytes != null) {
      final filename = meterImageName ?? 'meter.jpg';
      request.files.add(http.MultipartFile.fromBytes(
        'meter_image',
        meterImageBytes,
        filename: filename,
        contentType: _inferImageContentType(filename),
      ));
    }

    try {
      final streamed = await _sendMultipart(request);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 401) {
        await _handleUnauthorized();
        return (success: false, message: 'Unauthorized', statusCode: response.statusCode);
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return (success: true, message: null, statusCode: response.statusCode);
      }
      final message = _parseMessage(response);
      _debugResponse('Check-in failed', response);
      return (success: false, message: message, statusCode: response.statusCode);
    } catch (e) {
      _debugException('Check-in exception', e);
      return (success: false, message: null, statusCode: 0);
    }
  }

  Future<({bool success, String? message, int statusCode})> checkOut({
    required String meterReading,
    File? meterImage,
    Uint8List? meterImageBytes,
    String? meterImageName,
    double? latitude,
    double? longitude,
    bool mockLocation = false,
  }) async {
    await loadToken();
    final uri = Uri.parse(ApiConstants.baseUrl + ApiConstants.checkout);
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_authHeaders)
      ..fields['out_meter_reading'] = meterReading;

    // Send a single image part to reduce payload size and avoid duplicate upload processing.
    Future<void> attachImage(String fieldName) async {
      if (meterImage != null) {
        request.files.add(await http.MultipartFile.fromPath(
          fieldName,
          meterImage.path,
          contentType: _inferImageContentType(meterImage.path),
        ));
      } else if (meterImageBytes != null) {
        final filename = meterImageName ?? 'out_meter.jpg';
        request.files.add(http.MultipartFile.fromBytes(
          fieldName,
          meterImageBytes,
          filename: filename,
          contentType: _inferImageContentType(filename),
        ));
      }
    }

    await attachImage('out_meter_image');

    if (latitude  != null) request.fields['latitude']      = latitude.toStringAsFixed(7);
    if (longitude != null) request.fields['longitude']     = longitude.toStringAsFixed(7);
    request.fields['mock_location'] = mockLocation ? '1' : '0';

    try {
      final streamed = await _sendMultipart(request);
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 401) {
        await _handleUnauthorized();
        return (success: false, message: 'Unauthorized', statusCode: response.statusCode);
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return (success: true, message: null, statusCode: response.statusCode);
      }

      final message = _parseMessage(response);

      _debugResponse('Check-out failed', response);
      return (success: false, message: message, statusCode: response.statusCode);
    } catch (e) {
      _debugException('Check-out exception', e);
      return (success: false, message: null, statusCode: 0);
    }
  }

  Future<void> logout() async {
    await loadToken();
    try {
      await _post(
        Uri.parse(ApiConstants.baseUrl + ApiConstants.logout),
        headers: _authHeaders,
      );
    } catch (_) {}

    await _clearAuth();
  }

  Future<bool> sendDriverAppLogs(List<Map<String, dynamic>> logs) async {
    if (logs.isEmpty) return true;

    await loadToken();
    if (!hasToken) return false;

    try {
      final response = await _postJson(
        Uri.parse(ApiConstants.baseUrl + ApiConstants.appLogs),
        headers: _authHeaders,
        body: {'logs': logs},
        retryOnNetworkFailure: true,
      );

      if (response.statusCode == 401) {
        await _handleUnauthorized();
        return false;
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      }

      _debugResponse('Driver app logs failed', response);
      return false;
    } catch (e, stack) {
      _debugException('Driver app logs exception', e, stack);
      return false;
    }
  }

  Future<bool> updateProfile({
    required String name,
    required String mobile,
    String? nationality,
    String? language,
    String? currentPassword,
    String? newPassword,
    String? confirmPassword,
    double? latitude,
    double? longitude,
    String? locationAddress,
    File? imageFile,
    Uint8List? imageBytes,
    String? imageName,
  }) async {
    await loadToken();
    _resetRequestStatus();
    final uri = Uri.parse(ApiConstants.baseUrl + ApiConstants.profile);
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_authHeaders)
      ..fields['_method'] = 'PUT'
      ..fields['name'] = name
      ..fields['mobile'] = mobile;

    if (nationality != null) request.fields['nationality'] = nationality;
    if (language != null) request.fields['language'] = language;
    if (currentPassword != null && currentPassword.isNotEmpty) {
      request.fields['current_password'] = currentPassword;
    }
    if (newPassword != null && newPassword.isNotEmpty) {
      request.fields['new_password'] = newPassword;
      request.fields['confirm_password'] = confirmPassword ?? newPassword;
    }

    if (latitude != null) request.fields['latitude'] = latitude.toString();
    if (longitude != null) request.fields['longitude'] = longitude.toString();
    if (locationAddress != null && locationAddress.isNotEmpty) {
      request.fields['location_address'] = locationAddress;
    }

    if (imageFile != null) {
      request.files.add(await http.MultipartFile.fromPath(
        'image',
        imageFile.path,
        contentType: _inferImageContentType(imageFile.path),
      ));
    } else if (imageBytes != null) {
      final filename = imageName ?? 'profile.jpg';
      request.files.add(http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: filename,
        contentType: _inferImageContentType(filename),
      ));
    }

    try {
      final streamed = await _sendMultipart(request);
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 401) {
        await _handleUnauthorized();
        return false;
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }
      _lastRequestError = _parseMessage(response);
      _debugResponse('Update profile failed', response);
      return false;
    } catch (e, stack) {
      _setRequestException(e);
      _debugException('Update profile exception', e, stack);
      return false;
    }
  }

  /// Send a heartbeat ping to the server with security telemetry.
  /// Returns true on success, false on any failure (non-throwing).
  Future<bool> sendHeartbeat({
    double? latitude,
    double? longitude,
    double? gpsAccuracyM,
    int? batteryLevel,
    String appState = 'foreground',
    String? networkType,
    bool mockLocation = false,
    bool vpnDetected = false,
  }) async {
    try {
      await loadToken();
      if (_token == null || _token!.isEmpty) return false;

      final body = <String, String>{
        'app_state':        appState,
        'mock_location':    mockLocation ? '1' : '0',
        'vpn_detected':     vpnDetected  ? '1' : '0',
        'device_timestamp': DateTime.now().toUtc().toIso8601String(),
      };
      if (latitude     != null) body['latitude']       = latitude.toStringAsFixed(7);
      if (longitude    != null) body['longitude']      = longitude.toStringAsFixed(7);
      if (gpsAccuracyM != null) body['gps_accuracy_m'] = gpsAccuracyM.toStringAsFixed(2);
      if (batteryLevel != null) body['battery_level']  = batteryLevel.toString();
      if (networkType  != null && networkType.isNotEmpty) body['network_type'] = networkType;

      final response = await DriverAppHttpClient.client
          .post(
            Uri.parse(ApiConstants.baseUrl + ApiConstants.heartbeat),
            headers: {
              'Authorization': 'Bearer $_token',
              'Accept': 'application/json',
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  MediaType _inferImageContentType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.gif')) return MediaType('image', 'gif');
    if (lower.endsWith('.webp')) return MediaType('image', 'webp');
    return MediaType('image', 'jpeg');
  }
}
