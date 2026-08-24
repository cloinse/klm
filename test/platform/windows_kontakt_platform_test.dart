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
    final helper = _source('windows/runner/KontaktLibraryHelper.ps1');
    final registryBridge = _source('windows/runner/registry_bridge.cpp');

    expect(
      platform,
      contains("invokeMethod<void>('writeClassicOrder', entries)"),
    );
    expect(platform, contains("mode: 'classicOrder'"));
    expect(platform, contains("temporaryDirectoryPrefix: 'klm-order-'"));
    expect(platform, isNot(contains('_classicOrderUnsupported')));
    expect(
      registryBridge,
      contains('call.method_name() == "writeClassicOrder"'),
    );
    expect(registryBridge, contains('HKEY_CURRENT_USER'));
    expect(registryBridge, contains('L"UserListIndex"'));
    expect(registryBridge, contains('L"browserLibsAZSort"'));
    expect(registryBridge, contains('RestoreRegistryBackup'));
    expect(helper, contains("'inventory', 'mutation', 'classicOrder'"));
    expect(helper, contains('Get-UserListIndexes'));
    expect(helper, contains('\$record.visibility = \$parsedVisibility'));
    expect(helper, contains('RegistryHive]::CurrentUser'));
    expect(helper, contains('UserListIndex = \$entry.Index'));
    expect(helper, contains('browserLibsAZSort = 0'));

    expect(
      helper,
      contains(
        "  } elseif (\$Mode -eq 'mutation') {\n"
        "    if (-not (Test-IsAdministrator)) {",
      ),
    );
    expect(helper, contains("  } else {\n    \$result = Invoke-ClassicOrder"));
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

  test('Windows helper supports transactional mutation batches', () {
    final helper = _source('windows/runner/KontaktLibraryHelper.ps1');

    expect(helper, contains("Get-ObjectProperty \$request 'operations'"));
    expect(
      helper,
      contains(
        "  if (\$null -eq \$rawOperations) {\n"
        "    \$requests = @(\$request)\n"
        "  } else {\n"
        "    \$requests = @(\$rawOperations)\n"
        "  }\n"
        "  if (\$requests.Count -lt 1",
      ),
    );
    expect(
      helper,
      isNot(contains('\$requests = if (\$null -eq \$rawOperations)')),
    );
    expect(helper, contains('New-MutationPlan'));
    expect(helper, contains("operation = 'batch'"));
    expect(helper, contains('Conflicting mutation targets.'));
  });

  test('Windows launches PowerShell helpers with hidden windows', () {
    final platform = _source(
      'lib/platform/windows/windows_kontakt_platform.dart',
    );
    final helper = _source('windows/runner/KontaktLibraryHelper.ps1');

    expect(platform, contains("'-WindowStyle',\n    'Hidden',"));
    expect(
      RegExp(
        r"Process\.run\('powershell\.exe', \[\s*\.\.\._hiddenPowerShellArguments,",
      ).allMatches(platform),
      hasLength(2),
    );
    expect(helper, contains("'-WindowStyle Hidden'"));
    expect(helper, contains('-WindowStyle Hidden -Wait -PassThru'));
  });

  test('Windows mutations skip the unelevated PowerShell bootstrap', () {
    final platform = _source(
      'lib/platform/windows/windows_kontakt_platform.dart',
    );
    final elevator = _source('windows/runner/elevated_process_runner.cpp');
    final runnerCmake = _source('windows/runner/CMakeLists.txt');
    final windowsCmake = _source('windows/CMakeLists.txt');

    expect(platform, contains('KontaktLibraryElevator.exe'));
    expect(platform, contains("'--native-mutation'"));
    expect(platform, contains('WindowsNativeMutationCodec.encode(request)'));
    expect(elevator, contains('execute_info.lpVerb = L"runas"'));
    expect(elevator, contains('L"--apply-native-mutation"'));
    expect(elevator, contains('RunNativeMutation(arguments[2]'));
    expect(elevator, contains('IsAdministrator()'));
    expect(runnerCmake, contains('add_executable(kontakt_library_elevator'));
    expect(runnerCmake, contains('"native_mutation.cpp"'));
    expect(runnerCmake, contains('"bcrypt.lib"'));
    expect(windowsCmake, contains('install(TARGETS kontakt_library_elevator'));
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
