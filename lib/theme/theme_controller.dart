import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemePreference {
  system(ThemeMode.system),
  light(ThemeMode.light),
  dark(ThemeMode.dark);

  const AppThemePreference(this.themeMode);

  final ThemeMode themeMode;

  static AppThemePreference fromName(String? name) => switch (name) {
    'light' => AppThemePreference.light,
    'dark' => AppThemePreference.dark,
    _ => AppThemePreference.system,
  };
}

class ThemeController extends ChangeNotifier {
  ThemeController()
    : _preference = AppThemePreference.system,
      _preferences = null;

  ThemeController._(this._preference, this._preferences);

  static const _preferenceKey = 'interface_theme';

  final SharedPreferences? _preferences;
  AppThemePreference _preference;

  static Future<ThemeController> load() async {
    final preferences = await SharedPreferences.getInstance();
    return ThemeController._(
      AppThemePreference.fromName(preferences.getString(_preferenceKey)),
      preferences,
    );
  }

  AppThemePreference get preference => _preference;
  ThemeMode get themeMode => _preference.themeMode;

  Future<void> setPreference(AppThemePreference preference) async {
    if (_preference == preference) return;
    _preference = preference;
    notifyListeners();
    await _preferences?.setString(_preferenceKey, preference.name);
  }
}
