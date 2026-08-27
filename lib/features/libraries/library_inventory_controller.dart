import 'package:flutter/foundation.dart';
import 'package:kontakt_library_manager/core/models/kontakt_library.dart';
import 'package:kontakt_library_manager/core/models/kontakt_mutation.dart';
import 'package:kontakt_library_manager/platform/kontakt_platform.dart';

enum InventoryLoadState { initial, loading, ready, failure }

enum LibraryFilter { all, healthy, attention, offline }

enum LibrarySort { custom, name, health, path }

class OperationLog {
  const OperationLog({
    required this.timestamp,
    required this.code,
    required this.detail,
    required this.isError,
    this.count,
  });

  final DateTime timestamp;
  final String code;
  final String detail;
  final bool isError;
  final int? count;
}

class LibraryRepairMatch {
  const LibraryRepairMatch({required this.library, required this.candidate});

  final KontaktLibrary library;
  final KontaktLibraryCandidate candidate;
}

class LibraryRepairPreview {
  const LibraryRepairPreview({
    required this.matches,
    required this.unmatchedLibraries,
    required this.ambiguousLibraries,
    required this.unmatchedCandidates,
  });

  final List<LibraryRepairMatch> matches;
  final List<KontaktLibrary> unmatchedLibraries;
  final List<KontaktLibrary> ambiguousLibraries;
  final List<KontaktLibraryCandidate> unmatchedCandidates;
}

class LibraryInventoryController extends ChangeNotifier {
  LibraryInventoryController(this.platform) {
    if (!platform.capabilities.canManageClassicOrder) {
      sort = LibrarySort.name;
    }
  }

  final KontaktPlatform platform;

  InventoryLoadState state = InventoryLoadState.initial;
  InventorySnapshot? snapshot;
  Object? lastError;
  String query = '';
  LibraryFilter filter = LibraryFilter.all;
  LibrarySort sort = LibrarySort.custom;
  PrivilegedHelperStatus helperStatus = PrivilegedHelperStatus.unavailable;
  bool mutationInProgress = false;
  bool orderSaveInProgress = false;
  Object? _classicOrderWarning;
  bool _refreshQueued = false;
  bool _customOrderInitialized = false;
  final List<String> _customLibraryIds = <String>[];
  List<String> _savedCustomLibraryIds = const <String>[];
  final Set<String> _selectedLibraryIds = <String>{};
  final List<OperationLog> logs = <OperationLog>[];

  Future<void> refresh() async {
    if (state == InventoryLoadState.loading) {
      _refreshQueued = true;
      return;
    }
    state = InventoryLoadState.loading;
    lastError = null;
    notifyListeners();
    try {
      final inventory = await platform.scanLibraries();
      snapshot = inventory;
      final availableIds = inventory.libraries
          .map((library) => library.id)
          .toSet();
      _selectedLibraryIds.removeWhere((id) => !availableIds.contains(id));
      _synchronizeCustomOrder(inventory.libraries);
      await refreshHelperStatus(notify: false);
      state = InventoryLoadState.ready;
      _log('inventory_updated', '', count: snapshot!.libraries.length);
    } catch (error) {
      lastError = error;
      state = InventoryLoadState.failure;
      _log('inventory_error', error.toString(), isError: true);
    }
    if (_refreshQueued) {
      _refreshQueued = false;
      await refresh();
      return;
    }
    notifyListeners();
  }

  void setQuery(String value) {
    if (query == value) return;
    query = value;
    _selectedLibraryIds.clear();
    notifyListeners();
  }

  void setFilter(LibraryFilter value) {
    if (filter == value) return;
    filter = value;
    _selectedLibraryIds.clear();
    notifyListeners();
  }

  void setSort(LibrarySort value) {
    sort = value;
    notifyListeners();
  }

  Set<String> get selectedLibraryIds =>
      Set<String>.unmodifiable(_selectedLibraryIds);

  int get selectedLibraryCount => _selectedLibraryIds.length;

  bool isLibrarySelected(String libraryId) =>
      _selectedLibraryIds.contains(libraryId);

  List<KontaktLibrary> get selectedLibraries => [
    for (final library in snapshot?.libraries ?? const <KontaktLibrary>[])
      if (_selectedLibraryIds.contains(library.id)) library,
  ];

  List<KontaktLibrary> get selectedLibrariesNeedingRepair => [
    for (final library in selectedLibraries)
      if (library.health != LibraryHealth.healthy) library,
  ];

  bool get allVisibleLibrariesSelected =>
      visibleLibraries.isNotEmpty &&
      visibleLibraries.every((library) => isLibrarySelected(library.id));

  bool get someVisibleLibrariesSelected =>
      visibleLibraries.any((library) => isLibrarySelected(library.id));

  void setLibrarySelected(String libraryId, bool selected) {
    final changed = selected
        ? _selectedLibraryIds.add(libraryId)
        : _selectedLibraryIds.remove(libraryId);
    if (changed) notifyListeners();
  }

  void setVisibleLibrariesSelected(bool selected) {
    final visibleIds = visibleLibraries.map((library) => library.id);
    if (selected) {
      _selectedLibraryIds.addAll(visibleIds);
    } else {
      _selectedLibraryIds.removeAll(visibleIds);
    }
    notifyListeners();
  }

  void clearSelection() {
    if (_selectedLibraryIds.isEmpty) return;
    _selectedLibraryIds.clear();
    notifyListeners();
  }

  Object? consumeClassicOrderWarning() {
    final warning = _classicOrderWarning;
    _classicOrderWarning = null;
    return warning;
  }

  bool get hasUnsavedCustomOrder =>
      !listEquals(_customLibraryIds, _savedCustomLibraryIds);

  bool get canReorderVisibleLibraries =>
      platform.capabilities.canManageClassicOrder &&
      sort == LibrarySort.custom &&
      filter == LibraryFilter.all &&
      query.trim().isEmpty;

  void reorderLibrary(int oldIndex, int newIndex) {
    if (!canReorderVisibleLibraries ||
        oldIndex < 0 ||
        oldIndex >= _customLibraryIds.length) {
      return;
    }

    final selectedInOrder = _customLibraryIds
        .where(_selectedLibraryIds.contains)
        .toList(growable: false);
    final draggedLibraryId = _customLibraryIds[oldIndex];
    if (selectedInOrder.length > 1 &&
        selectedInOrder.contains(draggedLibraryId)) {
      _reorderSelectedLibraries(
        oldIndex: oldIndex,
        newIndex: newIndex,
        selectedInOrder: selectedInOrder,
      );
      return;
    }

    if (oldIndex == newIndex ||
        newIndex < 0 ||
        newIndex > _customLibraryIds.length - 1) {
      return;
    }
    final libraryId = _customLibraryIds.removeAt(oldIndex);
    _customLibraryIds.insert(newIndex, libraryId);
    notifyListeners();
  }

  /// Reorders an arbitrary group of libraries at an insertion point measured
  /// in the list that remains after the group is removed.
  void reorderLibrariesAt({
    required List<String> libraryIds,
    required int insertionIndex,
  }) {
    if (!canReorderVisibleLibraries || libraryIds.isEmpty) return;

    final movingIds = libraryIds.toSet();
    final moving = _customLibraryIds
        .where(movingIds.contains)
        .toList(growable: false);
    if (moving.isEmpty) return;

    final remaining = _customLibraryIds
        .where((id) => !movingIds.contains(id))
        .toList(growable: false);
    final targetIndex = insertionIndex.clamp(0, remaining.length).toInt();
    final reordered = <String>[
      ...remaining.take(targetIndex),
      ...moving,
      ...remaining.skip(targetIndex),
    ];
    if (listEquals(reordered, _customLibraryIds)) return;
    _customLibraryIds
      ..clear()
      ..addAll(reordered);
    notifyListeners();
  }

  void _reorderSelectedLibraries({
    required int oldIndex,
    required int newIndex,
    required List<String> selectedInOrder,
  }) {
    // ReorderableListView reports newIndex after removing only the dragged
    // row. Convert that insertion point to the list that remains after all
    // selected rows are removed, so dragging over another selected row does
    // not split the block or change its relative order.
    final afterDragged = List<String>.of(_customLibraryIds)..removeAt(oldIndex);
    final insertionPoint = newIndex.clamp(0, afterDragged.length).toInt();
    final targetIndex = afterDragged
        .take(insertionPoint)
        .where((id) => !selectedInOrder.contains(id))
        .length;
    final remaining = afterDragged
        .where((id) => !selectedInOrder.contains(id))
        .toList(growable: false);
    final reordered = <String>[
      ...remaining.take(targetIndex),
      ...selectedInOrder,
      ...remaining.skip(targetIndex),
    ];
    if (listEquals(reordered, _customLibraryIds)) return;
    _customLibraryIds
      ..clear()
      ..addAll(reordered);
    notifyListeners();
  }

  Future<void> saveCustomOrder() async {
    if (!hasUnsavedCustomOrder || orderSaveInProgress) return;
    final libraries = snapshot?.libraries ?? const <KontaktLibrary>[];
    final byId = {for (final library in libraries) library.id: library};
    final ordered = _customLibraryIds
        .map((id) => byId[id])
        .whereType<KontaktLibrary>()
        .toList(growable: false);
    if (ordered.length != libraries.length) {
      throw StateError('The custom library order is incomplete.');
    }

    orderSaveInProgress = true;
    notifyListeners();
    try {
      await platform.saveClassicLibraryOrder(ordered);
      snapshot = InventorySnapshot(
        libraries: [
          for (var index = 0; index < ordered.length; index++)
            ordered[index].copyWith(userListIndex: index + 1),
        ],
        diagnostics: snapshot!.diagnostics,
        scannedAt: snapshot!.scannedAt,
      );
      _savedCustomLibraryIds = List<String>.unmodifiable(_customLibraryIds);
      _log('classic_order_saved', '', count: ordered.length);
    } catch (error) {
      _log('classic_order_error', error.toString(), isError: true);
      rethrow;
    } finally {
      orderSaveInProgress = false;
      notifyListeners();
    }
  }

  void _synchronizeCustomOrder(List<KontaktLibrary> libraries) {
    if (!_customOrderInitialized) {
      _customLibraryIds
        ..clear()
        ..addAll(_defaultCustomOrder(libraries).map((library) => library.id));
      _savedCustomLibraryIds = List<String>.unmodifiable(_customLibraryIds);
      _customOrderInitialized = true;
      return;
    }

    final hadPendingChanges = hasUnsavedCustomOrder;
    final availableIds = libraries.map((library) => library.id).toSet();
    _customLibraryIds.removeWhere((id) => !availableIds.contains(id));
    final defaultOrder = _defaultCustomOrder(libraries);
    final defaultPositions = <String, int>{
      for (var index = 0; index < defaultOrder.length; index++)
        defaultOrder[index].id: index,
    };
    for (var index = 0; index < defaultOrder.length; index++) {
      final libraryId = defaultOrder[index].id;
      if (_customLibraryIds.contains(libraryId)) continue;
      final insertionIndex = _customLibraryIds.indexWhere((existingId) {
        final existingPosition = defaultPositions[existingId];
        return existingPosition != null && existingPosition > index;
      });
      if (insertionIndex < 0) {
        _customLibraryIds.add(libraryId);
      } else {
        _customLibraryIds.insert(insertionIndex, libraryId);
      }
    }

    if (hadPendingChanges) {
      _savedCustomLibraryIds = List<String>.unmodifiable(
        _savedCustomLibraryIds.where(availableIds.contains),
      );
    } else {
      _savedCustomLibraryIds = List<String>.unmodifiable(_customLibraryIds);
    }
  }

  List<KontaktLibrary> _defaultCustomOrder(List<KontaktLibrary> libraries) {
    final ordered = List<KontaktLibrary>.of(libraries);
    ordered.sort((left, right) {
      final leftIndex = left.userListIndex;
      final rightIndex = right.userListIndex;
      if (leftIndex != null && rightIndex != null) {
        final comparison = leftIndex.compareTo(rightIndex);
        if (comparison != 0) return comparison;
      } else if (leftIndex != null) {
        return -1;
      } else if (rightIndex != null) {
        return 1;
      }
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
    return ordered;
  }

  Future<void> reveal(KontaktLibrary library) async {
    final path = library.contentPath;
    if (path == null || path.isEmpty) return;
    try {
      await platform.revealInFileManager(path);
      _log('folder_opened', library.name);
    } catch (error) {
      _log('folder_error', error.toString(), isError: true);
      rethrow;
    } finally {
      notifyListeners();
    }
  }

  Future<void> refreshHelperStatus({bool notify = true}) async {
    try {
      helperStatus = await platform.privilegedHelperStatus();
    } catch (_) {
      helperStatus = PrivilegedHelperStatus.unavailable;
    }
    if (notify) notifyListeners();
  }

  Future<List<KontaktLibraryCandidate>> chooseLibraryCandidates({
    required bool allowMultiple,
  }) {
    return platform.chooseLibraryCandidates(allowMultiple: allowMultiple);
  }

  Future<String?> chooseContentDirectory() {
    return platform.chooseContentDirectory();
  }

  bool candidateMatchesLibrary(
    KontaktLibraryCandidate candidate,
    KontaktLibrary library,
  ) {
    final candidateKey = candidate.metadata.regKey.trim().toLowerCase();
    final libraryKey = (library.regKey ?? library.name).trim().toLowerCase();
    final candidateSnpid = candidate.metadata.snpid.trim().toLowerCase();
    final librarySnpid = library.snpid?.trim().toLowerCase();
    return candidateKey == libraryKey ||
        (librarySnpid != null &&
            librarySnpid.isNotEmpty &&
            candidateSnpid == librarySnpid) ||
        candidate.metadata.name.trim().toLowerCase() ==
            library.name.trim().toLowerCase();
  }

  List<KontaktLibraryCandidate> candidatesNotRegistered(
    Iterable<KontaktLibraryCandidate> candidates,
  ) {
    final registeredLibraries = snapshot?.libraries ?? const <KontaktLibrary>[];
    return candidates
        .where(
          (candidate) => !registeredLibraries.any(
            (library) => candidateMatchesLibrary(candidate, library),
          ),
        )
        .toList(growable: false);
  }

  LibraryRepairPreview previewRepairs(
    List<KontaktLibrary> libraries,
    List<KontaktLibraryCandidate> candidates,
  ) {
    final matches = <LibraryRepairMatch>[];
    final unmatched = <KontaktLibrary>[];
    final ambiguous = <KontaktLibrary>[];
    final usedCandidates = <KontaktLibraryCandidate>{};

    for (final library in libraries) {
      final available = candidates
          .where((candidate) => !usedCandidates.contains(candidate))
          .toList(growable: false);
      final candidateMatches = _bestRepairCandidates(library, available);
      if (candidateMatches.isEmpty) {
        unmatched.add(library);
      } else if (candidateMatches.length > 1) {
        ambiguous.add(library);
      } else {
        final candidate = candidateMatches.single;
        usedCandidates.add(candidate);
        matches.add(LibraryRepairMatch(library: library, candidate: candidate));
      }
    }

    return LibraryRepairPreview(
      matches: List.unmodifiable(matches),
      unmatchedLibraries: List.unmodifiable(unmatched),
      ambiguousLibraries: List.unmodifiable(ambiguous),
      unmatchedCandidates: List.unmodifiable(
        candidates.where((candidate) => !usedCandidates.contains(candidate)),
      ),
    );
  }

  List<KontaktLibraryCandidate> _bestRepairCandidates(
    KontaktLibrary library,
    List<KontaktLibraryCandidate> candidates,
  ) {
    final libraryKey = (library.regKey ?? '').trim().toLowerCase();
    final byRegKey = libraryKey.isEmpty
        ? const <KontaktLibraryCandidate>[]
        : candidates
              .where(
                (candidate) =>
                    candidate.metadata.regKey.trim().toLowerCase() ==
                    libraryKey,
              )
              .toList(growable: false);
    if (byRegKey.isNotEmpty) return byRegKey;

    final librarySnpid = (library.snpid ?? '').trim().toLowerCase();
    final bySnpid = librarySnpid.isEmpty
        ? const <KontaktLibraryCandidate>[]
        : candidates
              .where(
                (candidate) =>
                    candidate.metadata.snpid.trim().toLowerCase() ==
                    librarySnpid,
              )
              .toList(growable: false);
    if (bySnpid.isNotEmpty) return bySnpid;

    final libraryName = library.name.trim().toLowerCase();
    return candidates
        .where(
          (candidate) =>
              candidate.metadata.name.trim().toLowerCase() == libraryName,
        )
        .toList(growable: false);
  }

  Future<void> upsertCandidates(
    List<KontaktLibraryCandidate> candidates, {
    required bool repair,
  }) async {
    if (candidates.isEmpty) return;
    var candidatesToUpsert = candidates;
    if (!repair) {
      candidatesToUpsert = candidatesNotRegistered(candidates);
      if (candidatesToUpsert.isEmpty) {
        throw LibraryAlreadyRegistered(candidates.first.metadata.name);
      }
    }
    await _runMutation(() async {
      await _ensureHelperEnabled();
      await platform.upsertLibraries(candidatesToUpsert);
      for (final candidate in candidatesToUpsert) {
        _log(
          repair ? 'library_repaired' : 'library_added',
          candidate.metadata.name,
        );
      }
    });
  }

  Future<void> relocateLibrary(
    KontaktLibrary library,
    String contentPath,
  ) async {
    await _runMutation(() async {
      await _ensureHelperEnabled();
      await platform.relocateLibrary(library, contentPath);
      _log('library_relocated', library.name);
    });
  }

  Future<void> removeLibrary(KontaktLibrary library) async {
    await removeLibraries([library]);
  }

  Future<void> removeLibraries(Iterable<KontaktLibrary> values) async {
    if (mutationInProgress) return;
    _classicOrderWarning = null;
    final libraries = <KontaktLibrary>[];
    final seenIds = <String>{};
    for (final library in values) {
      if (seenIds.add(library.id)) libraries.add(library);
    }
    if (libraries.isEmpty) return;

    final removedIds = libraries.map((library) => library.id).toSet();
    final shouldPersistOrder = removedIds.any(
      (libraryId) => _customLibraryIds.contains(libraryId),
    );
    try {
      await _runMutation(() async {
        await _ensureHelperEnabled();
        await platform.removeLibraries(libraries);
        for (final library in libraries) {
          _log('library_removed', library.name);
        }
      });
    } catch (error) {
      // A platform can fail after removing an earlier item in the batch.
      // Refresh before surfacing the error so the UI never shows stale rows.
      await refresh();
      rethrow;
    }
    _selectedLibraryIds.removeAll(removedIds);
    notifyListeners();
    if (shouldPersistOrder && platform.capabilities.canManageClassicOrder) {
      _savedCustomLibraryIds = List<String>.unmodifiable([
        ..._savedCustomLibraryIds.where((id) => !removedIds.contains(id)),
        ...removedIds,
      ]);
      try {
        await saveCustomOrder();
      } catch (error) {
        _classicOrderWarning = error;
        _log('classic_order_error', error.toString(), isError: true);
        notifyListeners();
      }
    }
  }

  Future<void> _runMutation(Future<void> Function() operation) async {
    if (mutationInProgress) return;
    mutationInProgress = true;
    notifyListeners();
    try {
      await operation();
      mutationInProgress = false;
      await refresh();
    } catch (error) {
      _log('mutation_error', error.toString(), isError: true);
      mutationInProgress = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _ensureHelperEnabled() async {
    helperStatus = await platform.privilegedHelperStatus();
    if (helperStatus == PrivilegedHelperStatus.enabled) return;
    helperStatus = await platform.enablePrivilegedHelper();
    notifyListeners();
    if (helperStatus != PrivilegedHelperStatus.enabled) {
      throw PrivilegedHelperRequired(helperStatus);
    }
    _log('helper_enabled', '');
  }

  List<KontaktLibrary> get visibleLibraries {
    final normalizedQuery = query.trim().toLowerCase();
    final result = (snapshot?.libraries ?? const <KontaktLibrary>[]).where((
      library,
    ) {
      final matchesQuery =
          normalizedQuery.isEmpty ||
          library.name.toLowerCase().contains(normalizedQuery) ||
          (library.contentPath?.toLowerCase().contains(normalizedQuery) ??
              false) ||
          (library.snpid?.toLowerCase().contains(normalizedQuery) ?? false);
      if (!matchesQuery) return false;
      return switch (filter) {
        LibraryFilter.all => true,
        LibraryFilter.healthy => library.health == LibraryHealth.healthy,
        LibraryFilter.attention => library.health != LibraryHealth.healthy,
        LibraryFilter.offline => library.issues.any(
          (issue) => issue.code == 'content_offline',
        ),
      };
    }).toList();

    result.sort(
      (left, right) => switch (sort) {
        LibrarySort.custom =>
          _customLibraryIds
              .indexOf(left.id)
              .compareTo(_customLibraryIds.indexOf(right.id)),
        LibrarySort.name => left.name.toLowerCase().compareTo(
          right.name.toLowerCase(),
        ),
        LibrarySort.health => right.health.index.compareTo(left.health.index),
        LibrarySort.path => (left.contentPath ?? '').toLowerCase().compareTo(
          (right.contentPath ?? '').toLowerCase(),
        ),
      },
    );
    return result;
  }

  int get totalCount => snapshot?.libraries.length ?? 0;

  int get healthyCount =>
      snapshot?.libraries
          .where((library) => library.health == LibraryHealth.healthy)
          .length ??
      0;

  int get attentionCount =>
      snapshot?.libraries
          .where((library) => library.health != LibraryHealth.healthy)
          .length ??
      0;

  int get offlineCount =>
      snapshot?.libraries
          .where(
            (library) =>
                library.issues.any((issue) => issue.code == 'content_offline'),
          )
          .length ??
      0;

  void _log(String code, String detail, {bool isError = false, int? count}) {
    logs.insert(
      0,
      OperationLog(
        timestamp: DateTime.now(),
        code: code,
        detail: detail,
        isError: isError,
        count: count,
      ),
    );
  }
}

class PrivilegedHelperRequired implements Exception {
  const PrivilegedHelperRequired(this.status);

  final PrivilegedHelperStatus status;

  @override
  String toString() => 'The privileged helper is not enabled: ${status.name}';
}

class LibraryAlreadyRegistered implements Exception {
  const LibraryAlreadyRegistered(this.libraryName);

  final String libraryName;

  @override
  String toString() =>
      '$libraryName is already registered. Use Repair instead.';
}
