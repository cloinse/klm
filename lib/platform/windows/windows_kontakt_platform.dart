import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kontakt_library_manager/core/metadata/product_hints_parser.dart';
import 'package:kontakt_library_manager/core/models/kontakt_library.dart';
import 'package:kontakt_library_manager/core/models/kontakt_mutation.dart';
import 'package:kontakt_library_manager/core/validation/library_validator.dart';
import 'package:kontakt_library_manager/core/validation/classic_order_validator.dart';
import 'package:kontakt_library_manager/features/mutations/library_candidate_scanner.dart';
import 'package:kontakt_library_manager/platform/inventory_assembler.dart';
import 'package:kontakt_library_manager/platform/kontakt_platform.dart';
import 'package:kontakt_library_manager/platform/windows/windows_native_mutation_codec.dart';
import 'package:kontakt_library_manager/platform/windows/windows_portable_settings.dart';

class WindowsKontaktPlatform implements KontaktPlatform {
  static const _registryChannel = MethodChannel(
    'com.juanayala.kontaktLibraryManager/windows_registry',
  );
  static const _hiddenPowerShellArguments = <String>[
    '-NoLogo',
    '-NoProfile',
    '-NonInteractive',
    '-WindowStyle',
    'Hidden',
    '-ExecutionPolicy',
    'Bypass',
  ];

  WindowsKontaktPlatform({
    ProductHintsParser parser = const ProductHintsParser(),
    LibraryValidator validator = const LibraryValidator(),
    LibraryCandidateScanner candidateScanner = const LibraryCandidateScanner(),
    WindowsPortableSupport? portableSupport,
    this.serviceCenterPath,
    this.installedProductsPath,
  }) : _parser = parser,
       _validator = validator,
       _candidateScanner = candidateScanner,
       portableSupport = portableSupport ?? WindowsPortableSupport();

  final ProductHintsParser _parser;
  final LibraryValidator _validator;
  final LibraryCandidateScanner _candidateScanner;
  final ClassicOrderValidator _classicOrderValidator =
      const ClassicOrderValidator();
  final WindowsPortableSupport portableSupport;
  final String? serviceCenterPath;
  final String? installedProductsPath;

  bool get _portableMode => portableSupport.enabled;

  @override
  PlatformCapabilities get capabilities => const PlatformCapabilities(
    platformName: 'Windows',
    canReadInventory: true,
    privilegedMutationsAvailable: true,
    registryLayoutVerified: true,
    canManageClassicOrder: true,
  );

  @override
  Future<InventorySnapshot> scanLibraries() async {
    if (_portableMode) return _scanPortableLibraries();

    return _scanStandardLibraries();
  }

  Future<InventorySnapshot> _scanStandardLibraries() async {
    final totalStopwatch = Stopwatch()..start();
    final assembler = InventoryAssembler();
    final diagnostics = <InventoryDiagnostic>[];
    final knownRegKeys = <String>{};
    final excludedRegKeys = <String>{};
    final registryResult = _readRegistryRecords();
    final programFiles =
        Platform.environment['PROGRAMFILES'] ?? r'C:\Program Files';
    final publicDirectory =
        Platform.environment['PUBLIC'] ?? r'C:\Users\Public';

    final xmlStopwatch = Stopwatch()..start();
    await _readXmlDirectory(
      Directory(
        serviceCenterPath ??
            '$programFiles${Platform.pathSeparator}Common Files${Platform.pathSeparator}Native Instruments${Platform.pathSeparator}Service Center',
      ),
      assembler,
      knownRegKeys,
      excludedRegKeys,
    );
    xmlStopwatch.stop();
    final jsonStopwatch = Stopwatch()..start();
    await _readJsonDirectory(
      Directory(
        installedProductsPath ??
            '$publicDirectory${Platform.pathSeparator}Documents${Platform.pathSeparator}Native Instruments${Platform.pathSeparator}installed_products',
      ),
      assembler,
      diagnostics,
      knownRegKeys,
      excludedRegKeys,
    );
    jsonStopwatch.stop();
    final loadedRegistry = await registryResult;
    diagnostics.addAll(loadedRegistry.diagnostics);
    _addRegistryRecords(
      loadedRegistry.records,
      assembler,
      knownRegKeys,
      excludedRegKeys,
    );

    final validationStopwatch = Stopwatch()..start();
    final libraries = await _validator.validateAsync(assembler.build())
      ..sort(
        (left, right) =>
            left.name.toLowerCase().compareTo(right.name.toLowerCase()),
      );
    validationStopwatch.stop();
    totalStopwatch.stop();
    if (!kReleaseMode) {
      debugPrint(
        '[KLM inventory] XML=${xmlStopwatch.elapsedMilliseconds}ms '
        'JSON=${jsonStopwatch.elapsedMilliseconds}ms '
        'Registry=${loadedRegistry.elapsed.inMilliseconds}ms '
        '(${loadedRegistry.source}) '
        'Validation=${validationStopwatch.elapsedMilliseconds}ms '
        'Total=${totalStopwatch.elapsedMilliseconds}ms '
        'Libraries=${libraries.length}',
      );
    }
    return InventorySnapshot(
      libraries: libraries,
      diagnostics: diagnostics,
      scannedAt: DateTime.now(),
    );
  }

  Future<InventorySnapshot> _scanPortableLibraries() async {
    final assembler = InventoryAssembler();
    final diagnostics = <InventoryDiagnostic>[];
    final rootPath = portableSupport.rootPath;
    if (rootPath == null || rootPath.trim().isEmpty) {
      diagnostics.add(
        const InventoryDiagnostic(
          code: 'portable_path_missing',
          title: 'Ruta de Kontakt Portable no configurada',
          message: 'Selecciona la carpeta de Kontakt Portable en Ajustes.',
          severity: IssueSeverity.error,
        ),
      );
    } else {
      try {
        final store = PortableSettingsStore(rootPath);
        final records = await store.readRecords();
        for (final record in records) {
          final rawPath = record.contentPath;
          assembler.add(
            name: record.name,
            regKey: record.section,
            snpid: record.snpid,
            contentPath: rawPath == null
                ? null
                : store.resolveContentPath(rawPath),
            visibility: record.visibility,
            userListIndex: record.userListIndex,
            source: RegistrationSource.portableSettings,
          );
        }
      } catch (error) {
        diagnostics.add(
          InventoryDiagnostic(
            code: 'portable_settings_failed',
            title: 'No se pudo leer Kontakt Portable',
            message: error.toString(),
            severity: IssueSeverity.error,
            detail: error.toString(),
          ),
        );
      }
    }

    final libraries = await _validator.validateAsync(assembler.build())
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
    Set<String> excludedRegKeys,
  ) async {
    if (!await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.xml')) {
        continue;
      }
      try {
        final metadata = _parser.parseBytes(await entity.readAsBytes());
        if (!metadata.isKontaktLibraryMetadata) {
          excludedRegKeys
            ..add(metadata.regKey.toLowerCase())
            ..add(metadata.name.toLowerCase());
          continue;
        }
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
    Set<String> excludedRegKeys,
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
        final snpid = decoded['SNPID'] as String?;
        final contentPath =
            (decoded['ContentDir'] ?? decoded['contentDir']) as String?;
        final identity = (regKey ?? name).toLowerCase();
        if (excludedRegKeys.contains(identity) ||
            excludedRegKeys.contains(name.toLowerCase())) {
          continue;
        }
        if (!knownRegKeys.contains(identity) &&
            (snpid?.trim().isEmpty != false ||
                contentPath?.trim().isEmpty != false)) {
          continue;
        }
        knownRegKeys.add(identity);
        assembler.add(
          name: name,
          regKey: regKey,
          snpid: snpid,
          contentPath: contentPath,
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

  Future<_RegistryReadResult> _readRegistryRecords() async {
    final stopwatch = Stopwatch()..start();
    try {
      final rawRecords =
          await _registryChannel.invokeListMethod<Object?>('readInventory') ??
          const <Object?>[];
      stopwatch.stop();
      return _RegistryReadResult(
        records: _decodeRegistryRecords(rawRecords),
        source: 'native',
        elapsed: stopwatch.elapsed,
      );
    } on MissingPluginException {
      final fallback = await _readRegistryRecordsWithPowerShell();
      stopwatch.stop();
      return fallback.withElapsed(stopwatch.elapsed);
    } on PlatformException {
      final fallback = await _readRegistryRecordsWithPowerShell();
      stopwatch.stop();
      return fallback.withElapsed(stopwatch.elapsed);
    }
  }

  Future<_RegistryReadResult> _readRegistryRecordsWithPowerShell() async {
    final helper = _helperFile;
    if (!await helper.exists()) {
      return const _RegistryReadResult(
        source: 'powershell',
        diagnostics: <InventoryDiagnostic>[
          InventoryDiagnostic(
            code: 'windows_helper_missing',
            title: 'Componente de Windows no encontrado',
            message: 'No se pudo leer el Registro de Native Instruments.',
            severity: IssueSeverity.warning,
          ),
        ],
      );
    }

    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'klm-registry-',
    );
    final responseFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}response.json',
    );
    try {
      final process = await Process.run('powershell.exe', [
        ..._hiddenPowerShellArguments,
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
      final rawRecords = decoded is List ? decoded : <Object?>[decoded];
      return _RegistryReadResult(
        records: _decodeRegistryRecords(rawRecords.cast<Object?>()),
        source: 'powershell',
      );
    } catch (error) {
      return _RegistryReadResult(
        source: 'powershell',
        diagnostics: <InventoryDiagnostic>[
          InventoryDiagnostic(
            code: 'windows_registry_failed',
            title: 'No se pudo leer el Registro',
            message: error.toString(),
            severity: IssueSeverity.warning,
            detail: error.toString(),
          ),
        ],
      );
    } finally {
      await temporaryDirectory.delete(recursive: true);
    }
  }

  List<Map<String, Object?>> _decodeRegistryRecords(List<Object?> rawRecords) {
    final records = <Map<String, Object?>>[];
    for (final rawRecord in rawRecords) {
      if (rawRecord is! Map) continue;
      final record = <String, Object?>{};
      for (final entry in rawRecord.entries) {
        final key = entry.key;
        if (key is String) record[key] = entry.value;
      }
      records.add(record);
    }
    return records;
  }

  void _addRegistryRecords(
    List<Map<String, Object?>> records,
    InventoryAssembler assembler,
    Set<String> knownRegKeys,
    Set<String> excludedRegKeys,
  ) {
    for (final record in records) {
      final regKey = record['regKey'] as String?;
      final snpid = record['snpid'] as String?;
      final contentPath = record['contentPath'] as String?;
      final isKnownLibrary =
          regKey != null && knownRegKeys.contains(regKey.trim().toLowerCase());
      final isExcluded =
          regKey != null &&
          excludedRegKeys.contains(regKey.trim().toLowerCase());
      final hasLibraryIdentity =
          snpid?.trim().isNotEmpty == true &&
          contentPath?.trim().isNotEmpty == true;
      if (regKey == null ||
          isExcluded ||
          (!isKnownLibrary && !hasLibraryIdentity)) {
        continue;
      }
      assembler.add(
        name: record['name'] as String? ?? regKey,
        regKey: regKey,
        snpid: snpid,
        contentPath: contentPath,
        visibility: _intValue(record['visibility']),
        userListIndex: _intValue(record['userListIndex']),
        source: RegistrationSource.windowsRegistry,
      );
    }
  }

  int? _intValue(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  @override
  Future<void> revealInFileManager(String path) async {
    final result = await Process.run('explorer.exe', ['/select,$path']);
    if (result.exitCode != 0) {
      throw FileSystemException('El Explorador no pudo mostrar la ruta.', path);
    }
  }

  @override
  Future<void> saveClassicLibraryOrder(List<KontaktLibrary> libraries) async {
    _classicOrderValidator.validate(libraries);
    if (_portableMode) {
      final rootPath = portableSupport.rootPath;
      if (rootPath == null) {
        throw const PortableSettingsException(
          'La ruta de Kontakt Portable no está configurada.',
        );
      }
      await PortableSettingsStore(rootPath).saveClassicOrder(libraries);
      return;
    }

    if (libraries.length > 10000) {
      throw const FormatException('The classic Kontakt order is too large.');
    }

    final entries = <Map<String, Object>>[];
    for (var index = 0; index < libraries.length; index++) {
      final library = libraries[index];
      final regKey = library.regKey ?? library.name;
      if (!_isSafeRegistryComponent(regKey) ||
          !_isSafeRegistryComponent(library.name)) {
        throw FormatException('Unsafe Kontakt registry key: $regKey');
      }
      entries.add({
        'regKey': regKey,
        'name': library.name,
        'snpid': ?library.snpid,
        // Kontakt's classic browser stores positions as a one-based sequence.
        'userListIndex': index + 1,
      });
    }

    try {
      await _registryChannel.invokeMethod<void>('writeClassicOrder', entries);
      return;
    } on MissingPluginException {
      // Older runners continue to use the PowerShell implementation.
    }

    await _executeHelperRequest(
      mode: 'classicOrder',
      temporaryDirectoryPrefix: 'klm-order-',
      request: {'version': 1, 'entries': entries},
    );
  }

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
      _portableMode || await _helperFile.exists()
      ? PrivilegedHelperStatus.enabled
      : PrivilegedHelperStatus.unavailable;

  @override
  Future<KontaktMutationResult> relocateLibrary(
    KontaktLibrary library,
    String contentPath,
  ) async {
    if (_portableMode) {
      final rootPath = portableSupport.rootPath;
      if (rootPath == null) {
        throw const PortableSettingsException(
          'La ruta de Kontakt Portable no está configurada.',
        );
      }
      await PortableSettingsStore(rootPath).relocate(library, contentPath);
      return KontaktMutationResult(
        operation: KontaktMutationType.relocate,
        libraryName: library.name,
        changedPaths: [PortableSettingsStore(rootPath).settingsPath],
      );
    }
    return _executeMutation(
      KontaktMutationRequest.relocate(library, contentPath).payload,
    );
  }

  @override
  Future<KontaktMutationResult> removeLibrary(KontaktLibrary library) async {
    if (_portableMode) {
      final rootPath = portableSupport.rootPath;
      if (rootPath == null) {
        throw const PortableSettingsException(
          'La ruta de Kontakt Portable no está configurada.',
        );
      }
      await PortableSettingsStore(rootPath).remove(library);
      return KontaktMutationResult(
        operation: KontaktMutationType.remove,
        libraryName: library.name,
        changedPaths: [PortableSettingsStore(rootPath).settingsPath],
      );
    }
    return _executeMutation(KontaktMutationRequest.remove(library).payload);
  }

  @override
  Future<List<KontaktMutationResult>> removeLibraries(
    List<KontaktLibrary> libraries,
  ) async {
    if (libraries.isEmpty) return const [];
    if (_portableMode || libraries.length == 1) {
      final results = <KontaktMutationResult>[];
      for (final library in libraries) {
        results.add(await removeLibrary(library));
      }
      return results;
    }
    return _executeMutations(
      libraries
          .map((library) => KontaktMutationRequest.remove(library).payload)
          .toList(),
    );
  }

  @override
  Future<KontaktMutationResult> upsertLibrary(
    KontaktLibraryCandidate candidate,
  ) async {
    if (_portableMode) {
      final rootPath = portableSupport.rootPath;
      if (rootPath == null) {
        throw const PortableSettingsException(
          'La ruta de Kontakt Portable no está configurada.',
        );
      }
      await PortableSettingsStore(rootPath).upsert(candidate);
      return KontaktMutationResult(
        operation: KontaktMutationType.upsert,
        libraryName: candidate.metadata.name,
        changedPaths: [PortableSettingsStore(rootPath).settingsPath],
      );
    }
    return _executeMutation(candidate.toUpsertRequest());
  }

  @override
  Future<List<KontaktMutationResult>> upsertLibraries(
    List<KontaktLibraryCandidate> candidates,
  ) async {
    if (candidates.isEmpty) return const [];
    if (_portableMode || candidates.length == 1) {
      final results = <KontaktMutationResult>[];
      for (final candidate in candidates) {
        results.add(await upsertLibrary(candidate));
      }
      return results;
    }
    return _executeMutations(
      candidates.map((candidate) => candidate.toUpsertRequest()).toList(),
    );
  }

  File get _helperFile => File(
    '${File(Platform.resolvedExecutable).parent.path}'
    '${Platform.pathSeparator}KontaktLibraryHelper.ps1',
  );

  File get _elevatorFile => File(
    '${File(Platform.resolvedExecutable).parent.path}'
    '${Platform.pathSeparator}KontaktLibraryElevator.exe',
  );

  Future<KontaktMutationResult> _executeMutation(
    Map<String, Object> request,
  ) async {
    final response = await _executeHelperRequest(
      mode: 'mutation',
      temporaryDirectoryPrefix: 'klm-mutation-',
      request: request,
    );
    return KontaktMutationResult.fromMap(response);
  }

  Future<List<KontaktMutationResult>> _executeMutations(
    List<Map<String, Object>> operations,
  ) async {
    final response = await _executeHelperRequest(
      mode: 'mutation',
      temporaryDirectoryPrefix: 'klm-mutation-batch-',
      request: KontaktMutationRequest.batch(operations).payload,
    );
    return KontaktMutationResult.listFromMap(response);
  }

  Future<Map<String, dynamic>> _executeHelperRequest({
    required String mode,
    required String temporaryDirectoryPrefix,
    required Map<String, Object> request,
  }) async {
    final helper = _helperFile;
    if (!await helper.exists()) {
      throw PlatformException(
        code: 'helper_unavailable',
        message: 'The Windows helper is missing.',
      );
    }

    final temporaryDirectory = await Directory.systemTemp.createTemp(
      temporaryDirectoryPrefix,
    );
    final requestFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}request.json',
    );
    final nativeRequestFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}request.bin',
    );
    final responseFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}response.json',
    );
    try {
      final elevator = _elevatorFile;
      final useNativeMutation = mode == 'mutation' && await elevator.exists();
      late final ProcessResult process;
      if (useNativeMutation) {
        late final List<int> nativeRequestBytes;
        try {
          nativeRequestBytes = WindowsNativeMutationCodec.encode(request);
        } on FormatException catch (error) {
          throw PlatformException(
            code: 'mutation_request_invalid',
            message: error.message,
          );
        }
        await nativeRequestFile.writeAsBytes(nativeRequestBytes, flush: true);
        final nativeDigest = sha256.convert(nativeRequestBytes).toString();
        process = await Process.run(elevator.path, [
          '--native-mutation',
          nativeRequestFile.path,
          nativeDigest,
          responseFile.path,
        ]);
      } else {
        final requestBytes = utf8.encode(jsonEncode(request));
        if (requestBytes.length > 2500000) {
          throw PlatformException(
            code: 'mutation_request_too_large',
            message: 'The mutation request is too large.',
          );
        }
        await requestFile.writeAsBytes(requestBytes, flush: true);
        final digest = sha256.convert(requestBytes).toString();
        process = await Process.run('powershell.exe', [
          ..._hiddenPowerShellArguments,
          '-File',
          helper.path,
          '-Mode',
          mode,
          '-RequestPath',
          requestFile.path,
          '-RequestSha256',
          digest,
          '-ResponsePath',
          responseFile.path,
        ]);
      }

      Map<String, dynamic>? response;
      if (await responseFile.exists()) {
        final value = jsonDecode(await responseFile.readAsString());
        if (value is Map<String, dynamic>) response = value;
      }
      final errorMessage = response?['errorMessage'] as String?;
      if (process.exitCode != 0 || errorMessage != null) {
        throw PlatformException(
          code: response?['errorCode'] as String? ?? 'authorization_cancelled',
          message:
              errorMessage ??
              'The Windows helper operation was cancelled or failed.',
        );
      }
      if (response == null) {
        throw PlatformException(
          code: 'empty_helper_response',
          message: 'The Windows helper returned no response.',
        );
      }
      return response;
    } finally {
      await temporaryDirectory.delete(recursive: true);
    }
  }

  bool _isSafeRegistryComponent(String value) =>
      value.isNotEmpty &&
      value.length <= 255 &&
      value != '.' &&
      value != '..' &&
      !value.endsWith('.') &&
      !value.endsWith(' ') &&
      !value.contains('/') &&
      !value.contains('\\') &&
      !value.contains('\u0000') &&
      !value.contains('\n') &&
      !value.contains('\r');
}

class _RegistryReadResult {
  const _RegistryReadResult({
    this.records = const <Map<String, Object?>>[],
    this.diagnostics = const <InventoryDiagnostic>[],
    this.source = 'unknown',
    this.elapsed = Duration.zero,
  });

  final List<Map<String, Object?>> records;
  final List<InventoryDiagnostic> diagnostics;
  final String source;
  final Duration elapsed;

  _RegistryReadResult withElapsed(Duration value) => _RegistryReadResult(
    records: records,
    diagnostics: diagnostics,
    source: source,
    elapsed: value,
  );
}
