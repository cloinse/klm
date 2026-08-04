import 'dart:convert';
import 'dart:io';

import 'package:kontakt_library_manager/core/metadata/product_hints_parser.dart';
import 'package:kontakt_library_manager/core/models/kontakt_library.dart';
import 'package:kontakt_library_manager/core/models/kontakt_mutation.dart';
import 'package:kontakt_library_manager/core/validation/library_validator.dart';
import 'package:kontakt_library_manager/platform/inventory_assembler.dart';
import 'package:kontakt_library_manager/platform/kontakt_platform.dart';

class WindowsKontaktPlatform implements KontaktPlatform {
  WindowsKontaktPlatform({
    ProductHintsParser parser = const ProductHintsParser(),
    LibraryValidator validator = const LibraryValidator(),
  }) : _parser = parser,
       _validator = validator;

  final ProductHintsParser _parser;
  final LibraryValidator _validator;

  @override
  PlatformCapabilities get capabilities => const PlatformCapabilities(
    platformName: 'Windows',
    canReadInventory: true,
    privilegedMutationsAvailable: false,
    registryLayoutVerified: false,
    canManageClassicOrder: false,
  );

  @override
  Future<InventorySnapshot> scanLibraries() async {
    final assembler = InventoryAssembler();
    final diagnostics = <InventoryDiagnostic>[
      const InventoryDiagnostic(
        code: 'windows_registry_pending',
        title: 'Registro de Windows pendiente de validación',
        message:
            'El inventario lee XML y JSON. Las vistas de Registro 32/64 bits se habilitarán tras validarlas en una máquina con Kontakt.',
        severity: IssueSeverity.information,
      ),
    ];
    final programFiles =
        Platform.environment['PROGRAMFILES'] ?? r'C:\Program Files';
    final publicDirectory =
        Platform.environment['PUBLIC'] ?? r'C:\Users\Public';

    await _readXmlDirectory(
      Directory(
        '$programFiles${Platform.pathSeparator}Common Files${Platform.pathSeparator}Native Instruments${Platform.pathSeparator}Service Center',
      ),
      assembler,
    );
    await _readJsonDirectory(
      Directory(
        '$publicDirectory${Platform.pathSeparator}Documents${Platform.pathSeparator}Native Instruments${Platform.pathSeparator}installed_products',
      ),
      assembler,
      diagnostics,
    );

    final libraries = _validator.validate(assembler.build())
      ..sort(
        (left, right) =>
            left.name.toLowerCase().compareTo(right.name.toLowerCase()),
      );
    return InventorySnapshot(
      libraries: libraries,
      diagnostics: diagnostics,
      scannedAt: DateTime.now(),
    );
  }

  Future<void> _readXmlDirectory(
    Directory directory,
    InventoryAssembler assembler,
  ) async {
    if (!await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.xml')) {
        continue;
      }
      try {
        final metadata = _parser.parseBytes(await entity.readAsBytes());
        assembler.add(
          name: metadata.name,
          regKey: metadata.regKey,
          snpid: metadata.snpid,
          minimumKontaktVersion: metadata.minimumKontaktVersion,
          source: RegistrationSource.serviceCenter,
        );
      } catch (_) {}
    }
  }

  Future<void> _readJsonDirectory(
    Directory directory,
    InventoryAssembler assembler,
    List<InventoryDiagnostic> diagnostics,
  ) async {
    if (!await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) {
        continue;
      }
      try {
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map<String, dynamic>) continue;
        final fileName = entity.path.split(Platform.pathSeparator).last;
        assembler.add(
          name: fileName.substring(0, fileName.length - 5),
          regKey: decoded['RegKey'] as String?,
          snpid: decoded['SNPID'] as String?,
          contentPath:
              (decoded['ContentDir'] ?? decoded['contentDir']) as String?,
          source: RegistrationSource.installedProducts,
        );
      } catch (error) {
        diagnostics.add(
          InventoryDiagnostic(
            code: 'invalid_json',
            title: 'JSON ilegible',
            message: '${entity.path}: $error',
            severity: IssueSeverity.warning,
            detail: '${entity.path}: $error',
          ),
        );
      }
    }
  }

  @override
  Future<void> revealInFileManager(String path) async {
    final result = await Process.run('explorer.exe', ['/select,$path']);
    if (result.exitCode != 0) {
      throw FileSystemException('El Explorador no pudo mostrar la ruta.', path);
    }
  }

  @override
  Future<void> saveClassicLibraryOrder(List<KontaktLibrary> libraries) =>
      _mutationsPending();

  @override
  Future<List<KontaktLibraryCandidate>> chooseLibraryCandidates({
    required bool allowMultiple,
  }) => _mutationsPending();

  @override
  Future<String?> chooseContentDirectory() => _mutationsPending();

  @override
  Future<PrivilegedHelperStatus> enablePrivilegedHelper() async =>
      PrivilegedHelperStatus.unsupported;

  @override
  Future<PrivilegedHelperStatus> privilegedHelperStatus() async =>
      PrivilegedHelperStatus.unsupported;

  @override
  Future<KontaktMutationResult> relocateLibrary(
    KontaktLibrary library,
    String contentPath,
  ) => _mutationsPending();

  @override
  Future<KontaktMutationResult> removeLibrary(KontaktLibrary library) =>
      _mutationsPending();

  @override
  Future<KontaktMutationResult> upsertLibrary(
    KontaktLibraryCandidate candidate,
  ) => _mutationsPending();

  Future<T> _mutationsPending<T>() {
    throw UnsupportedError(
      'Windows mutations require Registry validation on a Windows machine.',
    );
  }
}
