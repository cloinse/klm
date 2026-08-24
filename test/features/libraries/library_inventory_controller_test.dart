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
      expect(platform.removeBatchCalls, 1);
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

  test('previews deterministic, unmatched, and ambiguous repairs', () {
    final controller = LibraryInventoryController(_OrderPlatform());
    addTearDown(controller.dispose);
    const libraries = [
      KontaktLibrary(
        id: 'alpha',
        name: 'Alpha',
        regKey: 'Alpha Key',
        snpid: 'A01',
      ),
      KontaktLibrary(id: 'beta', name: 'Beta', snpid: 'B01'),
      KontaktLibrary(id: 'gamma', name: 'Gamma', regKey: 'Gamma'),
    ];
    final candidates = [
      _candidate('Alpha New Name', 'Alpha Key', 'OTHER'),
      _candidate('Beta One', 'Beta One', 'B01'),
      _candidate('Beta Two', 'Beta Two', 'B01'),
      _candidate('Unused', 'Unused', 'U01'),
    ];

    final preview = controller.previewRepairs(libraries, candidates);

    expect(preview.matches, hasLength(1));
    expect(preview.matches.single.library.id, 'alpha');
    expect(preview.ambiguousLibraries.map((library) => library.id), ['beta']);
    expect(preview.unmatchedLibraries.map((library) => library.id), ['gamma']);
    expect(preview.unmatchedCandidates, hasLength(3));
  });

  test('repairs multiple candidates through one platform batch call', () async {
    final platform = _OrderPlatform();
    final controller = LibraryInventoryController(platform);
    addTearDown(controller.dispose);
    await controller.refresh();

    await controller.upsertCandidates([
      _candidate('Alpha', 'Alpha', 'A01'),
      _candidate('Beta', 'Beta', 'B01'),
    ], repair: true);

    expect(platform.upsertBatchCalls, 1);
    expect(platform.upsertedNames, ['Alpha', 'Beta']);
  });

  test(
    'skips registered candidates while adding the rest of a batch',
    () async {
      final platform = _OrderPlatform();
      final controller = LibraryInventoryController(platform);
      addTearDown(controller.dispose);
      await controller.refresh();

      await controller.upsertCandidates([
        _candidate('Alpha', 'Alpha', 'A01'),
        _candidate('Delta', 'Delta', 'D01'),
      ], repair: false);

      expect(platform.upsertBatchCalls, 1);
      expect(platform.upsertedNames, ['Delta']);
      expect(
        controller.logs
            .where((log) => log.code == 'library_added')
            .map((log) => log.detail),
        ['Delta'],
      );
    },
  );

  test(
    'keeps the already registered error when no candidate can be added',
    () async {
      final platform = _OrderPlatform();
      final controller = LibraryInventoryController(platform);
      addTearDown(controller.dispose);
      await controller.refresh();

      await expectLater(
        controller.upsertCandidates([
          _candidate('Alpha', 'Alpha', 'A01'),
          _candidate('Beta', 'Beta', 'B01'),
        ], repair: false),
        throwsA(isA<LibraryAlreadyRegistered>()),
      );

      expect(platform.upsertBatchCalls, 0);
      expect(platform.upsertedNames, isEmpty);
    },
  );

  test(
    'keeps removals successful when classic order persistence fails',
    () async {
      final platform = _OrderPlatform()..throwOnSave = true;
      final controller = LibraryInventoryController(platform);
      addTearDown(controller.dispose);
      await controller.refresh();

      await controller.removeLibraries([
        controller.snapshot!.libraries.singleWhere(
          (library) => library.id == 'alpha',
        ),
        controller.snapshot!.libraries.singleWhere(
          (library) => library.id == 'beta',
        ),
      ]);

      expect(platform.removeBatchCalls, 1);
      expect(controller.visibleLibraries.map((library) => library.id), [
        'gamma',
      ]);
      expect(controller.consumeClassicOrderWarning(), isA<StateError>());
      expect(controller.consumeClassicOrderWarning(), isNull);
    },
  );
}

KontaktLibraryCandidate _candidate(String name, String regKey, String snpid) {
  return KontaktLibraryCandidate(
    contentPath: '/content/$name',
    metadataPath: '/content/$name.nicnt',
    metadata: ProductMetadata(name: name, regKey: regKey, snpid: snpid),
    productHintsXml: '<ProductHints />',
  );
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
  final List<String> upsertedNames = <String>[];
  int removeBatchCalls = 0;
  int upsertBatchCalls = 0;
  bool throwOnSave = false;

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
    if (throwOnSave) throw StateError('unsafe or duplicate values');
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
  Future<List<KontaktMutationResult>> removeLibraries(
    List<KontaktLibrary> libraries,
  ) async {
    removeBatchCalls++;
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
}
