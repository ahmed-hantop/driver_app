import 'package:driver_app/services/auth_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeSecureValueStore implements SecureValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async {
    return values[key];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AuthStorage createStorage(FakeSecureValueStore secureStore, {Map<String, Object> initialPrefs = const {}}) {
    SharedPreferences.setMockInitialValues(initialPrefs);
    return AuthStorage.test(
      secureStore: secureStore,
      sharedPreferencesLoader: SharedPreferences.getInstance,
    );
  }

  group('AuthStorage', () {
    test('migrates a legacy shared-preferences token into secure storage', () async {
      final secureStore = FakeSecureValueStore();
      final storage = createStorage(
        secureStore,
        initialPrefs: const {'token': ' legacy-token '},
      );

      final token = await storage.readToken();
      final prefs = await SharedPreferences.getInstance();

      expect(token, 'legacy-token');
      expect(await storage.readToken(migrateLegacy: false), 'legacy-token');
      expect(prefs.getString('token'), isNull);
    });

    test('writeToken trims the value and clears the legacy token', () async {
      final secureStore = FakeSecureValueStore();
      final storage = createStorage(
        secureStore,
        initialPrefs: const {'token': 'old-token'},
      );

      await storage.writeToken(' fresh-token ');
      final prefs = await SharedPreferences.getInstance();

      expect(await storage.readToken(migrateLegacy: false), 'fresh-token');
      expect(prefs.getString('token'), isNull);
    });

    test('clearToken removes both secure and legacy token values', () async {
      final secureStore = FakeSecureValueStore();
      final storage = createStorage(
        secureStore,
        initialPrefs: const {'token': 'legacy-token'},
      );

      await storage.writeToken('secure-token');
      await storage.clearToken();
      final prefs = await SharedPreferences.getInstance();

      expect(await storage.readToken(migrateLegacy: false), isNull);
      expect(prefs.getString('token'), isNull);
      expect(secureStore.values, isEmpty);
    });
  });
}