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
    const library = KontaktLibrary(
      id: 'hidden',
      name: 'Hidden Library',
      regKey: 'Hidden Library',
      snpid: 'HID',
      contentPath: '/tmp',
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
}
