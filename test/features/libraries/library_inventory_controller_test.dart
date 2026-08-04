import 'package:flutter_test/flutter_test.dart';
import 'package:kontakt_library_manager/core/models/kontakt_library.dart';
import 'package:kontakt_library_manager/core/models/kontakt_mutation.dart';
import 'package:kontakt_library_manager/features/libraries/library_inventory_controller.dart';
import 'package:kontakt_library_manager/platform/kontakt_platform.dart';

void main() {
  test('loads, reorders, and saves the classic Kontakt order', () async {
    final platform = _OrderPlatform();
    final controller = LibraryInventoryController(platform);
    addTearDown(controller.dispose);

    await controller.refresh();
    expect(controller.visibleLibraries.map((library) => library.name), [
      'Beta',
      'Gamma',
      'Alpha',
    ]);
    expect(controller.hasUnsavedCustomOrder, isFalse);

    controller.reorderLibrary(0, 2);
    expect(controller.visibleLibraries.map((library) => library.name), [
      'Gamma',
      'Alpha',
      'Beta',
    ]);
    expect(controller.hasUnsavedCustomOrder, isTrue);

    await controller.refresh();
    expect(controller.visibleLibraries.map((library) => library.name), [
      'Gamma',
      'Alpha',
      'Beta',
    ]);
    expect(controller.hasUnsavedCustomOrder, isTrue);

    await controller.saveCustomOrder();
    expect(platform.savedOrder?.map((library) => library.name), [
      'Gamma',
      'Alpha',
      'Beta',
    ]);
    expect(controller.hasUnsavedCustomOrder, isFalse);
    expect(
      controller.snapshot!.libraries.map((library) => library.userListIndex),
      [0, 1, 2],
    );
  });

  test('reordering is disabled while filtering the inventory', () async {
    final controller = LibraryInventoryController(_OrderPlatform());
    addTearDown(controller.dispose);
    await controller.refresh();

    controller.setQuery('Alpha');
    expect(controller.canReorderVisibleLibraries, isFalse);
    controller.reorderLibrary(0, 1);
    expect(controller.hasUnsavedCustomOrder, isFalse);
  });

  test('refresh preserves the visible session order', () async {
    final platform = _OrderPlatform();
    final controller = LibraryInventoryController(platform);
    addTearDown(controller.dispose);
    await controller.refresh();

    platform.libraries = const [
      KontaktLibrary(id: 'alpha', name: 'Alpha', userListIndex: 0),
      KontaktLibrary(id: 'beta', name: 'Beta', userListIndex: 2),
      KontaktLibrary(id: 'gamma', name: 'Gamma', userListIndex: 1),
    ];
    await controller.refresh();

    expect(controller.visibleLibraries.map((library) => library.name), [
      'Beta',
      'Gamma',
      'Alpha',
    ]);
    expect(controller.hasUnsavedCustomOrder, isFalse);
  });
}

class _OrderPlatform implements KontaktPlatform {
  List<KontaktLibrary> libraries = const [
    KontaktLibrary(id: 'alpha', name: 'Alpha', userListIndex: 2),
    KontaktLibrary(id: 'beta', name: 'Beta', userListIndex: 0),
    KontaktLibrary(id: 'gamma', name: 'Gamma', userListIndex: 1),
  ];
  List<KontaktLibrary>? savedOrder;

  @override
  PlatformCapabilities get capabilities => const PlatformCapabilities(
    platformName: 'macOS',
    canReadInventory: true,
    privilegedMutationsAvailable: true,
    registryLayoutVerified: true,
    canManageClassicOrder: true,
  );

  @override
  Future<InventorySnapshot> scanLibraries() async => InventorySnapshot(
    libraries: libraries,
    diagnostics: const [],
    scannedAt: DateTime(2026),
  );

  @override
  Future<void> saveClassicLibraryOrder(List<KontaktLibrary> libraries) async {
    savedOrder = List<KontaktLibrary>.of(libraries);
  }

  @override
  Future<void> revealInFileManager(String path) async {}

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
}
