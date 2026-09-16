import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kontakt_library_manager/core/models/kontakt_library.dart';
import 'package:kontakt_library_manager/core/models/kontakt_mutation.dart';
import 'package:kontakt_library_manager/platform/macos/macos_kontakt_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reconcilia XML, JSON y PLIST como una sola librería', () async {
    if (!Platform.isMacOS) return;
    final root = await Directory.systemTemp.createTemp('klm-adapter-test-');
    addTearDown(() => root.delete(recursive: true));
    final serviceCenter = await Directory('${root.path}/service').create();
    final preferences = await Directory('${root.path}/preferences').create();
    final installed = await Directory('${root.path}/installed').create();
    final userPreferences = await Directory(
      '${root.path}/user-preferences',
    ).create();
    final content = await Directory('${root.path}/content').create();
    final staleContentPath = '${root.path}/old-content-location';

    await File('${serviceCenter.path}/Analog Dreams.xml').writeAsString('''
<ProductHints><Product>
  <Name>Analog Dreams</Name><RegKey>Analog Dreams</RegKey><SNPID>ABC</SNPID>
  <Type>Content</Type>
</Product></ProductHints>
''');
    await File(
      '${serviceCenter.path}/Reaktor Factory Library.xml',
    ).writeAsString('''
<ProductHints><Product>
  <Name>Reaktor Factory Library</Name><RegKey>Reaktor Factory Library</RegKey><SNPID>R01</SNPID>
  <Type>Content</Type><PoweredBy>Reaktor</PoweredBy>
  <Relevance><Application>Reaktor</Application></Relevance>
</Product></ProductHints>
''');
    await File('${serviceCenter.path}/Arturia Plugin.xml').writeAsString('''
<ProductHints><Product>
  <Name>Arturia Plugin</Name><RegKey>Arturia Plugin</RegKey><SNPID>A01</SNPID>
  <Type>Plugin</Type><Company>Arturia</Company>
  <Relevance><Application>Kontakt</Application></Relevance>
</Product></ProductHints>
''');
    await File(
      '${installed.path}/Analog Dreams.json',
    ).writeAsString('{"ContentDir":"${content.path}"}');
    await File('${installed.path}/Arturia Plugin.json').writeAsString(
      '{"RegKey":"Arturia Plugin","SNPID":"A01","ContentDir":"${content.path}"}',
    );
    await File('${installed.path}/Reaktor Factory Library.json').writeAsString(
      '{"RegKey":"Reaktor Factory Library","SNPID":"R01","ContentDir":"${content.path}"}',
    );
    await File(
      '${preferences.path}/com.native-instruments.Analog Dreams.plist',
    ).writeAsString('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Name</key><string>Analog Dreams</string>
  <key>RegKey</key><string>Analog Dreams</string>
  <key>SNPID</key><string>ABC</string>
  <key>ContentDir</key><string>$staleContentPath</string>
  <key>Visibility</key><integer>3</integer>
</dict></plist>
''');
    await File(
      '${preferences.path}/com.native-instruments.Reaktor Factory Library.plist',
    ).writeAsString('''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>Name</key><string>Reaktor Factory Library</string>
  <key>RegKey</key><string>Reaktor Factory Library</string>
  <key>SNPID</key><string>R01</string>
  <key>ContentDir</key><string>${content.path}</string>
  <key>Visibility</key><integer>3</integer>
</dict></plist>
''');
    await File(
      '${preferences.path}/com.native-instruments.Arturia Plugin.plist',
    ).writeAsString('''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>Name</key><string>Arturia Plugin</string>
  <key>RegKey</key><string>Arturia Plugin</string>
  <key>SNPID</key><string>A01</string>
  <key>ContentDir</key><string>${content.path}</string>
  <key>Visibility</key><integer>3</integer>
</dict></plist>
''');
    await File(
      '${userPreferences.path}/com.native-instruments.Analog Dreams.plist',
    ).writeAsString('''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>UserListIndex</key><integer>7</integer>
</dict></plist>
''');

    final adapter = MacOSKontaktPlatform(
      serviceCenterPath: serviceCenter.path,
      preferencesPath: preferences.path,
      userPreferencesPath: userPreferences.path,
      installedProductsPath: installed.path,
    );
    final snapshot = await adapter.scanLibraries();

    expect(snapshot.libraries, hasLength(1));
    final library = snapshot.libraries.single;
    expect(library.name, 'Analog Dreams');
    expect(library.contentPath, content.path);
    expect(library.visibility, 3);
    expect(library.registeredForKontakt6, isTrue);
    expect(library.registeredForKontakt78, isTrue);
    expect(library.health, LibraryHealth.healthy);
    expect(library.userListIndex, 7);
  });

  test(
    'inventories third-party Kontakt libraries without installed_products JSON',
    () async {
      if (!Platform.isMacOS) return;
      final root = await Directory.systemTemp.createTemp('klm-third-party-');
      addTearDown(() => root.delete(recursive: true));
      final serviceCenter = await Directory('${root.path}/service').create();
      final preferences = await Directory('${root.path}/preferences').create();
      final userPreferences = await Directory(
        '${root.path}/user-preferences',
      ).create();
      final content = await Directory('${root.path}/content').create();
      await File('${serviceCenter.path}/FANTHASY.xml').writeAsString('''
<ProductHints><Product>
  <Name>FANTHASY</Name><RegKey>FANTHASY</RegKey><SNPID>za8</SNPID>
  <Type>Content</Type><PoweredBy>Kontakt</PoweredBy>
</Product></ProductHints>
''');
      await File(
        '${preferences.path}/com.native-instruments.FANTHASY.plist',
      ).writeAsString('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Name</key><string>FANTHASY</string>
  <key>RegKey</key><string>FANTHASY</string>
  <key>SNPID</key><string>za8</string>
  <key>ContentDir</key><string>${content.path}</string>
  <key>Visibility</key><integer>3</integer>
</dict></plist>
''');

      final snapshot = await MacOSKontaktPlatform(
        serviceCenterPath: serviceCenter.path,
        preferencesPath: preferences.path,
        userPreferencesPath: userPreferences.path,
        installedProductsPath: '${root.path}/missing-installed-products',
      ).scanLibraries();

      expect(snapshot.libraries.map((library) => library.name), ['FANTHASY']);
      expect(
        snapshot.diagnostics.map((diagnostic) => diagnostic.code),
        isNot(contains('installed_products_missing')),
      );
      final library = snapshot.libraries.single;
      expect(library.hasInstalledProduct, isFalse);
      expect(library.registeredForKontakt6, isTrue);
      expect(library.registeredForKontakt78, isTrue);
      expect(library.health, LibraryHealth.healthy);
    },
  );

  test(
    'includes Native Access installer libraries without Service Center XML',
    () async {
      if (!Platform.isMacOS) return;
      final root = await Directory.systemTemp.createTemp('klm-installer-scan-');
      addTearDown(() => root.delete(recursive: true));
      final serviceCenter = await Directory('${root.path}/service').create();
      final preferences = await Directory('${root.path}/preferences').create();
      final installed = await Directory('${root.path}/installed').create();
      final userPreferences = await Directory(
        '${root.path}/user-preferences',
      ).create();
      final content = await Directory('${root.path}/content').create();
      final pluginContent = await Directory('${root.path}/plugin').create();
      await File('${content.path}/Electric Mint.nicnt').writeAsString('''
<ProductHints><Product>
  <Name>Session Guitarist - Electric Mint</Name>
  <RegKey>Session Guitarist - Electric Mint</RegKey>
  <SNPID>K54</SNPID>
  <Type>Content</Type>
  <Relevance><Application minVersion="6.7.0">Kontakt</Application></Relevance>
</Product></ProductHints>
''');
      await File('${serviceCenter.path}/NativeAccess.xml').writeAsString('''
<ProductHints>
  <Product>
    <Name>Service Center 2</Name>
    <Type>Utility</Type>
    <RegKey>ServiceCenter</RegKey>
  </Product>
  <Product>
    <Name>Session Guitarist - Electric Mint</Name>
    <Type>Content</Type>
    <RegKey>Session Guitarist - Electric Mint</RegKey>
    <SNPID>K54</SNPID>
    <Relevance>
      <Application minVersion="6.7.0" nativeContent="true">Kontakt</Application>
    </Relevance>
  </Product>
  <Product>
    <Name>Drumlab</Name>
    <Type>Content</Type>
    <RegKey>Drumlab</RegKey>
    <SNPID>K99</SNPID>
    <Relevance><Application>Kontakt</Application></Relevance>
  </Product>
</ProductHints>
''');
      await File(
        '${installed.path}/Session Guitarist - Electric Mint.json',
      ).writeAsString(
        '{"ContentDir":"${content.path}","ContentVersion":"1.1.0"}',
      );
      await File('${installed.path}/Waves-CLA-76 Stereo.json').writeAsString(
        '{"ContentDir":"${pluginContent.path}","ContentVersion":"1.0.0","InstallDir":"/Applications/Waves"}',
      );
      await File(
        '${preferences.path}/com.native-instruments.Session Guitarist - Electric Mint.plist',
      ).writeAsString('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>ContentDir</key><string>${content.path}</string>
  <key>ContentVersion</key><string>1.1.0</string>
  <key>HU</key><string>62E085678665FB567EEE28D7BAE251C3</string>
  <key>JDX</key><string>C4472FD328A1E1E8A414E755EDAC877EEE6B389F9864ABDFC82A08FEA405A598</string>
  <key>Visibility</key><integer>3</integer>
</dict></plist>
''');
      await File(
        '${preferences.path}/com.native-instruments.Waves-CLA-76 Stereo.plist',
      ).writeAsString('''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>ContentDir</key><string>${pluginContent.path}</string>
  <key>ContentVersion</key><string>1.0.0</string>
  <key>InstallDir</key><string>/Applications/Waves</string>
</dict></plist>
''');
      await File(
        '${preferences.path}/com.native-instruments.Kontakt 8.plist',
      ).writeAsString('''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>ContentDir</key><string>${root.path}/kontakt-app</string>
  <key>InstallDir</key><string>/Applications/Native Instruments/Kontakt 8</string>
  <key>ContentVersion</key><string>4.0.0</string>
</dict></plist>
''');

      final snapshot = await MacOSKontaktPlatform(
        serviceCenterPath: serviceCenter.path,
        preferencesPath: preferences.path,
        userPreferencesPath: userPreferences.path,
        installedProductsPath: installed.path,
      ).scanLibraries();

      expect(snapshot.libraries.map((library) => library.name), [
        'Session Guitarist - Electric Mint',
      ]);
      final library = snapshot.libraries.single;
      expect(library.snpid, 'K54');
      expect(library.contentPath, content.path);
      expect(library.visibility, 3);
      expect(library.registeredForKontakt78, isTrue);
      expect(library.hasLegacyRegistration, isTrue);
      expect(library.hasServiceCenter, isFalse);
      expect(library.hasNativeAccessCatalog, isTrue);
      expect(library.health, LibraryHealth.healthy);
    },
  );

  test('prefers individual Service Center XML over NativeAccess.xml', () async {
    if (!Platform.isMacOS) return;
    final root = await Directory.systemTemp.createTemp('klm-xml-priority-');
    addTearDown(() => root.delete(recursive: true));
    final serviceCenter = await Directory('${root.path}/service').create();
    final preferences = await Directory('${root.path}/preferences').create();
    final userPreferences = await Directory(
      '${root.path}/user-preferences',
    ).create();
    final content = await Directory('${root.path}/content').create();
    await File('${serviceCenter.path}/FANTHASY.xml').writeAsString('''
<ProductHints><Product>
  <Name>FANTHASY</Name><RegKey>FANTHASY</RegKey><SNPID>za8</SNPID>
  <Type>Content</Type><PoweredBy>Kontakt</PoweredBy>
</Product></ProductHints>
''');
    await File('${serviceCenter.path}/NativeAccess.xml').writeAsString('''
<ProductHints>
  <Product>
    <Name>FANTHASY</Name>
    <RegKey>FANTHASY</RegKey>
    <SNPID>za8</SNPID>
    <Type>Content</Type>
    <Relevance><Application>Kontakt</Application></Relevance>
  </Product>
</ProductHints>
''');
    await File(
      '${preferences.path}/com.native-instruments.FANTHASY.plist',
    ).writeAsString('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Name</key><string>FANTHASY</string>
  <key>RegKey</key><string>FANTHASY</string>
  <key>SNPID</key><string>za8</string>
  <key>ContentDir</key><string>${content.path}</string>
  <key>Visibility</key><integer>3</integer>
</dict></plist>
''');

    final snapshot = await MacOSKontaktPlatform(
      serviceCenterPath: serviceCenter.path,
      preferencesPath: preferences.path,
      userPreferencesPath: userPreferences.path,
      installedProductsPath: '${root.path}/missing-installed-products',
    ).scanLibraries();

    final library = snapshot.libraries.single;
    expect(library.hasServiceCenter, isTrue);
    expect(library.hasNativeAccessCatalog, isFalse);
    expect(library.health, LibraryHealth.healthy);
  });

  test(
    'warns when ProductHints is missing from both individual XML and catalog',
    () async {
      if (!Platform.isMacOS) return;
      final root = await Directory.systemTemp.createTemp('klm-no-hints-');
      addTearDown(() => root.delete(recursive: true));
      final serviceCenter = await Directory('${root.path}/service').create();
      final preferences = await Directory('${root.path}/preferences').create();
      final installed = await Directory('${root.path}/installed').create();
      final userPreferences = await Directory(
        '${root.path}/user-preferences',
      ).create();
      final content = await Directory('${root.path}/content').create();
      await File('${content.path}/Orphan.nicnt').writeAsString('''
<ProductHints><Product>
  <Name>Orphan Library</Name>
  <RegKey>Orphan Library</RegKey>
  <SNPID>Z99</SNPID>
  <Type>Content</Type>
  <Relevance><Application>Kontakt</Application></Relevance>
</Product></ProductHints>
''');
      await File('${installed.path}/Orphan Library.json').writeAsString(
        '{"ContentDir":"${content.path}","ContentVersion":"1.0.0"}',
      );
      await File(
        '${preferences.path}/com.native-instruments.Orphan Library.plist',
      ).writeAsString('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>ContentDir</key><string>${content.path}</string>
  <key>HU</key><string>62E085678665FB567EEE28D7BAE251C3</string>
  <key>JDX</key><string>C4472FD328A1E1E8A414E755EDAC877EEE6B389F9864ABDFC82A08FEA405A598</string>
  <key>Visibility</key><integer>3</integer>
</dict></plist>
''');

      final snapshot = await MacOSKontaktPlatform(
        serviceCenterPath: serviceCenter.path,
        preferencesPath: preferences.path,
        userPreferencesPath: userPreferences.path,
        installedProductsPath: installed.path,
      ).scanLibraries();

      final library = snapshot.libraries.single;
      expect(library.name, 'Orphan Library');
      expect(library.hasProductHints, isFalse);
      expect(
        library.issues.map((issue) => issue.code),
        contains('missing_product_hints'),
      );
      expect(library.health, LibraryHealth.warning);
    },
  );

  test(
    'warns when NativeAccess.xml exists but does not define the library',
    () async {
      if (!Platform.isMacOS) return;
      final root = await Directory.systemTemp.createTemp('klm-catalog-miss-');
      addTearDown(() => root.delete(recursive: true));
      final serviceCenter = await Directory('${root.path}/service').create();
      final preferences = await Directory('${root.path}/preferences').create();
      final installed = await Directory('${root.path}/installed').create();
      final userPreferences = await Directory(
        '${root.path}/user-preferences',
      ).create();
      final content = await Directory('${root.path}/content').create();
      await File('${serviceCenter.path}/NativeAccess.xml').writeAsString('''
<ProductHints>
  <Product>
    <Name>Noire</Name>
    <RegKey>Noire</RegKey>
    <SNPID>K07</SNPID>
    <Type>Content</Type>
    <Relevance><Application>Kontakt</Application></Relevance>
  </Product>
</ProductHints>
''');
      await File('${content.path}/Mint.nicnt').writeAsString('''
<ProductHints><Product>
  <Name>Session Guitarist - Electric Mint</Name>
  <RegKey>Session Guitarist - Electric Mint</RegKey>
  <SNPID>K54</SNPID>
  <Type>Content</Type>
  <Relevance><Application>Kontakt</Application></Relevance>
</Product></ProductHints>
''');
      await File(
        '${installed.path}/Session Guitarist - Electric Mint.json',
      ).writeAsString(
        '{"ContentDir":"${content.path}","ContentVersion":"1.1.0"}',
      );
      await File(
        '${preferences.path}/com.native-instruments.Session Guitarist - Electric Mint.plist',
      ).writeAsString('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>ContentDir</key><string>${content.path}</string>
  <key>HU</key><string>62E085678665FB567EEE28D7BAE251C3</string>
  <key>JDX</key><string>C4472FD328A1E1E8A414E755EDAC877EEE6B389F9864ABDFC82A08FEA405A598</string>
  <key>Visibility</key><integer>3</integer>
</dict></plist>
''');

      final snapshot = await MacOSKontaktPlatform(
        serviceCenterPath: serviceCenter.path,
        preferencesPath: preferences.path,
        userPreferencesPath: userPreferences.path,
        installedProductsPath: installed.path,
      ).scanLibraries();

      expect(snapshot.libraries.map((library) => library.name), [
        'Session Guitarist - Electric Mint',
      ]);
      expect(
        snapshot.libraries.single.issues.map((issue) => issue.code),
        contains('missing_product_hints'),
      );
      expect(snapshot.libraries.single.hasNativeAccessCatalog, isFalse);
    },
  );

  test('writes the classic Kontakt order with one-based indexes', () async {
    const channel = MethodChannel('com.juanayala.kontaktLibraryManager/system');
    MethodCall? capturedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          capturedCall = call;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final adapter = MacOSKontaktPlatform();
    await adapter.saveClassicLibraryOrder(const [
      KontaktLibrary(id: 'gamma', name: 'Gamma', regKey: 'Gamma'),
      KontaktLibrary(id: 'alpha', name: 'Alpha', regKey: 'Alpha'),
    ]);

    expect(capturedCall?.method, 'saveClassicOrder');
    final arguments = capturedCall?.arguments as Map<Object?, Object?>;
    final entries = arguments['entries'] as List<Object?>;
    expect(
      entries.cast<Map<Object?, Object?>>().map(
        (entry) => entry['userListIndex'],
      ),
      [1, 2],
    );
  });

  test(
    'sends multiple removals through one privileged batch request',
    () async {
      const channel = MethodChannel(
        'com.juanayala.kontaktLibraryManager/system',
      );
      final capturedCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            capturedCalls.add(call);
            return {
              'operation': 'batch',
              'results': [
                {
                  'operation': 'remove',
                  'libraryName': 'Alpha',
                  'changedPaths': <String>[],
                },
                {
                  'operation': 'remove',
                  'libraryName': 'Beta',
                  'changedPaths': <String>[],
                },
              ],
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final results = await MacOSKontaktPlatform().removeLibraries(const [
        KontaktLibrary(id: 'alpha', name: 'Alpha', regKey: 'Alpha'),
        KontaktLibrary(id: 'beta', name: 'Beta', regKey: 'Beta'),
      ]);

      expect(results, hasLength(2));
      expect(capturedCalls, hasLength(1));
      expect(capturedCalls.single.method, 'executeMutation');
      final arguments = capturedCalls.single.arguments as Map<Object?, Object?>;
      expect(arguments['operations'], isA<List<Object?>>());
      expect(arguments['operations'] as List<Object?>, hasLength(2));
    },
  );

  test(
    'sends multiple additions through one privileged batch request',
    () async {
      const channel = MethodChannel(
        'com.juanayala.kontaktLibraryManager/system',
      );
      final capturedCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            capturedCalls.add(call);
            return {
              'operation': 'batch',
              'results': [
                {
                  'operation': 'upsert',
                  'libraryName': 'Alpha',
                  'changedPaths': <String>[],
                },
                {
                  'operation': 'upsert',
                  'libraryName': 'Beta',
                  'changedPaths': <String>[],
                },
              ],
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      KontaktLibraryCandidate candidate(String name, String snpid) =>
          KontaktLibraryCandidate(
            contentPath: '/Library/$name',
            metadataPath: '/Library/$name/$name.nicnt',
            metadata: ProductMetadata(name: name, regKey: name, snpid: snpid),
            productHintsXml: '<ProductHints />',
          );
      final results = await MacOSKontaktPlatform().upsertLibraries([
        candidate('Alpha', 'A01'),
        candidate('Beta', 'B01'),
      ]);

      expect(results, hasLength(2));
      expect(capturedCalls, hasLength(1));
      final arguments = capturedCalls.single.arguments as Map<Object?, Object?>;
      expect(arguments['operations'] as List<Object?>, hasLength(2));
    },
  );
}
