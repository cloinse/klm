import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kontakt_library_manager/core/models/kontakt_library.dart';
import 'package:kontakt_library_manager/platform/windows/windows_kontakt_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Windows exposes classic library ordering', () {
    final capabilities = WindowsKontaktPlatform().capabilities;

    expect(capabilities.canReadInventory, isTrue);
    expect(capabilities.privilegedMutationsAvailable, isTrue);
    expect(capabilities.registryLayoutVerified, isTrue);
    expect(capabilities.canManageClassicOrder, isTrue);
  });

  test('Windows persists and reads per-user classic order without UAC', () {
    final platform = _source(
      'lib/platform/windows/windows_kontakt_platform.dart',
    );
    final registryBridge = _source('windows/runner/registry_bridge.cpp');

    expect(
      platform,
      contains("invokeMethod<void>('writeClassicOrder', entries)"),
    );
    expect(platform, isNot(contains("mode: 'classicOrder'")));
    expect(platform, isNot(contains('_classicOrderUnsupported')));
    expect(
      registryBridge,
      contains('call.method_name() == "writeClassicOrder"'),
    );
    expect(registryBridge, contains('HKEY_CURRENT_USER'));
    expect(registryBridge, contains('L"UserListIndex"'));
    expect(registryBridge, contains('L"browserLibsAZSort"'));
    expect(registryBridge, contains('RestoreRegistryBackup'));
  });

  test('standard inventory ignores plugin ProductHints records', () async {
    final root = await Directory.systemTemp.createTemp('klm-windows-scan-');
    addTearDown(() => root.delete(recursive: true));
    final serviceCenter = await Directory('${root.path}/service').create();
    final installed = await Directory('${root.path}/installed').create();
    final content = await Directory('${root.path}/content').create();

    await File('${serviceCenter.path}/Kontakt Library.xml').writeAsString('''
<ProductHints><Product>
  <Name>Kontakt Library</Name><RegKey>Kontakt Library</RegKey><SNPID>K01</SNPID>
  <Type>Content</Type>
</Product></ProductHints>
''');
    await File('${serviceCenter.path}/Waves Plugin.xml').writeAsString('''
<ProductHints><Product>
  <Name>Waves Plugin</Name><RegKey>Waves Plugin</RegKey><SNPID>W01</SNPID>
  <Type>Plugin</Type><Company>Waves</Company>
  <Relevance><Application>Maschine</Application></Relevance>
</Product></ProductHints>
''');
    await File(
      '${installed.path}/Kontakt Library.json',
    ).writeAsString('{"ContentDir":"${content.path}"}');
    await File('${installed.path}/Waves Plugin.json').writeAsString(
      '{"RegKey":"Waves Plugin","SNPID":"W01","ContentDir":"${content.path}"}',
    );

    final snapshot = await WindowsKontaktPlatform(
      serviceCenterPath: serviceCenter.path,
      installedProductsPath: installed.path,
    ).scanLibraries();

    expect(snapshot.libraries.map((library) => library.name), [
      'Kontakt Library',
    ]);
  });

  test(
    'standard inventory prefers the native Windows registry bridge',
    () async {
      const channel = MethodChannel(
        'com.juanayala.kontaktLibraryManager/windows_registry',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'readInventory');
        return <Map<String, Object?>>[
          <String, Object?>{
            'name': 'Native Library',
            'regKey': 'Native Library',
            'snpid': 'N01',
            'contentPath': Directory.systemTemp.path,
            'visibility': 3,
            'userListIndex': 4,
          },
        ];
      });

      final root = await Directory.systemTemp.createTemp('klm-native-scan-');
      addTearDown(() => root.delete(recursive: true));
      final serviceCenter = await Directory('${root.path}/service').create();
      final installed = await Directory('${root.path}/installed').create();
      await File('${serviceCenter.path}/Native Library.xml').writeAsString('''
<ProductHints><Product>
  <Name>Native Library</Name><RegKey>Native Library</RegKey><SNPID>N01</SNPID>
  <Type>Content</Type>
</Product></ProductHints>
''');

      final snapshot = await WindowsKontaktPlatform(
        serviceCenterPath: serviceCenter.path,
        installedProductsPath: installed.path,
      ).scanLibraries();

      final library = snapshot.libraries.single;
      expect(library.sources, contains(RegistrationSource.windowsRegistry));
      expect(library.userListIndex, 4);
      expect(snapshot.diagnostics, isEmpty);
    },
  );

  test(
    'standard inventory reports native bridge failures without fallback',
    () async {
      const channel = MethodChannel(
        'com.juanayala.kontaktLibraryManager/windows_registry',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'registry_read_failed');
      });

      final root = await Directory.systemTemp.createTemp('klm-registry-error-');
      addTearDown(() => root.delete(recursive: true));
      final serviceCenter = await Directory('${root.path}/service').create();
      final installed = await Directory('${root.path}/installed').create();
      await File('${serviceCenter.path}/Native Library.xml').writeAsString('''
<ProductHints><Product>
  <Name>Native Library</Name><RegKey>Native Library</RegKey><SNPID>N01</SNPID>
  <Type>Content</Type>
</Product></ProductHints>
''');

      final snapshot = await WindowsKontaktPlatform(
        serviceCenterPath: serviceCenter.path,
        installedProductsPath: installed.path,
      ).scanLibraries();

      expect(snapshot.libraries.map((library) => library.name), [
        'Native Library',
      ]);
      expect(
        snapshot.diagnostics.map((diagnostic) => diagnostic.code),
        contains('windows_registry_native_failed'),
      );
    },
  );

  test('Windows native helper supports transactional mutation batches', () {
    final nativeMutation = _source('windows/runner/native_mutation.cpp');

    expect(nativeMutation, contains('kMaximumOperations = 1000'));
    expect(
      nativeMutation,
      contains('request->operations.reserve(operation_count)'),
    );
    expect(nativeMutation, contains('file_targets'));
    expect(nativeMutation, contains('registry_targets'));
    expect(
      nativeMutation,
      contains('The mutation contains conflicting file targets.'),
    );
    expect(
      nativeMutation,
      contains('The mutation contains conflicting registry targets.'),
    );
  });

  test('Windows runtime does not include a PowerShell fallback', () {
    final platform = _source(
      'lib/platform/windows/windows_kontakt_platform.dart',
    );
    final elevator = _source('windows/runner/elevated_process_runner.cpp');
    final windowsCmake = _source('windows/CMakeLists.txt');
    final appcastGenerator = _source('tool/generate_appcast.dart');

    expect(platform, isNot(contains('powershell.exe')));
    expect(platform, isNot(contains('KontaktLibraryHelper.ps1')));
    expect(elevator, isNot(contains('powershell.exe')));
    expect(elevator, isNot(contains('KontaktLibraryHelper.ps1')));
    expect(windowsCmake, isNot(contains('KontaktLibraryHelper.ps1')));
    expect(appcastGenerator, isNot(contains('powershell')));
    expect(appcastGenerator, contains('--platform'));
    expect(
      File('windows/runner/KontaktLibraryHelper.ps1').existsSync(),
      isFalse,
    );
    expect(File('tool/generate_windows_appcast.ps1').existsSync(), isFalse);
    expect(File('tool/generate_macos_appcast.sh').existsSync(), isFalse);
  });

  test('Windows mutations use the self-contained native elevator', () {
    final platform = _source(
      'lib/platform/windows/windows_kontakt_platform.dart',
    );
    final elevator = _source('windows/runner/elevated_process_runner.cpp');
    final runnerCmake = _source('windows/runner/CMakeLists.txt');
    final windowsCmake = _source('windows/CMakeLists.txt');

    expect(platform, contains('KontaktLibraryElevator.exe'));
    expect(platform, contains("'--native-mutation'"));
    expect(platform, contains('WindowsNativeMutationCodec.encode(request)'));
    expect(platform, contains("code: 'native_elevator_unavailable'"));
    expect(elevator, contains('execute_info.lpVerb = L"runas"'));
    expect(elevator, contains('L"--apply-native-mutation"'));
    expect(elevator, contains('RunNativeMutation(arguments[2]'));
    expect(elevator, contains('IsAdministrator()'));
    expect(runnerCmake, contains('add_executable(kontakt_library_elevator'));
    expect(runnerCmake, contains('"native_mutation.cpp"'));
    expect(runnerCmake, contains('"bcrypt.lib"'));
    expect(runnerCmake, contains('MSVC_RUNTIME_LIBRARY'));
    expect(windowsCmake, contains('install(TARGETS kontakt_library_elevator'));
  });

  test('Unified appcast generation stays native to Dart tooling', () {
    final generator = _source('tool/generate_appcast.dart');

    expect(generator, contains('WinSparkle could not sign the installer'));
    expect(generator, contains('base64Decode(signature)'));
    expect(generator, contains('Installer signature verification failed'));
    expect(generator, contains('KLM_SPARKLE_PRIVATE_KEY'));
    expect(generator, contains('Sparkle appcast generation'));
    expect(generator, contains('sign_update'));
    expect(generator, contains('Sparkle-\$_sparkleVersion.tar.xz'));
    expect(
      generator,
      contains(
        '1cb340cbbef04c6c0d162078610c25e2221031d794a3449d89f2f56f4df77c95',
      ),
    );
  });

  test(
    'native mutations retain transport checks and transactional rollback',
    () {
      final nativeMutation = _source('windows/runner/native_mutation.cpp');

      expect(nativeMutation, contains('kMaximumRequestBytes = 2500000'));
      expect(nativeMutation, contains('VerifySha256'));
      expect(nativeMutation, contains('ValidateTransport'));
      expect(nativeMutation, contains('PathHasReparsePoint'));
      expect(nativeMutation, contains('ValidateProductHints'));
      expect(nativeMutation, contains('CaptureFileBackup'));
      expect(nativeMutation, contains('CaptureRegistryBackup'));
      expect(nativeMutation, contains('RestoreFileBackup'));
      expect(nativeMutation, contains('RestoreRegistryBackup'));
      expect(nativeMutation, contains('KEY_WOW64_64KEY'));
      expect(nativeMutation, contains('KEY_WOW64_32KEY'));
    },
  );
}

String _source(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');
