import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/fuel_request.dart';
import '../models/recharge_request.dart';
import 'api_constants.dart';
import 'api_service.dart';
import 'auth_storage.dart';

class RequestService {
  static const Duration _timeout = Duration(seconds: 20);
  static const Duration _uploadTimeout = Duration(seconds: 45);

  Future<Map<String, String>> _headers() async {
    final token = await AuthStorage.instance.readToken();
    return {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      'Accept-Encoding': 'gzip',
    };
  }

  MediaType _inferImageContentType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.gif')) return MediaType('image', 'gif');
    if (lower.endsWith('.webp')) return MediaType('image', 'webp');
    return MediaType('image', 'jpeg');
  }

  Future<
      ({
        List<FuelRequestItem> history,
        List<FuelRequestItem> pending,
        FuelAssignedVehicle? vehicle,
      })> fetchFuelRequests() async {
    final resp = await http
        .get(
          Uri.parse('${ApiConstants.baseUrl}${ApiConstants.fuelRequests}'),
          headers: await _headers(),
        )
        .timeout(_timeout);

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 200) {
      final data = (body['response'] ?? body['data'] ?? {}) as Map<String, dynamic>;
      final history = (data['history'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(FuelRequestItem.fromJson)
          .toList();
      final pending = (data['request'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(FuelRequestItem.fromJson)
          .toList();
      final vehicleRaw = data['vehicle'];
      final vehicle = vehicleRaw is Map<String, dynamic>
          ? FuelAssignedVehicle.fromJson(vehicleRaw)
          : null;
      return (history: history, pending: pending, vehicle: vehicle);
    }

    throw Exception(
      ApiService.parseUserVisibleMessage(resp) ?? 'Failed to load fuel requests',
    );
  }

  Future<({bool success, String? message})> submitFuelRequest({
    required int totalOrders,
    File? proofImage,
    Uint8List? proofImageBytes,
    String? proofImageName,
  }) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}${ApiConstants.fuelRequests}');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(await _headers())
      ..fields['total_orders'] = totalOrders.toString();

    if (proofImage != null) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'files',
          proofImage.path,
          contentType: _inferImageContentType(proofImage.path),
        ),
      );
    } else if (proofImageBytes != null) {
      final filename = proofImageName ?? 'fuel_proof.jpg';
      request.files.add(
        http.MultipartFile.fromBytes(
          'files',
          proofImageBytes,
          filename: filename,
          contentType: _inferImageContentType(filename),
        ),
      );
    }

    try {
      final streamed = await request.send().timeout(_uploadTimeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return (success: true, message: null);
      }
      return (
        success: false,
        message: ApiService.parseUserVisibleMessage(response) ??
            'Failed to submit fuel request',
      );
    } catch (_) {
      return (success: false, message: null);
    }
  }

  Future<({List<RechargeRequestItem> history, List<RechargeRequestItem> pending})>
      fetchRechargeRequests() async {
    final resp = await http
        .get(
          Uri.parse('${ApiConstants.baseUrl}${ApiConstants.rechargeRequests}'),
          headers: await _headers(),
        )
        .timeout(_timeout);

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 200) {
      final data = (body['response'] ?? body['data'] ?? {}) as Map<String, dynamic>;
      final history = (data['history'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(RechargeRequestItem.fromJson)
          .toList();
      final pending = (data['request'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(RechargeRequestItem.fromJson)
          .toList();
      return (history: history, pending: pending);
    }

    throw Exception(
      ApiService.parseUserVisibleMessage(resp) ?? 'Failed to load recharge requests',
    );
  }

  Future<({bool success, String? message})> submitRechargeRequest({
    required String mobile,
    required String operatorName,
  }) async {
    final headers = await _headers();
    headers['Content-Type'] = 'application/x-www-form-urlencoded';

    final resp = await http
        .post(
          Uri.parse('${ApiConstants.baseUrl}${ApiConstants.rechargeRequests}'),
          headers: headers,
          body: {'mobile': mobile, 'operator': operatorName},
        )
        .timeout(_timeout);

    if (resp.statusCode == 200 || resp.statusCode == 201) {
      return (success: true, message: null);
    }
    return (
      success: false,
      message: ApiService.parseUserVisibleMessage(resp) ??
          'Failed to submit recharge request',
    );
  }
}
