import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class SecureValueStore {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

class FlutterSecureValueStore implements SecureValueStore {
  const FlutterSecureValueStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) {
    return _storage.read(key: key);
  }

  @override
  Future<void> write({required String key, required String value}) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete({required String key}) {
    return _storage.delete(key: key);
  }
}

typedef SharedPreferencesLoader = Future<SharedPreferences> Function();

class AuthStorage {
  AuthStorage._({
    SecureValueStore? secureStore,
    SharedPreferencesLoader? sharedPreferencesLoader,
  }) : _secureStore = secureStore ?? const FlutterSecureValueStore(),
       _sharedPreferencesLoader = sharedPreferencesLoader ?? SharedPreferences.getInstance;

  static final AuthStorage instance = AuthStorage._();
  static const String _secureTokenKey = 'driver_auth_token_v1';
  static const String _legacyTokenKey = 'token';

  final SecureValueStore _secureStore;
  final SharedPreferencesLoader _sharedPreferencesLoader;

  @visibleForTesting
  factory AuthStorage.test({
    required SecureValueStore secureStore,
    required SharedPreferencesLoader sharedPreferencesLoader,
  }) {
    return AuthStorage._(
      secureStore: secureStore,
      sharedPreferencesLoader: sharedPreferencesLoader,
    );
  }

  Future<String?> readToken({bool migrateLegacy = true}) async {
    final secureToken = (await _secureStore.read(key: _secureTokenKey))?.trim();
    if (secureToken != null && secureToken.isNotEmpty) {
      if (migrateLegacy) {
        await clearLegacyToken();
      }
      return secureToken;
    }

    if (!migrateLegacy) {
      return null;
    }

    final prefs = await _sharedPreferencesLoader();
    final legacyToken = prefs.getString(_legacyTokenKey)?.trim();
    if (legacyToken == null || legacyToken.isEmpty) {
      await prefs.remove(_legacyTokenKey);
      return null;
    }

    await writeToken(legacyToken);
    return legacyToken;
  }

  Future<void> writeToken(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      await clearToken();
      return;
    }

    await _secureStore.write(key: _secureTokenKey, value: trimmed);
    await clearLegacyToken();
  }

  Future<void> clearToken() async {
    await _secureStore.delete(key: _secureTokenKey);
    await clearLegacyToken();
  }

  Future<void> clearLegacyToken() async {
    final prefs = await _sharedPreferencesLoader();
    await prefs.remove(_legacyTokenKey);
  }
}