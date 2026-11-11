import 'package:driver_app/services/log_redactor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LogRedactor', () {
    test('redacts sensitive fields in free-form text', () {
      const raw =
          'Authorization: Bearer super-secret token=abc123 {"password":"secret","lat":"26.42","email":"driver@example.com"}';

      final sanitized = LogRedactor.sanitizeText(raw, maxChars: 500);

      expect(sanitized, contains('Bearer <redacted>'));
      expect(sanitized, contains('token=<redacted>'));
      expect(sanitized, contains('"password":"<redacted>"'));
      expect(sanitized, contains('"lat":"<redacted>"'));
      expect(sanitized, contains('"email":"<redacted>"'));
      expect(sanitized, isNot(contains('super-secret')));
      expect(sanitized, isNot(contains('abc123')));
      expect(sanitized, isNot(contains('secret')));
      expect(sanitized, isNot(contains('26.42')));
      expect(sanitized, isNot(contains('driver@example.com')));
    });

    test('redacts nested sensitive values in structured context', () {
      final sanitized = LogRedactor.sanitizeContext({
        'event': 'upload_failed',
        'token': 'top-secret',
        'mobile': '0555000111',
        'nested': {
          'email': 'driver@example.com',
          'reason': 'timeout',
        },
        'items': [
          {'latitude': 26.42, 'label': 'pickup'},
        ],
      });

      expect(sanitized, isNotNull);
      expect(sanitized!['event'], 'upload_failed');
      expect(sanitized['token'], '<redacted>');
      expect(sanitized['mobile'], '<redacted>');
      expect((sanitized['nested'] as Map<String, dynamic>)['email'], '<redacted>');
      expect((sanitized['nested'] as Map<String, dynamic>)['reason'], 'timeout');
      expect(((sanitized['items'] as List<dynamic>).first as Map<String, dynamic>)['latitude'], '<redacted>');
      expect(((sanitized['items'] as List<dynamic>).first as Map<String, dynamic>)['label'], 'pickup');
    });
  });
}