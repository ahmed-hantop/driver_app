import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Global locale notifier to allow runtime language switching.
final ValueNotifier<Locale> localeNotifier = ValueNotifier(const Locale('en'));
const savedLocalePreferenceKey = 'locale';

Future<void> loadSavedLocale() async {
  final prefs = await SharedPreferences.getInstance();
  final code = prefs.getString(savedLocalePreferenceKey) ?? 'en';
  localeNotifier.value = Locale(code);
}

Future<void> saveLocale(String code) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(savedLocalePreferenceKey, code);
  localeNotifier.value = Locale(code);
}
