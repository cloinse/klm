import 'dart:io';

import 'package:kontakt_library_manager/core/models/kontakt_library.dart';

enum ContentPathAccess { available, missing, permissionDenied, unavailable }

class LibraryValidator {
  const LibraryValidator();

  List<KontaktLibrary> validate(List<KontaktLibrary> libraries) {
    return _validate(
      libraries,
      pathAccess: (path) => Directory(path).existsSync()
          ? ContentPathAccess.available
          : ContentPathAccess.missing,
    );
  }

  Future<List<KontaktLibrary>> validateAsync(
    List<KontaktLibrary> libraries, {
    Duration pathCheckTimeout = const Duration(seconds: 5),
    int maxConcurrentPathChecks = 16,
    Future<bool> Function(String path)? pathExists,
    Future<ContentPathAccess> Function(String path)? pathProbe,
  }) async {
    if (maxConcurrentPathChecks < 1) {
      throw ArgumentError.value(
        maxConcurrentPathChecks,
        'maxConcurrentPathChecks',
        'Must be greater than zero.',
      );
    }
    final probe =
        pathProbe ??
        (path) async {
          final exists = pathExists == null
              ? await Directory(path).exists()
              : await pathExists(path);
          return exists
              ? ContentPathAccess.available
              : ContentPathAccess.missing;
        };
    final paths = <String, String>{};
    for (final library in libraries) {
      final path = library.contentPath?.trim();
      if (path?.isNotEmpty == true) {
        paths.putIfAbsent(path!.toLowerCase(), () => path);
      }
    }

    final entries = paths.entries.toList(growable: false);
    final results = List<MapEntry<String, ContentPathAccess>?>.filled(
      entries.length,
      null,
    );
    var nextIndex = 0;
    Future<void> checkNextPaths() async {
      while (nextIndex < entries.length) {
        final index = nextIndex++;
        final entry = entries[index];
        var access = ContentPathAccess.unavailable;
        try {
          access = await probe(entry.value).timeout(pathCheckTimeout);
        } catch (_) {}
        results[index] = MapEntry(entry.key, access);
      }
    }

    final workerCount = entries.length < maxConcurrentPathChecks
        ? entries.length
        : maxConcurrentPathChecks;
    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => checkNextPaths()),
    );
    final pathStates = Map<String, ContentPathAccess>.fromEntries(
      results.whereType<MapEntry<String, ContentPathAccess>>(),
    );
    return _validate(
      libraries,
      pathAccess: (path) =>
          pathStates[path.toLowerCase()] ?? ContentPathAccess.unavailable,
    );
  }

  List<KontaktLibrary> _validate(
    List<KontaktLibrary> libraries, {
    required ContentPathAccess Function(String path) pathAccess,
  }) {
    final snpidCounts = <String, int>{};
    final pathCounts = <String, int>{};

    for (final library in libraries) {
      final snpid = library.snpid?.toLowerCase();
      if (snpid != null && snpid.isNotEmpty) {
        snpidCounts[snpid] = (snpidCounts[snpid] ?? 0) + 1;
      }
      final path = library.contentPath?.toLowerCase();
      if (path != null && path.isNotEmpty) {
        pathCounts[path] = (pathCounts[path] ?? 0) + 1;
      }
    }

    return libraries
        .map((library) {
          final issues = <LibraryIssue>[...library.issues];
          final path = library.contentPath;
          final hasPortableRegistration = library.sources.contains(
            RegistrationSource.portableSettings,
          );

          if (!library.hasServiceCenter && !hasPortableRegistration) {
            issues.add(
              const LibraryIssue(
                code: 'missing_service_center',
                message: 'Falta el XML de Service Center.',
                severity: IssueSeverity.warning,
              ),
            );
          }
          if (!library.hasLegacyRegistration && !hasPortableRegistration) {
            issues.add(
              const LibraryIssue(
                code: 'missing_legacy_registration',
                message: 'Falta el registro requerido por Kontakt 6.',
                severity: IssueSeverity.warning,
              ),
            );
          }
          if (!library.hasInstalledProduct && !hasPortableRegistration) {
            issues.add(
              const LibraryIssue(
                code: 'missing_installed_product',
                message: 'Falta el manifiesto de Kontakt 7/8.',
                severity: IssueSeverity.warning,
              ),
            );
          }
          if (library.visibility != null && library.visibility != 3) {
            issues.add(
              LibraryIssue(
                code: 'hidden_in_kontakt',
                message:
                    'Kontakt oculta esta librería '
                    '(Visibility=${library.visibility}). '
                    'Repara sus registros para mostrarla.',
                severity: IssueSeverity.warning,
              ),
            );
          }
          if (path == null || path.isEmpty) {
            issues.add(
              const LibraryIssue(
                code: 'missing_content_path',
                message: 'No se pudo determinar la ruta del contenido.',
                severity: IssueSeverity.error,
              ),
            );
          } else {
            switch (pathAccess(path)) {
              case ContentPathAccess.available:
                break;
              case ContentPathAccess.missing:
                issues.add(
                  const LibraryIssue(
                    code: 'content_offline',
                    message: 'La ruta no existe o el disco está desconectado.',
                    severity: IssueSeverity.error,
                  ),
                );
                break;
              case ContentPathAccess.permissionDenied:
                issues.add(
                  const LibraryIssue(
                    code: 'content_permission_denied',
                    message:
                        'El sistema no permitió verificar la ruta del contenido.',
                    severity: IssueSeverity.warning,
                  ),
                );
                break;
              case ContentPathAccess.unavailable:
                issues.add(
                  const LibraryIssue(
                    code: 'content_unavailable',
                    message:
                        'La ruta del contenido no pudo verificarse temporalmente.',
                    severity: IssueSeverity.warning,
                  ),
                );
                break;
            }
          }
          if ((snpidCounts[library.snpid?.toLowerCase()] ?? 0) > 1) {
            issues.add(
              const LibraryIssue(
                code: 'duplicate_snpid',
                message: 'Otra librería utiliza el mismo SNPID.',
                severity: IssueSeverity.error,
              ),
            );
          }
          if ((pathCounts[path?.toLowerCase()] ?? 0) > 1) {
            issues.add(
              const LibraryIssue(
                code: 'duplicate_path',
                message: 'La ruta está asignada a más de una librería.',
                severity: IssueSeverity.warning,
              ),
            );
          }
          if (!library.supportsKontakt6) {
            issues.add(
              LibraryIssue(
                code: 'kontakt6_incompatible',
                message:
                    'La metadata requiere Kontakt ${library.minimumKontaktVersion} o posterior.',
                severity: IssueSeverity.information,
              ),
            );
          }

          return library.copyWith(issues: _unique(issues));
        })
        .toList(growable: false);
  }

  List<LibraryIssue> _unique(List<LibraryIssue> issues) {
    final seen = <String>{};
    return issues
        .where((issue) => seen.add(issue.code))
        .toList(growable: false);
  }
}
