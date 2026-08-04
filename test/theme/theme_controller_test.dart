import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kontakt_library_manager/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('uses the system theme by default', () async {
    SharedPreferences.setMockInitialValues({});

    final controller = await ThemeController.load();

    expect(controller.preference, AppThemePreference.system);
    expect(controller.themeMode, ThemeMode.system);
  });

  test('persists the selected theme', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = await ThemeController.load();

    await controller.setPreference(AppThemePreference.dark);
    final restored = await ThemeController.load();

    expect(restored.preference, AppThemePreference.dark);
    expect(restored.themeMode, ThemeMode.dark);
  });
}
