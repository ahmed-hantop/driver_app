import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/chat_models.dart';
import 'api_constants.dart';
import 'auth_storage.dart';

class ChatService {
  static const Duration _timeout = Duration(seconds: 20);

  Future<Map<String, String>> _headers() async {
    final token = await AuthStorage.instance.readToken();
    return {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      'Accept-Encoding': 'gzip',
    };
  }

  Future<List<ChatConversation>> fetchConversations() async {
    final resp = await http
        .get(Uri.parse('${ApiConstants.baseUrl}${ApiConstants.chatConversations}'), headers: await _headers())
        .timeout(_timeout);
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 200) {
      final data = body['response'] as List? ?? [];
      return data.map((e) => ChatConversation.fromJson(e as Map<String, dynamic>)).toList();
    }
    if (resp.statusCode == 403) throw ChatFeatureDisabledException();
    throw Exception(body['message'] ?? 'Failed to load conversations');
  }

  Future<ChatConversation> startConversation({
    required String department,
    required String message,
    String? subject,
  }) async {
    final headers = await _headers();
    headers['Content-Type'] = 'application/json';
    final resp = await http
        .post(
          Uri.parse('${ApiConstants.baseUrl}${ApiConstants.chatConversations}'),
          headers: headers,
          body: jsonEncode({'department': department, 'message': message, 'subject': subject}),
        )
        .timeout(_timeout);
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 201) return ChatConversation.fromJson(body['response'] as Map<String, dynamic>);
    if (resp.statusCode == 403) throw ChatFeatureDisabledException();
    throw Exception(body['message'] ?? 'Failed to start conversation');
  }

  Future<List<ChatMessage>> fetchMessages(int conversationId, {int page = 1}) async {
    final resp = await http
        .get(
          Uri.parse('${ApiConstants.baseUrl}${ApiConstants.chatConversations}/$conversationId/messages?per_page=40&page=$page'),
          headers: await _headers(),
        )
        .timeout(_timeout);
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 200) {
      final data = (body['response']?['data'] ?? body['response']) as List? ?? [];
      return data.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception(body['message'] ?? 'Failed to load messages');
  }

  Future<List<ChatTicket>> fetchTickets(int conversationId) async {
    final resp = await http
        .get(
          Uri.parse('${ApiConstants.baseUrl}${ApiConstants.chatConversations}/$conversationId/tickets'),
          headers: await _headers(),
        )
        .timeout(_timeout);
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 200) {
      final data = body['response'] as List? ?? [];
      return data.map((e) => ChatTicket.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception(body['message'] ?? 'Failed to load tickets');
  }

  Future<ChatMessage> sendMessage(int conversationId, String text, {File? attachment}) async {
    final token = await AuthStorage.instance.readToken();
    final uri = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.chatConversations}/$conversationId/messages');

    http.Response resp;
    if (attachment != null) {
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..headers['Accept'] = 'application/json'
        ..fields['message'] = text
        ..files.add(await http.MultipartFile.fromPath('attachment', attachment.path));
      final streamed = await request.send().timeout(_timeout);
      resp = await http.Response.fromStream(streamed);
    } else {
      final headers = await _headers();
      headers['Content-Type'] = 'application/json';
      resp = await http.post(uri, headers: headers, body: jsonEncode({'message': text})).timeout(_timeout);
    }

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 201) return ChatMessage.fromJson(body['response'] as Map<String, dynamic>);
    throw Exception(body['message'] ?? 'Failed to send message');
  }

  Future<void> sendTypingIndicator(int conversationId) async {
    final headers = await _headers();
    headers['Content-Type'] = 'application/json';
    await http
        .post(Uri.parse('${ApiConstants.baseUrl}${ApiConstants.chatConversations}/$conversationId/typing'), headers: headers)
        .timeout(const Duration(seconds: 5));
  }

  Future<int> fetchUnreadCount() async {
    try {
      final resp = await http
          .get(Uri.parse('${ApiConstants.baseUrl}${ApiConstants.chatUnreadCount}'), headers: await _headers())
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return (body['response']?['count'] as num? ?? 0).toInt();
    } catch (_) {
      return 0;
    }
  }
}

class ChatFeatureDisabledException implements Exception {
  @override
  String toString() => 'Chat is currently unavailable.';
}
