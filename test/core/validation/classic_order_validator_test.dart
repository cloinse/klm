import 'package:flutter_test/flutter_test.dart';
import 'package:kontakt_library_manager/core/models/kontakt_library.dart';
import 'package:kontakt_library_manager/core/validation/classic_order_validator.dart';

void main() {
  const validator = ClassicOrderValidator();

  test('accepts a safe unique classic order', () {
    expect(
      () => validator.validate(const [
        KontaktLibrary(id: 'alpha', name: 'Alpha', regKey: 'Alpha'),
        KontaktLibrary(id: 'beta', name: 'Beta', regKey: 'Beta'),
      ]),
      returnsNormally,
    );
  });

  test('identifies the library responsible for an unsafe order value', () {
    expect(
      () => validator.validate(const [
        KontaktLibrary(id: 'unsafe', name: 'Unsafe', regKey: '../Unsafe'),
      ]),
      throwsA(
        isA<ClassicOrderValidationException>()
            .having((error) => error.libraryName, 'libraryName', 'Unsafe')
            .having((error) => error.reason, 'reason', contains('unsafe')),
      ),
    );
  });

  test('rejects duplicate RegKeys case-insensitively', () {
    expect(
      () => validator.validate(const [
        KontaktLibrary(id: 'one', name: 'One', regKey: 'Duplicate'),
        KontaktLibrary(id: 'two', name: 'Two', regKey: 'duplicate'),
      ]),
      throwsA(
        isA<ClassicOrderValidationException>().having(
          (error) => error.libraryName,
          'libraryName',
          'Two',
        ),
      ),
    );
  });
}
