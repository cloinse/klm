import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kontakt_library_manager/core/models/kontakt_library.dart';
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

    await File('${serviceCenter.path}/Analog Dreams.xml').writeAsString('''
<ProductHints><Product>
  <Name>Analog Dreams</Name><RegKey>Analog Dreams</RegKey><SNPID>ABC</SNPID>
  <Relevance><Application minVersion="6.0">Kontakt</Application></Relevance>
</Product></ProductHints>
''');
    await File(
      '${installed.path}/Analog Dreams.json',
    ).writeAsString('{"ContentDir":"${content.path}"}');
    await File(
      '${preferences.path}/com.native-instruments.Analog Dreams.plist',
    ).writeAsString('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Name</key><string>Analog Dreams</string>
  <key>RegKey</key><string>Analog Dreams</string>
  <key>SNPID</key><string>ABC</string>
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
}
