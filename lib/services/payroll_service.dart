import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/payroll_slip.dart';
import 'api_constants.dart';
import 'auth_storage.dart';

class PayrollService {
  static const Duration _timeout = Duration(seconds: 20);

  Future<Map<String, String>> _headers() async {
    final token = await AuthStorage.instance.readToken();
    return {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      'Accept-Encoding': 'gzip',
    };
  }

  Future<List<PayrollSlip>> fetchSlips() async {
    final resp = await http
        .get(Uri.parse('${ApiConstants.baseUrl}${ApiConstants.payrollSlips}'), headers: await _headers())
        .timeout(_timeout);

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 200) {
      final data = (body['response'] ?? body['data']) as List? ?? [];
      return data.map((e) => PayrollSlip.fromJson(e as Map<String, dynamic>)).toList();
    }
    if (resp.statusCode == 403) throw PayrollFeatureDisabledException();
    throw Exception(body['message'] ?? 'Failed to load payroll slips');
  }

  Future<PayrollSlipDetail> fetchSlipDetail(int id) async {
    final resp = await http
        .get(Uri.parse('${ApiConstants.baseUrl}${ApiConstants.payrollSlips}/$id'), headers: await _headers())
        .timeout(_timeout);

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode == 200) {
      final data = (body['response'] ?? body['data']) as Map<String, dynamic>;
      return PayrollSlipDetail.fromJson(data);
    }
    if (resp.statusCode == 403) throw PayrollFeatureDisabledException();
    throw Exception(body['message'] ?? 'Failed to load slip detail');
  }

  Future<void> acknowledge(int id) async {
    await http
        .post(Uri.parse('${ApiConstants.baseUrl}${ApiConstants.payrollSlips}/$id/acknowledge'), headers: await _headers())
        .timeout(_timeout);
  }
}

class PayrollFeatureDisabledException implements Exception {
  @override
  String toString() => 'Payroll is currently unavailable.';
}
