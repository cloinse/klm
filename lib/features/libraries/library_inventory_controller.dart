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
  bool _customOrderInitialized = false;
  final List<String> _customLibraryIds = <String>[];
  List<String> _savedCustomLibraryIds = const <String>[];
  final List<OperationLog> logs = <OperationLog>[];

  Future<void> refresh() async {
    if (state == InventoryLoadState.loading) return;
    state = InventoryLoadState.loading;
    lastError = null;
    notifyListeners();
    try {
      final inventory = await platform.scanLibraries();
      snapshot = inventory;
      _synchronizeCustomOrder(inventory.libraries);
      await refreshHelperStatus(notify: false);
      state = InventoryLoadState.ready;
      _log('inventory_updated', '', count: snapshot!.libraries.length);
    } catch (error) {
      lastError = error;
      state = InventoryLoadState.failure;
      _log('inventory_error', error.toString(), isError: true);
    }
    notifyListeners();
  }

  void setQuery(String value) {
    query = value;
    notifyListeners();
  }

  void setFilter(LibraryFilter value) {
    filter = value;
    notifyListeners();
  }

  void setSort(LibrarySort value) {
    sort = value;
    notifyListeners();
  }

  bool get hasUnsavedCustomOrder =>
      !listEquals(_customLibraryIds, _savedCustomLibraryIds);

  bool get canReorderVisibleLibraries =>
      platform.capabilities.canManageClassicOrder &&
      sort == LibrarySort.custom &&
      filter == LibraryFilter.all &&
      query.trim().isEmpty;

  void reorderLibrary(int oldIndex, int newIndex) {
    if (!canReorderVisibleLibraries || oldIndex == newIndex) return;
    final libraryId = _customLibraryIds.removeAt(oldIndex);
    _customLibraryIds.insert(newIndex, libraryId);
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
    for (final library in _defaultCustomOrder(libraries)) {
      if (!_customLibraryIds.contains(library.id)) {
        _customLibraryIds.add(library.id);
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
    return candidateKey == libraryKey ||
        candidate.metadata.name.trim().toLowerCase() ==
            library.name.trim().toLowerCase();
  }

  Future<void> upsertCandidates(
    List<KontaktLibraryCandidate> candidates, {
    required bool repair,
  }) async {
    if (candidates.isEmpty) return;
    if (!repair) {
      for (final candidate in candidates) {
        for (final library in snapshot?.libraries ?? const <KontaktLibrary>[]) {
          if (candidateMatchesLibrary(candidate, library)) {
            throw LibraryAlreadyRegistered(candidate.metadata.name);
          }
        }
      }
    }
    await _runMutation(() async {
      await _ensureHelperEnabled();
      for (final candidate in candidates) {
        await platform.upsertLibrary(candidate);
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
    await _runMutation(() async {
      await _ensureHelperEnabled();
      await platform.removeLibrary(library);
      _log('library_removed', library.name);
    });
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
