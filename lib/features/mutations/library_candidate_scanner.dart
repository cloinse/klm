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

  final ProductHintsParser _parser;

  Future<List<KontaktLibraryCandidate>> scanDirectories(
    Iterable<String> paths,
  ) async {
    final candidates = <KontaktLibraryCandidate>[];
    for (final path in paths) {
      candidates.addAll(await scanDirectory(path));
    }
    final identities = <String>{};
    final snpids = <String>{};
    for (final candidate in candidates) {
      final identity = candidate.metadata.regKey.trim().toLowerCase();
      final snpid = candidate.metadata.snpid.trim().toLowerCase();
      if (!identities.add(identity) || !snpids.add(snpid)) {
        throw const LibraryCandidateException(
          'The selection contains duplicate RegKey or SNPID values.',
        );
      }
    }
    return candidates;
  }

  Future<List<KontaktLibraryCandidate>> scanDirectory(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      throw LibraryCandidateException('The selected folder does not exist.');
    }

    final nicnt = <File>[];
    final nkx = <File>[];
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

    final files = nicnt.isNotEmpty ? nicnt : nkx;
    if (files.isEmpty) {
      throw const LibraryCandidateException(
        'The selected folder does not contain a .nicnt or *_info.nkx file.',
      );
    }

    final canonicalContentPath = await directory.resolveSymbolicLinks();
    final candidates = <KontaktLibraryCandidate>[];
    for (final file in files) {
      final document = _parser.parseDocumentBytes(await file.readAsBytes());
      if (!document.metadata.isKontaktLibraryMetadata) continue;
      candidates.add(
        KontaktLibraryCandidate(
          contentPath: canonicalContentPath,
          metadataPath: file.path,
          metadata: document.metadata,
          productHintsXml: document.xml,
        ),
      );
    }
    if (candidates.isEmpty) {
      throw const LibraryCandidateException(
        'The selected folder does not contain Kontakt library metadata.',
      );
    }
    return candidates;
  }

  String _fileName(String path) => path.replaceAll('\\', '/').split('/').last;
}
