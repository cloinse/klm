import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:kontakt_library_manager/core/metadata/product_hints_parser.dart';
import 'package:kontakt_library_manager/core/models/kontakt_library.dart';
import 'package:kontakt_library_manager/core/models/kontakt_mutation.dart';
import 'package:kontakt_library_manager/core/validation/library_validator.dart';
import 'package:kontakt_library_manager/features/mutations/library_candidate_scanner.dart';
import 'package:kontakt_library_manager/platform/inventory_assembler.dart';
import 'package:kontakt_library_manager/platform/kontakt_platform.dart';

class WindowsKontaktPlatform implements KontaktPlatform {
  WindowsKontaktPlatform({
    ProductHintsParser parser = const ProductHintsParser(),
    LibraryValidator validator = const LibraryValidator(),
    LibraryCandidateScanner candidateScanner = const LibraryCandidateScanner(),
  }) : _parser = parser,
       _validator = validator,
       _candidateScanner = candidateScanner;

  final ProductHintsParser _parser;
  final LibraryValidator _validator;
  final LibraryCandidateScanner _candidateScanner;

  @override
  PlatformCapabilities get capabilities => const PlatformCapabilities(
    platformName: 'Windows',
    canReadInventory: true,
    privilegedMutationsAvailable: true,
    registryLayoutVerified: true,
    canManageClassicOrder: false,
  );

  @override
  Future<InventorySnapshot> scanLibraries() async {
    final assembler = InventoryAssembler();
    final diagnostics = <InventoryDiagnostic>[];
    final knownRegKeys = <String>{};
    final programFiles =
        Platform.environment['PROGRAMFILES'] ?? r'C:\Program Files';
    final publicDirectory =
        Platform.environment['PUBLIC'] ?? r'C:\Users\Public';

    await _readXmlDirectory(
      Directory(
        '$programFiles${Platform.pathSeparator}Common Files${Platform.pathSeparator}Native Instruments${Platform.pathSeparator}Service Center',
      ),
      assembler,
      knownRegKeys,
    );
    await _readJsonDirectory(
      Directory(
        '$publicDirectory${Platform.pathSeparator}Documents${Platform.pathSeparator}Native Instruments${Platform.pathSeparator}installed_products',
      ),
      assembler,
      diagnostics,
      knownRegKeys,
    );
    await _readRegistry(assembler, diagnostics, knownRegKeys);

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
    Set<String> knownRegKeys,
  ) async {
    if (!await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.xml')) {
        continue;
      }
      try {
        final metadata = _parser.parseBytes(await entity.readAsBytes());
        knownRegKeys.add(metadata.regKey.toLowerCase());
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
    Set<String> knownRegKeys,
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
        final name = fileName.substring(0, fileName.length - 5);
        final regKey = decoded['RegKey'] as String?;
        knownRegKeys.add((regKey ?? name).toLowerCase());
        assembler.add(
          name: name,
          regKey: regKey,
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

  Future<void> _readRegistry(
    InventoryAssembler assembler,
    List<InventoryDiagnostic> diagnostics,
    Set<String> knownRegKeys,
  ) async {
    final helper = _helperFile;
    if (!await helper.exists()) {
      diagnostics.add(
        const InventoryDiagnostic(
          code: 'windows_helper_missing',
          title: 'Componente de Windows no encontrado',
          message: 'No se pudo leer el Registro de Native Instruments.',
          severity: IssueSeverity.warning,
        ),
      );
      return;
    }

    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'klm-registry-',
    );
    final responseFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}response.json',
    );
    try {
      final process = await Process.run('powershell.exe', [
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        helper.path,
        '-Mode',
        'inventory',
        '-ResponsePath',
        responseFile.path,
      ]);
      if (process.exitCode != 0 || !await responseFile.exists()) {
        throw const FormatException('Registry helper failed.');
      }
      final decoded = jsonDecode(await responseFile.readAsString());
      final records = decoded is List ? decoded : <Object?>[decoded];
      for (final record in records.whereType<Map<String, dynamic>>()) {
        final regKey = record['regKey'] as String?;
        final snpid = record['snpid'] as String?;
        final contentPath = record['contentPath'] as String?;
        final isKnownLibrary =
            regKey != null &&
            knownRegKeys.contains(regKey.trim().toLowerCase());
        final hasLibraryIdentity =
            snpid?.trim().isNotEmpty == true &&
            contentPath?.trim().isNotEmpty == true;
        if (regKey == null || (!isKnownLibrary && !hasLibraryIdentity)) {
          continue;
        }
        assembler.add(
          name: record['name'] as String? ?? regKey,
          regKey: regKey,
          snpid: snpid,
          contentPath: contentPath,
          userListIndex: record['userListIndex'] as int?,
          source: RegistrationSource.windowsRegistry,
        );
      }
    } catch (error) {
      diagnostics.add(
        InventoryDiagnostic(
          code: 'windows_registry_failed',
          title: 'No se pudo leer el Registro',
          message: error.toString(),
          severity: IssueSeverity.warning,
          detail: error.toString(),
        ),
      );
    } finally {
      await temporaryDirectory.delete(recursive: true);
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
      _classicOrderUnsupported();

  @override
  Future<List<KontaktLibraryCandidate>> chooseLibraryCandidates({
    required bool allowMultiple,
  }) async {
    const options = FileDialogOptions(canCreateDirectories: false);
    final paths = allowMultiple
        ? await FileSelectorPlatform.instance.getDirectoryPathsWithOptions(
            options,
          )
        : <String?>[
            await FileSelectorPlatform.instance.getDirectoryPathWithOptions(
              options,
            ),
          ];
    return _candidateScanner.scanDirectories(paths.whereType<String>());
  }

  @override
  Future<String?> chooseContentDirectory() async {
    final path = await FileSelectorPlatform.instance
        .getDirectoryPathWithOptions(
          const FileDialogOptions(canCreateDirectories: false),
        );
    if (path == null) return null;
    return Directory(path).resolveSymbolicLinks();
  }

  @override
  Future<PrivilegedHelperStatus> enablePrivilegedHelper() =>
      privilegedHelperStatus();

  @override
  Future<PrivilegedHelperStatus> privilegedHelperStatus() async =>
      await _helperFile.exists()
      ? PrivilegedHelperStatus.enabled
      : PrivilegedHelperStatus.unavailable;

  @override
  Future<KontaktMutationResult> relocateLibrary(
    KontaktLibrary library,
    String contentPath,
  ) => _executeMutation(
    KontaktMutationRequest.relocate(library, contentPath).payload,
  );

  @override
  Future<KontaktMutationResult> removeLibrary(KontaktLibrary library) =>
      _executeMutation(KontaktMutationRequest.remove(library).payload);

  @override
  Future<KontaktMutationResult> upsertLibrary(
    KontaktLibraryCandidate candidate,
  ) => _executeMutation(candidate.toUpsertRequest());

  File get _helperFile => File(
    '${File(Platform.resolvedExecutable).parent.path}'
    '${Platform.pathSeparator}KontaktLibraryHelper.ps1',
  );

  Future<KontaktMutationResult> _executeMutation(
    Map<String, Object> request,
  ) async {
    final helper = _helperFile;
    if (!await helper.exists()) {
      throw PlatformException(
        code: 'helper_unavailable',
        message: 'The Windows administrator helper is missing.',
      );
    }

    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'klm-mutation-',
    );
    final requestFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}request.json',
    );
    final responseFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}response.json',
    );
    try {
      final requestBytes = utf8.encode(jsonEncode(request));
      if (requestBytes.length > 2500000) {
        throw PlatformException(
          code: 'mutation_request_too_large',
          message: 'The mutation request is too large.',
        );
      }
      await requestFile.writeAsBytes(requestBytes, flush: true);
      final digest = sha256.convert(requestBytes).toString();
      final process = await Process.run('powershell.exe', [
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        _elevatedHelperLauncher,
        helper.path,
        requestFile.path,
        digest,
        responseFile.path,
      ]);

      Map<String, dynamic>? response;
      if (await responseFile.exists()) {
        final value = jsonDecode(await responseFile.readAsString());
        if (value is Map<String, dynamic>) response = value;
      }
      final errorMessage = response?['errorMessage'] as String?;
      if (process.exitCode != 0 || errorMessage != null) {
        final stderr = (process.stderr as String).trim();
        throw PlatformException(
          code: response?['errorCode'] as String? ?? 'authorization_cancelled',
          message:
              errorMessage ??
              (stderr.isEmpty
                  ? 'The administrator operation was cancelled or failed.'
                  : stderr),
        );
      }
      if (response == null) {
        throw PlatformException(
          code: 'empty_helper_response',
          message: 'The administrator helper returned no response.',
        );
      }
      return KontaktMutationResult.fromMap(response);
    } finally {
      await temporaryDirectory.delete(recursive: true);
    }
  }

  static const _elevatedHelperLauncher = r'''
$ErrorActionPreference = 'Stop'
$helperArguments = @(
  '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
  '-File', ('"' + $args[0] + '"'),
  '-Mode', 'mutation',
  '-RequestPath', ('"' + $args[1] + '"'),
  '-RequestSha256', $args[2],
  '-ResponsePath', ('"' + $args[3] + '"')
)
$elevated = Start-Process -FilePath 'powershell.exe' -Verb RunAs `
  -ArgumentList $helperArguments -Wait -PassThru
exit $elevated.ExitCode
''';

  Future<T> _classicOrderUnsupported<T>() {
    throw UnsupportedError(
      'Classic library ordering is not available on Windows.',
    );
  }
}
