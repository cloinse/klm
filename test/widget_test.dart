import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kontakt_library_manager/app/kontakt_library_manager_app.dart';
import 'package:kontakt_library_manager/core/models/kontakt_library.dart';
import 'package:kontakt_library_manager/core/models/kontakt_mutation.dart';
import 'package:kontakt_library_manager/l10n/app_localizations.dart';
import 'package:kontakt_library_manager/l10n/locale_controller.dart';
import 'package:kontakt_library_manager/platform/app_update_platform.dart';
import 'package:kontakt_library_manager/platform/kontakt_platform.dart';
import 'package:kontakt_library_manager/theme/app_theme.dart';
import 'package:kontakt_library_manager/theme/theme_controller.dart';

void main() {
  testWidgets('uses English by default and shows the inventory', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      KontaktLibraryManagerApp(platform: _FakePlatform()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Installed Libraries'), findsOneWidget);
    expect(find.text('Analog Dreams'), findsOneWidget);
    expect(find.text('ABC'), findsOneWidget);
    expect(find.text('SNPID ABC'), findsNothing);
    expect(find.byIcon(Icons.tag_rounded), findsNothing);
    expect(find.byTooltip('SNPID: ABC'), findsOneWidget);
    expect(find.text('K6'), findsNothing);
    expect(find.text('K7/8'), findsNothing);
    expect(find.text('Reload'), findsNothing);
    expect(find.byTooltip('Reload'), findsOneWidget);
    expect(
      tester.widget(find.byKey(const ValueKey('reload-libraries-button'))),
      isA<OutlinedButton>(),
    );
  });

  testWidgets('changes the interface language from Settings', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final localeController = LocaleController();
    addTearDown(localeController.dispose);

    await tester.pumpWidget(
      KontaktLibraryManagerApp(
        platform: _FakePlatform(),
        localeController: localeController,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Check now'), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Español').last);
    await tester.pumpAndSettle();

    expect(find.text('Ajustes'), findsNWidgets(2));
    expect(find.text('Idioma de la interfaz'), findsOneWidget);
    expect(find.text('Comprobar ahora'), findsOneWidget);
    expect(const AppLocalizations(Locale('es')).refresh, 'Recargar');
    expect(localeController.language, AppLanguage.spanish);

    await tester.tap(find.text('Español'));
    await tester.pumpAndSettle();
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Inglés'), findsNothing);
    await tester.tap(find.text('Português (Brasil)').last);
    await tester.pumpAndSettle();

    expect(find.text('Configurações'), findsNWidgets(2));
    expect(find.text('Idioma da interface'), findsOneWidget);
    expect(find.text('Verificar agora'), findsOneWidget);
    expect(const AppLocalizations(Locale('pt', 'BR')).refresh, 'Recarregar');
    expect(
      const AppLocalizations(Locale('zh', 'CN')).tr('checkForUpdates'),
      '立即检查',
    );
    expect(localeController.language, AppLanguage.portugueseBrazil);
  });

  testWidgets('shows a localized update notice after the launch probe', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final localeController = LocaleController();
    final updatePlatform = _FakeAppUpdatePlatform(
      availableUpdate: const AvailableAppUpdate(
        version: '1.1.0',
        build: '2',
        releaseNotes:
            '- Muestra los cambios antes de instalar.\n- Mejoras de estabilidad.',
      ),
    );
    addTearDown(localeController.dispose);
    await localeController.setLanguage(AppLanguage.spanish);

    await tester.pumpWidget(
      KontaktLibraryManagerApp(
        platform: _FakePlatform(),
        localeController: localeController,
        updatePlatform: updatePlatform,
      ),
    );
    await tester.pumpAndSettle();

    expect(updatePlatform.probeCount, 1);
    expect(
      find.byKey(const ValueKey('update-available-banner')),
      findsOneWidget,
    );
    expect(find.text('Actualización disponible'), findsOneWidget);
    expect(find.text('Instalar actualización'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('download-install-update')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('update-available-dialog')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Kontakt Library Manager 1.1.0 ya está disponible '
        '(tienes la versión 1.0.0).',
      ),
      findsOneWidget,
    );
    expect(find.text('Cambios de esta versión'), findsOneWidget);
    expect(
      find.text(
        '- Muestra los cambios antes de instalar.\n- Mejoras de estabilidad.',
      ),
      findsOneWidget,
    );
    expect(find.text('Recordármelo más tarde'), findsNothing);
    expect(find.text('Omitir esta versión'), findsNothing);
    expect(
      tester
          .widget<AlertDialog>(
            find.byKey(const ValueKey('update-available-dialog')),
          )
          .actions,
      hasLength(1),
    );
    expect(updatePlatform.installCount, 0);

    await tester.tap(find.byKey(const ValueKey('confirm-install-update')));
    await tester.pumpAndSettle();

    expect(updatePlatform.installCount, 1);
    expect(
      find.byKey(const ValueKey('update-available-banner')),
      findsOneWidget,
    );
  });

  testWidgets('Settings shows the same version dialog before installing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final updatePlatform = _FakeAppUpdatePlatform(
      availableUpdate: const AvailableAppUpdate(version: '1.1.0', build: '2'),
    );

    await tester.pumpWidget(
      KontaktLibraryManagerApp(
        platform: _FakePlatform(),
        updatePlatform: updatePlatform,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey('update-available-dialog')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Kontakt Library Manager 1.1.0 is now available '
        '(you have 1.0.0).',
      ),
      findsOneWidget,
    );
    expect(updatePlatform.installCount, 0);
    expect(
      tester
          .widget<AlertDialog>(
            find.byKey(const ValueKey('update-available-dialog')),
          )
          .actions,
      hasLength(1),
    );

    await tester.tap(find.byKey(const ValueKey('confirm-install-update')));
    await tester.pumpAndSettle();

    expect(updatePlatform.installCount, 1);
  });

  testWidgets('Settings only shows its title and changes the app theme', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final themeController = ThemeController();
    final updatePlatform = _FakeAppUpdatePlatform();
    addTearDown(themeController.dispose);

    await tester.pumpWidget(
      KontaktLibraryManagerApp(
        platform: _FakePlatform(),
        themeController: themeController,
        updatePlatform: updatePlatform,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('KLM v1.0.0 cloin.se'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsNWidgets(2));
    expect(find.text('CONFIGURATION'), findsNothing);
    expect(
      find.text('Application language, adapter, and security.'),
      findsNothing,
    );
    expect(find.text('macOS adapter'), findsNothing);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Application updates'), findsOneWidget);
    expect(find.textContaining('Version 1.0.0'), findsOneWidget);

    await tester.tap(find.text('Check now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(updatePlatform.probeCount, 2);
    expect(updatePlatform.installCount, 0);
    expect(find.byKey(const ValueKey('up-to-date-dialog')), findsOneWidget);
    expect(find.text("You're up to date!"), findsOneWidget);
    expect(
      find.text(
        'Kontakt Library Manager 1.0.0 is currently the newest version available.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light').last);
    await tester.pumpAndSettle();

    expect(themeController.preference, AppThemePreference.light);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark').last);
    await tester.pumpAndSettle();

    expect(themeController.preference, AppThemePreference.dark);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
  });

  testWidgets(
    'light theme clearly distinguishes the selected navigation item',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final themeController = ThemeController();
      addTearDown(themeController.dispose);
      await themeController.setPreference(AppThemePreference.light);

      await tester.pumpWidget(
        KontaktLibraryManagerApp(
          platform: _FakePlatform(),
          themeController: themeController,
        ),
      );
      await tester.pumpAndSettle();

      Material selectedMaterial(String key) => tester.widget<Material>(
        find
            .descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(Material),
            )
            .first,
      );

      expect(
        selectedMaterial('navigation-library').color,
        KlmColors.light.navigationSelectedBackground,
      );
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const ValueKey('navigation-library')),
                matching: find.text('Library'),
              ),
            )
            .style
            ?.color,
        KlmColors.light.navigationSelectedForeground,
      );

      final addLibraryButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('add-library-button')),
      );
      expect(
        addLibraryButton.style?.backgroundColor?.resolve({}),
        KlmColors.light.accentButtonBackground,
      );
      expect(
        addLibraryButton.style?.foregroundColor?.resolve({}),
        KlmColors.light.accentButtonForeground,
      );
      expect(
        addLibraryButton.style?.side?.resolve({})?.color,
        KlmColors.light.accentButtonBorder,
      );

      await tester.tap(find.byKey(const ValueKey('navigation-settings')));
      await tester.pumpAndSettle();

      expect(
        selectedMaterial('navigation-settings').color,
        KlmColors.light.navigationSelectedBackground,
      );
      expect(selectedMaterial('navigation-library').color, Colors.transparent);
    },
  );

  testWidgets('dragging a library reveals the save changes button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final platform = _FakePlatform(
      libraries: const [
        KontaktLibrary(id: 'alpha', name: 'Alpha', userListIndex: 0),
        KontaktLibrary(id: 'beta', name: 'Beta', userListIndex: 1),
        KontaktLibrary(id: 'gamma', name: 'Gamma', userListIndex: 2),
      ],
    );

    await tester.pumpWidget(KontaktLibraryManagerApp(platform: platform));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.drag_indicator_rounded), findsNWidgets(3));
    expect(find.text('Save'), findsNothing);

    await tester.drag(
      find.byIcon(Icons.drag_indicator_rounded).first,
      const Offset(0, 180),
    );
    await tester.pumpAndSettle();

    expect(find.text('Save'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(platform.savedOrder, isNotNull);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('library rows keep the same height when filtering', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final platform = _FakePlatform(
      libraries: const [
        KontaktLibrary(id: 'alpha', name: 'Alpha', userListIndex: 0),
        KontaktLibrary(id: 'beta', name: 'Beta', userListIndex: 1),
      ],
    );

    await tester.pumpWidget(KontaktLibraryManagerApp(platform: platform));
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('library-card-alpha'));
    final unfilteredHeight = tester.getSize(card).height;
    expect(
      find.descendant(of: card, matching: find.text('Healthy')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Healthy').last);
    await tester.pumpAndSettle();
    final filteredHeight = tester.getSize(card).height;

    expect(filteredHeight, unfilteredHeight);
  });

  testWidgets('status cards filter the inventory', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final platform = _FakePlatform(
      libraries: const [
        KontaktLibrary(
          id: 'healthy',
          name: 'Healthy Library',
          userListIndex: 0,
        ),
        KontaktLibrary(
          id: 'attention',
          name: 'Attention Library',
          userListIndex: 1,
          issues: [
            LibraryIssue(
              code: 'duplicate_registration',
              message: 'Duplicate registration',
              severity: IssueSeverity.warning,
            ),
          ],
        ),
        KontaktLibrary(
          id: 'offline',
          name: 'Offline Library',
          userListIndex: 2,
          issues: [
            LibraryIssue(
              code: 'content_offline',
              message: 'Content is offline',
              severity: IssueSeverity.error,
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(KontaktLibraryManagerApp(platform: platform));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('stat-card-healthy')));
    await tester.pumpAndSettle();
    expect(find.text('Healthy Library'), findsOneWidget);
    expect(find.text('Attention Library'), findsNothing);
    expect(find.text('Offline Library'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('stat-card-attention')));
    await tester.pumpAndSettle();
    expect(find.text('Healthy Library'), findsNothing);
    expect(find.text('Attention Library'), findsOneWidget);
    expect(find.text('Offline Library'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('stat-card-offline')));
    await tester.pumpAndSettle();
    expect(find.text('Attention Library'), findsNothing);
    expect(find.text('Offline Library'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('stat-card-all')));
    await tester.pumpAndSettle();
    expect(find.text('Healthy Library'), findsOneWidget);
    expect(find.text('Attention Library'), findsOneWidget);
    expect(find.text('Offline Library'), findsOneWidget);
  });

  testWidgets('removes multiple selected libraries from the inventory', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final platform = _FakePlatform(
      libraries: [
        const KontaktLibrary(id: 'alpha', name: 'Alpha', userListIndex: 0),
        const KontaktLibrary(id: 'beta', name: 'Beta', userListIndex: 1),
      ],
    );

    await tester.pumpWidget(KontaktLibraryManagerApp(platform: platform));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('select-library-alpha')));
    await tester.tap(find.byKey(const ValueKey('select-library-beta')));
    await tester.pumpAndSettle();

    expect(find.text('Remove'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('repair-selected-libraries')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('remove-selected-libraries')));
    await tester.pumpAndSettle();
    expect(find.text('Remove 2 library records?'), findsOneWidget);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(platform.removedLibraryIds, ['alpha', 'beta']);
    expect(find.text('Alpha'), findsNothing);
    expect(find.text('Beta'), findsNothing);
    expect(
      find.byKey(const ValueKey('remove-selected-libraries')),
      findsNothing,
    );
  });

  testWidgets('previews and repairs multiple selected libraries in one batch', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final themeController = ThemeController();
      await themeController.setPreference(AppThemePreference.dark);
      addTearDown(themeController.dispose);
      final platform = _FakePlatform(
        libraries: [
          const KontaktLibrary(
            id: 'alpha',
            name: 'Alpha',
            regKey: 'Alpha',
            snpid: 'A01',
            issues: [
              LibraryIssue(
                code: 'missing_registration',
                message: 'Missing registration',
                severity: IssueSeverity.warning,
              ),
            ],
          ),
          const KontaktLibrary(
            id: 'beta',
            name: 'Beta',
            regKey: 'Beta',
            snpid: 'B01',
            issues: [
              LibraryIssue(
                code: 'content_offline',
                message: 'Content is offline',
                severity: IssueSeverity.error,
              ),
            ],
          ),
          const KontaktLibrary(
            id: 'gamma',
            name: 'Gamma',
            regKey: 'Gamma',
            snpid: 'G01',
          ),
        ],
        candidates: [
          _widgetCandidate('Alpha', 'A01'),
          _widgetCandidate('Beta', 'B01'),
        ],
      );

      await tester.pumpWidget(
        KontaktLibraryManagerApp(
          platform: platform,
          themeController: themeController,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('select-library-alpha')));
      await tester.tap(find.byKey(const ValueKey('select-library-beta')));
      await tester.tap(find.byKey(const ValueKey('select-library-gamma')));
      await tester.pumpAndSettle();

      expect(find.text('Repair'), findsOneWidget);
      final repairCenter = tester.getCenter(
        find.byKey(const ValueKey('repair-selected-libraries')),
      );
      final reloadRect = tester.getRect(
        find.byKey(const ValueKey('reload-libraries-button')),
      );
      final repairRect = tester.getRect(
        find.byKey(const ValueKey('repair-selected-libraries')),
      );
      final removeRect = tester.getRect(
        find.byKey(const ValueKey('remove-selected-libraries')),
      );
      final addRect = tester.getRect(
        find.byKey(const ValueKey('add-library-button')),
      );
      final reloadCenter = tester.getCenter(
        find.byKey(const ValueKey('reload-libraries-button')),
      );
      final addCenter = tester.getCenter(
        find.byKey(const ValueKey('add-library-button')),
      );
      final addMenuCenter = tester.getCenter(
        find.byTooltip('Add multiple libraries'),
      );
      final reloadSize = tester.getSize(
        find.byKey(const ValueKey('reload-libraries-button')),
      );
      final repairSize = tester.getSize(
        find.byKey(const ValueKey('repair-selected-libraries')),
      );
      final removeSize = tester.getSize(
        find.byKey(const ValueKey('remove-selected-libraries')),
      );
      final addSize = tester.getSize(
        find.byKey(const ValueKey('add-library-button')),
      );
      final addMenuSize = tester.getSize(
        find.byKey(const ValueKey('add-multiple-libraries-button')),
      );
      final reloadButton = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('reload-libraries-button')),
      );
      final repairButton = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('repair-selected-libraries')),
      );
      final addMenuButton = tester.widget<TextButton>(
        find.byKey(const ValueKey('add-multiple-libraries-button')),
      );
      final reloadVisualSize = tester.getSize(
        find
            .descendant(
              of: find.byKey(const ValueKey('reload-libraries-button')),
              matching: find.byType(Material),
            )
            .first,
      );
      final repairVisualSize = tester.getSize(
        find
            .descendant(
              of: find.byKey(const ValueKey('repair-selected-libraries')),
              matching: find.byType(Material),
            )
            .first,
      );
      final removeVisualSize = tester.getSize(
        find
            .descendant(
              of: find.byKey(const ValueKey('remove-selected-libraries')),
              matching: find.byType(Material),
            )
            .first,
      );
      final addVisualSize = tester.getSize(
        find
            .descendant(
              of: find.byKey(const ValueKey('add-library-button')),
              matching: find.byType(Material),
            )
            .first,
      );
      final addMenuVisualSize = tester.getSize(
        find
            .descendant(
              of: find.byKey(const ValueKey('add-multiple-libraries-button')),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(repairCenter.dx, greaterThan(tester.view.physicalSize.width / 2));
      expect(reloadCenter.dx, lessThan(repairCenter.dx));
      expect(reloadCenter.dx, lessThan(addCenter.dx));
      expect((repairCenter.dy - addCenter.dy).abs(), lessThan(1));
      expect((repairCenter.dy - addMenuCenter.dy).abs(), lessThan(1));
      expect(reloadSize.height, repairSize.height);
      expect(reloadSize.height, removeSize.height);
      expect(reloadSize.height, addSize.height);
      expect(addMenuSize.height, addSize.height);
      expect(
        reloadButton.style?.minimumSize?.resolve(const <WidgetState>{}),
        const Size.square(40),
      );
      expect(reloadButton.style?.fixedSize, isNull);
      expect(
        reloadButton.style?.shape?.resolve(const <WidgetState>{}),
        isA<CircleBorder>(),
      );
      expect(
        reloadButton.style?.foregroundColor,
        repairButton.style?.foregroundColor,
      );
      expect(
        reloadButton.style?.backgroundColor,
        repairButton.style?.backgroundColor,
      );
      expect(reloadButton.style?.side, repairButton.style?.side);
      expect(addMenuButton.style?.side, isNull);
      expect(
        addMenuButton.style?.backgroundColor?.resolve(const <WidgetState>{}),
        Colors.transparent,
      );
      expect(
        addMenuButton.style?.backgroundColor?.resolve(const <WidgetState>{
          WidgetState.hovered,
        }),
        isNot(Colors.transparent),
      );
      expect(reloadVisualSize.height, repairVisualSize.height);
      expect(reloadVisualSize.height, removeVisualSize.height);
      expect(reloadVisualSize.height, addVisualSize.height);
      expect(addMenuVisualSize.height, addVisualSize.height);
      final addMenuRectBeforeHover = tester.getRect(
        find.byKey(const ValueKey('add-multiple-libraries-button')),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(addMenuRectBeforeHover.center);
      await tester.pump();
      expect(
        tester.getRect(
          find.byKey(const ValueKey('add-multiple-libraries-button')),
        ),
        addMenuRectBeforeHover,
      );
      expect(
        tester
            .getSize(
              find
                  .descendant(
                    of: find.byKey(
                      const ValueKey('add-multiple-libraries-button'),
                    ),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .height,
        addVisualSize.height,
      );
      await mouse.removePointer();
      await tester.pump();
      expect(repairRect.left - reloadRect.right, 10);
      expect(removeRect.left - repairRect.right, 10);
      expect(addRect.left - removeRect.right, 10);
      await tester.tap(find.byKey(const ValueKey('repair-selected-libraries')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('batch-repair-preview-dialog')),
        findsOneWidget,
      );
      expect(find.text('2 matched, 0 unmatched, 0 ambiguous.'), findsOneWidget);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(platform.upsertBatchCalls, 1);
      expect(platform.upsertedNames, ['Alpha', 'Beta']);
      expect(
        find.byKey(const ValueKey('repair-selected-libraries')),
        findsNothing,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('diagnostics exposes direct library actions', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final platform = _FakePlatform(
      libraries: const [
        KontaktLibrary(
          id: 'offline',
          name: 'Offline Library',
          contentPath: '/Library/Offline',
          issues: [
            LibraryIssue(
              code: 'content_offline',
              message: 'Content is offline',
              severity: IssueSeverity.error,
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(KontaktLibraryManagerApp(platform: platform));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diagnostics').first);
    await tester.pumpAndSettle();

    final actions = find.byIcon(Icons.more_horiz_rounded);
    expect(actions, findsOneWidget);
    await tester.tap(actions);
    await tester.pumpAndSettle();
    expect(find.text('Remove records'), findsOneWidget);
    await tester.tap(find.text('Remove records'));
    await tester.pumpAndSettle();
    expect(find.text('Remove library records?'), findsOneWidget);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(platform.removedLibraryIds, ['offline']);
    expect(find.text('Everything looks good'), findsOneWidget);
  });
}

KontaktLibraryCandidate _widgetCandidate(String name, String snpid) {
  return KontaktLibraryCandidate(
    contentPath: '/Library/$name',
    metadataPath: '/Library/$name/$name.nicnt',
    metadata: ProductMetadata(name: name, regKey: name, snpid: snpid),
    productHintsXml: '<ProductHints />',
  );
}

class _FakeAppUpdatePlatform implements AppUpdatePlatform {
  _FakeAppUpdatePlatform({this.availableUpdate});

  final AvailableAppUpdate? availableUpdate;
  int installCount = 0;
  int probeCount = 0;

  @override
  Future<AppUpdateInfo> getInfo() async =>
      const AppUpdateInfo(currentVersion: '1.0.0', configured: true);

  @override
  Future<AvailableAppUpdate?> probeForUpdates() async {
    probeCount += 1;
    return availableUpdate;
  }

  @override
  Future<void> installUpdate() async {
    installCount += 1;
  }
}

class _FakePlatform implements KontaktPlatform {
  _FakePlatform({
    this.libraries = const [
      KontaktLibrary(
        id: 'analog-dreams',
        name: 'Analog Dreams',
        regKey: 'Analog Dreams',
        snpid: 'aBc',
        contentPath: '/Library/Analog Dreams',
        sources: {
          RegistrationSource.serviceCenter,
          RegistrationSource.preferences,
          RegistrationSource.installedProducts,
        },
      ),
    ],
    this.candidates = const [],
  });

  List<KontaktLibrary> libraries;
  final List<KontaktLibraryCandidate> candidates;
  List<KontaktLibrary>? savedOrder;
  final List<String> removedLibraryIds = <String>[];
  final List<String> upsertedNames = <String>[];
  int upsertBatchCalls = 0;

  @override
  PlatformCapabilities get capabilities => const PlatformCapabilities(
    platformName: 'macOS',
    canReadInventory: true,
    privilegedMutationsAvailable: false,
    registryLayoutVerified: true,
    canManageClassicOrder: true,
  );

  @override
  Future<void> revealInFileManager(String path) async {}

  @override
  Future<void> saveClassicLibraryOrder(List<KontaktLibrary> libraries) async {
    savedOrder = List<KontaktLibrary>.of(libraries);
  }

  @override
  Future<List<KontaktLibraryCandidate>> chooseLibraryCandidates({
    required bool allowMultiple,
  }) async => candidates;

  @override
  Future<String?> chooseContentDirectory() async => null;

  @override
  Future<PrivilegedHelperStatus> enablePrivilegedHelper() async =>
      PrivilegedHelperStatus.enabled;

  @override
  Future<PrivilegedHelperStatus> privilegedHelperStatus() async =>
      PrivilegedHelperStatus.enabled;

  @override
  Future<KontaktMutationResult> relocateLibrary(
    KontaktLibrary library,
    String contentPath,
  ) => throw UnimplementedError();

  @override
  Future<KontaktMutationResult> removeLibrary(KontaktLibrary library) async {
    removedLibraryIds.add(library.id);
    libraries = libraries
        .where((candidate) => candidate.id != library.id)
        .toList(growable: false);
    return KontaktMutationResult(
      operation: KontaktMutationType.remove,
      libraryName: library.name,
      changedPaths: const [],
    );
  }

  @override
  Future<List<KontaktMutationResult>> removeLibraries(
    List<KontaktLibrary> libraries,
  ) async {
    final results = <KontaktMutationResult>[];
    for (final library in libraries) {
      results.add(await removeLibrary(library));
    }
    return results;
  }

  @override
  Future<KontaktMutationResult> upsertLibrary(
    KontaktLibraryCandidate candidate,
  ) async {
    upsertedNames.add(candidate.metadata.name);
    return KontaktMutationResult(
      operation: KontaktMutationType.upsert,
      libraryName: candidate.metadata.name,
      changedPaths: const [],
    );
  }

  @override
  Future<List<KontaktMutationResult>> upsertLibraries(
    List<KontaktLibraryCandidate> candidates,
  ) async {
    upsertBatchCalls++;
    final results = <KontaktMutationResult>[];
    for (final candidate in candidates) {
      results.add(await upsertLibrary(candidate));
    }
    return results;
  }

  @override
  Future<InventorySnapshot> scanLibraries() async => InventorySnapshot(
    libraries: libraries,
    diagnostics: const [],
    scannedAt: DateTime(2026),
  );
}
