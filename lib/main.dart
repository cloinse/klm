import 'package:flutter/material.dart';
import 'package:kontakt_library_manager/app/kontakt_library_manager_app.dart';
import 'package:kontakt_library_manager/l10n/locale_controller.dart';
import 'package:kontakt_library_manager/platform/platform_adapter_factory.dart';
import 'package:kontakt_library_manager/theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final localeController = await LocaleController.load();
  final themeController = await ThemeController.load();
  runApp(
    KontaktLibraryManagerApp(
      platform: createKontaktPlatform(),
      localeController: localeController,
      themeController: themeController,
    ),
  );
}
