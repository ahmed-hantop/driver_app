import 'package:driver_app/services/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = AppUpdateService.instance;

  group('AppUpdateService', () {
    test('only allows approved store and company update URLs', () {
      expect(
        service.allowedUpdateUri('https://play.google.com/store/apps/details?id=com.example')?.host,
        'play.google.com',
      );
      expect(
        service.allowedUpdateUri('market://details?id=com.example')?.scheme,
        'market',
      );
      expect(
        service.allowedUpdateUri('https://speedlogi.sa/driver-app')?.host,
        'speedlogi.sa',
      );
      expect(
        service.allowedUpdateUri('https://updates.speedlogi.sa/driver-app')?.host,
        'updates.speedlogi.sa',
      );
      expect(service.allowedUpdateUri('http://play.google.com/store/apps/details?id=com.example'), isNull);
      expect(service.allowedUpdateUri('https://evil.example.com/driver-app'), isNull);
    });

    test('requires update when current version is below minimum', () {
      final decision = service.decisionFromPolicyForTest('1.0.0', {
        'latest_version': '1.0.5',
        'minimum_version': '1.0.2',
        'force_update': false,
        'android_url': 'https://play.google.com/store/apps/details?id=com.example',
        'ios_url': 'https://apps.apple.com/app/id123',
        'message': 'Please update',
      });

      expect(decision.mustUpdate, isTrue);
      expect(decision.updateUrl, 'https://play.google.com/store/apps/details?id=com.example');
      expect(decision.message, 'Please update');
    });

    test('strips a disallowed update URL even when update is required', () {
      final decision = service.decisionFromPolicyForTest('1.0.4+9', {
        'latest_version': '1.0.5',
        'minimum_version': '1.0.0',
        'force_update': true,
        'android_url': 'https://evil.example.com/update.apk',
        'ios_url': 'https://evil.example.com/update',
        'message': 'Blocked version',
      });

      expect(decision.mustUpdate, isTrue);
      expect(decision.updateUrl, isEmpty);
    });

    test('compares versions while ignoring build suffixes', () {
      expect(service.isVersionLowerForTest('1.0.8+10', '1.0.9'), isTrue);
      expect(service.isVersionLowerForTest('1.0.9+10', '1.0.9'), isFalse);
      expect(service.isVersionLowerForTest('1.0.10', '1.0.9'), isFalse);
    });
  });
}