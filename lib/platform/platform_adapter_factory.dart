import 'dart:io';

import 'package:kontakt_library_manager/core/models/kontakt_library.dart';
import 'package:kontakt_library_manager/core/models/kontakt_mutation.dart';
import 'package:kontakt_library_manager/platform/kontakt_platform.dart';
import 'package:kontakt_library_manager/platform/macos/macos_kontakt_platform.dart';
import 'package:kontakt_library_manager/platform/windows/windows_kontakt_platform.dart';
import 'package:kontakt_library_manager/platform/windows/windows_portable_settings.dart';

KontaktPlatform createKontaktPlatform({
  WindowsPortableSupport? portableSupport,
}) {
  if (Platform.isMacOS) return MacOSKontaktPlatform();
  if (Platform.isWindows) {
    return WindowsKontaktPlatform(portableSupport: portableSupport);
  }
  return UnsupportedKontaktPlatform(Platform.operatingSystem);
}

class UnsupportedKontaktPlatform implements KontaktPlatform {
  UnsupportedKontaktPlatform(this.operatingSystem);

  final String operatingSystem;

  @override
  PlatformCapabilities get capabilities => PlatformCapabilities(
    platformName: operatingSystem,
    canReadInventory: false,
    privilegedMutationsAvailable: false,
    registryLayoutVerified: false,
    canManageClassicOrder: false,
  );

  @override
  Future<void> revealInFileManager(String path) {
    throw UnsupportedError('Plataforma no compatible: $operatingSystem');
  }

  @override
  Future<void> saveClassicLibraryOrder(List<KontaktLibrary> libraries) =>
      _unsupported();

  @override
  Future<List<KontaktLibraryCandidate>> chooseLibraryCandidates({
    required bool allowMultiple,
  }) => _unsupported();

  @override
  Future<String?> chooseContentDirectory() => _unsupported();

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
  ) => _unsupported();

  @override
  Future<KontaktMutationResult> removeLibrary(KontaktLibrary library) =>
      _unsupported();

  @override
  Future<List<KontaktMutationResult>> removeLibraries(
    List<KontaktLibrary> libraries,
  ) => _unsupported();

  @override
  Future<KontaktMutationResult> upsertLibrary(
    KontaktLibraryCandidate candidate,
  ) => _unsupported();

  @override
  Future<List<KontaktMutationResult>> upsertLibraries(
    List<KontaktLibraryCandidate> candidates,
  ) => _unsupported();

  Future<T> _unsupported<T>() {
    throw UnsupportedError('Platform not supported: $operatingSystem');
  }

  @override
  Future<InventorySnapshot> scanLibraries() async => InventorySnapshot(
    libraries: const [],
    diagnostics: [
      InventoryDiagnostic(
        code: 'unsupported_platform',
        title: 'Plataforma no compatible',
        message: 'El inventario solo está disponible en macOS y Windows.',
        severity: IssueSeverity.error,
      ),
    ],
    scannedAt: DateTime.now(),
  );
}
