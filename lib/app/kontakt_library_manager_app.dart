import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:kontakt_library_manager/features/libraries/library_dashboard.dart';
import 'package:kontakt_library_manager/features/libraries/library_inventory_controller.dart';
import 'package:kontakt_library_manager/l10n/app_localizations.dart';
import 'package:kontakt_library_manager/l10n/locale_controller.dart';
import 'package:kontakt_library_manager/platform/kontakt_platform.dart';
import 'package:kontakt_library_manager/theme/app_theme.dart';
import 'package:kontakt_library_manager/theme/theme_controller.dart';

class KontaktLibraryManagerApp extends StatefulWidget {
  const KontaktLibraryManagerApp({
    super.key,
    required this.platform,
    this.localeController,
    this.themeController,
  });

  final KontaktPlatform platform;
  final LocaleController? localeController;
  final ThemeController? themeController;

  @override
  State<KontaktLibraryManagerApp> createState() =>
      _KontaktLibraryManagerAppState();
}

class _KontaktLibraryManagerAppState extends State<KontaktLibraryManagerApp> {
  late final LibraryInventoryController _controller;
  late final LocaleController _localeController;
  late final ThemeController _themeController;
  late final bool _ownsLocaleController;
  late final bool _ownsThemeController;

  @override
  void initState() {
    super.initState();
    _ownsLocaleController = widget.localeController == null;
    _ownsThemeController = widget.themeController == null;
    _localeController = widget.localeController ?? LocaleController();
    _themeController = widget.themeController ?? ThemeController();
    _controller = LibraryInventoryController(widget.platform)..refresh();
  }

  @override
  void dispose() {
    _controller.dispose();
    if (_ownsLocaleController) _localeController.dispose();
    if (_ownsThemeController) _themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_localeController, _themeController]),
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        onGenerateTitle: (context) => context.l10n.appTitle,
        locale: _localeController.locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: buildKlmTheme(Brightness.light),
        darkTheme: buildKlmTheme(Brightness.dark),
        themeMode: _themeController.themeMode,
        home: LibraryDashboard(
          controller: _controller,
          localeController: _localeController,
          themeController: _themeController,
        ),
      ),
    );
  }
}
