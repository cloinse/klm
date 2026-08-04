import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kontakt_library_manager/app/kontakt_library_manager_app.dart';
import 'package:kontakt_library_manager/core/models/kontakt_library.dart';
import 'package:kontakt_library_manager/core/models/kontakt_mutation.dart';
import 'package:kontakt_library_manager/l10n/locale_controller.dart';
import 'package:kontakt_library_manager/platform/kontakt_platform.dart';
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

    expect(find.text('Local Kontakt Libraries'), findsOneWidget);
    expect(find.text('Analog Dreams'), findsOneWidget);
    expect(find.text('ABC'), findsOneWidget);
    expect(find.text('SNPID ABC'), findsNothing);
    expect(find.byIcon(Icons.tag_rounded), findsNothing);
    expect(find.byTooltip('SNPID: ABC'), findsOneWidget);
    expect(find.text('K6'), findsNothing);
    expect(find.text('K7/8'), findsNothing);
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
    await tester.tap(find.text('Spanish').last);
    await tester.pumpAndSettle();

    expect(find.text('Ajustes'), findsNWidgets(2));
    expect(find.text('Idioma de la interfaz'), findsOneWidget);
    expect(localeController.language, AppLanguage.spanish);

    await tester.tap(find.text('Español'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Portugués (Brasil)').last);
    await tester.pumpAndSettle();

    expect(find.text('Configurações'), findsNWidgets(2));
    expect(find.text('Idioma da interface'), findsOneWidget);
    expect(localeController.language, AppLanguage.portugueseBrazil);
  });

  testWidgets('Settings only shows its title and changes the app theme', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final themeController = ThemeController();
    addTearDown(themeController.dispose);

    await tester.pumpWidget(
      KontaktLibraryManagerApp(
        platform: _FakePlatform(),
        themeController: themeController,
      ),
    );
    await tester.pumpAndSettle();

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

  final List<KontaktLibrary> libraries;
  List<KontaktLibrary>? savedOrder;

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
  Future<KontaktMutationResult> removeLibrary(KontaktLibrary library) =>
      throw UnimplementedError();

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
