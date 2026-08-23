import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kontakt_library_manager/platform/windows/windows_kontakt_platform.dart';

void main() {
  test('Windows exposes classic library ordering', () {
    final capabilities = WindowsKontaktPlatform().capabilities;

    expect(capabilities.canReadInventory, isTrue);
    expect(capabilities.privilegedMutationsAvailable, isTrue);
    expect(capabilities.registryLayoutVerified, isTrue);
    expect(capabilities.canManageClassicOrder, isTrue);
  });

  test('Windows persists and reads per-user classic order without UAC', () {
    final platform = File(
      'lib/platform/windows/windows_kontakt_platform.dart',
    ).readAsStringSync();
    final helper = File(
      'windows/runner/KontaktLibraryHelper.ps1',
    ).readAsStringSync();

    expect(platform, contains("mode: 'classicOrder'"));
    expect(platform, contains("temporaryDirectoryPrefix: 'klm-order-'"));
    expect(platform, isNot(contains('_classicOrderUnsupported')));
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

  test('Windows helper supports transactional mutation batches', () {
    final helper = File(
      'windows/runner/KontaktLibraryHelper.ps1',
    ).readAsStringSync();

    expect(helper, contains("Get-ObjectProperty \$request 'operations'"));
    expect(helper, contains('New-MutationPlan'));
    expect(helper, contains("operation = 'batch'"));
    expect(helper, contains('Conflicting mutation targets.'));
  });

  test('Windows launches PowerShell helpers with hidden windows', () {
    final platform = File(
      'lib/platform/windows/windows_kontakt_platform.dart',
    ).readAsStringSync();
    final helper = File(
      'windows/runner/KontaktLibraryHelper.ps1',
    ).readAsStringSync();

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
}
