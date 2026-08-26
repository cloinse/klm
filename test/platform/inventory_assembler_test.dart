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

  test('permite que una fuente autoritativa reemplace una ruta anterior', () {
    final assembler = InventoryAssembler()
      ..add(
        name: 'Test Library',
        regKey: 'TestLibrary',
        contentPath: '/Volumes/Old/Test Library',
        source: RegistrationSource.preferences,
      )
      ..add(
        name: 'TestLibrary',
        contentPath: '/Volumes/Current/Test Library',
        preferContentPath: true,
        source: RegistrationSource.installedProducts,
      );

    final library = assembler.build().single;
    expect(library.regKey, 'TestLibrary');
    expect(library.contentPath, '/Volumes/Current/Test Library');
    expect(
      library.sources,
      containsAll([
        RegistrationSource.preferences,
        RegistrationSource.installedProducts,
      ]),
    );
  });

  test('permite que una fuente autoritativa reemplace sus metadatos', () {
    final assembler = InventoryAssembler()
      ..add(
        name: 'Old Name',
        regKey: 'Old Name',
        snpid: 'OLD',
        visibility: 7,
        userListIndex: 9,
        source: RegistrationSource.serviceCenter,
      )
      ..add(
        name: 'Current Name',
        regKey: 'Old Name',
        snpid: 'CURRENT',
        visibility: 3,
        userListIndex: 2,
        preferValues: true,
        source: RegistrationSource.windowsRegistry,
      );

    final library = assembler.build().single;
    expect(library.name, 'Current Name');
    expect(library.snpid, 'CURRENT');
    expect(library.visibility, 3);
    expect(library.userListIndex, 2);
  });
}
