import 'dart:io';

import 'package:kontakt_library_manager/core/metadata/product_hints_parser.dart';
import 'package:kontakt_library_manager/core/models/kontakt_mutation.dart';

class LibraryCandidateException implements Exception {
  const LibraryCandidateException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LibraryCandidateScanner {
  const LibraryCandidateScanner() : _parser = const ProductHintsParser();

  static const _maxDepth = 4;
  static const _maxDirectories = 2500;
  static const _contentDirectoryNames = {
    'instruments',
    'samples',
    'sounds',
    'data',
    'resource',
    'resources',
  };
  static const _skipDirectoryNames = {
    'samples',
    'instruments',
    'sounds',
    'data',
    'resource',
    'resources',
    'wav',
    'ncw',
    'waves',
    '.git',
    '.svn',
    '__macosx',
    r'$recycle.bin',
    'system volume information',
    'lost+found',
    'node_modules',
  };

  final ProductHintsParser _parser;

  Future<LibraryCandidateScanResult> scanDirectories(
    Iterable<String> paths,
  ) async {
    final selected = paths.where((path) => path.trim().isNotEmpty).toList();
    if (selected.isEmpty) return LibraryCandidateScanResult.empty;

    final candidates = <KontaktLibraryCandidate>[];
    final skipped = <LibraryCandidateSkip>[];
    final budget = _ScanBudget();

    for (final path in selected) {
      final before = candidates.length;
      await _collectFromPath(
        path,
        depth: 0,
        candidates: candidates,
        budget: budget,
      );
      if (candidates.length == before) {
        skipped.add(
          LibraryCandidateSkip(
            path: path,
            reason: budget.exhausted
                ? LibraryCandidateSkipReason.searchLimit
                : LibraryCandidateSkipReason.missingMetadata,
          ),
        );
      }
    }

    if (candidates.isEmpty) {
      throw const LibraryCandidateException(
        'None of the selected folders contain Kontakt library metadata.',
      );
    }

    return LibraryCandidateScanResult(
      candidates: _uniqueCandidates(candidates),
      skipped: skipped,
    );
  }

  Future<List<KontaktLibraryCandidate>> scanDirectory(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      throw LibraryCandidateException('The selected folder does not exist.');
    }
    if (_isFilesystemRoot(directory.path)) {
      throw const LibraryCandidateException(
        'Select a library folder rather than a drive root.',
      );
    }

    final outcome = await _readLibraryFolder(directory);
    switch (outcome.kind) {
      case _FolderKind.library:
        return outcome.candidates;
      case _FolderKind.missingMetadata:
        throw const LibraryCandidateException(
          'The selected folder does not contain a .nicnt or *_info.nkx file.',
        );
      case _FolderKind.notKontakt:
        throw const LibraryCandidateException(
          'The selected folder does not contain Kontakt library metadata.',
        );
      case _FolderKind.invalidMetadata:
        throw const LibraryCandidateException(
          'The selected folder does not contain valid Kontakt library metadata.',
        );
    }
  }

  Future<void> _collectFromPath(
    String path, {
    required int depth,
    required List<KontaktLibraryCandidate> candidates,
    required _ScanBudget budget,
  }) async {
    if (!budget.take()) return;

    final directory = Directory(path);
    if (!await directory.exists()) return;
    if (_isFilesystemRoot(directory.path)) return;

    final outcome = await _readLibraryFolder(directory);
    if (outcome.kind == _FolderKind.library) {
      candidates.addAll(outcome.candidates);
      return;
    }
    // A folder that already has .nicnt / *_info.nkx is a product root.
    // Do not search inside Reaktor or invalid metadata folders.
    if (outcome.kind != _FolderKind.missingMetadata) return;
    if (depth >= _maxDepth) return;

    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (!budget.hasCapacity) return;
        if (entity is! Directory) continue;
        final name = _fileName(entity.path).toLowerCase();
        if (name.startsWith('.') || _skipDirectoryNames.contains(name)) {
          continue;
        }
        await _collectFromPath(
          entity.path,
          depth: depth + 1,
          candidates: candidates,
          budget: budget,
        );
      }
    } on FileSystemException {
      return;
    }
  }

  Future<_FolderRead> _readLibraryFolder(Directory directory) async {
    final nicnt = <File>[];
    final nkx = <File>[];
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = _fileName(entity.path).toLowerCase();
        if (name.startsWith('._')) continue;
        if (name.endsWith('.nicnt')) {
          nicnt.add(entity);
        } else if (name.endsWith('_info.nkx')) {
          nkx.add(entity);
        }
      }
    } on FileSystemException {
      return const _FolderRead(_FolderKind.missingMetadata);
    }

    final files = nicnt.isNotEmpty ? nicnt : nkx;
    if (files.isEmpty) {
      return const _FolderRead(_FolderKind.missingMetadata);
    }

    final contentPath = await _resolveContentPath(directory);
    final candidates = <KontaktLibraryCandidate>[];
    var parseFailed = false;
    for (final file in files) {
      try {
        final document = _parser.parseDocumentBytes(await file.readAsBytes());
        if (!document.metadata.isKontaktLibraryMetadata) continue;
        candidates.add(
          KontaktLibraryCandidate(
            contentPath: contentPath,
            metadataPath: file.path,
            metadata: document.metadata,
            productHintsXml: document.xml,
          ),
        );
      } on ProductHintsException {
        parseFailed = true;
      }
    }
    if (candidates.isNotEmpty) {
      return _FolderRead(_FolderKind.library, candidates: candidates);
    }
    if (parseFailed) {
      return const _FolderRead(_FolderKind.invalidMetadata);
    }
    return const _FolderRead(_FolderKind.notKontakt);
  }

  Future<String> _resolveContentPath(Directory metadataDirectory) async {
    if (await _hasLibraryContent(metadataDirectory)) {
      return metadataDirectory.resolveSymbolicLinks();
    }

    final parent = metadataDirectory.parent;
    if (parent.path == metadataDirectory.path ||
        _isFilesystemRoot(parent.path)) {
      return metadataDirectory.resolveSymbolicLinks();
    }
    if (await _hasLibraryContent(parent) && !await _hasMetadataFiles(parent)) {
      return parent.resolveSymbolicLinks();
    }
    return metadataDirectory.resolveSymbolicLinks();
  }

  Future<bool> _hasMetadataFiles(Directory directory) async {
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = _fileName(entity.path).toLowerCase();
        if (name.startsWith('._')) continue;
        if (name.endsWith('.nicnt') || name.endsWith('_info.nkx')) return true;
      }
    } on FileSystemException {
      return false;
    }
    return false;
  }

  Future<bool> _hasLibraryContent(Directory directory) async {
    try {
      await for (final entity in directory.list(followLinks: false)) {
        final name = _fileName(entity.path).toLowerCase();
        if (name.startsWith('._')) continue;
        if (entity is Directory && _contentDirectoryNames.contains(name)) {
          return true;
        }
        if (entity is! File) continue;
        if (name.endsWith('.nki') ||
            name.endsWith('.nkm') ||
            name.endsWith('.nkc') ||
            name.endsWith('.ncw') ||
            name.endsWith('.wav')) {
          return true;
        }
        if (name.endsWith('.nkx') && !name.endsWith('_info.nkx')) {
          return true;
        }
      }
    } on FileSystemException {
      return false;
    }
    return false;
  }

  List<KontaktLibraryCandidate> _uniqueCandidates(
    List<KontaktLibraryCandidate> candidates,
  ) {
    final identityPaths = <String, String>{};
    final snpidPaths = <String, String>{};
    final unique = <KontaktLibraryCandidate>[];
    for (final candidate in candidates) {
      final identity = candidate.metadata.regKey.trim().toLowerCase();
      final snpid = candidate.metadata.snpid.trim().toLowerCase();
      final path = candidate.contentPath;
      final existingIdentityPath = identityPaths[identity];
      final existingSnpidPath = snpidPaths[snpid];
      if (existingIdentityPath != null || existingSnpidPath != null) {
        if (existingIdentityPath == path || existingSnpidPath == path) {
          continue;
        }
        throw const LibraryCandidateException(
          'The selection contains duplicate RegKey or SNPID values.',
        );
      }
      identityPaths[identity] = path;
      snpidPaths[snpid] = path;
      unique.add(candidate);
    }
    return unique;
  }

  bool _isFilesystemRoot(String path) {
    final normalized = path.replaceAll('\\', '/');
    if (normalized == '/' || normalized.isEmpty) return true;
    return RegExp(r'^[a-zA-Z]:/?$').hasMatch(normalized);
  }

  String _fileName(String path) => path.replaceAll('\\', '/').split('/').last;
}

class _ScanBudget {
  int visited = 0;

  bool get exhausted => visited >= LibraryCandidateScanner._maxDirectories;
  bool get hasCapacity => !exhausted;

  bool take() {
    if (exhausted) return false;
    visited += 1;
    return true;
  }
}

enum _FolderKind { library, missingMetadata, notKontakt, invalidMetadata }

class _FolderRead {
  const _FolderRead(this.kind, {this.candidates = const []});

  final _FolderKind kind;
  final List<KontaktLibraryCandidate> candidates;
}
