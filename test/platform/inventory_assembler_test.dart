import 'package:flutter_test/flutter_test.dart';
import 'package:kontakt_library_manager/core/models/kontakt_library.dart';
import 'package:kontakt_library_manager/platform/inventory_assembler.dart';

void main() {
  test('normaliza los SNPID del inventario a mayúsculas', () {
    final assembler = InventoryAssembler()
      ..add(
        name: 'Test Library',
        snpid: ' aBc ',
        source: RegistrationSource.serviceCenter,
      );

    expect(assembler.build().single.snpid, 'ABC');
  });
}
