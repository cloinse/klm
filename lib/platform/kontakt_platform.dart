import 'package:kontakt_library_manager/core/models/kontakt_library.dart';
import 'package:kontakt_library_manager/core/models/kontakt_mutation.dart';

class InventoryDiagnostic {
  const InventoryDiagnostic({
    required this.code,
    required this.title,
    required this.message,
    required this.severity,
    this.detail,
  });

  final String code;
  final String title;
  final String message;
  final IssueSeverity severity;
  final String? detail;
}

class InventorySnapshot {
  const InventorySnapshot({
    required this.libraries,
    required this.diagnostics,
    required this.scannedAt,
  });

  final List<KontaktLibrary> libraries;
  final List<InventoryDiagnostic> diagnostics;
  final DateTime scannedAt;
}

class PlatformCapabilities {
  const PlatformCapabilities({
    required this.platformName,
    required this.canReadInventory,
    required this.privilegedMutationsAvailable,
    required this.registryLayoutVerified,
    required this.canManageClassicOrder,
  });

  final String platformName;
  final bool canReadInventory;
  final bool privilegedMutationsAvailable;
  final bool registryLayoutVerified;
  final bool canManageClassicOrder;
}

abstract class KontaktPlatform {
  PlatformCapabilities get capabilities;

  Future<InventorySnapshot> scanLibraries();

  Future<void> revealInFileManager(String path);

  Future<void> saveClassicLibraryOrder(List<KontaktLibrary> libraries);

  Future<PrivilegedHelperStatus> privilegedHelperStatus();

  Future<PrivilegedHelperStatus> enablePrivilegedHelper();

  Future<List<KontaktLibraryCandidate>> chooseLibraryCandidates({
    required bool allowMultiple,
  });

  Future<String?> chooseContentDirectory();

  Future<KontaktMutationResult> upsertLibrary(
    KontaktLibraryCandidate candidate,
  );

  Future<List<KontaktMutationResult>> upsertLibraries(
    List<KontaktLibraryCandidate> candidates,
  ) async {
    final results = <KontaktMutationResult>[];
    for (final candidate in candidates) {
      results.add(await upsertLibrary(candidate));
    }
    return results;
  }

  Future<KontaktMutationResult> relocateLibrary(
    KontaktLibrary library,
    String contentPath,
  );

  Future<KontaktMutationResult> removeLibrary(KontaktLibrary library);

  Future<List<KontaktMutationResult>> removeLibraries(
    List<KontaktLibrary> libraries,
  ) async {
    final results = <KontaktMutationResult>[];
    for (final library in libraries) {
      results.add(await removeLibrary(library));
    }
    return results;
  }
}
