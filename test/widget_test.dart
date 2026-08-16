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
    expect(find.text('Reload'), findsOneWidget);
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
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Español').last);
    await tester.pumpAndSettle();

    expect(find.text('Ajustes'), findsNWidgets(2));
    expect(find.text('Idioma de la interfaz'), findsOneWidget);
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
    expect(const AppLocalizations(Locale('pt', 'BR')).refresh, 'Recarregar');
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
    await tester.tap(find.text('Check for updates'));
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

    expect(find.text('KLM v1.0.0 - Juan Ayala'), findsOneWidget);

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

    await tester.tap(find.text('Check for updates'));
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
    expect(find.text('Save changes'), findsNothing);

    await tester.drag(
      find.byIcon(Icons.drag_indicator_rounded).first,
      const Offset(0, 180),
    );
    await tester.pumpAndSettle();

    expect(find.text('Save changes'), findsOneWidget);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(platform.savedOrder, isNotNull);
    expect(find.text('Save changes'), findsNothing);
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

    expect(find.text('Remove selected (2)'), findsOneWidget);
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
  });

  List<KontaktLibrary> libraries;
  List<KontaktLibrary>? savedOrder;
  final List<String> removedLibraryIds = <String>[];

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
  }) async => const [];

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
  Future<KontaktMutationResult> upsertLibrary(
    KontaktLibraryCandidate candidate,
  ) => throw UnimplementedError();

  @override
  Future<InventorySnapshot> scanLibraries() async => InventorySnapshot(
    libraries: libraries,
    diagnostics: const [],
    scannedAt: DateTime(2026),
  );
}
