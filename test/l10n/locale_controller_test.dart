import 'package:flutter_test/flutter_test.dart';
import 'package:kontakt_library_manager/l10n/locale_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('English is the default language', () async {
    SharedPreferences.setMockInitialValues({});

    final controller = await LocaleController.load();

    expect(controller.language, AppLanguage.english);
    expect(controller.locale.languageCode, 'en');
  });

  test('persists Brazilian Portuguese selection', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = await LocaleController.load();

    await controller.setLanguage(AppLanguage.portugueseBrazil);
    final restored = await LocaleController.load();

    expect(restored.language, AppLanguage.portugueseBrazil);
    expect(restored.locale.languageCode, 'pt');
    expect(restored.locale.countryCode, 'BR');
  });

  test('persists Simplified Chinese selection', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = await LocaleController.load();

    await controller.setLanguage(AppLanguage.chineseSimplified);
    final restored = await LocaleController.load();

    expect(restored.language, AppLanguage.chineseSimplified);
    expect(restored.locale.languageCode, 'zh');
    expect(restored.locale.countryCode, isNull);
  });
}
