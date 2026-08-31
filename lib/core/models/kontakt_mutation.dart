import 'package:kontakt_library_manager/core/models/kontakt_library.dart';

enum KontaktMutationType { upsert, relocate, remove }

enum PrivilegedHelperStatus {
  unsupported,
  notRegistered,
  approvalRequired,
  enabled,
  unavailable,
}

class KontaktLibraryCandidate {
  const KontaktLibraryCandidate({
    required this.contentPath,
    required this.metadataPath,
    required this.metadata,
    required this.productHintsXml,
  });

  final String contentPath;
  final String metadataPath;
  final ProductMetadata metadata;
  final String productHintsXml;

  Map<String, Object> toUpsertRequest() => {
    'version': 1,
    'operation': KontaktMutationType.upsert.name,
    'name': metadata.name,
    'regKey': metadata.regKey,
    'snpid': metadata.snpid,
    'contentPath': contentPath,
    'productHintsXml': productHintsXml,
    'visibility': metadata.visibility ?? 3,
    if (metadata.hu != null) 'hu': metadata.hu!,
    if (metadata.jdx != null) 'jdx': metadata.jdx!,
    if (metadata.upid != null) 'upid': metadata.upid!,
    if (metadata.authSystem != null) 'authSystem': metadata.authSystem!,
  };
}

enum LibraryCandidateSkipReason {
  missingMetadata,
  notKontakt,
  invalidMetadata,
  missingFolder,
  searchLimit,
  filesystemRoot,
}

class LibraryCandidateSkip {
  const LibraryCandidateSkip({required this.path, required this.reason});

  final String path;
  final LibraryCandidateSkipReason reason;
}

class LibraryCandidateScanResult {
  const LibraryCandidateScanResult({
    required this.candidates,
    this.skipped = const [],
  });

  static const empty = LibraryCandidateScanResult(candidates: []);

  final List<KontaktLibraryCandidate> candidates;
  final List<LibraryCandidateSkip> skipped;

  bool get isEmpty => candidates.isEmpty;
}

class KontaktMutationRequest {
  const KontaktMutationRequest._(this.payload);

  factory KontaktMutationRequest.relocate(
    KontaktLibrary library,
    String contentPath,
  ) {
    return KontaktMutationRequest._({
      'version': 1,
      'operation': KontaktMutationType.relocate.name,
      'name': library.name,
      'regKey': library.regKey ?? library.name,
      if (library.snpid != null) 'snpid': library.snpid!,
      'contentPath': contentPath,
    });
  }

  factory KontaktMutationRequest.remove(KontaktLibrary library) {
    return KontaktMutationRequest._({
      'version': 1,
      'operation': KontaktMutationType.remove.name,
      'name': library.name,
      'regKey': library.regKey ?? library.name,
    });
  }

  factory KontaktMutationRequest.batch(
    Iterable<Map<String, Object>> operations,
  ) {
    return KontaktMutationRequest._({
      'version': 1,
      'operations': operations.toList(growable: false),
    });
  }

  final Map<String, Object> payload;
}

class KontaktMutationResult {
  const KontaktMutationResult({
    required this.operation,
    required this.libraryName,
    required this.changedPaths,
  });

  final KontaktMutationType operation;
  final String libraryName;
  final List<String> changedPaths;

  factory KontaktMutationResult.fromMap(Map<Object?, Object?> map) {
    final operationName = map['operation'] as String? ?? 'upsert';
    return KontaktMutationResult(
      operation: KontaktMutationType.values.firstWhere(
        (value) => value.name == operationName,
        orElse: () => KontaktMutationType.upsert,
      ),
      libraryName: map['libraryName'] as String? ?? '',
      changedPaths: (map['changedPaths'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  static List<KontaktMutationResult> listFromMap(Map<Object?, Object?> map) {
    final results = map['results'];
    if (results is! List) return [KontaktMutationResult.fromMap(map)];
    return results
        .whereType<Map>()
        .map((result) => KontaktMutationResult.fromMap(result))
        .toList(growable: false);
  }
}
