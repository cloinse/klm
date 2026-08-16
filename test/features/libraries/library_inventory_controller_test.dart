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
      [1, 2, 3],
    );

    final reopenedController = LibraryInventoryController(platform);
    addTearDown(reopenedController.dispose);
    await reopenedController.refresh();
    expect(reopenedController.visibleLibraries.map((library) => library.name), [
      'Gamma',
      'Alpha',
      'Beta',
    ]);
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

  test(
    'refresh restores a re-added library to its registered position',
    () async {
      final platform = _OrderPlatform();
      final controller = LibraryInventoryController(platform);
      addTearDown(controller.dispose);

      await controller.refresh();
      platform.libraries = const [
        KontaktLibrary(id: 'beta', name: 'Beta', userListIndex: 2),
        KontaktLibrary(id: 'gamma', name: 'Gamma', userListIndex: 3),
      ];
      await controller.refresh();

      platform.libraries = const [
        KontaktLibrary(id: 'alpha', name: 'Alpha', userListIndex: 1),
        KontaktLibrary(id: 'beta', name: 'Beta', userListIndex: 2),
        KontaktLibrary(id: 'gamma', name: 'Gamma', userListIndex: 3),
      ];
      await controller.refresh();

      expect(controller.visibleLibraries.map((library) => library.name), [
        'Alpha',
        'Beta',
        'Gamma',
      ]);
      expect(controller.hasUnsavedCustomOrder, isFalse);
    },
  );

  test('removing a library compacts and saves the classic order', () async {
    final platform = _OrderPlatform()
      ..libraries = const [
        KontaktLibrary(id: 'alpha', name: 'Alpha', userListIndex: 1),
        KontaktLibrary(id: 'beta', name: 'Beta', userListIndex: 2),
        KontaktLibrary(id: 'gamma', name: 'Gamma', userListIndex: 3),
        KontaktLibrary(id: 'delta', name: 'Delta', userListIndex: 4),
      ];
    final controller = LibraryInventoryController(platform);
    addTearDown(controller.dispose);

    await controller.refresh();
    await controller.removeLibrary(
      controller.snapshot!.libraries.singleWhere(
        (library) => library.id == 'beta',
      ),
    );

    expect(platform.removedLibraryId, 'beta');
    expect(platform.savedOrder?.map((library) => library.name), [
      'Alpha',
      'Gamma',
      'Delta',
    ]);
    expect(platform.libraries.map((library) => library.userListIndex), [
      1,
      2,
      3,
    ]);
    expect(controller.hasUnsavedCustomOrder, isFalse);
  });

  test(
    'selects and removes multiple libraries while preserving order',
    () async {
      final platform = _OrderPlatform()
        ..libraries = const [
          KontaktLibrary(id: 'alpha', name: 'Alpha', userListIndex: 1),
          KontaktLibrary(id: 'beta', name: 'Beta', userListIndex: 2),
          KontaktLibrary(id: 'gamma', name: 'Gamma', userListIndex: 3),
          KontaktLibrary(id: 'delta', name: 'Delta', userListIndex: 4),
        ];
      final controller = LibraryInventoryController(platform);
      addTearDown(controller.dispose);

      await controller.refresh();
      final selected = controller.snapshot!.libraries
          .where((library) => library.id == 'beta' || library.id == 'gamma')
          .toList();
      for (final library in selected) {
        controller.setLibrarySelected(library.id, true);
      }

      expect(controller.selectedLibraryCount, 2);
      expect(controller.selectedLibraries.map((library) => library.id), [
        'beta',
        'gamma',
      ]);

      await controller.removeLibraries(selected);

      expect(platform.removedLibraryIds, ['beta', 'gamma']);
      expect(platform.savedOrder?.map((library) => library.name), [
        'Alpha',
        'Delta',
      ]);
      expect(controller.selectedLibraryCount, 0);
      expect(controller.visibleLibraries.map((library) => library.name), [
        'Alpha',
        'Delta',
      ]);
    },
  );

  test('changing a filter clears hidden library selections', () async {
    final controller = LibraryInventoryController(_OrderPlatform());
    addTearDown(controller.dispose);
    await controller.refresh();

    controller.setLibrarySelected('alpha', true);
    expect(controller.selectedLibraryCount, 1);

    controller.setFilter(LibraryFilter.healthy);

    expect(controller.selectedLibraryCount, 0);
  });
}

class _OrderPlatform implements KontaktPlatform {
  List<KontaktLibrary> libraries = const [
    KontaktLibrary(id: 'alpha', name: 'Alpha', userListIndex: 2),
    KontaktLibrary(id: 'beta', name: 'Beta', userListIndex: 0),
    KontaktLibrary(id: 'gamma', name: 'Gamma', userListIndex: 1),
  ];
  List<KontaktLibrary>? savedOrder;
  String? removedLibraryId;
  final List<String> removedLibraryIds = <String>[];

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
    this.libraries = [
      for (var index = 0; index < libraries.length; index++)
        libraries[index].copyWith(userListIndex: index + 1),
    ];
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
  Future<KontaktMutationResult> removeLibrary(KontaktLibrary library) async {
    removedLibraryId = library.id;
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
}
