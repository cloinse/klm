import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kontakt_library_manager/core/models/kontakt_library.dart';
import 'package:kontakt_library_manager/core/validation/library_validator.dart';

void main() {
  const validator = LibraryValidator();

  test('detecta registros modernos y ruta ausentes', () {
    const library = KontaktLibrary(
      id: 'test',
      name: 'Test Library',
      regKey: 'Test Library',
      snpid: 'ABC',
      sources: {
        RegistrationSource.serviceCenter,
        RegistrationSource.preferences,
      },
    );

    final result = validator.validate([library]).single;
    final codes = result.issues.map((issue) => issue.code);

    expect(codes, contains('missing_installed_product'));
    expect(codes, contains('missing_content_path'));
    expect(result.health, LibraryHealth.error);
  });

  test('detecta SNPID duplicado', () {
    const first = KontaktLibrary(id: 'first', name: 'First', snpid: 'ABC');
    const second = KontaktLibrary(id: 'second', name: 'Second', snpid: 'abc');

    final result = validator.validate([first, second]);

    expect(
      result.every(
        (library) =>
            library.issues.any((issue) => issue.code == 'duplicate_snpid'),
      ),
      isTrue,
    );
  });

  test('detecta bibliotecas ocultas por Visibility', () {
    final library = KontaktLibrary(
      id: 'hidden',
      name: 'Hidden Library',
      regKey: 'Hidden Library',
      snpid: 'HID',
      contentPath: Directory.systemTemp.path,
      visibility: 7,
      sources: {
        RegistrationSource.serviceCenter,
        RegistrationSource.preferences,
        RegistrationSource.installedProducts,
      },
    );

    final result = validator.validate([library]).single;

    expect(result.health, LibraryHealth.warning);
    expect(
      result.issues.map((issue) => issue.code),
      contains('hidden_in_kontakt'),
    );
  });

  test('comprueba rutas en paralelo durante la validación asíncrona', () async {
    const libraries = [
      KontaktLibrary(id: 'first', name: 'First', contentPath: r'C:\First'),
      KontaktLibrary(id: 'second', name: 'Second', contentPath: r'C:\Second'),
    ];
    final stopwatch = Stopwatch()..start();

    final result = await validator.validateAsync(
      libraries,
      pathExists: (path) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return true;
      },
    );
    stopwatch.stop();

    expect(stopwatch.elapsedMilliseconds, lessThan(180));
    expect(
      result.expand((library) => library.issues).map((issue) => issue.code),
      isNot(contains('content_offline')),
    );
  });

  test('limita la espera de una ruta desconectada', () async {
    const library = KontaktLibrary(
      id: 'offline',
      name: 'Offline',
      contentPath: r'Z:\Offline',
    );

    final result = await validator.validateAsync(
      const [library],
      pathCheckTimeout: const Duration(milliseconds: 20),
      pathExists: (path) =>
          Future<bool>.delayed(const Duration(seconds: 1), () => true),
    );

    expect(
      result.single.issues.map((issue) => issue.code),
      contains('content_unavailable'),
    );
  });

  test('separa acceso denegado de una ruta offline', () async {
    const library = KontaktLibrary(
      id: 'protected',
      name: 'Protected',
      contentPath: '/Volumes/Protected/Library',
    );

    final result = await validator.validateAsync(const [
      library,
    ], pathProbe: (_) async => ContentPathAccess.permissionDenied);
    final codes = result.single.issues.map((issue) => issue.code);

    expect(codes, contains('content_permission_denied'));
    expect(codes, isNot(contains('content_offline')));
    expect(result.single.health, LibraryHealth.warning);
  });

  test('limita la concurrencia al comprobar inventarios grandes', () async {
    final libraries = List<KontaktLibrary>.generate(
      40,
      (index) => KontaktLibrary(
        id: 'library-$index',
        name: 'Library $index',
        contentPath: '/Volumes/Libraries/$index',
      ),
    );
    var active = 0;
    var maximumActive = 0;

    await validator.validateAsync(
      libraries,
      maxConcurrentPathChecks: 3,
      pathProbe: (_) async {
        active++;
        if (active > maximumActive) maximumActive = active;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        active--;
        return ContentPathAccess.available;
      },
    );

    expect(maximumActive, 3);
  });
}
