import 'package:driver_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('ApiService.parseUserVisibleMessage', () {
    test('returns structured validation messages', () {
      final response = http.Response(
        '{"message":"Validation errors","response":{"meter_image":["Meter image required"]}}',
        422,
        headers: const {'content-type': 'application/json'},
      );

      expect(ApiService.parseUserVisibleMessage(response), 'Meter image required');
    });

    test('drops unstructured raw response bodies', () {
      final response = http.Response(
        r'<html><body>Undefined variable $token</body></html>',
        500,
        headers: const {'content-type': 'text/html'},
      );

      expect(ApiService.parseUserVisibleMessage(response), isNull);
    });
  });
}