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
}
