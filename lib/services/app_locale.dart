import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefKey = 'app_language_code';

final ValueNotifier<Locale> appLocaleNotifier = ValueNotifier(const Locale('en'));

String normalizeLanguageCode(String? code) {
  if (code == null || code.isEmpty) return 'en';
  final c = code.toLowerCase().trim();
  if (c.startsWith('ar')) return 'ar';
  return 'en';
}

Future<void> loadAppLocaleFromPrefs() async {
  final p = await SharedPreferences.getInstance();
  final code = normalizeLanguageCode(p.getString(_prefKey));
  appLocaleNotifier.value = Locale(code);
}

Future<void> setAppLanguageCode(String code) async {
  final normalized = normalizeLanguageCode(code);
  final p = await SharedPreferences.getInstance();
  await p.setString(_prefKey, normalized);
  appLocaleNotifier.value = Locale(normalized);
}

/// If the user has never chosen a language on this device, follow the server value.
Future<void> initAppLanguageFromServerIfNeeded(String? languageFromServer) async {
  final p = await SharedPreferences.getInstance();
  if (p.containsKey(_prefKey)) return;
  await setAppLanguageCode(languageFromServer ?? 'en');
}
