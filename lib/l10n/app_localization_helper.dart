import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../locale.dart';
import 'app_localizations.dart';

AppLocalizations currentAppLocalizations() {
  return lookupAppLocalizations(localeNotifier.value);
}

Future<AppLocalizations> loadStoredAppLocalizations() async {
  final prefs = await SharedPreferences.getInstance();
  final code = prefs.getString(savedLocalePreferenceKey) ?? localeNotifier.value.languageCode;
  return lookupAppLocalizations(Locale(code));
}