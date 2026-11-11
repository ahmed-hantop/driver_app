import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/chat_models.dart';
import 'api_constants.dart';
import 'auth_storage.dart';

class CallService {
  static const Duration _timeout = Duration(seconds: 15);

  Future<Map<String, String>> _headers() async {
    final token = await AuthStorage.instance.readToken();
    return {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      'Accept-Encoding': 'gzip',
    };
  }

  /// Poll for an incoming call (FCM fallback — app checks when foregrounded)
  Future<IncomingCallData?> checkPendingCall() async {
    try {
      final resp = await http
          .get(Uri.parse('${ApiConstants.baseUrl}${ApiConstants.callsPending}'), headers: await _headers())
          .timeout(_timeout);
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 200 && body['response']?['pending'] == true) {
        return IncomingCallData.fromJson(body['response'] as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  /// Poll to detect if admin cancelled (incoming) or ended (in-call) a specific call.
  /// Returns the DB status string ('initiated', 'answered', 'ended', etc.) or null on error.
  Future<String?> checkCallStatus(int callLogId) async {
    try {
      final resp = await http
          .get(Uri.parse('${ApiConstants.baseUrl}/calls/$callLogId/status'), headers: await _headers())
          .timeout(_timeout);
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 200) return body['response']?['status'] as String?;
    } catch (_) {}
    return null;
  }

  /// Answer a call — returns LiveKit URL, room, and token
  Future<IncomingCallData> answerCall(int callLogId) async {
    final headers = await _headers();
    headers['Content-Type'] = 'application/json';
    final resp = await http
        .post(Uri.parse('${ApiConstants.baseUrl}/calls/$callLogId/answer'), headers: headers)
        .timeout(_timeout);
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 200) return IncomingCallData.fromJson(body['response'] as Map<String, dynamic>);
    throw Exception(body['message'] ?? 'Failed to answer call');
  }

  /// Records that Android displayed the native incoming-call UI. This lets DMS
  /// distinguish a real ring from an undelivered FCM request.
  Future<void> markRinging(int callLogId) async {
    final headers = await _headers();
    headers['Content-Type'] = 'application/json';
    await http
        .post(Uri.parse('${ApiConstants.baseUrl}/calls/$callLogId/ring'), headers: headers)
        .timeout(const Duration(seconds: 5));
  }

  Future<void> rejectCall(int callLogId) async {
    final headers = await _headers();
    headers['Content-Type'] = 'application/json';
    await http
        .post(Uri.parse('${ApiConstants.baseUrl}/calls/$callLogId/reject'), headers: headers)
        .timeout(_timeout);
  }

  Future<int> endCall(int callLogId, {Map<String, dynamic>? qualityStats}) async {
    final headers = await _headers();
    headers['Content-Type'] = 'application/json';
    final resp = await http
        .post(
          Uri.parse('${ApiConstants.baseUrl}/calls/$callLogId/end'),
          headers: headers,
          body: jsonEncode({'quality_stats': qualityStats}),
        )
        .timeout(_timeout);
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return (body['response']?['duration_seconds'] as num? ?? 0).toInt();
  }
}
