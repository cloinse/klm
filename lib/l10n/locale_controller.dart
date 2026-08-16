import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage {
  english(Locale('en')),
  spanish(Locale('es')),
  portugueseBrazil(Locale('pt', 'BR')),
  chineseSimplified(Locale('zh'));

  const AppLanguage(this.locale);

  final Locale locale;

  static AppLanguage fromTag(String? tag) {
    return switch (tag) {
      'es' => AppLanguage.spanish,
      'pt_BR' => AppLanguage.portugueseBrazil,
      'zh' => AppLanguage.chineseSimplified,
      _ => AppLanguage.english,
    };
  }

  String get tag => switch (this) {
    AppLanguage.english => 'en',
    AppLanguage.spanish => 'es',
    AppLanguage.portugueseBrazil => 'pt_BR',
    AppLanguage.chineseSimplified => 'zh',
  };

  String get nativeName => switch (this) {
    AppLanguage.english => 'English',
    AppLanguage.spanish => 'Español',
    AppLanguage.portugueseBrazil => 'Português (Brasil)',
    AppLanguage.chineseSimplified => '简体中文',
  };
}

class LocaleController extends ChangeNotifier {
  LocaleController() : _language = AppLanguage.english, _preferences = null;

  LocaleController._(this._language, this._preferences);

  static const _preferenceKey = 'interface_language';

  final SharedPreferences? _preferences;
  AppLanguage _language;

  static Future<LocaleController> load() async {
    final preferences = await SharedPreferences.getInstance();
    return LocaleController._(
      AppLanguage.fromTag(preferences.getString(_preferenceKey)),
      preferences,
    );
  }

  AppLanguage get language => _language;
  Locale get locale => _language.locale;

  Future<void> setLanguage(AppLanguage language) async {
    if (_language == language) return;
    _language = language;
    notifyListeners();
    await _preferences?.setString(_preferenceKey, language.tag);
  }
}
