import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:kontakt_library_manager/core/metadata/product_hints_parser.dart';
import 'package:kontakt_library_manager/core/models/kontakt_library.dart';
import 'package:kontakt_library_manager/core/models/kontakt_mutation.dart';
import 'package:kontakt_library_manager/core/validation/library_validator.dart';
import 'package:kontakt_library_manager/features/mutations/library_candidate_scanner.dart';
import 'package:kontakt_library_manager/platform/inventory_assembler.dart';
import 'package:kontakt_library_manager/platform/kontakt_platform.dart';

class MacOSKontaktPlatform implements KontaktPlatform {
  MacOSKontaktPlatform({
    ProductHintsParser parser = const ProductHintsParser(),
    LibraryValidator validator = const LibraryValidator(),
    LibraryCandidateScanner candidateScanner = const LibraryCandidateScanner(),
    this.serviceCenterPath =
        '/Library/Application Support/Native Instruments/Service Center',
    this.preferencesPath = '/Library/Preferences',
    String? userPreferencesPath,
    this.installedProductsPath =
        '/Users/Shared/Native Instruments/installed_products',
  }) : _parser = parser,
       _validator = validator,
       _candidateScanner = candidateScanner,
       userPreferencesPath =
           userPreferencesPath ??
           '${Platform.environment['HOME'] ?? ''}/Library/Preferences';

  final ProductHintsParser _parser;
  final LibraryValidator _validator;
  final LibraryCandidateScanner _candidateScanner;
  final String serviceCenterPath;
  final String preferencesPath;
  final String userPreferencesPath;
  final String installedProductsPath;

  @override
  PlatformCapabilities get capabilities => const PlatformCapabilities(
    platformName: 'macOS',
    canReadInventory: true,
    privilegedMutationsAvailable: true,
    registryLayoutVerified: true,
    canManageClassicOrder: true,
  );

  @override
  Future<InventorySnapshot> scanLibraries() async {
    final assembler = InventoryAssembler();
    final diagnostics = <InventoryDiagnostic>[];

    await _readServiceCenter(assembler, diagnostics);
    await _readInstalledProducts(assembler, diagnostics);
    await _readPreferences(assembler, diagnostics);
    await _readUserListIndexes(assembler);

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

  Future<void> _readServiceCenter(
    InventoryAssembler assembler,
    List<InventoryDiagnostic> diagnostics,
  ) async {
    final directory = Directory(serviceCenterPath);
    if (!await directory.exists()) {
      diagnostics.add(
        const InventoryDiagnostic(
          code: 'service_center_missing',
          title: 'Service Center no encontrado',
          message: 'No existe la carpeta compartida de Service Center.',
          severity: IssueSeverity.warning,
        ),
      );
      return;
    }

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
      } catch (_) {
        // Service Center también contiene XML de aplicaciones que no son
        // librerías. Se omiten sin convertirlos en falsos positivos.
      }
    }
  }

  Future<void> _readInstalledProducts(
    InventoryAssembler assembler,
    List<InventoryDiagnostic> diagnostics,
  ) async {
    final directory = Directory(installedProductsPath);
    if (!await directory.exists()) {
      diagnostics.add(
        const InventoryDiagnostic(
          code: 'installed_products_missing',
          title: 'Catálogo moderno no encontrado',
          message: 'No existe installed_products para Kontakt 7/8.',
          severity: IssueSeverity.warning,
        ),
      );
      return;
    }

    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) {
        continue;
      }
      try {
        final object = jsonDecode(await entity.readAsString());
        if (object is! Map<String, dynamic>) continue;
        assembler.add(
          name: _stem(entity.path),
          regKey: _stringValue(object, const ['RegKey', 'regKey']),
          snpid: _stringValue(object, const ['SNPID', 'snpid']),
          contentPath: _stringValue(object, const [
            'ContentDir',
            'contentDir',
            'content_path',
          ]),
          source: RegistrationSource.installedProducts,
        );
      } catch (error) {
        diagnostics.add(
          InventoryDiagnostic(
            code: 'invalid_json',
            title: 'JSON ilegible',
            message: '${_fileName(entity.path)}: $error',
            severity: IssueSeverity.warning,
            detail: '${_fileName(entity.path)}: $error',
          ),
        );
      }
    }
  }

  Future<void> _readPreferences(
    InventoryAssembler assembler,
    List<InventoryDiagnostic> diagnostics,
  ) async {
    final directory = Directory(preferencesPath);
    if (!await directory.exists()) return;

    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File ||
          !_fileName(
            entity.path,
          ).toLowerCase().startsWith('com.native-instruments.') ||
          !entity.path.toLowerCase().endsWith('.plist')) {
        continue;
      }
      try {
        final result = await Process.run('/usr/bin/plutil', [
          '-convert',
          'json',
          '-o',
          '-',
          entity.path,
        ]);
        if (result.exitCode != 0) continue;
        final object = jsonDecode(result.stdout as String);
        if (object is! Map<String, dynamic>) continue;
        final name = _stringValue(object, const ['Name', 'name']);
        final snpid = _stringValue(object, const ['SNPID', 'snpid']);
        if (name == null || snpid == null) continue;
        assembler.add(
          name: name,
          regKey: _stringValue(object, const ['RegKey', 'regKey']),
          snpid: snpid,
          contentPath: _stringValue(object, const ['ContentDir', 'contentDir']),
          source: RegistrationSource.preferences,
        );
      } catch (_) {
        // Un PLIST de Native Instruments que no sea de librería es esperado.
      }
    }
  }

  Future<void> _readUserListIndexes(InventoryAssembler assembler) async {
    final directory = Directory(userPreferencesPath);
    if (!await directory.exists()) return;

    await for (final entity in directory.list(followLinks: false)) {
      final fileName = _fileName(entity.path);
      const prefix = 'com.native-instruments.';
      if (entity is! File ||
          !fileName.toLowerCase().startsWith(prefix) ||
          !fileName.toLowerCase().endsWith('.plist')) {
        continue;
      }
      try {
        final result = await Process.run('/usr/bin/plutil', [
          '-convert',
          'json',
          '-o',
          '-',
          entity.path,
        ]);
        if (result.exitCode != 0) continue;
        final object = jsonDecode(result.stdout as String);
        if (object is! Map<String, dynamic>) continue;
        final rawIndex = object['UserListIndex'];
        if (rawIndex is! num) continue;
        final fileRegKey = fileName.substring(
          prefix.length,
          fileName.length - '.plist'.length,
        );
        final regKey =
            _stringValue(object, const ['RegKey', 'regKey', 'Name', 'name']) ??
            fileRegKey;
        if (!_isSafeComponent(regKey)) continue;
        assembler.setUserListIndex(
          regKey: regKey,
          userListIndex: rawIndex.toInt(),
        );
      } catch (_) {
        // Other Native Instruments preferences are unrelated to libraries.
      }
    }
  }

  String? _stringValue(Map<String, dynamic> object, List<String> keys) {
    for (final key in keys) {
      final value = object[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  String _fileName(String path) => path.split('/').last;

  String _stem(String path) {
    final name = _fileName(path);
    return name.toLowerCase().endsWith('.json')
        ? name.substring(0, name.length - 5)
        : name;
  }

  @override
  Future<void> revealInFileManager(String path) async {
    final result = await Process.run('/usr/bin/open', ['-R', path]);
    if (result.exitCode != 0) {
      throw FileSystemException('Finder no pudo mostrar la ruta.', path);
    }
  }

  @override
  Future<void> saveClassicLibraryOrder(List<KontaktLibrary> libraries) async {
    final entries = <Map<String, Object>>[];
    for (var index = 0; index < libraries.length; index++) {
      final library = libraries[index];
      final regKey = library.regKey ?? library.name;
      if (!_isSafeComponent(regKey)) {
        throw FormatException('Unsafe Kontakt RegKey: $regKey');
      }
      entries.add({
        'regKey': regKey,
        'name': library.name,
        if (library.snpid != null) 'snpid': library.snpid!,
        'userListIndex': index,
      });
    }
    await _systemChannel.invokeMethod<void>('saveClassicOrder', {
      'entries': entries,
    });
  }

  static const _systemChannel = MethodChannel(
    'com.juanayala.kontaktLibraryManager/system',
  );

  @override
  Future<PrivilegedHelperStatus> privilegedHelperStatus() async {
    final value = await _systemChannel.invokeMethod<String>('helperStatus');
    return _helperStatus(value);
  }

  @override
  Future<PrivilegedHelperStatus> enablePrivilegedHelper() async {
    final value = await _systemChannel.invokeMethod<String>('enableHelper');
    return _helperStatus(value);
  }

  @override
  Future<List<KontaktLibraryCandidate>> chooseLibraryCandidates({
    required bool allowMultiple,
  }) async {
    final paths =
        await _systemChannel.invokeListMethod<String>('selectDirectories', {
          'allowMultiple': allowMultiple,
        }) ??
        const <String>[];
    return _candidateScanner.scanDirectories(paths);
  }

  @override
  Future<String?> chooseContentDirectory() async {
    final paths =
        await _systemChannel.invokeListMethod<String>('selectDirectories', {
          'allowMultiple': false,
        }) ??
        const <String>[];
    if (paths.isEmpty) return null;
    return Directory(paths.single).resolveSymbolicLinks();
  }

  @override
  Future<KontaktMutationResult> upsertLibrary(
    KontaktLibraryCandidate candidate,
  ) {
    return _executeMutation(candidate.toUpsertRequest());
  }

  @override
  Future<KontaktMutationResult> relocateLibrary(
    KontaktLibrary library,
    String contentPath,
  ) {
    return _executeMutation(
      KontaktMutationRequest.relocate(library, contentPath).payload,
    );
  }

  @override
  Future<KontaktMutationResult> removeLibrary(KontaktLibrary library) async {
    final result = await _executeMutation(
      KontaktMutationRequest.remove(library).payload,
    );
    final regKey = library.regKey;
    final home = Platform.environment['HOME'];
    if (regKey != null && home != null && _isSafeComponent(regKey)) {
      final userPlist = File(
        '$home/Library/Preferences/com.native-instruments.$regKey.plist',
      );
      if (await userPlist.exists()) await userPlist.delete();
    }
    return result;
  }

  Future<KontaktMutationResult> _executeMutation(
    Map<String, Object> request,
  ) async {
    final response = await _systemChannel.invokeMapMethod<Object?, Object?>(
      'executeMutation',
      request,
    );
    if (response == null) {
      throw PlatformException(
        code: 'empty_helper_response',
        message: 'The privileged helper returned no response.',
      );
    }
    return KontaktMutationResult.fromMap(response);
  }

  PrivilegedHelperStatus _helperStatus(String? value) => switch (value) {
    'enabled' => PrivilegedHelperStatus.enabled,
    'notRegistered' => PrivilegedHelperStatus.notRegistered,
    'approvalRequired' => PrivilegedHelperStatus.approvalRequired,
    'unsupported' => PrivilegedHelperStatus.unsupported,
    _ => PrivilegedHelperStatus.unavailable,
  };

  bool _isSafeComponent(String value) =>
      value.isNotEmpty &&
      value != '.' &&
      value != '..' &&
      !value.contains('/') &&
      !value.contains('\\') &&
      !value.contains('\n') &&
      !value.contains('\r');
}
