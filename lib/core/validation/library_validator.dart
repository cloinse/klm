import 'dart:io';

import 'package:kontakt_library_manager/core/models/kontakt_library.dart';

class LibraryValidator {
  const LibraryValidator();

  List<KontaktLibrary> validate(List<KontaktLibrary> libraries) {
    return _validate(
      libraries,
      pathExists: (path) => Directory(path).existsSync(),
    );
  }

  Future<List<KontaktLibrary>> validateAsync(
    List<KontaktLibrary> libraries, {
    Duration pathCheckTimeout = const Duration(seconds: 5),
    Future<bool> Function(String path)? pathExists,
  }) async {
    final probe = pathExists ?? (path) => Directory(path).exists();
    final paths = <String, String>{};
    for (final library in libraries) {
      final path = library.contentPath?.trim();
      if (path?.isNotEmpty == true) {
        paths.putIfAbsent(path!.toLowerCase(), () => path);
      }
    }

    final results = await Future.wait(
      paths.entries.map((entry) async {
        var exists = false;
        try {
          exists = await probe(entry.value).timeout(pathCheckTimeout);
        } catch (_) {}
        return MapEntry(entry.key, exists);
      }),
    );
    final pathStates = Map<String, bool>.fromEntries(results);
    return _validate(
      libraries,
      pathExists: (path) => pathStates[path.toLowerCase()] ?? false,
    );
  }

  List<KontaktLibrary> _validate(
    List<KontaktLibrary> libraries, {
    required bool Function(String path) pathExists,
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
          } else if (!pathExists(path)) {
            issues.add(
              const LibraryIssue(
                code: 'content_offline',
                message: 'La ruta no existe o el disco está desconectado.',
                severity: IssueSeverity.error,
              ),
            );
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
