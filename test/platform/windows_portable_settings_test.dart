import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kontakt_library_manager/core/models/kontakt_library.dart';
import 'package:kontakt_library_manager/core/models/kontakt_mutation.dart';
import 'package:kontakt_library_manager/platform/windows/windows_kontakt_platform.dart';
import 'package:kontakt_library_manager/platform/windows/windows_portable_settings.dart';

void main() {
  late Directory temporaryRoot;
  late Directory contentDirectory;
  late File settingsFile;

  setUp(() async {
    temporaryRoot = await Directory.systemTemp.createTemp('klm-portable-');
    contentDirectory = Directory(
      '${temporaryRoot.path}${Platform.pathSeparator}Libraries${Platform.pathSeparator}Portable Piano',
    )..createSync(recursive: true);
    settingsFile =
        File(
            '${temporaryRoot.path}${Platform.pathSeparator}UserData${Platform.pathSeparator}Settings.cfg',
          )
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(
            '[Portable Piano]\n'
            'Name=sz:Portable Piano\n'
            'SNPID=sz:PPI\n'
            'ContentDir=sz:.\\Libraries\\Portable Piano\n'
            'Visibility=dw:3\n'
            'UserListIndex=dw:1\n',
          );
  });

  tearDown(() async {
    if (await temporaryRoot.exists()) {
      await temporaryRoot.delete(recursive: true);
    }
  });

  test('lee solo las librerías de Settings.cfg en modo portable', () async {
    final platform = WindowsKontaktPlatform(
      portableSupport: WindowsPortableSupport(
        enabled: true,
        rootPath: temporaryRoot.path,
      ),
    );

    final snapshot = await platform.scanLibraries();

    expect(snapshot.diagnostics, isEmpty);
    expect(snapshot.libraries, hasLength(1));
    expect(snapshot.libraries.single.name, 'Portable Piano');
    expect(
      snapshot.libraries.single.sources,
      contains(RegistrationSource.portableSettings),
    );
    expect(
      snapshot.libraries.single.contentPath,
      contentDirectory.resolveSymbolicLinksSync(),
    );
    expect(snapshot.libraries.single.issues, isEmpty);
  });

  test('agrega y reubica usando ContentDir relativo al portable', () async {
    final store = PortableSettingsStore(temporaryRoot.path);
    final addedDirectory = Directory(
      '${temporaryRoot.path}${Platform.pathSeparator}Libraries${Platform.pathSeparator}Portable Strings',
    )..createSync(recursive: true);
    const metadata = ProductMetadata(
      name: 'Portable Strings',
      regKey: 'Portable Strings',
      snpid: 'PST',
    );
    final candidate = KontaktLibraryCandidate(
      contentPath: addedDirectory.path,
      metadataPath: 'unused',
      metadata: metadata,
      productHintsXml: '<ProductHints />',
    );

    await store.upsert(candidate);
    var contents = settingsFile.readAsStringSync();
    expect(contents, contains(r'ContentDir=sz:.\Libraries\Portable Strings'));
    expect(contents, isNot(contains(temporaryRoot.path)));

    await store.relocate(
      const KontaktLibrary(
        id: 'portable-strings',
        name: 'Portable Strings',
        regKey: 'Portable Strings',
        snpid: 'PST',
        sources: {RegistrationSource.portableSettings},
      ),
      contentDirectory.path,
    );
    contents = settingsFile.readAsStringSync();
    expect(contents, contains(r'ContentDir=sz:.\Libraries\Portable Piano'));
    expect(contents, isNot(contains(temporaryRoot.path)));
  });

  test('persiste el modo y la ruta seleccionada', () async {
    SharedPreferences.setMockInitialValues({});
    final support = await WindowsPortableSupport.load();

    await support.configure(enabled: true, rootPath: temporaryRoot.path);
    final restored = await WindowsPortableSupport.load();

    expect(restored.enabled, isTrue);
    expect(restored.rootPath, temporaryRoot.path);
  });
}
