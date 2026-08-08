import 'package:flutter_test/flutter_test.dart';
import 'package:kontakt_library_manager/core/models/kontakt_library.dart';
import 'package:kontakt_library_manager/platform/inventory_assembler.dart';

void main() {
  test('limpia el SNPID sin cambiar su capitalización', () {
    final assembler = InventoryAssembler()
      ..add(
        name: 'Test Library',
        snpid: ' aBc ',
        source: RegistrationSource.serviceCenter,
      );

    expect(assembler.build().single.snpid, 'aBc');
  });
}
